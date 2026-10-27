#ifndef RUNNER_NATIVE_EXTERNAL_OPEN_H_
#define RUNNER_NATIVE_EXTERNAL_OPEN_H_

#include <flutter/flutter_engine.h>
#include <windows.h>

#include <memory>

class NativeExternalOpen {
 public:
  NativeExternalOpen(flutter::FlutterEngine* engine, HWND window);
  ~NativeExternalOpen();
  bool HandleMessage(UINT message);

 private:
  class Implementation;
  std::unique_ptr<Implementation> implementation_;
};

#endif  // RUNNER_NATIVE_EXTERNAL_OPEN_H_
