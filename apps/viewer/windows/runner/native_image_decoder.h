#ifndef RUNNER_NATIVE_IMAGE_DECODER_H_
#define RUNNER_NATIVE_IMAGE_DECODER_H_

#include <flutter/flutter_engine.h>
#include <memory>

class NativeImageDecoder {
 public:
  explicit NativeImageDecoder(flutter::FlutterEngine* engine);
  ~NativeImageDecoder();
  NativeImageDecoder(const NativeImageDecoder&) = delete;
  NativeImageDecoder& operator=(const NativeImageDecoder&) = delete;

 private:
  class Implementation;
  std::unique_ptr<Implementation> implementation_;
};

#endif
