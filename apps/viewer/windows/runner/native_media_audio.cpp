#include "native_media_audio.h"
#include <flutter/standard_method_codec.h>

namespace {
int64_t Integer(const flutter::EncodableValue* value) {
  if (value == nullptr) return -1;
  if (const auto* n = std::get_if<int32_t>(value)) return *n;
  if (const auto* n = std::get_if<int64_t>(value)) return *n;
  return -1;
}
}

NativeMediaAudio::NativeMediaAudio(flutter::FlutterEngine* engine) {
  using flutter::EncodableValue;
  using flutter::EncodableMap;
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
    engine->messenger(), "shenview/media_audio", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "open") {
      const auto owner = Integer(call.arguments());
      if (owner < 0) { result->Error("arguments", "Invalid audio owner"); return; }
      Stop();
      WAVEFORMATEX format{};
      format.wFormatTag = WAVE_FORMAT_PCM;
      format.nChannels = 2;
      format.nSamplesPerSec = 48000;
      format.wBitsPerSample = 16;
      format.nBlockAlign = 4;
      format.nAvgBytesPerSec = 192000;
      if (waveOutOpen(&device_, WAVE_MAPPER, &format, 0, 0, CALLBACK_NULL) != MMSYSERR_NOERROR) {
        device_ = nullptr;
        result->Error("audio_device", "Cannot open audio output"); return;
      }
      owner_ = owner;
      result->Success();
    } else if (call.method_name() == "stop") {
      if (Integer(call.arguments()) == owner_) Stop();
      result->Success();
    } else if (call.method_name() == "write") {
      const auto* args = call.arguments() == nullptr ? nullptr : std::get_if<EncodableMap>(call.arguments());
      if (args == nullptr) { result->Error("arguments", "Missing PCM data"); return; }
      const auto id = args->find(EncodableValue("owner"));
      const auto data = args->find(EncodableValue("bytes"));
      if (id == args->end() || Integer(&id->second) != owner_ || device_ == nullptr) {
        result->Error("audio_session", "Audio session has ended"); return;
      }
      const auto* bytes = data == args->end() ? nullptr : std::get_if<std::vector<uint8_t>>(&data->second);
      if (bytes == nullptr || bytes->empty() || bytes->size() > 8192 || bytes->size() % 4 != 0) {
        result->Error("arguments", "Invalid PCM buffer"); return;
      }
      Collect();
      if (queued_ + bytes->size() > 48000) { result->Success(EncodableValue(false)); return; }
      auto buffer = std::make_unique<Buffer>();
      buffer->bytes = *bytes;
      buffer->header.lpData = reinterpret_cast<LPSTR>(buffer->bytes.data());
      buffer->header.dwBufferLength = static_cast<DWORD>(buffer->bytes.size());
      if (waveOutPrepareHeader(device_, &buffer->header, sizeof(WAVEHDR)) != MMSYSERR_NOERROR) {
        result->Error("audio_buffer", "Cannot prepare PCM buffer"); return;
      }
      if (waveOutWrite(device_, &buffer->header, sizeof(WAVEHDR)) != MMSYSERR_NOERROR) {
        waveOutUnprepareHeader(device_, &buffer->header, sizeof(WAVEHDR));
        result->Error("audio_buffer", "Cannot queue PCM buffer"); return;
      }
      queued_ += buffer->bytes.size();
      buffers_.push_back(std::move(buffer));
      result->Success(EncodableValue(true));
    } else if (call.method_name() == "position") {
      Collect();
      MMTIME time{}; time.wType = TIME_SAMPLES;
      if (device_ != nullptr) waveOutGetPosition(device_, &time, sizeof(time));
      result->Success(EncodableValue(EncodableMap{
        {EncodableValue("samples"), EncodableValue(static_cast<int64_t>(time.u.sample))},
        {EncodableValue("queuedBytes"), EncodableValue(static_cast<int64_t>(queued_))}}));
    } else { result->NotImplemented(); }
  });
}

void NativeMediaAudio::Collect() {
  for (auto it = buffers_.begin(); it != buffers_.end();) {
    if ((*it)->header.dwFlags & WHDR_DONE) {
      waveOutUnprepareHeader(device_, &(*it)->header, sizeof(WAVEHDR));
      queued_ -= (*it)->bytes.size();
      it = buffers_.erase(it);
    } else { ++it; }
  }
}
void NativeMediaAudio::Stop() {
  if (device_ != nullptr) {
    waveOutReset(device_);
    for (const auto& buffer : buffers_) waveOutUnprepareHeader(device_, &buffer->header, sizeof(WAVEHDR));
    waveOutClose(device_);
  }
  device_ = nullptr; owner_ = -1; queued_ = 0; buffers_.clear();
}
NativeMediaAudio::~NativeMediaAudio() { Stop(); }
