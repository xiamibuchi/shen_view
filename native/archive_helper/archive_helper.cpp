// Indexed, read-only 7-Zip client. Credentials and paths arrive only on stdin.
// GUID initialization must precede the SDK interface declarations.
// clang-format off
#include "Common/MyWindows.h"
#include "Common/MyInitGuid.h"
#include "Common/MyCom.h"
#include "7zip/Archive/IArchive.h"
#include "7zip/IPassword.h"
// clang-format on
#include <algorithm>
#include <chrono>
#include <codecvt>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <locale>
#include <set>
#include <sstream>
#include <string>
#include <vector>
#ifndef _WIN32
#include <dlfcn.h>
#include <sys/resource.h>
#endif
namespace fs = std::filesystem;

static std::wstring wide(const std::string &text) {
#ifdef _WIN32
  if (text.empty())
    return {};
  const int length =
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                          static_cast<int>(text.size()), nullptr, 0);
  if (length <= 0)
    throw std::runtime_error("utf8");
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                      static_cast<int>(text.size()), result.data(), length);
  return result;
#else
  return std::wstring_convert<std::codecvt_utf8<wchar_t>>().from_bytes(text);
#endif
}
static std::string utf8(const wchar_t *text) {
#ifdef _WIN32
  if (!text || !*text)
    return {};
  const int length = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text,
                                         -1, nullptr, 0, nullptr, nullptr);
  if (length <= 0)
    throw std::runtime_error("utf16");
  std::string result(length, '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text, -1, result.data(),
                      length, nullptr, nullptr);
  result.pop_back();
  return result;
#else
  return text
             ? std::wstring_convert<std::codecvt_utf8<wchar_t>>().to_bytes(text)
             : std::string();
#endif
}
static bool constrainMemory() {
#ifdef _WIN32
  MEMORYSTATUSEX status{};
  status.dwLength = sizeof(status);
  const UInt64 available =
      GlobalMemoryStatusEx(&status) ? status.ullAvailPhys : 256ULL << 20;
  if (available < (16ULL << 20))
    return false;
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_PROCESS_MEMORY;
  limits.ProcessMemoryLimit =
      static_cast<SIZE_T>(std::min<UInt64>(512ULL << 20, available / 4));
  HANDLE job = CreateJobObjectW(nullptr, nullptr);
  if (!job)
    return false;
  if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits,
                               sizeof(limits)) ||
      !AssignProcessToJobObject(job, GetCurrentProcess())) {
    CloseHandle(job);
    return false;
  }
  // Keep a successful job handle for process lifetime.
#else
  struct rlimit limit;
  if (getrlimit(RLIMIT_DATA, &limit) == 0) {
    limit.rlim_cur = std::min<rlim_t>(limit.rlim_max, 64ULL << 20);
    setrlimit(RLIMIT_DATA, &limit);
  }
#endif
  return true;
}
static std::string unhex(const std::string &text) {
  if (text.size() % 2 ||
      text.find_first_not_of("0123456789abcdefABCDEF") != std::string::npos)
    throw std::runtime_error("protocol");
  std::string result;
  result.reserve(text.size() / 2);
  for (size_t i = 0; i < text.size(); i += 2)
    result.push_back(
        static_cast<char>(std::stoul(text.substr(i, 2), nullptr, 16)));
  return result;
}
static std::string quote(const std::string &value) {
  std::ostringstream out;
  out << '"';
  const char *digits = "0123456789abcdef";
  for (unsigned char c : value) {
    if (c == '"' || c == '\\')
      out << '\\' << c;
    else if (c < 32)
      out << "\\u00" << digits[c >> 4] << digits[c & 15];
    else
      out << c;
  }
  out << '"';
  return out.str();
}
static void error(const char *kind) {
  std::cout << "{\"event\":\"error\",\"kind\":" << quote(kind) << "}\n"
            << std::flush;
}
static void done(const std::string &fields = "") {
  std::cout << "{\"event\":\"done\"" << fields << "}\n" << std::flush;
}

