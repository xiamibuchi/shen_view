#pragma once
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <windows.h>
#include <mmsystem.h>
#include <memory>
#include <list>
#include <vector>

class NativeMediaAudio {
 public:
  explicit NativeMediaAudio(flutter::FlutterEngine* engine);
  ~NativeMediaAudio();
 private:
  struct Buffer { WAVEHDR header{}; std::vector<uint8_t> bytes; };
  void Stop();
  void Collect();
  HWAVEOUT device_ = nullptr;
  int64_t owner_ = -1;
  size_t queued_ = 0;
  std::list<std::unique_ptr<Buffer>> buffers_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
