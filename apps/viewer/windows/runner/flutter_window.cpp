#include "flutter_window.h"

#include <optional>
#include <filesystem>
#include <flutter/standard_method_codec.h>
#include <commctrl.h>

#pragma comment(lib, "imm32.lib")
#pragma comment(lib, "comctl32.lib")

#include "flutter/generated_plugin_registrant.h"


FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  native_external_open_ = std::make_unique<NativeExternalOpen>(
      flutter_controller_->engine(), GetHandle());
  native_media_audio_ = std::make_unique<NativeMediaAudio>(flutter_controller_->engine());
  native_file_associations_ =
      std::make_unique<NativeFileAssociations>(flutter_controller_->engine());
  material_effects_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "shenview/material_effects",
      &flutter::StandardMethodCodec::GetInstance());
  material_effects_->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() != "enabled") {
      result->NotImplemented();
      return;
    }
    DWORD transparency = 1, bytes = sizeof(transparency);
    RegGetValueW(HKEY_CURRENT_USER,
                 LR"(Software\Microsoft\Windows\CurrentVersion\Themes\Personalize)",
                 L"EnableTransparency", RRF_RT_REG_DWORD, nullptr,
                 &transparency, &bytes);
    HIGHCONTRASTW contrast{};
    contrast.cbSize = sizeof(contrast);
    SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast), &contrast, 0);
    SYSTEM_POWER_STATUS power{};
    const bool saving = GetSystemPowerStatus(&power) && (power.SystemStatusFlag & 1);
    result->Success(flutter::EncodableValue(
        transparency != 0 && !(contrast.dwFlags & HCF_HIGHCONTRASTON) && !saving));
  });
  app_instance_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "shenview/app_instance",
      &flutter::StandardMethodCodec::GetInstance());
  app_instance_->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() != "allowActivation" || call.arguments() == nullptr) {
      result->NotImplemented();
      return;
    }
    const auto* process_id = std::get_if<int32_t>(call.arguments());
    if (process_id != nullptr && *process_id > 0) {
      // Transfer the shell's foreground right specifically to the viewer.
      AllowSetForegroundWindow(static_cast<DWORD>(*process_id));
    }
    result->Success();
  });
  system_resources_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "shenview/system_resources",
      &flutter::StandardMethodCodec::GetInstance());
  system_resources_->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() != "read") {
      result->NotImplemented();
      return;
    }
    using flutter::EncodableMap;
    using flutter::EncodableValue;
    EncodableMap response;
    MEMORYSTATUSEX memory{};
    memory.dwLength = sizeof(memory);
    if (GlobalMemoryStatusEx(&memory)) {
      response[EncodableValue("physicalMemoryBytes")] = EncodableValue(static_cast<int64_t>(memory.ullTotalPhys));
      response[EncodableValue("availableMemoryBytes")] = EncodableValue(static_cast<int64_t>(memory.ullAvailPhys));
    }
    const auto* args = call.arguments() == nullptr ? nullptr : std::get_if<EncodableMap>(call.arguments());
    if (args != nullptr) {
      const auto item = args->find(EncodableValue("diskPath"));
      if (item != args->end()) {
        const auto* path = std::get_if<std::string>(&item->second);
        if (path != nullptr && !path->empty()) {
          std::error_code error;
          auto directory = std::filesystem::u8path(*path);
          // Cache roots may not exist on the first read. Use the nearest
          // existing directory on the same volume; never query the working drive.
          while (!directory.empty() && !std::filesystem::is_directory(directory, error)) {
            const auto parent = directory.parent_path();
            if (parent == directory) break;
            directory = parent;
            error.clear();
          }
          ULARGE_INTEGER available{}, capacity{}, free{};
          if (!directory.empty() && GetDiskFreeSpaceExW(directory.c_str(), &available, &capacity, &free)) {
            response[EncodableValue("availableDiskBytes")] = EncodableValue(static_cast<int64_t>(available.QuadPart));
            response[EncodableValue("diskCapacityBytes")] = EncodableValue(static_cast<int64_t>(capacity.QuadPart));
          }
        }
      }
    }
    result->Success(EncodableValue(std::move(response)));
  });
  native_image_decoder_ =
      std::make_unique<NativeImageDecoder>(flutter_controller_->engine());
  native_explorer_reveal_ =
      std::make_unique<NativeExplorerReveal>(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  native_hdr_display_ = std::make_unique<NativeHdrDisplay>(
      flutter_controller_->engine(), flutter_controller_->view()->GetNativeWindow());
  const HWND view = flutter_controller_->view()->GetNativeWindow();
  window_ime_context_ = ImmGetContext(GetHandle());
  if (window_ime_context_ != nullptr) {
    ImmReleaseContext(GetHandle(), window_ime_context_);
  }
  view_ime_context_ = ImmGetContext(view);
  if (view_ime_context_ != nullptr) {
    ImmReleaseContext(view, view_ime_context_);
  }
  text_input_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "shenview/text_input",
      &flutter::StandardMethodCodec::GetInstance());
  text_input_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "setEnabled") {
      result->NotImplemented();
      return;
    }
    const auto* enabled = call.arguments() == nullptr
        ? nullptr : std::get_if<bool>(call.arguments());
    if (enabled == nullptr) {
      result->Error("invalid_arguments", "Expected a text-input enabled flag.");
      return;
    }
    SetTextInputEnabled(*enabled);
    result->Success();
  });
  // Dart restores these associations only while an editable field owns focus.
  SetWindowSubclass(GetHandle(), TextInputWindowProc, 1,
                    reinterpret_cast<DWORD_PTR>(this));
  SetWindowSubclass(view, TextInputWindowProc, 1,
                    reinterpret_cast<DWORD_PTR>(this));
  SetTextInputEnabled(false);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  native_external_open_.reset();
  native_media_audio_.reset();
  text_input_.reset();
  if (GetHandle()) {
    RemoveWindowSubclass(GetHandle(), TextInputWindowProc, 1);
  }
  if (flutter_controller_ && flutter_controller_->view()) {
    RemoveWindowSubclass(flutter_controller_->view()->GetNativeWindow(),
                         TextInputWindowProc, 1);
    SetTextInputEnabled(true);
  }
  app_instance_.reset();
  material_effects_.reset();
  system_resources_.reset();
  native_hdr_display_.reset();
  native_image_decoder_.reset();
  native_explorer_reveal_.reset();
  native_file_associations_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetTextInputEnabled(bool enabled) {
  text_input_enabled_ = enabled;
  const HWND view = flutter_controller_->view()->GetNativeWindow();
  if (enabled) {
    ImmAssociateContext(GetHandle(), window_ime_context_);
    ImmAssociateContext(view, view_ime_context_);
  } else {
    EnforceTextInputPolicy();
  }
}

