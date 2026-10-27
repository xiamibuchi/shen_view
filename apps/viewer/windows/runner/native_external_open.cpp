#include "native_external_open.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <condition_variable>
#include <cwctype>
#include <functional>
#include <mutex>
#include <queue>
#include <set>
#include <stdexcept>
#include <thread>

#include "utils.h"

namespace {
using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;
constexpr UINT kCompleted = WM_APP + 321;

struct ShellError {
  HRESULT code;
};
void Check(HRESULT value) {
  if (FAILED(value)) {
    throw ShellError{value};
  }
}

std::wstring Wide(const std::string& value) {
  if (value.empty()) {
    return {};
  }
  const int size =
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                          static_cast<int>(value.size()), nullptr, 0);
  if (!size) {
    throw std::runtime_error("Invalid UTF-8 path");
  }
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

std::wstring Lower(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(towlower(c)); });
  return value;
}

std::wstring HandlerName(IAssocHandler* handler, bool display = false) {
  LPWSTR text = nullptr;
  const HRESULT status =
      display ? handler->GetUIName(&text) : handler->GetName(&text);
  const std::wstring value = SUCCEEDED(status) && text ? text : L"";
  CoTaskMemFree(text);
  return value;
}

bool IsViewer(const std::wstring& id, const std::wstring& name) {
  const auto normalized = Lower(id);
  const auto display = Lower(name);
  return Lower(PathFindFileNameW(id.c_str())) == L"shenview.exe" ||
         normalized.find(L"shenview.") != std::wstring::npos ||
         display == L"shenview" || display == L"神羊看图";
}

std::vector<uint8_t> HandlerIcon(IAssocHandler* handler) {
  LPWSTR location = nullptr;
  int index = 0;
  if (FAILED(handler->GetIconLocation(&location, &index))) {
    return {};
  }
  HICON icon = nullptr;
  const HRESULT extracted =
      location ? SHDefExtractIconW(location, index, 0, &icon, nullptr, 32)
               : E_FAIL;
  CoTaskMemFree(location);
  if (FAILED(extracted) || !icon) {
    return {};
  }
  ComPtr<IWICImagingFactory> factory;
  ComPtr<IWICBitmap> bitmap;
  ComPtr<IStream> stream;
  ComPtr<IWICBitmapEncoder> encoder;
  ComPtr<IWICBitmapFrameEncode> frame;
  HRESULT status =
      CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                       IID_PPV_ARGS(&factory));
  if (SUCCEEDED(status)) {
    status = factory->CreateBitmapFromHICON(icon, &bitmap);
  }
  DestroyIcon(icon);
  if (FAILED(status)) {
    return {};
  }
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream)) ||
      FAILED(
          factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder)) ||
      FAILED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache)) ||
      FAILED(encoder->CreateNewFrame(&frame, nullptr)) ||
      FAILED(frame->Initialize(nullptr)) ||
      FAILED(frame->WriteSource(bitmap.Get(), nullptr)) ||
      FAILED(frame->Commit()) || FAILED(encoder->Commit())) {
    return {};
  }
  STATSTG info{};
  if (FAILED(stream->Stat(&info, STATFLAG_NONAME)) ||
      info.cbSize.QuadPart > 256 * 1024) {
    return {};
  }
  LARGE_INTEGER start{};
  if (FAILED(stream->Seek(start, STREAM_SEEK_SET, nullptr))) {
    return {};
  }
  std::vector<uint8_t> bytes(static_cast<size_t>(info.cbSize.QuadPart));
  ULONG read = 0;
  if (FAILED(stream->Read(bytes.data(), static_cast<ULONG>(bytes.size()),
                          &read))) {
    return {};
  }
  bytes.resize(read);
  return bytes;
}

EncodableValue Applications(const std::wstring& extension) {
  EncodableList values;
  if (extension.empty()) {
    return EncodableValue(values);
  }
  ComPtr<IEnumAssocHandlers> handlers;
  Check(SHAssocEnumHandlers(extension.c_str(), ASSOC_FILTER_RECOMMENDED,
                            &handlers));
  std::set<std::wstring> seen;
  ComPtr<IAssocHandler> handler;
  while (handlers->Next(1, &handler, nullptr) == S_OK) {
    const auto id = HandlerName(handler.Get());
    const auto name = HandlerName(handler.Get(), true);
    if (!id.empty() && !name.empty() && !IsViewer(id, name) &&
        seen.insert(Lower(id)).second) {
      EncodableMap app;
      app[EncodableValue("id")] = EncodableValue(Utf8FromUtf16(id.c_str()));
      app[EncodableValue("name")] = EncodableValue(Utf8FromUtf16(name.c_str()));
      const auto icon = HandlerIcon(handler.Get());
      if (!icon.empty()) {
        app[EncodableValue("icon")] = EncodableValue(icon);
      }
      values.emplace_back(app);
    }
    handler.Reset();
    if (values.size() == 8) {
      break;
    }
  }
  return EncodableValue(values);
}