struct Property {
  PROPVARIANT v{};
  ~Property() {
    if (v.vt == VT_BSTR)
      SysFreeString(v.bstrVal);
  }
  UInt64 number(UInt64 fallback = 0) const {
    if (v.vt == VT_UI8)
      return v.uhVal.QuadPart;
    if (v.vt == VT_UI4)
      return v.ulVal;
    return fallback;
  }
  bool boolean() const { return v.vt == VT_BOOL && v.boolVal != VARIANT_FALSE; }
  std::string text() const {
    return v.vt == VT_BSTR ? utf8(v.bstrVal) : std::string();
  }
};

class Input final : public IInStream, public CMyUnknownImp {
  Z7_IFACES_IMP_UNK_2(ISequentialInStream, IInStream)
public:
  std::ifstream file;
  explicit Input(const fs::path &path) : file(path, std::ios::binary) {}
};
Z7_COM7F_IMF(Input::Read(void *data, UInt32 size, UInt32 *processed)) {
  file.read(static_cast<char *>(data), size);
  if (processed)
    *processed = static_cast<UInt32>(file.gcount());
  return file.bad() ? E_FAIL : S_OK;
}
Z7_COM7F_IMF(Input::Seek(Int64 offset, UInt32 origin, UInt64 *position)) {
  file.clear();
  file.seekg(offset, origin == 0   ? std::ios::beg
                     : origin == 1 ? std::ios::cur
                                   : std::ios::end);
  if (!file)
    return E_FAIL;
  if (position)
    *position = static_cast<UInt64>(file.tellg());
  return S_OK;
}

class OpenCallback final : public IArchiveOpenCallback,
                           public ICryptoGetTextPassword,
                           public IArchiveOpenVolumeCallback,
                           public CMyUnknownImp {
  Z7_IFACES_IMP_UNK_3(IArchiveOpenCallback, ICryptoGetTextPassword,
                      IArchiveOpenVolumeCallback)
public:
  std::wstring password;
  bool defined = false, asked = false, volume = false;
};
Z7_COM7F_IMF(OpenCallback::SetTotal(const UInt64 *, const UInt64 *)) {
  return S_OK;
}
Z7_COM7F_IMF(OpenCallback::SetCompleted(const UInt64 *, const UInt64 *)) {
  return S_OK;
}
Z7_COM7F_IMF(OpenCallback::CryptoGetTextPassword(BSTR *value)) {
  asked = true;
  if (!defined)
    return E_ABORT;
  *value = SysAllocString(password.c_str());
  return *value ? S_OK : E_OUTOFMEMORY;
}
Z7_COM7F_IMF(OpenCallback::GetProperty(PROPID, PROPVARIANT *value)) {
  value->vt = VT_EMPTY;
  return S_OK;
}
Z7_COM7F_IMF(OpenCallback::GetStream(const wchar_t *, IInStream **value)) {
  *value = nullptr;
  volume = true;
  return S_FALSE;
}

