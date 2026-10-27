#ifndef RUNNER_NATIVE_EXPLORER_REVEAL_H_
#define RUNNER_NATIVE_EXPLORER_REVEAL_H_

#include <flutter/flutter_engine.h>

#include <memory>

class NativeExplorerReveal {
 public:
  explicit NativeExplorerReveal(flutter::FlutterEngine* engine);
  ~NativeExplorerReveal();
  NativeExplorerReveal(const NativeExplorerReveal&) = delete;
  NativeExplorerReveal& operator=(const NativeExplorerReveal&) = delete;

 private:
  class Implementation;
  std::unique_ptr<Implementation> implementation_;
};

#endif  // RUNNER_NATIVE_EXPLORER_REVEAL_H_