EncodableValue Open(const std::wstring& path, const std::wstring& application) {
  ComPtr<IEnumAssocHandlers> handlers;
  Check(SHAssocEnumHandlers(PathFindExtensionW(path.c_str()),
                            ASSOC_FILTER_RECOMMENDED, &handlers));
  ComPtr<IAssocHandler> handler;
  while (handlers->Next(1, &handler, nullptr) == S_OK) {
    const auto id = HandlerName(handler.Get());
    if (Lower(id) == Lower(application) &&
        !IsViewer(id, HandlerName(handler.Get(), true))) {
      ComPtr<IObjectWithProgID> association;
      Check(handler.As(&association));
      LPWSTR registered = nullptr;
      Check(association->GetProgID(&registered));
      const std::wstring prog_id = registered ? registered : L"";
      CoTaskMemFree(registered);
      if (prog_id.empty()) {
        throw ShellError{HRESULT_FROM_WIN32(ERROR_NO_ASSOCIATION)};
      }
      // Invoke can fall back to OpenWith on Windows 11 despite returning S_OK.
      // Bind the launch to this handler's registration instead of the default.
      SHELLEXECUTEINFOW info{};
      info.cbSize = sizeof(info);
      info.fMask = SEE_MASK_CLASSNAME | SEE_MASK_FLAG_NO_UI | SEE_MASK_NOASYNC;
      info.lpClass = prog_id.c_str();
      info.lpFile = path.c_str();
      info.nShow = SW_SHOWNORMAL;
      if (!ShellExecuteExW(&info)) {
        throw ShellError{HRESULT_FROM_WIN32(GetLastError())};
      }
      return EncodableValue(true);
    }
    handler.Reset();
  }
  throw std::runtime_error(
      "The application is no longer available. Choose another application.");
}

std::string Argument(const EncodableMap& arguments, const char* key) {
  const auto it = arguments.find(EncodableValue(key));
  if (it == arguments.end()) {
    return {};
  }
  const auto* value = std::get_if<std::string>(&it->second);
  return value ? *value : "";
}
}  // namespace

class NativeExternalOpen::Implementation {
 public:
  Implementation(flutter::FlutterEngine* engine, HWND window)
      : window_(window) {
    channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
        engine->messenger(), "shenview/external_open",
        &flutter::StandardMethodCodec::GetInstance());
    worker_ = std::thread([this] { Run(); });
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      const auto* args = call.arguments()
                             ? std::get_if<EncodableMap>(call.arguments())
                             : nullptr;
      if (!args) {
        result->Error("invalid_arguments", "Invalid file arguments");
        return;
      }
      const auto method = call.method_name();
      if (method != "applications" && method != "open" && method != "choose") {
        result->NotImplemented();
        return;
      }
      const auto path = Wide(Argument(*args, "path"));
      if (method == "choose") {
        if (path.empty() ||
            GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES) {
          result->Error("file_missing", "The image no longer exists");
          return;
        }
        OPENASINFO info{};
        info.pcszFile = path.c_str();
        info.oaifInFlags = OAIF_EXEC;
        const HRESULT status = SHOpenWithDialog(window_, &info);
        if (status == HRESULT_FROM_WIN32(ERROR_CANCELLED) ||
            status == E_ABORT) {
          result->Success(EncodableValue(false));
        } else if (FAILED(status)) {
          result->Error("open_failed", "Windows could not open the image",
                        EncodableValue(static_cast<int64_t>(status)));
        } else {
          result->Success(EncodableValue(true));
        }
        return;
      }
      const auto extension = Wide(Argument(*args, "extension"));
      const auto application = Wide(Argument(*args, "application"));
      auto reply = std::shared_ptr<flutter::MethodResult<EncodableValue>>(
          std::move(result));
      {
        std::lock_guard<std::mutex> lock(mutex_);
        tasks_.push([this, method, path, extension, application, reply] {
          std::function<void()> complete;
          try {
            const auto value = method == "applications"
                                   ? Applications(extension)
                                   : Open(path, application);
            complete = [reply, value] { reply->Success(value); };
          } catch (const ShellError& error) {
            const auto code = static_cast<int64_t>(error.code);
            complete = [reply, code] {
              reply->Error("shell_failed",
                           "Windows could not complete the operation",
                           EncodableValue(code));
            };
          } catch (const std::exception& error) {
            const std::string message = error.what();
            complete = [reply, message] {
              reply->Error("open_failed", message);
            };
          }
          {
            std::lock_guard<std::mutex> guard(mutex_);
            completions_.push(std::move(complete));
          }
          PostMessageW(window_, kCompleted, 0, 0);
        });
      }
      ready_.notify_one();
    });
  }

  ~Implementation() {
    channel_->SetMethodCallHandler(nullptr);
    {
      std::lock_guard<std::mutex> lock(mutex_);
      stopping_ = true;
      tasks_ = {};
    }
    ready_.notify_one();
    worker_.join();
  }

  bool HandleMessage(UINT message) {
    if (message != kCompleted) {
      return false;
    }
    std::queue<std::function<void()>> completed;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      completed.swap(completions_);
    }
    while (!completed.empty()) {
      completed.front()();
      completed.pop();
    }
    return true;
  }

 private:
  void Run() {
    const HRESULT initialized =
        CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    for (;;) {
      std::function<void()> task;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        ready_.wait(lock, [this] { return stopping_ || !tasks_.empty(); });
        if (stopping_) {
          break;
        }
        task = std::move(tasks_.front());
        tasks_.pop();
      }
      task();
    }
    if (SUCCEEDED(initialized)) {
      CoUninitialize();
    }
  }
  HWND window_;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel_;
  std::thread worker_;
  std::mutex mutex_;
  std::condition_variable ready_;
  bool stopping_ = false;
  std::queue<std::function<void()>> tasks_;
  std::queue<std::function<void()>> completions_;
};

NativeExternalOpen::NativeExternalOpen(flutter::FlutterEngine* engine,
                                       HWND window)
    : implementation_(std::make_unique<Implementation>(engine, window)) {}
NativeExternalOpen::~NativeExternalOpen() = default;
bool NativeExternalOpen::HandleMessage(UINT message) {
  return implementation_->HandleMessage(message);
}
