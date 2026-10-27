#include "native_image_decoder.h"
#include "native_decode_queue.h"

#include <windows.h>
#include <wincodec.h>
#include <propvarutil.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <wrl/client.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <condition_variable>
#include <deque>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {
using Microsoft::WRL::ComPtr;
using flutter::EncodableMap;
using flutter::EncodableValue;
constexpr UINT kCompletionMessage = WM_APP + 73;
constexpr double kMaxPixels = 16.0 * 1024 * 1024;
constexpr double kMaxFloatPixels = 4.0 * 1024 * 1024;
thread_local bool decoderComInitialized = false;

double Number(const EncodableMap& values, const char* key) {
  const auto item = values.find(EncodableValue(key));
  if (item == values.end()) return 0;
  if (const auto* value = std::get_if<double>(&item->second)) return *value;
  if (const auto* value = std::get_if<int32_t>(&item->second)) return *value;
  if (const auto* value = std::get_if<int64_t>(&item->second)) return static_cast<double>(*value);
  return 0;
}

int64_t Integer(const EncodableMap& values, const char* key, int64_t fallback = 0) {
  const auto item = values.find(EncodableValue(key));
  if (item == values.end()) return fallback;
  if (const auto* value = std::get_if<int32_t>(&item->second)) return *value;
  if (const auto* value = std::get_if<int64_t>(&item->second)) return *value;
  return fallback;
}

bool Boolean(const EncodableMap& values, const char* key) {
  const auto item = values.find(EncodableValue(key));
  if (item == values.end()) return false;
  if (const auto* value = std::get_if<bool>(&item->second)) return *value;
  return false;
}

std::wstring ToWide(const std::string& value) {
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), size);
  return result;
}

UINT Orientation(IWICBitmapFrameDecode* frame) {
  ComPtr<IWICMetadataQueryReader> reader;
  if (FAILED(frame->GetMetadataQueryReader(&reader))) return 1;
  for (const auto* query : {L"/app1/ifd/{ushort=274}", L"/ifd/{ushort=274}"}) {
    PROPVARIANT value;
    PropVariantInit(&value);
    const HRESULT status = reader->GetMetadataByName(query, &value);
    const UINT orientation = value.vt == VT_UI2 ? value.uiVal : 1;
    PropVariantClear(&value);
    if (SUCCEEDED(status) && orientation >= 1 && orientation <= 8) return orientation;
  }
  return 1;
}

