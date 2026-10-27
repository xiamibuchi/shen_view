#include "native_hdr_display.h"

#include <d3d11.h>
#include <d3dcompiler.h>
#include <dcomp.h>
#include <dxgi1_6.h>
#include <DirectXPackedVector.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <wrl/client.h>
#include <algorithm>
#include <cmath>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
using Microsoft::WRL::ComPtr;
using flutter::EncodableMap;
using flutter::EncodableValue;
constexpr auto kColorSpace = DXGI_COLOR_SPACE_RGB_FULL_G10_NONE_P709;
constexpr size_t kMaxPixels = 4 * 1024 * 1024;
constexpr size_t kTotalPixels = 8 * 1024 * 1024;

void Check(HRESULT status) {
  if (FAILED(status)) throw std::runtime_error("HDR graphics operation failed");
}
const EncodableValue* Value(const EncodableMap& args, const char* key) {
  const auto item = args.find(EncodableValue(key));
  return item == args.end() ? nullptr : &item->second;
}
int64_t Integer(const EncodableMap& args, const char* key) {
  const auto* v = Value(args, key);
  if (v) {
    if (const auto* n = std::get_if<int32_t>(v)) return *n;
    if (const auto* n = std::get_if<int64_t>(v)) return *n;
  }
  return 0;
}
bool Boolean(const EncodableMap& args, const char* key) {
  const auto* v = Value(args, key);
  return v && std::holds_alternative<bool>(*v) && std::get<bool>(*v);
}
// 1 scRGB unit is 80 cd/m2, as defined by Windows Advanced Color.
// Untagged scene-linear EXR/HDR has no mastering white: choose 203 cd/m2.
constexpr char kShader[] = R"(
Texture2D<float4> image : register(t0);
SamplerState sampleState : register(s0);
cbuffer HdrParams : register(b0) { float scale; float peak; float contentPeak; float padding; };
struct Vertex { float4 position : SV_POSITION; float2 uv : TEXCOORD0; };
Vertex vs(uint id : SV_VertexID) {
  Vertex v;
  v.uv = float2((id << 1) & 2, id & 2);
  v.position = float4(v.uv * float2(2, -2) + float2(-1, 1), 0, 1);
  return v;
}
float4 ps(Vertex v) : SV_TARGET {
  float4 pixel = image.Sample(sampleState, v.uv);
  float3 rgb = pixel.a > 0 ? pixel.rgb / pixel.a : 0;
  float maximum = max(max(rgb.r, rgb.g), rgb.b);
  float start = min(1.0, peak * 0.75);
  if (contentPeak > peak && maximum > start) {
    float distance = maximum - start;
    float range = peak - start;
    rgb *= (start + range * distance / (range + distance)) / maximum;
  }
  return float4(clamp(rgb * (scale * pixel.a), -65504.0, 65504.0), pixel.a);
}
)";