void FlutterWindow::EnforceTextInputPolicy() {
  EnforceTextInputPolicy(GetHandle());
  if (flutter_controller_ && flutter_controller_->view()) {
    EnforceTextInputPolicy(flutter_controller_->view()->GetNativeWindow());
  }
}

void FlutterWindow::EnforceTextInputPolicy(HWND window) {
  if (text_input_enabled_ || updating_ime_ || !IsWindow(window)) return;
  updating_ime_ = true;
  const HIMC context = ImmGetContext(window);
  if (context != nullptr) {
    // Detaching alone can leave an already visible candidates window behind.
    ImmNotifyIME(context, NI_COMPOSITIONSTR, CPS_CANCEL, 0);
    ImmNotifyIME(context, NI_CLOSECANDIDATE, 0, 0);
    ImmReleaseContext(window, context);
    ImmAssociateContext(window, nullptr);
  }
  updating_ime_ = false;
}

LRESULT CALLBACK FlutterWindow::TextInputWindowProc(
    HWND window, UINT message, WPARAM wparam, LPARAM lparam,
    UINT_PTR subclass_id, DWORD_PTR data) {
  auto* self = reinterpret_cast<FlutterWindow*>(data);
  if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(window, TextInputWindowProc, subclass_id);
    return DefSubclassProc(window, message, wparam, lparam);
  }
  const bool key_message = message == WM_KEYDOWN || message == WM_KEYUP ||
      message == WM_SYSKEYDOWN || message == WM_SYSKEYUP;
  if (key_message && !self->text_input_enabled_) {
    // A key already translated by the old IME can still be queued when focus
    // returns to the canvas. Recover its virtual key from the original scan code.
    if (wparam == VK_PROCESSKEY) {
      UINT scan = (static_cast<UINT_PTR>(lparam) >> 16) & 0xff;
      if ((lparam & (1 << 24)) != 0) scan |= 0xe000;
      UINT key = MapVirtualKeyW(scan, MAPVK_VSC_TO_VK_EX);
      if (key == 0) key = ImmGetVirtualKey(window);
      if (key != 0 && key != VK_PROCESSKEY) wparam = key;
    }
    self->EnforceTextInputPolicy();
  }
  const bool input_transition = message == WM_SETFOCUS ||
      message == WM_KILLFOCUS || message == WM_INPUTLANGCHANGE ||
      message == WM_IME_SETCONTEXT || message == WM_IME_NOTIFY ||
      message == WM_IME_STARTCOMPOSITION;
  if (input_transition) {
    self->EnforceTextInputPolicy();
    if (!self->text_input_enabled_ && message == WM_IME_SETCONTEXT) {
      lparam = 0;  // Do not show a composition/candidates UI on the canvas.
    }
    if (!self->text_input_enabled_ && message == WM_IME_STARTCOMPOSITION) {
      return 0;
    }
  }
  const LRESULT result = DefSubclassProc(window, message, wparam, lparam);
  // Default/Flutter handling can re-associate an IME while processing focus or
  // language changes. Enforce the policy after that handling as well.
  if (input_transition) self->EnforceTextInputPolicy();
  return result;
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (native_external_open_ && native_external_open_->HandleMessage(message)) {
    return 0;
  }
  if (material_effects_ &&
      (message == WM_SETTINGCHANGE || message == WM_POWERBROADCAST ||
       message == WM_THEMECHANGED)) {
    material_effects_->InvokeMethod("changed", nullptr);
  }
  if (native_hdr_display_) {
    if (message == WM_DISPLAYCHANGE || message == WM_DEVICECHANGE) {
      native_hdr_display_->OnDisplayChanged(true);
    } else if (message == WM_WINDOWPOSCHANGED) {
      native_hdr_display_->OnDisplayChanged(false);
    }
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