struct OutputBudget {
  UInt64 written = 0, maximum;
  bool limited = false;
};
class Output final : public ISequentialOutStream, public CMyUnknownImp {
  Z7_IFACES_IMP_UNK_1(ISequentialOutStream)
public:
  std::ofstream file;
  fs::path parent;
  UInt64 written = 0, maximum;
  bool limited = false, disk = false, opened;
  OutputBudget *budget;
  Output(const fs::path &path, UInt64 max, OutputBudget *sharedBudget)
      : file(path, std::ios::binary | std::ios::trunc),
        parent(path.parent_path()), maximum(max), opened(file.is_open()),
        budget(sharedBudget) {}
};
Z7_COM7F_IMF(Output::Write(const void *data, UInt32 size, UInt32 *processed)) {
  if (processed)
    *processed = 0;
  if (size > maximum - written || size > budget->maximum - budget->written) {
    limited = true;
    budget->limited = true;
    return E_ABORT;
  }
  std::error_code ec;
  const auto space = fs::space(parent, ec);
  if (!ec) {
    const auto margin = std::min<uintmax_t>(
        8ULL << 30, std::max<uintmax_t>(1ULL << 30, space.capacity / 20));
    if (space.available < margin + size) {
      disk = true;
      return E_ABORT;
    }
  }
  file.write(static_cast<const char *>(data), size);
  if (!file)
    return E_FAIL;
  written += size;
  budget->written += size;
  if (processed)
    *processed = size;
  return S_OK;
}
struct ExtractTarget {
  UInt32 index;
  fs::path path;
  UInt64 maximum;
  Output *stream = nullptr;
  CMyComPtr<ISequentialOutStream> output;
  bool seen = false, completed = false;
};
class ExtractCallback final : public IArchiveExtractCallback,
                              public ICryptoGetTextPassword,
                              public CMyUnknownImp {
  Z7_IFACES_IMP_UNK_2(IArchiveExtractCallback, ICryptoGetTextPassword)
  Z7_IFACE_COM7_IMP(IProgress)
public:
  std::vector<ExtractTarget> *targets;
  ExtractTarget *current = nullptr;
  std::wstring password;
  bool defined = false, asked = false, limited = false;
  UInt64 maximumWork, workBytes = 0;
  Int32 result = 0;
  std::chrono::steady_clock::time_point last = std::chrono::steady_clock::now();
};
Z7_COM7F_IMF(ExtractCallback::SetTotal(UInt64)) { return S_OK; }
Z7_COM7F_IMF(ExtractCallback::SetCompleted(const UInt64 *value)) {
  if (value)
    workBytes = std::max(workBytes, *value);
  if (value && *value > maximumWork) {
    limited = true;
    return E_ABORT;
  }
  auto now = std::chrono::steady_clock::now();
  if (value && now - last > std::chrono::milliseconds(100)) {
    std::cout << "{\"event\":\"progress\",\"completed\":" << *value << "}\n"
              << std::flush;
    last = now;
  }
  return S_OK;
}
Z7_COM7F_IMF(ExtractCallback::GetStream(UInt32 index,
                                        ISequentialOutStream **stream,
                                        Int32 mode)) {
  *stream = nullptr;
  current = nullptr;
  for (auto &target : *targets) {
    if (index == target.index &&
        mode == NArchive::NExtract::NAskMode::kExtract) {
      current = &target;
      target.seen = true;
      *stream = target.output;
      (*stream)->AddRef();
      break;
    }
  }
  return S_OK;
}
Z7_COM7F_IMF(ExtractCallback::PrepareOperation(Int32)) { return S_OK; }
Z7_COM7F_IMF(ExtractCallback::SetOperationResult(Int32 value)) {
  if (value)
    result = value;
  if (current)
    current->completed = value == 0;
  return S_OK;
}
Z7_COM7F_IMF(ExtractCallback::CryptoGetTextPassword(BSTR *value)) {
  asked = true;
  if (!defined)
    return E_ABORT;
  *value = SysAllocString(password.c_str());
  return *value ? S_OK : E_OUTOFMEMORY;
}

static bool unsignedNumber(const std::string &text, UInt64 &value) {
  if (text.empty() || text.find_first_not_of("0123456789") != std::string::npos)
    return false;
  try {
    value = std::stoull(text);
    return true;
  } catch (...) {
    return false;
  }
}
static fs::path uniquePath(const fs::path &path) {
  auto canonical = fs::weakly_canonical(fs::absolute(path));
#ifdef _WIN32
  auto text = canonical.native();
  CharLowerBuffW(text.data(), static_cast<DWORD>(text.size()));
  return fs::path(text);
#else
  return canonical;
#endif
}