// Uses the exact production shader and an FP16 render target. This runs
// offscreen even on SDR test machines; it does not claim HDR monitor output.
double VerifyFloatPipeline(float alpha = 1.0f, float* resultAlpha = nullptr, float headroom = 0) {
  ComPtr<ID3D11Device> device;
  ComPtr<ID3D11DeviceContext> context;
  Check(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, 0, nullptr, 0,
      D3D11_SDK_VERSION, &device, nullptr, &context));
  ComPtr<ID3DBlob> vs, ps, errors;
  Check(D3DCompile(kShader, sizeof(kShader) - 1, nullptr, nullptr, nullptr, "vs", "vs_4_0",
      0, 0, &vs, &errors));
  Check(D3DCompile(kShader, sizeof(kShader) - 1, nullptr, nullptr, nullptr, "ps", "ps_4_0",
      0, 0, &ps, &errors));
  ComPtr<ID3D11VertexShader> vertexShader; ComPtr<ID3D11PixelShader> pixelShader;
  Check(device->CreateVertexShader(vs->GetBufferPointer(), vs->GetBufferSize(), nullptr, &vertexShader));
  Check(device->CreatePixelShader(ps->GetBufferPointer(), ps->GetBufferSize(), nullptr, &pixelShader));
  D3D11_TEXTURE2D_DESC desc{};
  desc.Width = desc.Height = desc.MipLevels = desc.ArraySize = desc.SampleDesc.Count = 1;
  desc.Format = DXGI_FORMAT_R32G32B32A32_FLOAT;
  desc.Usage = D3D11_USAGE_IMMUTABLE; desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
  const float input[] = {8 * alpha, 4 * alpha, 2 * alpha, alpha};
  D3D11_SUBRESOURCE_DATA data{}; data.pSysMem = input; data.SysMemPitch = sizeof(input);
  ComPtr<ID3D11Texture2D> source; Check(device->CreateTexture2D(&desc, &data, &source));
  ComPtr<ID3D11ShaderResourceView> image;
  Check(device->CreateShaderResourceView(source.Get(), nullptr, &image));
  desc.Format = DXGI_FORMAT_R16G16B16A16_FLOAT; desc.Usage = D3D11_USAGE_DEFAULT;
  desc.BindFlags = D3D11_BIND_RENDER_TARGET;
  ComPtr<ID3D11Texture2D> destination; Check(device->CreateTexture2D(&desc, nullptr, &destination));
  ComPtr<ID3D11RenderTargetView> rt; Check(device->CreateRenderTargetView(destination.Get(), nullptr, &rt));
  D3D11_SAMPLER_DESC samplerDesc{};
  samplerDesc.Filter = D3D11_FILTER_MIN_MAG_MIP_POINT;
  samplerDesc.AddressU = samplerDesc.AddressV = samplerDesc.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
  samplerDesc.MaxLOD = D3D11_FLOAT32_MAX;
  ComPtr<ID3D11SamplerState> sampler; Check(device->CreateSamplerState(&samplerDesc, &sampler));
  auto* renderTarget = rt.Get(); context->OMSetRenderTargets(1, &renderTarget, nullptr);
  D3D11_VIEWPORT viewport{0, 0, 1, 1, 0, 1}; context->RSSetViewports(1, &viewport);
  context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  context->VSSetShader(vertexShader.Get(), nullptr, 0);
  context->PSSetShader(pixelShader.Get(), nullptr, 0);
  auto* srv = image.Get(); context->PSSetShaderResources(0, 1, &srv);
  auto* sample = sampler.Get(); context->PSSetSamplers(0, 1, &sample);
  const float referenceScale = headroom > 0 ? std::min(203.0f / 80.0f, headroom) : 203.0f / 80.0f;
  const float scale[] = {referenceScale, headroom > 0 ? headroom / referenceScale : 65504.0f, 8, 0};
  D3D11_BUFFER_DESC paramsDesc{};
  paramsDesc.ByteWidth = sizeof(scale);
  paramsDesc.Usage = D3D11_USAGE_IMMUTABLE;
  paramsDesc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
  D3D11_SUBRESOURCE_DATA paramsData{}; paramsData.pSysMem = scale;
  ComPtr<ID3D11Buffer> params;
  Check(device->CreateBuffer(&paramsDesc, &paramsData, &params));
  auto* paramsPtr = params.Get(); context->PSSetConstantBuffers(0, 1, &paramsPtr);
  context->Draw(3, 0); context->ClearState();
  desc.Usage = D3D11_USAGE_STAGING; desc.BindFlags = 0; desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  ComPtr<ID3D11Texture2D> readback; Check(device->CreateTexture2D(&desc, nullptr, &readback));
  context->CopyResource(readback.Get(), destination.Get());
  D3D11_MAPPED_SUBRESOURCE mapped{}; Check(context->Map(readback.Get(), 0, D3D11_MAP_READ, 0, &mapped));
  uint16_t red; memcpy(&red, mapped.pData, sizeof(red));
  const double result = DirectX::PackedVector::XMConvertHalfToFloat(red);
  if (resultAlpha) {
    uint16_t encodedAlpha; memcpy(&encodedAlpha, static_cast<const uint8_t*>(mapped.pData) + 6, sizeof(encodedAlpha));
    *resultAlpha = DirectX::PackedVector::XMConvertHalfToFloat(encodedAlpha);
  }
  context->Unmap(readback.Get(), 0);
  return result;
}
}

