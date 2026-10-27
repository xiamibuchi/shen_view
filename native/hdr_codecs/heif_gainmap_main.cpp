#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <fstream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
#include "color_profile.h"
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <fcntl.h>
#include <io.h>
#else
#include <dlfcn.h>
#endif

namespace {
struct Error { int code; int subcode; const char* message; };
struct Context; struct Handle; struct Image;
using Item = uint32_t;
constexpr int kRgb = 1, kRgba16Le = 15, kInterleaved = 10;

uint32_t Fourcc(const char* p) {
  return (uint32_t(uint8_t(p[0])) << 24) | (uint32_t(uint8_t(p[1])) << 16) |
         (uint32_t(uint8_t(p[2])) << 8) | uint8_t(p[3]);
}

class Heif {
 public:
  Heif() {
#ifdef _WIN32
    wchar_t buffer[32768]{};
    const auto n = GetModuleFileNameW(nullptr, buffer, 32768);
    const auto dir = std::filesystem::path(buffer, buffer + n).parent_path();
    for (const auto& path : {dir / L"CORE_RL_heif_.dll", std::filesystem::path(L"CORE_RL_heif_.dll")}) {
      module = LoadLibraryW(path.c_str());
      if (module) break;
    }
#else
    for (const auto* path : {"libheif.dylib", "libheif.so.1", "/opt/homebrew/lib/libheif.dylib"}) {
      module = dlopen(path, RTLD_NOW | RTLD_LOCAL);
      if (module) break;
    }
#endif
    if (!module) throw std::runtime_error("libheif 动态组件不可用");
#define LOAD(name) name = Get<decltype(name)>(#name)
    LOAD(heif_context_alloc); LOAD(heif_context_free);
    LOAD(heif_context_read_from_memory_without_copy); LOAD(heif_context_get_primary_image_ID);
    LOAD(heif_context_get_image_handle); LOAD(heif_context_get_number_of_items);
    LOAD(heif_context_get_list_of_item_IDs); LOAD(heif_item_get_item_type);
    LOAD(heif_item_get_item_data); LOAD(heif_release_item_data);
    LOAD(heif_context_get_item_references); LOAD(heif_release_item_references);
    LOAD(heif_decode_image); LOAD(heif_image_handle_release); LOAD(heif_image_release);
    LOAD(heif_image_handle_get_width); LOAD(heif_image_handle_get_height);
    LOAD(heif_image_get_plane_readonly); LOAD(heif_image_get_bits_per_pixel_range);
    LOAD(heif_image_handle_get_nclx_color_profile); LOAD(heif_nclx_color_profile_free);
    LOAD(heif_image_get_width); LOAD(heif_image_get_height);
    LOAD(heif_image_handle_get_raw_color_profile_size); LOAD(heif_image_handle_get_raw_color_profile);
    LOAD(heif_image_handle_get_list_of_metadata_block_IDs); LOAD(heif_image_handle_get_metadata_size);
    LOAD(heif_image_handle_get_metadata);
#undef LOAD
  }
  ~Heif() {
#ifdef _WIN32
    if (module) FreeLibrary(module);
#else
    if (module) dlclose(module);
#endif
  }
  template <typename T> T Get(const char* name) {
#ifdef _WIN32
    auto symbol = GetProcAddress(module, name);
#else
    auto symbol = dlsym(module, name);
#endif
    if (!symbol) throw std::runtime_error(std::string("libheif 缺少 API: ") + name);
    return reinterpret_cast<T>(symbol);
  }
  using Alloc = Context* (*)(); using Free = void (*)(Context*);
  using Read = Error (*)(Context*, const void*, size_t, const void*);
  using Primary = Error (*)(Context*, Item*);
  using GetHandle = Error (*)(Context*, Item, Handle**);
  using Count = int (*)(const Context*); using List = int (*)(const Context*, Item*, int);
  using Type = uint32_t (*)(const Context*, Item);
  using ItemData = Error (*)(const Context*, Item, int*, uint8_t**, size_t*);
  using ReleaseData = void (*)(const Context*, uint8_t**);
  using Refs = size_t (*)(const Context*, Item, int, uint32_t*, Item**);
  using ReleaseRefs = void (*)(const Context*, Item**);
  using Decode = Error (*)(const Handle*, Image**, int, int, const void*);
  using ReleaseHandle = void (*)(const Handle*); using ReleaseImage = void (*)(const Image*);
  using Size = int (*)(const Handle*); using Plane = const uint8_t* (*)(const Image*, int, int*);
  using Bits = int (*)(const Image*, int);
  struct Nclx {
    uint8_t version; int primaries; int transfer; int matrix; uint8_t fullRange;
    float values[8];
  };
  using NclxGet = Error (*)(const Handle*, Nclx**); using NclxFree = void (*)(Nclx*);
  using ImageSize = int (*)(const Image*, int);
  using ProfileSize = size_t (*)(const Handle*);
  using ProfileGet = Error (*)(const Handle*, void*);
  using MetadataIds = int (*)(const Handle*, const char*, Item*, int);
  using MetadataSize = size_t (*)(const Handle*, Item);
  using MetadataGet = Error (*)(const Handle*, Item, void*);
  Alloc heif_context_alloc{}; Free heif_context_free{}; Read heif_context_read_from_memory_without_copy{};
  Primary heif_context_get_primary_image_ID{}; GetHandle heif_context_get_image_handle{};
  Count heif_context_get_number_of_items{}; List heif_context_get_list_of_item_IDs{};
  Type heif_item_get_item_type{}; ItemData heif_item_get_item_data{}; ReleaseData heif_release_item_data{};
  Refs heif_context_get_item_references{}; ReleaseRefs heif_release_item_references{};
  Decode heif_decode_image{}; ReleaseHandle heif_image_handle_release{}; ReleaseImage heif_image_release{};
  Size heif_image_handle_get_width{}; Size heif_image_handle_get_height{};
  Plane heif_image_get_plane_readonly{}; Bits heif_image_get_bits_per_pixel_range{};
  NclxGet heif_image_handle_get_nclx_color_profile{}; NclxFree heif_nclx_color_profile_free{};
  ImageSize heif_image_get_width{}, heif_image_get_height{};
  ProfileSize heif_image_handle_get_raw_color_profile_size{};
  ProfileGet heif_image_handle_get_raw_color_profile{};
  MetadataIds heif_image_handle_get_list_of_metadata_block_IDs{};
  MetadataSize heif_image_handle_get_metadata_size{};
  MetadataGet heif_image_handle_get_metadata{};
#ifdef _WIN32
  HMODULE module{};
#else
  void* module{};
#endif
};

struct Gain {
  float baseHeadroom = 0, alternateHeadroom = 3;
  float min[3]{}, max[3]{}, gamma[3]{1, 1, 1}, baseOffset[3]{}, alternateOffset[3]{};
};

Gain Parse(const std::vector<uint8_t>& bytes) {
  if (bytes.size() < 62 || bytes.size() > 4096 || bytes[0] != 0 || bytes[1] != 0 || bytes[2] != 0) {
    throw std::runtime_error("HEIF Gain Map 元数据或版本无效");
  }
  size_t bit = 40;
  auto readBits = [&](int count) {
    uint32_t value = 0;
    for (int i = 0; i < count; ++i) {
      if (bit / 8 >= bytes.size()) throw std::runtime_error("HEIF Gain Map 元数据截断");
      value = (value << 1) | ((bytes[bit / 8] >> (7 - bit % 8)) & 1);
      ++bit;
    }
    return value;
  };
  const bool multi = readBits(1) != 0;
  const bool useBase = readBits(1) != 0;
  readBits(6);
  if (!useBase) throw std::runtime_error("HEIF Gain Map alternate color space 暂不支持");
  auto u32 = [&]() { return readBits(32); };
  auto fraction = [&](bool signedNumerator) {
    const uint32_t numerator = u32();
    const uint32_t denominator = u32();
    if (denominator == 0) throw std::runtime_error("HEIF Gain Map 分母无效");
    return (signedNumerator ? static_cast<float>(static_cast<int32_t>(numerator)) : static_cast<float>(numerator)) / denominator;
  };
  Gain gain;
  gain.baseHeadroom = fraction(false); gain.alternateHeadroom = fraction(false);
  const int channels = multi ? 3 : 1;
  for (int c = 0; c < channels; ++c) {
    gain.min[c] = fraction(true); gain.max[c] = fraction(true);
    gain.gamma[c] = fraction(false); gain.baseOffset[c] = fraction(true); gain.alternateOffset[c] = fraction(true);
    if (!(gain.gamma[c] > 0) || gain.max[c] < gain.min[c]) throw std::runtime_error("HEIF Gain Map 参数无效");
  }
  for (int c = channels; c < 3; ++c) {
    gain.min[c] = gain.min[0]; gain.max[c] = gain.max[0]; gain.gamma[c] = gain.gamma[0];
    gain.baseOffset[c] = gain.baseOffset[0]; gain.alternateOffset[c] = gain.alternateOffset[0];
  }
  if (bytes[3] == 0 && bytes[4] == 0 && bit / 8 != bytes.size()) throw std::runtime_error("HEIF Gain Map 元数据长度无效");
  return gain;
}

struct Pixels { int width, height, bits, primaries, transfer; std::vector<uint16_t> values; std::vector<uint8_t> icc; };

float ToLinear(float value, int transfer) {
  if (transfer == 8) return value;
  if (transfer == 13) return value <= 0.04045f ? value / 12.92f : std::pow((value + 0.055f) / 1.055f, 2.4f);
  if (transfer == 1 || transfer == 6) return value < 0.081f ? value / 4.5f : std::pow((value + 0.099f) / 1.099f, 1.0f / 0.45f);
  if (transfer == 16) {
    const double power = std::pow(value, 32.0 / 2523.0);
    return float(std::pow(std::max(power - 3424.0 / 4096.0, 0.0) / (2413.0 / 128.0 - 2392.0 / 128.0 * power), 16384.0 / 2610.0) * (10000.0 / 203.0));
  }
  throw std::runtime_error("HEIF Gain Map 基础图传递函数不支持");
}

Pixels Decode(Heif& heif, Context* context, Item item) {
  Handle* handle = nullptr;
  auto error = heif.heif_context_get_image_handle(context, item, &handle);
  if (error.code || !handle) throw std::runtime_error(error.message ? error.message : "HEIF 句柄失败");
  std::unique_ptr<Handle, Heif::ReleaseHandle> keepHandle(handle, heif.heif_image_handle_release);
  const int width = heif.heif_image_handle_get_width(handle), height = heif.heif_image_handle_get_height(handle);
  if (width < 1 || height < 1 || int64_t(width) * height > 16 * 1024 * 1024) {
    throw std::runtime_error("HEIF 图像尺寸超限");
  }
  int primaries = 0, transfer = 13;
  Heif::Nclx* profile = nullptr;
  if (!heif.heif_image_handle_get_nclx_color_profile(handle, &profile).code && profile) {
    const int cp = profile->primaries;
    transfer = profile->transfer;
    primaries = cp == 12 ? 1 : cp == 9 ? 2 : cp == 1 ? 0 : -1;
    heif.heif_nclx_color_profile_free(profile);
  }
  Image* image = nullptr;
  error = heif.heif_decode_image(handle, &image, kRgb, kRgba16Le, nullptr);
  if (error.code || !image) throw std::runtime_error(error.message ? error.message : "HEIF 图像解码失败");
  std::unique_ptr<Image, Heif::ReleaseImage> keepImage(image, heif.heif_image_release);
  int stride = 0;
  const auto* source = heif.heif_image_get_plane_readonly(image, kInterleaved, &stride);
  const int bits = heif.heif_image_get_bits_per_pixel_range(image, kInterleaved);
  if (!source || stride < width * 8 || bits < 8 || bits > 16 || heif.heif_image_get_width(image, kInterleaved) != width || heif.heif_image_get_height(image, kInterleaved) != height) {
    throw std::runtime_error("HEIF RGBA 平面不可用");
  }
  Pixels output{width, height, bits, primaries, transfer, std::vector<uint16_t>(size_t(width) * height * 4)};
  const auto profileSize = heif.heif_image_handle_get_raw_color_profile_size(handle);
  if (profileSize > 4 * 1024 * 1024) throw std::runtime_error("ICC budget");
  if (profileSize) {
    output.icc.resize(profileSize);
    if (heif.heif_image_handle_get_raw_color_profile(handle, output.icc.data()).code)
      throw std::runtime_error("HEIF ICC read failed");
  }
  for (int y = 0; y < height; ++y) {
    std::memcpy(output.values.data() + size_t(y) * width * 4, source + size_t(y) * stride, size_t(width) * 8);
  }
  return output;
}

void Run(const std::filesystem::path& path, bool metadata) {
  const auto fileSize = std::filesystem::file_size(path);
  if (fileSize < 16 || fileSize > 64 * 1024 * 1024) throw std::runtime_error("HEIF 输入大小超限");
  std::vector<uint8_t> fileBytes(static_cast<size_t>(fileSize));
  std::ifstream input(path, std::ios::binary);
  if (!input.read(reinterpret_cast<char*>(fileBytes.data()), fileBytes.size())) throw std::runtime_error("HEIF 读取失败");
  Heif heif;
  Context* context = heif.heif_context_alloc();
  if (!context) throw std::runtime_error("HEIF context 不可用");
  std::unique_ptr<Context, Heif::Free> keepContext(context, heif.heif_context_free);
  auto error = heif.heif_context_read_from_memory_without_copy(context, fileBytes.data(), fileBytes.size(), nullptr);
  if (error.code) throw std::runtime_error(error.message ? error.message : "HEIF 读取失败");
  Item primary = 0, tmap = 0, gainItem = 0;
  error = heif.heif_context_get_primary_image_ID(context, &primary);
  if (error.code) throw std::runtime_error("HEIF 主图不可用");
  if (metadata) {
    Handle* handle = nullptr;
    if (heif.heif_context_get_image_handle(context, primary, &handle).code || !handle) throw std::runtime_error("HEIF metadata handle");
    std::unique_ptr<Handle, Heif::ReleaseHandle> keep(handle, heif.heif_image_handle_release);
    size_t remaining = 4 * 1024 * 1024;
    for (const auto* type : {"Exif", "mime"}) {
      Item ids[32]{};
      const int count = heif.heif_image_handle_get_list_of_metadata_block_IDs(handle, type, ids, 32);
      for (int i = 0; i < std::min(count, 32); ++i) {
        const auto size = heif.heif_image_handle_get_metadata_size(handle, ids[i]);
        if (!size || size > remaining) continue;
        std::vector<uint8_t> bytes(size);
        if (heif.heif_image_handle_get_metadata(handle, ids[i], bytes.data()).code) continue;
        std::cout << (type[0] == 'E' ? "EXIF " : "XMP ") << size << '\n';
        std::cout.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
        remaining -= size;
      }
    }
    const auto profileSize = heif.heif_image_handle_get_raw_color_profile_size(handle);
    if (profileSize) {
      if (profileSize <= remaining) {
        std::vector<uint8_t> profile(profileSize);
        if (!heif.heif_image_handle_get_raw_color_profile(handle, profile.data()).code) {
          std::cout << "ICC " << profile.size() << '\n';
          std::cout.write(reinterpret_cast<const char*>(profile.data()), profile.size());
        }
      } else {
        std::cout << "COLOR 3\nICC";
      }
    }
    else {
      Heif::Nclx* profile = nullptr;
      if (!heif.heif_image_handle_get_nclx_color_profile(handle, &profile).code && profile) {
        const std::string gamut = profile->primaries == 12 ? "Display P3" : profile->primaries == 9 ? "Rec.2020" :
            profile->primaries == 1 ? "Rec.709" : "CICP " + std::to_string(profile->primaries);
        const std::string transfer = profile->transfer == 16 ? " / PQ" : profile->transfer == 18 ? " / HLG" : "";
        const auto color = gamut + transfer;
        std::cout << "COLOR " << color.size() << '\n' << color;
        heif.heif_nclx_color_profile_free(profile);
      }
    }
    return;
  }
  const int count = heif.heif_context_get_number_of_items(context);
  if (count < 1 || count > 65536) throw std::runtime_error("HEIF item 数量超限");
  std::vector<Item> ids(std::max(0, count));
  heif.heif_context_get_list_of_item_IDs(context, ids.data(), count);
  for (const auto id : ids) {
    if (heif.heif_item_get_item_type(context, id) != Fourcc("tmap")) continue;
    uint32_t type = 0; Item* references = nullptr;
    const auto number = heif.heif_context_get_item_references(context, id, 0, &type, &references);
    if (number == 2 && type == Fourcc("dimg") && references && references[0] == primary) { tmap = id; gainItem = references[1]; }
    if (references) heif.heif_release_item_references(context, &references);
  }
  if (!tmap || !gainItem) throw std::runtime_error("HEIF Gain Map 引用缺失");
  uint8_t* raw = nullptr; size_t size = 0; int compression = 0;
  error = heif.heif_item_get_item_data(context, tmap, &compression, &raw, &size);
  if (error.code || !raw) throw std::runtime_error("HEIF Gain Map 元数据缺失");
  if (size > 4096) { heif.heif_release_item_data(context, &raw); throw std::runtime_error("HEIF Gain Map 元数据超限"); }
  std::vector<uint8_t> gainMetadata(raw, raw + size); heif.heif_release_item_data(context, &raw);
  const auto gain = Parse(gainMetadata);
  auto base = Decode(heif, context, primary), map = Decode(heif, context, gainItem);
  std::unique_ptr<viewer::ProfileLinearizer> icc;
  if (!base.icc.empty()) {
    icc = std::make_unique<viewer::ProfileLinearizer>(base.icc);
    base.primaries = icc->gamut();
  }
  if (base.primaries < 0) throw std::runtime_error("HEIF Gain Map 基础图色域不支持");
  const double scale = std::min(1.0, 2048.0 / std::max(base.width, base.height));
  const int outputWidth = std::max(1, int(base.width * scale)), outputHeight = std::max(1, int(base.height * scale));
  std::cout << "FVGAIN32 " << outputWidth << ' ' << outputHeight << ' ' << base.primaries << '\n';
  // Reconstruct the source's full HDR rendition; display peak mapping belongs
  // downstream. If the base is HDR, retain that base rather than reducing it.
  const float weight = std::clamp(
      (5.622f - gain.baseHeadroom) /
          (gain.alternateHeadroom - gain.baseHeadroom),
      0.0f, 1.0f);
  const float baseMax = float((uint32_t(1) << base.bits) - 1), mapMax = float((uint32_t(1) << map.bits) - 1);
  std::vector<float> row(size_t(outputWidth) * 3);
  for (int y = 0; y < outputHeight; ++y) {
    for (int x = 0; x < outputWidth; ++x) {
      const int bx = std::min(base.width - 1, int(x / scale)), by = std::min(base.height - 1, int(y / scale));
      const auto* pixel = base.values.data() + (size_t(by) * base.width + bx) * 4;
      for (int c = 0; c < 3; ++c) row[x * 3 + c] = icc ? pixel[c] / baseMax : ToLinear(pixel[c] / baseMax, base.transfer);
    }
    if (icc) icc->Convert(row.data(), outputWidth);
    for (int x = 0; x < outputWidth; ++x) {
      const int bx = std::min(base.width - 1, int(x / scale)), by = std::min(base.height - 1, int(y / scale));
      const int gx = std::min(map.width - 1, bx * map.width / base.width), gy = std::min(map.height - 1, by * map.height / base.height);
      const auto* basePixel = base.values.data() + (size_t(by) * base.width + bx) * 4;
      const auto* mapPixel = map.values.data() + (size_t(gy) * map.width + gx) * 4;
      float result[4]{};
      for (int channel = 0; channel < 3; ++channel) {
        const float mapValue = std::clamp(mapPixel[channel] / mapMax, 0.0f, 1.0f);
        const float logGain = gain.min[channel] + (gain.max[channel] - gain.min[channel]) * std::pow(mapValue, 1.0f / gain.gamma[channel]);
        const float linear = row[x * 3 + channel];
        result[channel] =
            (linear + gain.baseOffset[channel]) * std::exp2(logGain * weight) -
            gain.alternateOffset[channel];
        if (!std::isfinite(result[channel]) || std::abs(result[channel]) > 65504) throw std::runtime_error("HEIF Gain Map 重建值超限");
      }
      result[3] = basePixel[3] / baseMax;
      std::cout.write(reinterpret_cast<const char*>(result), sizeof(result));
    }
  }
}
}  // namespace

int Entry(const std::filesystem::path& path, bool metadata) {
  try {
#ifdef _WIN32
    _setmode(_fileno(stdout), _O_BINARY);
#endif
    Run(path, metadata);
    return std::cout.good() ? 0 : 2;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 2;
  }
}
#ifdef _WIN32
int wmain(int argc, wchar_t** argv) {
  if (argc != 3 || (std::wstring(argv[1]) != L"decode" && std::wstring(argv[1]) != L"metadata")) return 2;
  return Entry(argv[2], std::wstring(argv[1]) == L"metadata");
}
#else
int main(int argc, char** argv) {
  if (argc != 3 || (std::string(argv[1]) != "decode" && std::string(argv[1]) != "metadata")) return 2;
  return Entry(argv[2], std::string(argv[1]) == "metadata");
}
#endif