int main(int argc, char **argv) {
  try {
    if (!constrainMemory()) {
      error("resource");
      return 1;
    }
    // Engine is always adjacent to the helper. Never search writable PATH.
#ifdef _WIN32
    std::wstring module(32768, L'\0');
    const DWORD moduleLength = GetModuleFileNameW(
        nullptr, module.data(), static_cast<DWORD>(module.size()));
    if (!moduleLength || moduleLength >= module.size()) {
      error("missingTool");
      return 1;
    }
    module.resize(moduleLength);
    const fs::path directory = fs::path(module).parent_path();
    const auto library = LoadLibraryExW(
        (directory / L"7z.dll").c_str(), nullptr,
        LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
    auto create = reinterpret_cast<Func_CreateObject>(
        library ? GetProcAddress(library, "CreateObject") : nullptr);
#else
    const fs::path directory = fs::absolute(fs::u8path(argv[0])).parent_path();
    const auto library =
        dlopen((directory / "7z.so").c_str(), RTLD_NOW | RTLD_LOCAL);
    auto create = reinterpret_cast<Func_CreateObject>(
        library ? dlsym(library, "CreateObject") : nullptr);
#endif
    if (!create) {
      error("missingTool");
      return 1;
    }
    CMyComPtr<IInArchive> archive;
    CMyComPtr<IInStream> input;
    std::wstring password;
    bool defined = false, encrypted = false;
    UInt32 count = 0;
    for (std::string line; std::getline(std::cin, line);) {
      if (line.size() > 2 * 1024 * 1024) {
        error("limit");
        break;
      }
      std::vector<std::string> f;
      std::istringstream parts(line);
      for (std::string s; std::getline(parts, s, '\t');)
        f.push_back(s);
      if (f.empty())
        continue;
      if (f[0] == "open" && f.size() == 5) {
        archive.Release();
        input.Release();
        encrypted = false;
        defined = f[2] != "-";
        password = defined ? wide(unhex(f[2])) : L"";
        auto *in = new Input(fs::u8path(unhex(f[1])));
        input = in;
        if (!in->file) {
          error("io");
          continue;
        }
        const unsigned ids[] = {1, 3, 0xCC, 7, 0xEE};
        const char *names[] = {"zip", "rar", "rar5", "7z", "tar"};
        const char *format = "";
        bool failed = false;
        for (size_t k = 0; k < 5; k++) {
          GUID id = {0x23170f69,
                     0x40c1,
                     0x278a,
                     {0x10, 0, 0, 1, 0x10, static_cast<Byte>(ids[k]), 0, 0}};
          if (create(&id, &IID_IInArchive,
                     reinterpret_cast<void **>(&archive)) != S_OK)
            continue;
          input->Seek(0, 0, nullptr);
          auto *cb = new OpenCallback;
          CMyComPtr<IArchiveOpenCallback> callback = cb;
          cb->defined = defined;
          cb->password = password;
          const UInt64 search = 0;
          const HRESULT hr = archive->Open(input, &search, callback);
          if (hr == S_OK) {
            format = names[k];
            encrypted = cb->asked;
            break;
          }
          archive.Release();
          if (cb->asked) {
            error(defined ? "passwordUnverifiable" : "encrypted");
            failed = true;
            break;
          }
          if (cb->volume) {
            error("volumeMissing");
            failed = true;
            break;
          }
        }
        if (!archive) {
          if (!failed)
            error("corrupt");
          continue;
        }
        if (archive->GetNumberOfItems(&count) != S_OK) {
          error("corrupt");
          continue;
        }
        if (count > std::stoul(f[3])) {
          error("limit");
          continue;
        }
        size_t nameBytes = 0;
        bool invalid = false;
        const bool rar =
            std::strcmp(format, "rar") == 0 || std::strcmp(format, "rar5") == 0;
        bool rarBlockKnown = false;
        UInt32 rarBlock = 0;
        for (UInt32 i = 0; i < count; i++) {
          Property name, size, dir, crypt, crc, block, time, symlink, hardlink,
              attrib, itemSolid;
          archive->GetProperty(i, kpidPath, &name.v);
          archive->GetProperty(i, kpidSize, &size.v);
          archive->GetProperty(i, kpidIsDir, &dir.v);
          archive->GetProperty(i, kpidEncrypted, &crypt.v);
          archive->GetProperty(i, kpidCRC, &crc.v);
          archive->GetProperty(i, kpidBlock, &block.v);
          archive->GetProperty(i, kpidMTime, &time.v);
          archive->GetProperty(i, kpidSymLink, &symlink.v);
          archive->GetProperty(i, kpidHardLink, &hardlink.v);
          archive->GetProperty(i, kpidPosixAttrib, &attrib.v);
          if (rar) {
            archive->GetProperty(i, kpidSolid, &itemSolid.v);
            // RAR's item flag means dependency on the preceding dictionary.
            // Unknown flags and directory boundaries are conservative barriers.
            if (dir.v.vt != VT_BOOL || dir.boolean() ||
                itemSolid.v.vt != VT_BOOL) {
              rarBlockKnown = false;
            } else if (!itemSolid.boolean()) {
              rarBlock = i;
              rarBlockKnown = true;
            }
          }
          const auto path = name.text();
          nameBytes += path.size();
          if (nameBytes > std::stoull(f[4]) || path.size() > 32768) {
            error("limit");
            invalid = true;
            break;
          }
          const auto type = (attrib.number() & 0170000);
          const bool link = !symlink.text().empty() ||
                            !hardlink.text().empty() ||
                            (type && type != 0100000 && type != 0040000);
          encrypted |= crypt.boolean();
          std::cout << "{\"event\":\"entry\",\"index\":" << i
                    << ",\"name\":" << quote(path)
                    << ",\"size\":" << size.number()
                    << ",\"directory\":" << (dir.boolean() ? "true" : "false")
                    << ",\"encrypted\":" << (crypt.boolean() ? "true" : "false")
                    << ",\"link\":" << (link ? "true" : "false");
          if (crc.v.vt != VT_EMPTY)
            std::cout << ",\"crc\":" << crc.number();
          if (block.v.vt != VT_EMPTY)
            std::cout << ",\"block\":" << block.number();
          else if (rar && rarBlockKnown && !dir.boolean())
            std::cout << ",\"block\":" << rarBlock;
          if (time.v.vt == VT_FILETIME) {
            UInt64 t =
                (static_cast<UInt64>(time.v.filetime.dwHighDateTime) << 32) |
                time.v.filetime.dwLowDateTime;
            std::cout << ",\"modified\":"
                      << (static_cast<Int64>(t) - 116444736000000000LL) / 10000;
          }
          std::cout << "}\n";
        }
        if (invalid)
          continue;
        Property solid;
        archive->GetArchiveProperty(kpidSolid, &solid.v);
        done(std::string(",\"format\":") + quote(format) +
             ",\"solid\":" + (solid.boolean() ? "true" : "false") +
             ",\"encrypted\":" + (encrypted ? "true" : "false"));
      } else if (((f[0] == "read" && f.size() == 5) ||
                  (f[0] == "readMany" && f.size() >= 6 &&
                   (f.size() - 3) % 3 == 0)) &&
                 archive) {
        const bool batch = f[0] == "readMany";
        const size_t targetCount = batch ? (f.size() - 3) / 3 : 1;
        UInt64 maxTotal = 0, maxWork = 0;
        if (targetCount > 16 || !unsignedNumber(f[batch ? 1 : 3], maxTotal) ||
            !unsignedNumber(f[batch ? 2 : 4], maxWork)) {
          error("limit");
          continue;
        }
        std::vector<ExtractTarget> targets;
        std::set<UInt32> seenIndices;
        std::set<fs::path> seenPaths;
        const char *failure = nullptr;
        UInt64 indexedBytes = 0;
        for (size_t t = 0; t < targetCount; ++t) {
          const size_t base = batch ? 3 + t * 3 : 1;
          UInt64 index = 0, maximum = 0;
          if (!unsignedNumber(f[base], index) || index >= count) {
            failure = "corrupt";
            break;
          }
          if (!unsignedNumber(f[base + 2], maximum)) {
            failure = "limit";
            break;
          }
          const auto pathText = unhex(f[base + 1]);
          if (pathText.empty() || pathText.find('\0') != std::string::npos) {
            failure = "unsafePath";
            break;
          }
          const auto path = fs::u8path(pathText);
          if (!seenIndices.insert(static_cast<UInt32>(index)).second ||
              !seenPaths.insert(uniquePath(path)).second) {
            failure = "unsafePath";
            break;
          }
          if (batch) {
            Property size, dir;
            archive->GetProperty(static_cast<UInt32>(index), kpidSize, &size.v);
            archive->GetProperty(static_cast<UInt32>(index), kpidIsDir, &dir.v);
            if (dir.boolean()) {
              failure = "corrupt";
              break;
            }
            if (size.v.vt != VT_EMPTY) {
              const auto bytes = size.number();
              if (bytes > maximum || bytes > maxTotal - indexedBytes) {
                failure = "limit";
                break;
              }
              indexedBytes += bytes;
            }
          }
          targets.push_back({static_cast<UInt32>(index), path, maximum});
        }
        if (failure) {
          error(failure);
          continue;
        }
        std::sort(targets.begin(), targets.end(),
                  [](const ExtractTarget &a, const ExtractTarget &b) {
                    return a.index < b.index;
                  });
        OutputBudget budget{0, maxTotal};
        std::vector<UInt32> indices;
        for (auto &target : targets) {
          indices.push_back(target.index);
          target.stream = new Output(target.path, target.maximum, &budget);
          target.output = target.stream;
          if (!target.stream->file) {
            failure = "io";
            break;
          }
        }
        auto *cb = new ExtractCallback;
        CMyComPtr<IArchiveExtractCallback> callback = cb;
        cb->targets = &targets;
        cb->password = password;
        cb->defined = defined;
        cb->maximumWork = maxWork;
        const HRESULT hr =
            failure ? E_FAIL
                    : archive->Extract(indices.data(),
                                       static_cast<UInt32>(indices.size()), 0,
                                       callback);
        for (auto &target : targets) {
          if (!target.stream)
            continue;
          target.stream->file.close();
          if (target.stream->limited || cb->limited || budget.limited)
            failure = "limit";
          else if (target.stream->disk)
            failure = "resource";
          else if (!failure && target.stream->file.fail())
            failure = "io";
          else if (!failure && (!target.seen || !target.completed))
            failure = "corrupt";
        }
        const auto r = cb->result;
        if (cb->limited || budget.limited)
          failure = "limit";
        else if (cb->asked && !defined)
          failure = "encrypted";
        else if (r == NArchive::NExtract::NOperationResult::kWrongPassword)
          failure = "wrongPassword";
        else if (r == NArchive::NExtract::NOperationResult::kUnsupportedMethod)
          failure = "unsupported";
        else if (r == NArchive::NExtract::NOperationResult::kUnavailable)
          failure = "volumeMissing";
        else if (r == NArchive::NExtract::NOperationResult::kCRCError ||
                 r == NArchive::NExtract::NOperationResult::kDataError)
          failure = cb->asked ? "passwordUnverifiable" : "corrupt";
        else if (hr == E_OUTOFMEMORY)
          failure = "resource";
        else if (!failure && (hr != S_OK || r))
          failure = "corrupt";
        if (failure) {
          for (auto &target : targets) {
            if (target.stream && target.stream->opened) {
              std::error_code ec;
              fs::remove(target.path, ec);
            }
          }
          error(failure);
          continue;
        }
        done(std::string(",\"bytes\":") + std::to_string(budget.written) +
             ",\"workBytes\":" + std::to_string(cb->workBytes) +
             ",\"extractCalls\":1");
      } else {
        error("unsupported");
      }
    }
    if (archive)
      archive->Close();
  } catch (const std::bad_alloc &) {
    error("resource");
    return 1;
  } catch (...) {
    error("corrupt");
    return 1;
  }
  return 0;
}