EncodableValue Decode(const EncodableMap& arguments, bool metadata, const std::atomic<bool>& cancelled) {
  const auto pathItem = arguments.find(EncodableValue("path"));
  if (pathItem == arguments.end()) return {};
  const auto* path = std::get_if<std::string>(&pathItem->second);
  if (path == nullptr || cancelled.load()) return {};
  const bool preserveHdr = Boolean(arguments, "preserveHdr");
  ComPtr<IWICImagingFactory> factory;
  ComPtr<IWICBitmapDecoder> decoder;
  ComPtr<IWICBitmapFrameDecode> frame;
  if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)))) return {};
  if (FAILED(factory->CreateDecoderFromFilename(ToWide(*path).c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand, &decoder))) return {};
  if (cancelled.load()) return {};
  if (FAILED(decoder->GetFrame(0, &frame)) || cancelled.load()) return {};
  UINT sourceWidth = 0;
  UINT sourceHeight = 0;
  if (FAILED(frame->GetSize(&sourceWidth, &sourceHeight)) || sourceWidth == 0 || sourceHeight == 0) return {};
  const UINT orientation = Orientation(frame.Get());
  if (cancelled.load()) return {};
  if (metadata) {
    EncodableMap response{
      {EncodableValue("width"), EncodableValue(static_cast<int32_t>(sourceWidth))},
      {EncodableValue("height"), EncodableValue(static_cast<int32_t>(sourceHeight))},
      {EncodableValue("orientation"), EncodableValue(static_cast<int32_t>(orientation))},
    };
    return EncodableValue(std::move(response));
  }
  ComPtr<IWICBitmapSource> source = frame;
  ComPtr<IWICBitmapFlipRotator> rotator;
  if (orientation != 1) {
    const WICBitmapTransformOptions options[] = {
      WICBitmapTransformRotate0, WICBitmapTransformRotate0,
      WICBitmapTransformFlipHorizontal, WICBitmapTransformRotate180,
      WICBitmapTransformFlipVertical,
      static_cast<WICBitmapTransformOptions>(WICBitmapTransformRotate90 | WICBitmapTransformFlipHorizontal),
      WICBitmapTransformRotate90,
      static_cast<WICBitmapTransformOptions>(WICBitmapTransformRotate270 | WICBitmapTransformFlipHorizontal),
      WICBitmapTransformRotate270,
    };
    if (FAILED(factory->CreateBitmapFlipRotator(&rotator)) || FAILED(rotator->Initialize(source.Get(), options[orientation]))) return {};
    source = rotator;
  }
  if (FAILED(source->GetSize(&sourceWidth, &sourceHeight))) return {};
  if (cancelled.load()) return {};
  ComPtr<IWICBitmapClipper> clipper;
  const auto regionItem = arguments.find(EncodableValue("region"));
  if (regionItem != arguments.end()) {
    const auto* region = std::get_if<EncodableMap>(&regionItem->second);
    if (region == nullptr) return {};
    const int64_t left = Integer(*region, "left");
    const int64_t top = Integer(*region, "top");
    const int64_t width = Integer(*region, "width");
    const int64_t height = Integer(*region, "height");
    if (left < 0 || top < 0 || width <= 0 || height <= 0 || left + width > sourceWidth || top + height > sourceHeight) return {};
    WICRect rect{static_cast<INT>(left), static_cast<INT>(top), static_cast<INT>(width), static_cast<INT>(height)};
    if (FAILED(factory->CreateBitmapClipper(&clipper)) || FAILED(clipper->Initialize(source.Get(), &rect))) return {};
    source = clipper;
    sourceWidth = static_cast<UINT>(width);
    sourceHeight = static_cast<UINT>(height);
  }
  const double pixelBudget = preserveHdr ? kMaxFloatPixels : kMaxPixels;
  double ratio = std::min(1.0, std::sqrt(pixelBudget / (static_cast<double>(sourceWidth) * sourceHeight)));
  const int64_t targetWidth = Integer(arguments, "targetWidth");
  const int64_t targetHeight = Integer(arguments, "targetHeight");
  if (targetWidth > 0) ratio = std::min(ratio, static_cast<double>(targetWidth) / sourceWidth);
  if (targetHeight > 0) ratio = std::min(ratio, static_cast<double>(targetHeight) / sourceHeight);
  const UINT width = std::max(1U, static_cast<UINT>(sourceWidth * ratio));
  const UINT height = std::max(1U, static_cast<UINT>(sourceHeight * ratio));
  ComPtr<IWICBitmapScaler> scaler;
  if (width != sourceWidth || height != sourceHeight) {
    if (FAILED(factory->CreateBitmapScaler(&scaler)) || FAILED(scaler->Initialize(source.Get(), width, height, WICBitmapInterpolationModeFant))) return {};
    source = scaler;
  }
  // WIC's pixel-format converter alone does not apply an embedded ICC
  // profile. Normalize tagged SDR pixels through the OS color transform
  // before handing a premultiplied sRGB bitmap to Flutter. Bad profiles keep
  // the regular decoder path working; no global display settings are changed.
  ComPtr<IWICColorTransform> colorTransform;
  if (cancelled.load()) return {};
  if (!preserveHdr) {
    UINT count = 0;
    if (SUCCEEDED(frame->GetColorContexts(0, nullptr, &count)) && count > 0 && count <= 16) {
      std::vector<ComPtr<IWICColorContext>> contexts(count);
      std::vector<IWICColorContext*> pointers(count);
      bool allocated = true;
      for (UINT i = 0; i < count; ++i) {
        if (FAILED(factory->CreateColorContext(&contexts[i]))) { allocated = false; break; }
        pointers[i] = contexts[i].Get();
      }
      UINT actual = 0;
      if (allocated && SUCCEEDED(frame->GetColorContexts(count, pointers.data(), &actual))) {
        ComPtr<IWICColorContext> destination;
        if (SUCCEEDED(factory->CreateColorContext(&destination)) &&
            SUCCEEDED(destination->InitializeFromExifColorSpace(1))) {
          for (UINT i = 0; i < std::min(count, actual); ++i) {
            if (cancelled.load()) return {};
            WICColorContextType type = WICColorContextUninitialized;
            if (FAILED(contexts[i]->GetType(&type)) || type == WICColorContextUninitialized) continue;
            if (SUCCEEDED(factory->CreateColorTransformer(&colorTransform)) &&
                SUCCEEDED(colorTransform->Initialize(source.Get(), contexts[i].Get(),
                    destination.Get(), GUID_WICPixelFormat32bppPRGBA))) {
              source = colorTransform; break;
            }
            colorTransform.Reset();
          }
        }
      }
    }
  }
  ComPtr<IWICFormatConverter> converter;
  if (cancelled.load()) return {};
  bool outputFloat = preserveHdr;
  const GUID outputPixelFormat = outputFloat
      ? GUID_WICPixelFormat128bppPRGBAFloat
      : GUID_WICPixelFormat32bppPRGBA;
  if (FAILED(factory->CreateFormatConverter(&converter))) return {};
  auto conversion = converter->Initialize(
      source.Get(), outputPixelFormat, WICBitmapDitherTypeNone, nullptr, 0,
      WICBitmapPaletteTypeCustom);
  if (FAILED(conversion) && outputFloat) {
    // Older WIC codecs expose HDR frames but cannot convert them to a float
    // bitmap. Fall back to an 8-bit frame instead of making the image fail.
    outputFloat = false;
    converter.Reset();
    if (FAILED(factory->CreateFormatConverter(&converter))) return {};
    conversion = converter->Initialize(
        source.Get(), GUID_WICPixelFormat32bppPRGBA, WICBitmapDitherTypeNone,
        nullptr, 0, WICBitmapPaletteTypeCustom);
  }
  if (FAILED(conversion)) return {};
  if (cancelled.load()) return {};
  const UINT bytesPerPixel = outputFloat ? 16 : 4;
  const UINT stride = width * bytesPerPixel;
  std::vector<uint8_t> pixels(static_cast<size_t>(stride) * height);
  if (FAILED(converter->CopyPixels(nullptr, stride, static_cast<UINT>(pixels.size()), pixels.data())) || cancelled.load()) return {};
  EncodableMap response;
  response[EncodableValue("width")] = EncodableValue(static_cast<int32_t>(width));
  response[EncodableValue("height")] = EncodableValue(static_cast<int32_t>(height));
  response[EncodableValue("pixels")] = EncodableValue(std::move(pixels));
  response[EncodableValue("pixelFormat")] = EncodableValue(
      outputFloat ? "rgbaFloat32" : "rgba8888");
  return EncodableValue(std::move(response));
}
}

