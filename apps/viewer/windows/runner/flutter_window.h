#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>

#include <memory>
#include <imm.h>

#include "win32_window.h"
#include "native_image_decoder.h"
#include "native_hdr_display.h"
#include "native_explorer_reveal.h"
#include "native_file_associations.h"
#include "native_external_open.h"
#include "native_media_audio.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void SetTextInputEnabled(bool enabled);
  void EnforceTextInputPolicy();
  void EnforceTextInputPolicy(HWND window);
  static LRESULT CALLBACK TextInputWindowProc(HWND window, UINT message,
      WPARAM wparam, LPARAM lparam, UINT_PTR subclass_id, DWORD_PTR data);
  bool text_input_enabled_ = false;
  bool updating_ime_ = false;
  HIMC window_ime_context_ = nullptr;
  HIMC view_ime_context_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> text_input_;

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<NativeImageDecoder> native_image_decoder_;
  std::unique_ptr<NativeMediaAudio> native_media_audio_;
  std::unique_ptr<NativeHdrDisplay> native_hdr_display_;
  std::unique_ptr<NativeExplorerReveal> native_explorer_reveal_;
  std::unique_ptr<NativeFileAssociations> native_file_associations_;
  std::unique_ptr<NativeExternalOpen> native_external_open_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> system_resources_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> app_instance_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> material_effects_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
