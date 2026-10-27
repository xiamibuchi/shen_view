#ifndef RUNNER_NATIVE_FILE_ASSOCIATIONS_H_
#define RUNNER_NATIVE_FILE_ASSOCIATIONS_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <optional>
#include <string>
#include <vector>

class NativeFileAssociations {
 public:
  explicit NativeFileAssociations(flutter::FlutterEngine* engine);
  static std::optional<int> HandleCommand(const std::vector<std::string>& args);

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif
