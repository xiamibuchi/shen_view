#include "native_file_associations.h"

#include <windows.h>
#include <appmodel.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include <cwctype>
#include <filesystem>
#include <fstream>
#include <set>
#include <sstream>
#include <stdexcept>

namespace {
using flutter::EncodableMap;
using flutter::EncodableValue;
const std::wstring kClasses = L"Software\\Classes\\";

std::wstring PhysicalExecutable() {
  std::wstring path(32768, L'\0');
  const DWORD length = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (!length || length == path.size()) throw std::runtime_error("Executable path unavailable");
  path.resize(length);
  return path;
}

std::wstring Executable() {
  const auto path = std::filesystem::path(PhysicalExecutable());
  std::ifstream marker(path.parent_path() / L"installation-mode");
  std::string mode;
  marker >> mode;
  if (mode == "scoop") {
    // Scoop replaces version directories; its current junction remains stable.
    const auto current = path.parent_path().parent_path() / L"current" / path.filename();
    if (std::filesystem::exists(current)) return current.wstring();
  }
  return path.wstring();
}

std::wstring PackageFamily() {
  UINT32 length = 0;
  if (GetCurrentPackageFamilyName(&length, nullptr) != ERROR_INSUFFICIENT_BUFFER) return {};
  std::wstring family(length, L'\0');
  if (GetCurrentPackageFamilyName(&length, family.data()) != ERROR_SUCCESS) return {};
  family.resize(length - 1);
  return family;
}

std::string Mode() {
  if (!PackageFamily().empty()) return "msix";
  std::ifstream marker(std::filesystem::path(Executable()).parent_path() / L"installation-mode");
  std::string mode;
  marker >> mode;
  return mode == "installed" || mode == "installed-system" || mode == "scoop" ? mode : "portable";
}

HKEY RegistryRoot() { return Mode() == "installed-system" ? HKEY_LOCAL_MACHINE : HKEY_CURRENT_USER; }

std::wstring Identity() {
  if (Mode() == "installed-system") return L"ShenView.Machine";
  if (Mode() == "installed") return L"ShenView.Installed";
  // Stable across runs, distinct for separate portable directories.
  auto path = Executable();
  std::transform(path.begin(), path.end(), path.begin(), towlower);
  uint64_t hash = 14695981039346656037ULL;
  for (const auto c : path) { hash ^= static_cast<uint16_t>(c); hash *= 1099511628211ULL; }
  std::wostringstream value;
  value << L"ShenView.Portable." << std::hex << hash;
  return value.str();
}

std::wstring Capabilities() { return L"Software\\ShenView\\Associations\\" + Identity(); }
std::wstring Command() { return L"\"" + Executable() + L"\" -- \"%1\""; }

void Check(LSTATUS status) {
  if (status != ERROR_SUCCESS) throw std::runtime_error("Windows registry error " + std::to_string(status));
}

std::wstring Read(const std::wstring& key, const std::wstring& name = L"") {
  DWORD bytes = 0;
  if (RegGetValueW(RegistryRoot(), key.c_str(), name.c_str(), RRF_RT_REG_SZ,
                  nullptr, nullptr, &bytes) != ERROR_SUCCESS) return {};
  std::wstring value(bytes / sizeof(wchar_t), L'\0');
  if (RegGetValueW(RegistryRoot(), key.c_str(), name.c_str(), RRF_RT_REG_SZ,
                  nullptr, value.data(), &bytes) != ERROR_SUCCESS) return {};
  value.resize(bytes / sizeof(wchar_t));
  while (!value.empty() && value.back() == L'\0') value.pop_back();
  return value;
}

void Write(const std::wstring& key, const std::wstring& name, const std::wstring& value) {
  HKEY handle = nullptr;
  Check(RegCreateKeyExW(RegistryRoot(), key.c_str(), 0, nullptr, 0,
                       KEY_SET_VALUE, nullptr, &handle, nullptr));
  const auto status = RegSetValueExW(handle, name.c_str(), 0, REG_SZ,
      reinterpret_cast<const BYTE*>(value.c_str()),
      static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(handle);
  Check(status);
}

void DeleteValue(const std::wstring& key, const std::wstring& name) {
  HKEY handle = nullptr;
  const auto status = RegOpenKeyExW(RegistryRoot(), key.c_str(), 0, KEY_SET_VALUE, &handle);
  if (status == ERROR_FILE_NOT_FOUND) return;
  Check(status);
  const auto removed = RegDeleteValueW(handle, name.c_str());
  RegCloseKey(handle);
  if (removed != ERROR_FILE_NOT_FOUND) Check(removed);
}

std::set<std::wstring> Registered() {
  std::set<std::wstring> result;
  HKEY handle = nullptr;
  if (RegOpenKeyExW(RegistryRoot(), (Capabilities() + L"\\FileAssociations").c_str(),
                    0, KEY_QUERY_VALUE, &handle) != ERROR_SUCCESS) return result;
  for (DWORD i = 0;; ++i) {
    wchar_t name[256];
    DWORD size = 256;
    const auto status = RegEnumValueW(handle, i, name, &size, nullptr, nullptr, nullptr, nullptr);
    if (status == ERROR_NO_MORE_ITEMS) break;
    if (status == ERROR_SUCCESS && size > 1 && name[0] == L'.') result.insert(std::wstring(name + 1, size - 1));
  }
  RegCloseKey(handle);
  return result;
}

std::wstring Extension(const std::string& text) {
  if (text.empty() || text.size() > 16 || !std::all_of(text.begin(), text.end(),
      [](unsigned char c) { return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'); })) {
    throw std::runtime_error("Invalid file extension");
  }
  return std::wstring(text.begin(), text.end());
}

void Update(const std::set<std::wstring>& selected) {
  if (!PackageFamily().empty()) throw std::runtime_error("MSIX file types are managed by Windows");
  const auto identity = Identity();
  const auto caps = Capabilities();
  for (const auto& ext : Registered()) {
    if (selected.count(ext)) continue;
    const auto prog = identity + L"." + ext;
    if (Read(kClasses + prog + L"\\shell\\open\\command") != Command()) continue;
    DeleteValue(kClasses + L"." + ext + L"\\OpenWithProgids", prog);
    Check(RegDeleteTreeW(RegistryRoot(), (kClasses + prog).c_str()));
    DeleteValue(caps + L"\\FileAssociations", L"." + ext);
  }
  if (selected.empty()) {
    if (Read(caps, L"ApplicationPath") == Executable()) {
      DeleteValue(L"Software\\RegisteredApplications", identity);
      Check(RegDeleteTreeW(RegistryRoot(), caps.c_str()));
    }
  } else {
    Write(caps, L"ApplicationName", L"ShenView");
    Write(caps, L"ApplicationDescription", L"ShenView image and comic viewer");
    Write(caps, L"ApplicationIcon", L"\"" + Executable() + L"\",0");
    Write(caps, L"ApplicationPath", Executable());
    Write(L"Software\\RegisteredApplications", identity, caps);
    for (const auto& ext : selected) {
      const auto prog = identity + L"." + ext;
      Write(kClasses + prog, L"", L"ShenView ." + ext);
      Write(kClasses + prog + L"\\DefaultIcon", L"", L"\"" + Executable() + L"\",0");
      Write(kClasses + prog + L"\\shell\\open\\command", L"", Command());
      Write(kClasses + L"." + ext + L"\\OpenWithProgids", prog, L"");
      Write(caps + L"\\FileAssociations", L"." + ext, prog);
    }
  }
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
}

bool IsDefault(const std::wstring& ext) {
  wchar_t path[32768];
  DWORD size = 32768;
  if (FAILED(AssocQueryStringW(ASSOCF_NONE, ASSOCSTR_EXECUTABLE,
      (L"." + ext).c_str(), L"open", path, &size))) return false;
  return _wcsicmp(path, Executable().c_str()) == 0;
}

bool OpenSettings() {
  std::wstring uri = L"ms-settings:defaultapps";
  const auto family = PackageFamily();
  if (!family.empty()) uri += L"?registeredAUMID=" + family + L"!ShenView";
  else if (Read(Capabilities(), L"ApplicationPath") == Executable())
    uri += (Mode() == "installed-system" ? L"?registeredAppMachine=" : L"?registeredAppUser=") + Identity();
  return reinterpret_cast<INT_PTR>(ShellExecuteW(nullptr, L"open", uri.c_str(),
      nullptr, nullptr, SW_SHOWNORMAL)) > 32;
}

void UpdateFromSettings(const std::set<std::wstring>& selected) {
  HANDLE token = nullptr;
  TOKEN_ELEVATION elevation{};
  DWORD size = 0;
  if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    GetTokenInformation(token, TokenElevation, &elevation, sizeof(elevation), &size);
    CloseHandle(token);
  }
  if (Mode() != "installed-system" || elevation.TokenIsElevated) {
    Update(selected);
    return;
  }
  std::wstring parameters = L"--set-file-types=";
  for (const auto& extension : selected) {
    if (parameters.back() != L'=') parameters += L",";
    parameters += extension;
  }
  const auto executable = Executable();
  SHELLEXECUTEINFOW request{};
  request.cbSize = sizeof(request);
  request.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC;
  request.lpVerb = L"runas";
  request.lpFile = executable.c_str();
  request.lpParameters = parameters.c_str();
  request.nShow = SW_HIDE;
  if (!ShellExecuteExW(&request)) throw std::runtime_error("Administrator approval was not granted");
  if (!request.hProcess) throw std::runtime_error("Association helper did not start");
  WaitForSingleObject(request.hProcess, INFINITE);
  DWORD code = 1;
  GetExitCodeProcess(request.hProcess, &code);
  CloseHandle(request.hProcess);
  if (code != 0) throw std::runtime_error("Association helper failed");
}
}  // namespace

NativeFileAssociations::NativeFileAssociations(flutter::FlutterEngine* engine) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      engine->messenger(), "shenview/file_associations", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([](const auto& call, auto result) {
    try {
      if (call.method_name() == "openSettings") {
        if (!OpenSettings()) throw std::runtime_error("Unable to open Windows default apps");
        result->Success();
        return;
      }
      const auto* list = call.arguments() == nullptr ? nullptr :
          std::get_if<flutter::EncodableList>(call.arguments());
      if (list == nullptr) throw std::runtime_error("Expected file extensions");
      std::set<std::wstring> extensions;
      for (const auto& item : *list) {
        const auto* text = std::get_if<std::string>(&item);
        if (text == nullptr) throw std::runtime_error("Expected extension string");
        extensions.insert(Extension(*text));
      }
      if (call.method_name() == "update") {
        UpdateFromSettings(extensions);
        result->Success();
      } else if (call.method_name() == "read") {
        const auto registered = Registered();
        EncodableMap states;
        for (const auto& ext : extensions) {
          const auto prog = Identity() + L"." + ext;
          const bool owned = registered.count(ext) &&
              Read(kClasses + prog + L"\\shell\\open\\command") == Command();
          std::string extension;
          for (const auto c : ext) extension.push_back(static_cast<char>(c));
          states[EncodableValue(extension)] = EncodableValue(EncodableMap{
              {EncodableValue("registered"), EncodableValue(Mode() == "msix" || owned)},
              {EncodableValue("isDefault"), EncodableValue(IsDefault(ext))}});
        }
        result->Success(EncodableValue(EncodableMap{
            {EncodableValue("mode"), EncodableValue(Mode())},
            {EncodableValue("extensions"), EncodableValue(states)}}));
      } else result->NotImplemented();
    } catch (const std::exception& error) { result->Error("file_association_error", error.what()); }
  });
}

std::optional<int> NativeFileAssociations::HandleCommand(const std::vector<std::string>& args) {
  if (args.empty()) return std::nullopt;
  try {
    const std::string prefix = "--register-file-types=";
    const std::string replace_prefix = "--set-file-types=";
    const bool replace = args[0].rfind(replace_prefix, 0) == 0;
    if (replace || args[0].rfind(prefix, 0) == 0) {
      auto selected = replace ? std::set<std::wstring>{} : Registered();
      std::istringstream input(args[0].substr(replace ? replace_prefix.size() : prefix.size()));
      std::string extension;
      while (std::getline(input, extension, ',')) selected.insert(Extension(extension));
      Update(selected);
    } else if (args[0] == "--repair-file-types") Update(Registered());
    else if (args[0] == "--remove-file-types") Update({});
    else if (args[0] == "--default-apps") return OpenSettings() ? 0 : 1;
    else return std::nullopt;
    return 0;
  } catch (const std::exception&) { return 1; }
}