class NativeHdrDisplay::Implementation {
 public:
  Implementation(flutter::FlutterEngine* engine, HWND view) : view_(view) {
    channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
        engine->messenger(), "shenview/hdr_display",
        &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      try {
#ifndef NDEBUG
        if (call.method_name() == "verifyComposition") {
          // Exercise composition on SDR CI machines without enabling HDR in
          // the OS. This override exists only during this Debug-only probe.
          probeOnly_ = true;
          const float pixel[] = {8, 4, 2, 1};
          std::vector<uint8_t> pixels(sizeof(pixel));
          memcpy(pixels.data(), pixel, sizeof(pixel));
          EncodableMap upload{
            {EncodableValue("width"), EncodableValue(1)},
            {EncodableValue("height"), EncodableValue(1)},
            {EncodableValue("pixels"), EncodableValue(std::move(pixels))},
          };
          EncodableMap geometry{
            {EncodableValue("visible"), EncodableValue(true)},
            {EncodableValue("geometry"), EncodableValue(std::vector<double>{100, 100, 200, 100, 100, 200, 80, 80, 240, 240})},
          };
          const bool okay = Upload(9000002, upload) && Geometry(9000002, geometry);
          if (composition_) Check(composition_->WaitForCommitCompletion());
          Reset(); probeOnly_ = false;
          result->Success(EncodableValue(okay)); return;
        }
#endif
        if (call.method_name() == "verifyFloatPipeline") {
          result->Success(EncodableValue(VerifyFloatPipeline())); return;
        }
        if (call.method_name() == "verifyDisplayMapping") {
          result->Success(EncodableValue(VerifyFloatPipeline(1.0f, nullptr, 5.0f))); return;
        }
        if (call.method_name() == "verifyPremultipliedPipeline") {
          float alpha; const auto red = VerifyFloatPipeline(0.5f, &alpha);
          result->Success(EncodableValue(EncodableMap{
            {EncodableValue("red"), EncodableValue(red)},
            {EncodableValue("alpha"), EncodableValue(static_cast<double>(alpha))},
          })); return;
        }
        if (call.method_name() == "diagnostics") {
          int visible = 0;
          for (const auto& entry : frames_) if (entry.second.visible) ++visible;
          result->Success(EncodableValue(EncodableMap{
            {EncodableValue("activeFrames"), EncodableValue(static_cast<int32_t>(frames_.size()))},
            {EncodableValue("visibleFrames"), EncodableValue(visible)},
            {EncodableValue("surfaceFormat"), EncodableValue("R16G16B16A16_FLOAT")},
            {EncodableValue("colorSpace"), EncodableValue("RGB_FULL_G10_NONE_P709")},
          })); return;
        }
        if (call.method_name() == "capabilities") {
          const bool available = Probe();
          result->Success(EncodableValue(EncodableMap{
            {EncodableValue("available"), EncodableValue(available)},
            {EncodableValue("output"), EncodableValue(output_)},
            {EncodableValue("headroom"), EncodableValue(headroom_)},
            {EncodableValue("colorManagement"), EncodableValue("Windows Advanced Color / WCS")},
            {EncodableValue("displayProfile"), EncodableValue(DisplayProfile())},
            {EncodableValue("reason"), EncodableValue(available ? "scRGB-FP16" : "hdr-disabled-or-unavailable")},
          }));
          return;
        }
        const auto* args = call.arguments() ? std::get_if<EncodableMap>(call.arguments()) : nullptr;
        if (!args) { result->Success(EncodableValue(false)); return; }
        const auto id = Integer(*args, "id");
        if (call.method_name() == "remove") {
          Remove(id);
          result->Success();
        } else if (call.method_name() == "upload") {
          result->Success(EncodableValue(Upload(id, *args)));
        } else if (call.method_name() == "geometry") {
          result->Success(EncodableValue(Geometry(id, *args)));
        } else { result->NotImplemented(); }
      } catch (...) {
        // Device removal, old drivers and DWM transitions never escape to the
        // Flutter runner. Removing the overlay exposes the working SDR frame.
        Reset();
        probeOnly_ = false;
        channel_->InvokeMethod("invalidated", std::make_unique<EncodableValue>("device-failed"));
        result->Success(EncodableValue(false));
      }
    });
  }
  ~Implementation() { channel_->SetMethodCallHandler(nullptr); Reset(); }
  void OnDisplayChanged(bool force) {
    if (force || (monitor_ && monitor_ != MonitorFromWindow(
        GetAncestor(view_, GA_ROOT), MONITOR_DEFAULTTONEAREST))) {
      const bool hadFrames = !frames_.empty();
      Reset();
      if (hadFrames) channel_->InvokeMethod("invalidated",
          std::make_unique<EncodableValue>("display-changed"));
    }
  }

 private:
  struct Frame {
    UINT width = 0;
    UINT height = 0;
    bool visible = false;
    ComPtr<ID3D11Buffer> params;
    ComPtr<IDXGISwapChain3> swapChain;
    ComPtr<IDCompositionVisual> clip;
    ComPtr<IDCompositionVisual> image;
  };

  bool Probe() {
    const auto monitor = MonitorFromWindow(GetAncestor(view_, GA_ROOT), MONITOR_DEFAULTTONEAREST);
    ComPtr<IDXGIFactory1> factory;
    Check(CreateDXGIFactory1(IID_PPV_ARGS(&factory)));
    ComPtr<IDXGIAdapter1> selected;
    DXGI_OUTPUT_DESC1 desc{};
    bool found = false;
    for (UINT a = 0; !found; ++a) {
      ComPtr<IDXGIAdapter1> adapter;
      if (factory->EnumAdapters1(a, &adapter) == DXGI_ERROR_NOT_FOUND) break;
      if (!adapter) break;
      for (UINT o = 0; ; ++o) {
        ComPtr<IDXGIOutput> output;
        if (adapter->EnumOutputs(o, &output) == DXGI_ERROR_NOT_FOUND) break;
        if (!output) break;
        ComPtr<IDXGIOutput6> advanced;
        if (SUCCEEDED(output.As(&advanced)) && SUCCEEDED(advanced->GetDesc1(&desc)) &&
            desc.Monitor == monitor) { selected = adapter; found = true; break; }
      }
    }
    // Conservative gate: supported monitor AND Windows HDR actually enabled.
    // Do not promote an ordinary SDR / wide-gamut SDR desktop into HDR.
    if (!found || (!probeOnly_ && desc.ColorSpace != DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020)) {
      Reset(); return false;
    }
    const double headroom = std::isfinite(desc.MaxLuminance) && desc.MaxLuminance > 0
        ? std::max(1.0, static_cast<double>(desc.MaxLuminance) / 80.0) : 1.0;
    if (!probeOnly_ && headroom <= 1.0) { Reset(); return false; }
    if (device_ && monitor_ == monitor && std::abs(headroom_ - headroom) < 0.01) return true;
    Reset();
    monitor_ = monitor;
    output_ = std::to_string(reinterpret_cast<uintptr_t>(monitor)) + "-" + std::to_string(generation_);
    headroom_ = headroom;
    const D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1};
    Check(D3D11CreateDevice(selected.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT, levels, ARRAYSIZE(levels),
        D3D11_SDK_VERSION, &device_, nullptr, &context_));
    ComPtr<IDXGIDevice> dxgiDevice;
    Check(device_.As(&dxgiDevice));
    Check(DCompositionCreateDevice(dxgiDevice.Get(), IID_PPV_ARGS(&composition_)));
    Check(composition_->CreateTargetForHwnd(view_, TRUE, &target_));
    Check(composition_->CreateVisual(&root_));
    Check(target_->SetRoot(root_.Get()));
    ComPtr<ID3DBlob> vs, ps, errors;
    Check(D3DCompile(kShader, sizeof(kShader) - 1, nullptr, nullptr, nullptr, "vs", "vs_4_0",
        D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &vs, &errors));
    Check(D3DCompile(kShader, sizeof(kShader) - 1, nullptr, nullptr, nullptr, "ps", "ps_4_0",
        D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &ps, &errors));
    Check(device_->CreateVertexShader(vs->GetBufferPointer(), vs->GetBufferSize(), nullptr, &vertexShader_));
    Check(device_->CreatePixelShader(ps->GetBufferPointer(), ps->GetBufferSize(), nullptr, &pixelShader_));
    D3D11_SAMPLER_DESC sampler{};
    sampler.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
    sampler.AddressU = sampler.AddressV = sampler.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
    sampler.MaxLOD = D3D11_FLOAT32_MAX;
    Check(device_->CreateSamplerState(&sampler, &sampler_));
    Check(composition_->Commit());
    return true;
  }

  std::string DisplayProfile() const {
    MONITORINFOEXW info{}; info.cbSize = sizeof(info);
    const auto monitor = MonitorFromWindow(GetAncestor(view_, GA_ROOT), MONITOR_DEFAULTTONEAREST);
    if (!GetMonitorInfoW(monitor, reinterpret_cast<MONITORINFO*>(&info))) return {};
    HDC dc = CreateDCW(L"DISPLAY", info.szDevice, nullptr, nullptr);
    if (!dc) return {};
    DWORD length = 0;
    GetICMProfileW(dc, &length, nullptr);
    if (length < 2 || length > 32768) { DeleteDC(dc); return {}; }
    std::wstring profile(length, L'\0');
    const bool okay = length > 1 && GetICMProfileW(dc, &length, profile.data());
    DeleteDC(dc);
    if (!okay) return {};
    if (!profile.empty() && profile.back() == L'\0') profile.pop_back();
    const int size = WideCharToMultiByte(CP_UTF8, 0, profile.data(),
        static_cast<int>(profile.size()), nullptr, 0, nullptr, nullptr);
    if (size <= 0) return {};
    std::string result(size, '\0');
    WideCharToMultiByte(CP_UTF8, 0, profile.data(), static_cast<int>(profile.size()),
        result.data(), size, nullptr, nullptr);
    return result;
  }

  bool Upload(int64_t id, const EncodableMap& args) {
    const auto width = Integer(args, "width"), height = Integer(args, "height");
    const auto* data = Value(args, "pixels");
    const auto* pixels = data ? std::get_if<std::vector<uint8_t>>(data) : nullptr;
    if (id <= 0 || width < 1 || height < 1 || width > 16384 || height > 16384 ||
        static_cast<size_t>(width * height) > kMaxPixels || !pixels ||
        pixels->size() != static_cast<size_t>(width * height * 16)) return false;
    Remove(id);
    size_t total = static_cast<size_t>(width * height);
    for (const auto& entry : frames_) total += entry.second.width * entry.second.height;
    if (total > kTotalPixels || frames_.size() >= 4 || !Probe()) return false;
    // Reject NaN/Inf before touching the GPU. The Dart parser normally already
    // sanitizes these; this also protects the native method-channel boundary.
    float contentPeak = 0;
    for (size_t offset = 0; offset < pixels->size(); offset += sizeof(float)) {
      float value; memcpy(&value, pixels->data() + offset, sizeof(value));
      if (!std::isfinite(value) || std::abs(value) > 65504.0f) return false;
      if (offset % 16 == 12 && (value < 0 || value > 1)) return false;
    }
    for (size_t offset = 0; offset < pixels->size(); offset += 16) {
      float pixel[4]; memcpy(pixel, pixels->data() + offset, sizeof(pixel));
      if (pixel[3] > 0) for (int c = 0; c < 3; ++c) {
        const float straight = pixel[c] / pixel[3];
        if (!std::isfinite(straight) || std::abs(straight) > 65504.0f) return false;
        contentPeak = std::max(contentPeak, straight);
      }
    }
    D3D11_TEXTURE2D_DESC textureDesc{};
    textureDesc.Width = static_cast<UINT>(width); textureDesc.Height = static_cast<UINT>(height);
    textureDesc.MipLevels = 1; textureDesc.ArraySize = 1;
    textureDesc.Format = DXGI_FORMAT_R32G32B32A32_FLOAT;
    textureDesc.SampleDesc.Count = 1; textureDesc.Usage = D3D11_USAGE_IMMUTABLE;
    textureDesc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    D3D11_SUBRESOURCE_DATA source{}; source.pSysMem = pixels->data();
    source.SysMemPitch = static_cast<UINT>(width * 16);
    ComPtr<ID3D11Texture2D> texture;
    Check(device_->CreateTexture2D(&textureDesc, &source, &texture));
    ComPtr<ID3D11ShaderResourceView> image;
    Check(device_->CreateShaderResourceView(texture.Get(), nullptr, &image));
    ComPtr<IDXGIDevice> dxgiDevice; Check(device_.As(&dxgiDevice));
    ComPtr<IDXGIAdapter> adapter; Check(dxgiDevice->GetAdapter(&adapter));
    ComPtr<IDXGIFactory2> factory; Check(adapter->GetParent(IID_PPV_ARGS(&factory)));
    DXGI_SWAP_CHAIN_DESC1 swap{};
    swap.Width = static_cast<UINT>(width); swap.Height = static_cast<UINT>(height);
    swap.Format = DXGI_FORMAT_R16G16B16A16_FLOAT; swap.SampleDesc.Count = 1;
    swap.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT; swap.BufferCount = 2;
    swap.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
    swap.AlphaMode = DXGI_ALPHA_MODE_PREMULTIPLIED;
    swap.Scaling = DXGI_SCALING_STRETCH;
    Frame frame; frame.width = swap.Width; frame.height = swap.Height;
    ComPtr<IDXGISwapChain1> swapChain;
    Check(factory->CreateSwapChainForComposition(device_.Get(), &swap, nullptr, &swapChain));
    Check(swapChain.As(&frame.swapChain));
    UINT support = 0; Check(frame.swapChain->CheckColorSpaceSupport(kColorSpace, &support));
    if (!(support & DXGI_SWAP_CHAIN_COLOR_SPACE_SUPPORT_FLAG_PRESENT)) return false;
    Check(frame.swapChain->SetColorSpace1(kColorSpace));
    ComPtr<ID3D11Texture2D> buffer; Check(frame.swapChain->GetBuffer(0, IID_PPV_ARGS(&buffer)));
    ComPtr<ID3D11RenderTargetView> renderTarget;
    Check(device_->CreateRenderTargetView(buffer.Get(), nullptr, &renderTarget));
    auto* rt = renderTarget.Get(); context_->OMSetRenderTargets(1, &rt, nullptr);
    D3D11_VIEWPORT viewport{0, 0, static_cast<float>(width), static_cast<float>(height), 0, 1};
    context_->RSSetViewports(1, &viewport);
    context_->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    context_->VSSetShader(vertexShader_.Get(), nullptr, 0);
    context_->PSSetShader(pixelShader_.Get(), nullptr, 0);
    auto* srv = image.Get(); context_->PSSetShaderResources(0, 1, &srv);
    auto* sampler = sampler_.Get(); context_->PSSetSamplers(0, 1, &sampler);
    // Map the chosen reference white to the available scRGB headroom. On a
    // normal HDR monitor this stays 203/80; on a lower-peak display it avoids
    // pushing the reference white above the display's supported range.
    const float referenceScale = static_cast<float>(std::min(203.0 / 80.0,
        std::max(1.0, headroom_)));
    const float scale[] = {referenceScale, static_cast<float>(headroom_) / referenceScale, contentPeak, 0};
    D3D11_BUFFER_DESC paramsDesc{};
    paramsDesc.ByteWidth = sizeof(scale);
    paramsDesc.Usage = D3D11_USAGE_IMMUTABLE;
    paramsDesc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    D3D11_SUBRESOURCE_DATA paramsData{}; paramsData.pSysMem = scale;
    Check(device_->CreateBuffer(&paramsDesc, &paramsData, &frame.params));
    auto* params = frame.params.Get(); context_->PSSetConstantBuffers(0, 1, &params);
    context_->Draw(3, 0);
    context_->ClearState();
    Check(frame.swapChain->Present(0, 0));
    Check(composition_->CreateVisual(&frame.clip));
    Check(composition_->CreateVisual(&frame.image));
    Check(frame.image->SetContent(frame.swapChain.Get()));
    Check(frame.clip->AddVisual(frame.image.Get(), FALSE, nullptr));
    Check(frame.clip->SetClip(D2D_RECT_F{0, 0, 0, 0}));
    Check(root_->AddVisual(frame.clip.Get(), TRUE, nullptr));
    frames_.emplace(id, std::move(frame));
    Check(composition_->Commit());
    return true;
  }

  bool Geometry(int64_t id, const EncodableMap& args) {
    auto entry = frames_.find(id); if (entry == frames_.end() || !composition_) return false;
    auto& frame = entry->second;
    if (!Boolean(args, "visible") || IsIconic(GetAncestor(view_, GA_ROOT))) {
      frame.visible = false;
      Check(frame.clip->SetClip(D2D_RECT_F{0, 0, 0, 0})); Check(composition_->Commit()); return true;
    }
    const auto* value = Value(args, "geometry");
    const auto* g = value ? std::get_if<std::vector<double>>(value) : nullptr;
    if (!g || g->size() != 10) return false;
    for (auto v : *g) if (!std::isfinite(v) || std::abs(v) > 1e8) return false;
    if ((*g)[8] <= (*g)[6] || (*g)[9] <= (*g)[7]) return false;
    D2D_MATRIX_3X2_F transform{
      static_cast<float>(((*g)[2] - (*g)[0]) / frame.width),
      static_cast<float>(((*g)[3] - (*g)[1]) / frame.width),
      static_cast<float>(((*g)[4] - (*g)[0]) / frame.height),
      static_cast<float>(((*g)[5] - (*g)[1]) / frame.height),
      static_cast<float>((*g)[0]), static_cast<float>((*g)[1])};
    Check(frame.image->SetTransform(transform));
    D2D_RECT_F clip{static_cast<float>((*g)[6]), static_cast<float>((*g)[7]),
        static_cast<float>((*g)[8]), static_cast<float>((*g)[9])};
    Check(frame.clip->SetClip(clip));
    frame.visible = true;
    Check(composition_->Commit());
    return true;
  }
  void Remove(int64_t id) {
    const auto entry = frames_.find(id);
    if (entry == frames_.end()) return;
    if (root_) root_->RemoveVisual(entry->second.clip.Get());
    frames_.erase(entry);
    if (composition_) composition_->Commit();
  }
  void Reset() {
    if (target_) target_->SetRoot(nullptr);
    if (composition_) composition_->Commit();
    frames_.clear(); root_.Reset(); target_.Reset(); composition_.Reset();
    sampler_.Reset(); vertexShader_.Reset(); pixelShader_.Reset();
    context_.Reset(); device_.Reset(); output_ = "SDR"; headroom_ = 1;
    monitor_ = nullptr; ++generation_;
  }

  HWND view_;
  bool probeOnly_ = false;
  HMONITOR monitor_ = nullptr;
  uint64_t generation_ = 0;
  std::string output_ = "SDR";
  double headroom_ = 1;
  std::map<int64_t, Frame> frames_;
  ComPtr<ID3D11Device> device_;
  ComPtr<ID3D11DeviceContext> context_;
  ComPtr<ID3D11VertexShader> vertexShader_;
  ComPtr<ID3D11PixelShader> pixelShader_;
  ComPtr<ID3D11SamplerState> sampler_;
  ComPtr<IDCompositionDevice> composition_;
  ComPtr<IDCompositionTarget> target_;
  ComPtr<IDCompositionVisual> root_;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel_;
};

NativeHdrDisplay::NativeHdrDisplay(flutter::FlutterEngine* engine, HWND view)
    : implementation_(std::make_unique<Implementation>(engine, view)) {}
NativeHdrDisplay::~NativeHdrDisplay() = default;
void NativeHdrDisplay::OnDisplayChanged(bool force) { implementation_->OnDisplayChanged(force); }
