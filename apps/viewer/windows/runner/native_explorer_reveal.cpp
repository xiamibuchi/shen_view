#include "native_explorer_reveal.h"

#include <exdisp.h>
#include <shldisp.h>
#include <shlwapi.h>
#include <windows.h>
#include <wrl/client.h>

#include <algorithm>
#include <string>
#include <vector>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#pragma comment(lib, "shlwapi.lib")

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int length = MultiByteToWideChar(
      CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
  if (length <= 0) return {};
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      result.data(), length);
  return result;
}

std::wstring NormalizePath(std::wstring value) {
  while (value.size() > 1 &&
         (value.back() == L'\\' || value.back() == L'/')) {
    value.pop_back();
  }
  std::transform(value.begin(), value.end(), value.begin(), towlower);
  return value;
}

bool SamePath(const std::wstring& left, const std::wstring& right) {
  return NormalizePath(left) == NormalizePath(right);
}

std::wstring LocationUrlToPath(BSTR location_url) {
  if (location_url == nullptr) return {};
  std::vector<wchar_t> buffer(32768);
  DWORD length = static_cast<DWORD>(buffer.size());
  if (FAILED(PathCreateFromUrlW(location_url, buffer.data(), &length, 0))) {
    return {};
  }
  return std::wstring(buffer.data());
}

int ZOrder(HWND target) {
  const HWND foreground = GetForegroundWindow();
  int order = 0;
  for (HWND current = foreground; current != nullptr && order < 4096;
       current = GetWindow(current, GW_HWNDPREV), ++order) {
    if (current == target) return order;
  }
  return INT_MAX;
}

bool FolderWindowMatches(IWebBrowserApp* browser,
                         const std::wstring& target_folder,
                         IShellFolderViewDual** view) {
  ComPtr<IDispatch> document;
  if (FAILED(browser->get_Document(&document))) return false;
  ComPtr<IShellFolderViewDual> folder_view;
  if (FAILED(document.As(&folder_view))) return false;

  ComPtr<Folder> folder;
  if (FAILED(folder_view->get_Folder(&folder))) return false;
  BSTR location_url = nullptr;
  if (FAILED(browser->get_LocationURL(&location_url)) || location_url == nullptr) {
    return false;
  }
  const std::wstring path = LocationUrlToPath(location_url);
  SysFreeString(location_url);
  if (!SamePath(path, target_folder)) return false;
  *view = folder_view.Detach();
  return true;
}

bool RevealInExistingExplorer(const std::wstring& file_path) {
  const size_t separator = file_path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) return false;
  const std::wstring folder_path = file_path.substr(0, separator);
  const std::wstring file_name = file_path.substr(separator + 1);
  if (folder_path.empty() || file_name.empty()) return false;

  ComPtr<IShellWindows> shell_windows;
  if (FAILED(CoCreateInstance(CLSID_ShellWindows, nullptr, CLSCTX_LOCAL_SERVER,
                              IID_PPV_ARGS(&shell_windows)))) {
    return false;
  }
  long count = 0;
  if (FAILED(shell_windows->get_Count(&count))) return false;

  struct Candidate {
    int z_order;
    HWND hwnd;
    ComPtr<IShellFolderViewDual> view;
  };
  std::vector<Candidate> candidates;
  for (long index = 0; index < count; ++index) {
    VARIANT variant;
    VariantInit(&variant);
    V_VT(&variant) = VT_I4;
    V_I4(&variant) = index;
    ComPtr<IDispatch> dispatch;
    const HRESULT item_result = shell_windows->Item(variant, &dispatch);
    VariantClear(&variant);
    if (FAILED(item_result) || dispatch == nullptr) continue;

    ComPtr<IWebBrowserApp> browser;
    if (FAILED(dispatch.As(&browser))) continue;
    SHANDLE_PTR hwnd_value = 0;
    if (FAILED(browser->get_HWND(&hwnd_value))) continue;
    ComPtr<IShellFolderViewDual> view;
    if (!FolderWindowMatches(browser.Get(), folder_path, &view)) continue;
    const HWND hwnd = reinterpret_cast<HWND>(static_cast<INT_PTR>(hwnd_value));
    candidates.push_back({ZOrder(hwnd), hwnd, std::move(view)});
  }
  if (candidates.empty()) return false;
  std::sort(candidates.begin(), candidates.end(),
            [](const Candidate& left, const Candidate& right) {
              return left.z_order < right.z_order;
            });

  const Candidate& candidate = candidates.front();
  if (IsIconic(candidate.hwnd)) ShowWindow(candidate.hwnd, SW_RESTORE);
  SetForegroundWindow(candidate.hwnd);

  ComPtr<Folder> folder;
  if (FAILED(candidate.view->get_Folder(&folder))) return false;
  BSTR name_bstr = SysAllocString(file_name.c_str());
  if (name_bstr == nullptr) return false;
  ComPtr<FolderItem> item;
  const HRESULT parse_result = folder->ParseName(name_bstr, &item);
  SysFreeString(name_bstr);
  if (FAILED(parse_result) || item == nullptr) return false;

  VARIANT item_variant;
  VariantInit(&item_variant);
  V_VT(&item_variant) = VT_DISPATCH;
  V_DISPATCH(&item_variant) = item.Get();
  item->AddRef();
  const HRESULT select_result = candidate.view->SelectItem(&item_variant, 29);
  VariantClear(&item_variant);
  return SUCCEEDED(select_result);
}

}  // namespace

class NativeExplorerReveal::Implementation {
 public:
  explicit Implementation(flutter::FlutterEngine* engine) {
    channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
        engine->messenger(), "shenview/explorer_reveal",
        &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() != "reveal") {
        result->NotImplemented();
        return;
      }
      const auto* arguments = call.arguments() == nullptr
                                  ? nullptr
                                  : std::get_if<EncodableMap>(call.arguments());
      if (arguments == nullptr) {
        result->Error("invalid_arguments", "文件路径无效");
        return;
      }
      const auto path = arguments->find(EncodableValue("path"));
      if (path == arguments->end()) {
        result->Error("invalid_arguments", "文件路径无效");
        return;
      }
      const auto* path_value = std::get_if<std::string>(&path->second);
      if (path_value == nullptr || path_value->empty()) {
        result->Error("invalid_arguments", "文件路径无效");
        return;
      }
      result->Success(EncodableValue(
          RevealInExistingExplorer(Utf8ToWide(*path_value))));
    });
  }

  ~Implementation() { channel_->SetMethodCallHandler(nullptr); }

 private:
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel_;
};

NativeExplorerReveal::NativeExplorerReveal(flutter::FlutterEngine* engine)
    : implementation_(std::make_unique<Implementation>(engine)) {}

NativeExplorerReveal::~NativeExplorerReveal() = default;