class NativeImageDecoder::Implementation {
  struct Payload {
    EncodableMap arguments;
    bool metadata = false;
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result;
    EncodableValue decoded;
  };
  using Queue = NativeDecodeQueue<Payload>;
  using Job = Queue::Job;

 public:
  explicit Implementation(flutter::FlutterEngine* engine) {
    WNDCLASSW windowClass{};
    windowClass.hInstance = GetModuleHandle(nullptr);
    windowClass.lpszClassName = L"ShenViewDecoderCompletion";
    windowClass.lpfnWndProc = WindowProcedure;
    RegisterClassW(&windowClass);
    window_ = CreateWindowW(windowClass.lpszClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, windowClass.hInstance, this);
    queue_ = std::make_unique<Queue>(
      [](const Job& task) {
        try {
          task->payload.decoded = Decode(task->payload.arguments, task->payload.metadata, task->cancelled);
        } catch (...) {
          task->payload.decoded = EncodableValue();
        }
      },
      [this](const Job& task) {
        {
          std::lock_guard<std::mutex> lock(completionMutex_);
          completed_.push_back(task);
        }
        PostMessage(window_, kCompletionMessage, 0, 0);
      },
      [] { decoderComInitialized = SUCCEEDED(CoInitializeEx(nullptr, COINIT_MULTITHREADED)); },
      [] { if (decoderComInitialized) CoUninitialize(); });
    channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(engine->messenger(), "shenview/native_decoder", &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      const auto* arguments = call.arguments() == nullptr ? nullptr : std::get_if<EncodableMap>(call.arguments());
      if (arguments == nullptr) {
        result->Error("invalid_arguments", "图片路径无效");
        return;
      }
      if (call.method_name() == "cancel") {
        queue_->Cancel(Integer(*arguments, "requestId"));
        result->Success();
        return;
      }
      if (call.method_name() == "updatePriority") {
        queue_->UpdatePriority(Integer(*arguments, "requestId"),
            static_cast<int>(Integer(*arguments, "priority")), Number(*arguments, "distance"));
        result->Success();
        return;
      }
      if (call.method_name() != "decode" && call.method_name() != "metadata") {
        result->NotImplemented();
        return;
      }
      auto task = std::make_shared<Queue::Task>();
      task->payload.arguments = *arguments;
      task->payload.metadata = call.method_name() == "metadata";
      task->payload.result = std::move(result);
      task->id = Integer(*arguments, "requestId", --metadataId_);
      task->priority = static_cast<int>(Integer(*arguments, "priority", task->payload.metadata ? 5 : 0));
      task->distance = Number(*arguments, "distance");
      queue_->Enqueue(task);
    });
  }

  ~Implementation() {
    channel_->SetMethodCallHandler(nullptr);
    queue_->Stop();
    DestroyWindow(window_);
  }

 private:
  static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == WM_NCCREATE) {
      const auto* creation = reinterpret_cast<CREATESTRUCTW*>(lparam);
      SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(creation->lpCreateParams));
    }
    auto* instance = reinterpret_cast<Implementation*>(GetWindowLongPtr(window, GWLP_USERDATA));
    if (message == kCompletionMessage && instance != nullptr) {
      instance->Complete();
      return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
  }

  void Complete() {
    std::deque<Job> completed;
    {
      std::lock_guard<std::mutex> lock(completionMutex_);
      completed.swap(completed_);
    }
    for (const auto& task : completed) {
      queue_->Acknowledge(task->id);
      if (task->cancelled.load()) task->payload.result->Error("cancelled", "解码已取消");
      else if (task->payload.decoded.IsNull()) task->payload.result->Success();
      else task->payload.result->Success(task->payload.decoded);
    }
  }

  HWND window_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel_;
  std::unique_ptr<Queue> queue_;
  std::mutex completionMutex_;
  int64_t metadataId_ = 0;
  std::deque<Job> completed_;
};

NativeImageDecoder::NativeImageDecoder(flutter::FlutterEngine* engine)
    : implementation_(std::make_unique<Implementation>(engine)) {}
NativeImageDecoder::~NativeImageDecoder() = default;
