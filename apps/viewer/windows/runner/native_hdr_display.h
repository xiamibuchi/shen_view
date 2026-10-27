#ifndef RUNNER_NATIVE_HDR_DISPLAY_H_
#define RUNNER_NATIVE_HDR_DISPLAY_H_
#include <windows.h>
#include <flutter/flutter_engine.h>
#include <memory>

class NativeHdrDisplay {
 public:
  NativeHdrDisplay(flutter::FlutterEngine* engine, HWND view);
  ~NativeHdrDisplay();
  void OnDisplayChanged(bool force);
 private:
  class Implementation;
  std::unique_ptr<Implementation> implementation_;
};
#endif
