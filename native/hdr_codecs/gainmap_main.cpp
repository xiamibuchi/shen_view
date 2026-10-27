#include <ultrahdr_api.h>
#ifdef VIEWER_HAS_AVIF
#include <avif/avif.h>
#endif
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <vector>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

namespace {
void Check(uhdr_error_info_t error) {
  if (error.error_code != UHDR_CODEC_OK)
    throw std::runtime_error(error.has_detail ? error.detail : "libultrahdr error");
}
float Half(uint16_t half) {
  const int exponent = (half >> 10) & 31;
  const int mantissa = half & 1023;
  const float sign = (half & 32768) ? -1.0f : 1.0f;
  return exponent == 0 ? sign * std::ldexp(static_cast<float>(mantissa), -24) :
      exponent == 31 ? 0.0f : sign * std::ldexp(1.0f + mantissa / 1024.0f, exponent - 15);
}
uint16_t ToHalf(float value) {
  uint32_t bits; std::memcpy(&bits, &value, sizeof(bits));
  const int exponent = static_cast<int>((bits >> 23) & 255) - 127 + 15;
  if (exponent <= 0) return 0;
  return static_cast<uint16_t>(((bits >> 16) & 0x8000) |
      (std::min(exponent, 30) << 10) | ((bits >> 13) & 1023));
}
float PqToLinear(uint16_t value) {
  constexpr double m1 = 2610.0 / 16384.0, m2 = 2523.0 / 32.0;
  constexpr double c1 = 3424.0 / 4096.0, c2 = 2413.0 / 128.0, c3 = 2392.0 / 128.0;
  const double p = std::pow(value / 65535.0, 1.0 / m2);
  return static_cast<float>(std::pow(std::max(p - c1, 0.0) / (c2 - c3 * p), 1.0 / m1) * (10000.0 / 203.0));
}
void Decode(const std::filesystem::path& path) {
  const auto size = std::filesystem::file_size(path);
  if (size < 4 || size > 64 * 1024 * 1024) throw std::runtime_error("Gain map input budget");
  std::vector<uint8_t> bytes(static_cast<size_t>(size));
  std::ifstream input(path, std::ios::binary);
  if (!input.read(reinterpret_cast<char*>(bytes.data()), bytes.size())) throw std::runtime_error("Read failed");
  std::unique_ptr<uhdr_codec_private_t, decltype(&uhdr_release_decoder)> decoder(uhdr_create_decoder(), uhdr_release_decoder);
  if (!decoder) throw std::runtime_error("Decoder unavailable");
  uhdr_compressed_image_t image{bytes.data(), bytes.size(), bytes.size(), UHDR_CG_UNSPECIFIED, UHDR_CT_UNSPECIFIED, UHDR_CR_UNSPECIFIED};
  Check(uhdr_dec_set_image(decoder.get(), &image));
  Check(uhdr_dec_set_out_img_format(decoder.get(), UHDR_IMG_FMT_64bppRGBAHalfFloat));
  Check(uhdr_dec_set_out_color_transfer(decoder.get(), UHDR_CT_LINEAR));
  // Reconstruct the full source rendition; display mapping belongs downstream.
  Check(uhdr_dec_set_out_max_display_boost(decoder.get(), 10000.0f / 203.0f));
  Check(uhdr_dec_probe(decoder.get()));
  const int w = uhdr_dec_get_image_width(decoder.get()), h = uhdr_dec_get_image_height(decoder.get());
  if (w < 1 || h < 1 || static_cast<int64_t>(w) * h > 16 * 1024 * 1024) throw std::runtime_error("Gain map pixel budget");
  const double scale = std::min(1.0, 2048.0 / std::max(w, h));
  if (scale < 1) Check(uhdr_add_effect_resize(decoder.get(), std::max(1, static_cast<int>(w * scale)), std::max(1, static_cast<int>(h * scale))));
  const auto* exif = uhdr_dec_get_exif(decoder.get());
  auto orientation = [](const uhdr_mem_block_t* block) {
    if (!block || block->data_sz < 14) return 1;
    const auto* b = static_cast<const uint8_t*>(block->data);
    size_t start = 0;
    while (start + 6 <= block->data_sz && std::memcmp(b + start, "Exif\0\0", 6) != 0) ++start;
    if (start + 14 > block->data_sz) return 1;
    const auto* t = b + start + 6;
    const auto length = block->data_sz - start - 6;
    const bool little = t[0] == 'I' && t[1] == 'I';
    auto u16 = [little](const uint8_t* p) { return static_cast<uint16_t>(little ? p[0] | p[1] << 8 : p[0] << 8 | p[1]); };
    auto u32 = [little](const uint8_t* p) { return little ? uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24 : uint32_t(p[3]) | uint32_t(p[2]) << 8 | uint32_t(p[1]) << 16 | uint32_t(p[0]) << 24; };
    if ((!little && !(t[0] == 'M' && t[1] == 'M')) || u16(t + 2) != 42) return 1;
    const auto ifd = u32(t + 4);
    if (ifd < 8 || ifd > length - 2) return 1;
    const auto* entries = t + ifd;
    const auto count = u16(entries);
    for (uint16_t i = 0; i < count && uint64_t(ifd) + 2 + i * 12 + 12 <= length; ++i) {
      const auto* e = entries + 2 + i * 12;
      if (u16(e) == 0x0112 && u16(e + 2) == 3 && u32(e + 4) == 1) return std::clamp<int>(u16(e + 8), 1, 8);
    }
    return 1;
  }(exif);
  // libultrahdr preserves EXIF but does not apply its orientation. Apply it
  // before decode so thumbnails and native HDR use the same displayed pose.
  switch (orientation) {
    case 2: Check(uhdr_add_effect_mirror(decoder.get(), UHDR_MIRROR_HORIZONTAL)); break;
    case 3: Check(uhdr_add_effect_rotate(decoder.get(), 180)); break;
    case 4: Check(uhdr_add_effect_mirror(decoder.get(), UHDR_MIRROR_VERTICAL)); break;
    case 5: Check(uhdr_add_effect_mirror(decoder.get(), UHDR_MIRROR_HORIZONTAL)); Check(uhdr_add_effect_rotate(decoder.get(), 270)); break;
    case 6: Check(uhdr_add_effect_rotate(decoder.get(), 90)); break;
    case 7: Check(uhdr_add_effect_mirror(decoder.get(), UHDR_MIRROR_HORIZONTAL)); Check(uhdr_add_effect_rotate(decoder.get(), 90)); break;
    case 8: Check(uhdr_add_effect_rotate(decoder.get(), 270)); break;
    default: break;
  }
  Check(uhdr_decode(decoder.get()));
  const auto* decoded = uhdr_get_decoded_image(decoder.get());
  if (!decoded || decoded->fmt != UHDR_IMG_FMT_64bppRGBAHalfFloat || decoded->ct != UHDR_CT_LINEAR) throw std::runtime_error("Nonlinear gain map output");
  std::cout << "FVGAIN32 " << decoded->w << ' ' << decoded->h << ' ' << decoded->cg << '\n';
  std::vector<float> row(decoded->w * 4);
  const auto* pixels = static_cast<const uint16_t*>(decoded->planes[0]);
  for (unsigned y = 0; y < decoded->h; ++y) {
    for (unsigned x = 0; x < decoded->w * 4; ++x) row[x] = Half(pixels[y * decoded->stride[0] * 4 + x]);
    std::cout.write(reinterpret_cast<const char*>(row.data()), row.size() * sizeof(float));
  }
}

#ifdef VIEWER_HAS_AVIF
void FixtureAvif(const std::filesystem::path& path) {
  avifImage* image = avifImageCreate(192, 96, 8, AVIF_PIXEL_FORMAT_YUV444);
  image->colorPrimaries = AVIF_COLOR_PRIMARIES_BT709;
  image->transferCharacteristics = AVIF_TRANSFER_CHARACTERISTICS_SRGB;
  image->matrixCoefficients = AVIF_MATRIX_COEFFICIENTS_IDENTITY;
  avifImageAllocatePlanes(image, AVIF_PLANES_YUV);
  image->gainMap = avifGainMapCreate();
  auto* gm = image->gainMap;
  gm->image = avifImageCreate(192, 96, 8, AVIF_PIXEL_FORMAT_YUV400);
  gm->image->matrixCoefficients = AVIF_MATRIX_COEFFICIENTS_BT601;
  avifImageAllocatePlanes(gm->image, AVIF_PLANES_YUV);
  gm->alternateHdrHeadroom = {3, 1};
  gm->altColorPrimaries = AVIF_COLOR_PRIMARIES_BT709;
  gm->altTransferCharacteristics = AVIF_TRANSFER_CHARACTERISTICS_LINEAR;
  for (int c = 0; c < 3; ++c) { gm->gainMapMin[c] = {0, 1}; gm->gainMapMax[c] = {3, 1}; }
  for (uint32_t y = 0; y < 96; ++y) for (uint32_t x = 0; x < 192; ++x) {
    for (int c = 0; c < 3; ++c) image->yuvPlanes[c][y * image->yuvRowBytes[c] + x] = 188;
    gm->image->yuvPlanes[0][y * gm->image->yuvRowBytes[0] + x] = static_cast<uint8_t>(x / 64 * 127 + (x >= 128 ? 1 : 0));
  }
  avifEncoder* encoder = avifEncoderCreate();
  encoder->speed = AVIF_SPEED_FASTEST; encoder->quality = 100; encoder->qualityGainMap = 100;
  avifRWData bytes = AVIF_DATA_EMPTY;
  const auto result = avifEncoderWrite(encoder, image, &bytes);
  if (result != AVIF_RESULT_OK) {
    const std::string error = avifResultToString(result);
    avifEncoderDestroy(encoder); avifImageDestroy(image);
    throw std::runtime_error(error);
  }
  std::ofstream out(path, std::ios::binary);
  out.write(reinterpret_cast<const char*>(bytes.data), bytes.size);
  avifRWDataFree(&bytes); avifEncoderDestroy(encoder); avifImageDestroy(image);
  if (!out) throw std::runtime_error("AVIF fixture write failed");
}

void DecodeAvif(const std::filesystem::path& path) {
  const auto size = std::filesystem::file_size(path);
  if (size < 16 || size > 128 * 1024 * 1024) throw std::runtime_error("AVIF input budget");
  std::vector<uint8_t> bytes(static_cast<size_t>(size));
  std::ifstream input(path, std::ios::binary);
  if (!input.read(reinterpret_cast<char*>(bytes.data()), bytes.size())) throw std::runtime_error("Read failed");
  avifDecoder* decoder = avifDecoderCreate();
  if (!decoder) throw std::runtime_error("AVIF decoder unavailable");
  decoder->imageContentToDecode = AVIF_IMAGE_CONTENT_ALL;
  decoder->imageSizeLimit = 16 * 1024 * 1024;
  decoder->imageDimensionLimit = 8192;
  avifImage* decodedImage = avifImageCreateEmpty();
  if (!decodedImage) { avifDecoderDestroy(decoder); throw std::runtime_error("AVIF image unavailable"); }
  const avifResult result = avifDecoderReadMemory(decoder, decodedImage, bytes.data(), bytes.size());
  if (result != AVIF_RESULT_OK || !decoder->image) {
    const std::string error = decoder->diag.error;
    avifImageDestroy(decodedImage); avifDecoderDestroy(decoder);
    throw std::runtime_error(error.empty() ? "AVIF decode failed" : error);
  }
  const avifImage* image = decodedImage;
  if (!image->gainMap || !image->gainMap->image) {
    avifImageDestroy(decodedImage); avifDecoderDestroy(decoder);
    throw std::runtime_error("AVIF gain map not present");
  }
  avifRGBImage output{};
  output.width = image->width; output.height = image->height;
  // libavif 1.4.2 clamps RGB gain-map results to [0,1] even for f16.
  // Request uint16 PQ to preserve highlights, then explicitly apply the EOTF.
  output.depth = 16; output.format = AVIF_RGB_FORMAT_RGBA; output.isFloat = AVIF_FALSE;
  avifContentLightLevelInformationBox clli{};
  avifDiagnostics diag{};
  const float baseHeadroom = static_cast<float>(image->gainMap->baseHdrHeadroom.n) / image->gainMap->baseHdrHeadroom.d;
  const float altHeadroom = static_cast<float>(image->gainMap->alternateHdrHeadroom.n) / image->gainMap->alternateHdrHeadroom.d;
  const float headroom = std::min(5.622f, std::max(baseHeadroom, altHeadroom));
  const avifResult apply = avifImageApplyGainMap(
      image, image->gainMap, headroom, AVIF_COLOR_PRIMARIES_BT2020,
      AVIF_TRANSFER_CHARACTERISTICS_SMPTE2084, &output, &clli, &diag);
  if (apply != AVIF_RESULT_OK || !output.pixels) {
    const std::string error = diag.error;
    avifImageDestroy(decodedImage); avifDecoderDestroy(decoder);
    throw std::runtime_error(error.empty() ? "AVIF gain map synthesis failed" : error);
  }
  if (output.width < 1 || output.height < 1 || static_cast<uint64_t>(output.width) * output.height > 16 * 1024 * 1024) {
    avifRGBImageFreePixels(&output); avifImageDestroy(decodedImage); avifDecoderDestroy(decoder);
    throw std::runtime_error("AVIF gain map pixel budget");
  }
  // Crop/rotate the reconstructed rendition, never the base alone.
  avifCropRect crop{0, 0, output.width, output.height};
  if (image->transformFlags & AVIF_TRANSFORM_CLAP) {
    if (!avifCropRectFromCleanApertureBox(&crop, &image->clap, image->width, image->height, &diag)) {
      avifRGBImageFreePixels(&output); avifImageDestroy(decodedImage); avifDecoderDestroy(decoder);
      throw std::runtime_error("AVIF crop");
    }
  }
  const int angle = (image->transformFlags & AVIF_TRANSFORM_IROT) ? image->irot.angle : 0;
  const bool mirror = (image->transformFlags & AVIF_TRANSFORM_IMIR) != 0;
  const double scale = std::min(1.0, 2048.0 / std::max(crop.width, crop.height));
  const uint32_t sw = std::max(1U, static_cast<uint32_t>(crop.width * scale));
  const uint32_t sh = std::max(1U, static_cast<uint32_t>(crop.height * scale));
  const uint32_t ow = angle % 2 ? sh : sw, oh = angle % 2 ? sw : sh;
  std::cout << "FVGAIN32 " << ow << ' ' << oh << " 2\n";
  const auto* pixels = reinterpret_cast<const uint16_t*>(output.pixels);
  for (uint32_t y = 0; y < oh; ++y) {
    for (uint32_t x = 0; x < ow; ++x) {
      uint32_t mx = x, my = y;
      if (mirror) {
        if (image->imir.axis == 0) my = oh - 1 - my; else mx = ow - 1 - mx;
      }
      const uint32_t sx = angle == 0 ? mx : angle == 1 ? sw - 1 - my : angle == 2 ? sw - 1 - mx : my;
      const uint32_t sy = angle == 0 ? my : angle == 1 ? mx : angle == 2 ? sh - 1 - my : sh - 1 - mx;
      const uint32_t px = crop.x + sx * crop.width / sw, py = crop.y + sy * crop.height / sh;
      const uint16_t* p = pixels + py * (output.rowBytes / 2) + px * 4;
      const float rgba[] = {PqToLinear(p[0]), PqToLinear(p[1]), PqToLinear(p[2]), p[3] / 65535.0f};
      std::cout.write(reinterpret_cast<const char*>(rgba), sizeof(rgba));
    }
  }
  avifRGBImageFreePixels(&output);
  avifImageDestroy(decodedImage); avifDecoderDestroy(decoder);
}
#endif

// Owned deterministic fixture; this uses the actual codec, not a fake sidecar.
void Fixture(const std::filesystem::path& path, uhdr_codec_t codec = UHDR_CODEC_JPG) {
  constexpr int w = 384, h = 192;
  const float stops[] = {0.18f, 1, 2, 4, 8, 16};
  std::vector<uint16_t> data(w * h * 4);
  for (int y = 0; y < h; ++y) for (int x = 0; x < w; ++x) {
    const float level = stops[x / 64] * (0.65f + 0.35f * (x % 64) / 63);
    const float color[] = {y < 128 ? 1.0f : 0.05f, y < 64 ? 1.0f : y < 128 ? 0.25f : 0.4f, y < 64 || y >= 128 ? 1.0f : 0.05f};
    for (int c = 0; c < 3; ++c) data[(y * w + x) * 4 + c] = ToHalf(level * color[c]);
    data[(y * w + x) * 4 + 3] = ToHalf(1);
  }
  std::unique_ptr<uhdr_codec_private_t, decltype(&uhdr_release_encoder)> encoder(uhdr_create_encoder(), uhdr_release_encoder);
  if (!encoder) throw std::runtime_error("Encoder unavailable");
  Check(uhdr_enc_set_output_format(encoder.get(), codec));
  uhdr_raw_image_t source{};
  source.fmt = UHDR_IMG_FMT_64bppRGBAHalfFloat; source.cg = UHDR_CG_BT_709;
  source.ct = UHDR_CT_LINEAR; source.range = UHDR_CR_FULL_RANGE;
  source.w = w; source.h = h; source.planes[0] = data.data(); source.stride[0] = w;
  Check(uhdr_enc_set_raw_image(encoder.get(), &source, UHDR_HDR_IMG));
  Check(uhdr_enc_set_quality(encoder.get(), 98, UHDR_BASE_IMG));
  Check(uhdr_enc_set_quality(encoder.get(), 98, UHDR_GAIN_MAP_IMG));
  Check(uhdr_encode(encoder.get()));
  const auto* encoded = uhdr_get_encoded_stream(encoder.get());
  if (!encoded) throw std::runtime_error("Encode failed");
  std::ofstream output(path, std::ios::binary);
  output.write(static_cast<const char*>(encoded->data), encoded->data_sz);
  if (!output) throw std::runtime_error("Write failed");
}
int Run(int fixture, const std::filesystem::path& path) {
  try {
#ifdef _WIN32
    _setmode(_fileno(stdout), _O_BINARY);
#endif
#ifdef VIEWER_HAS_AVIF
    if (fixture == 2) FixtureAvif(path); else
#endif
    if (fixture == 1) Fixture(path); else {
#ifdef VIEWER_HAS_AVIF
      const auto ext = path.extension().wstring();
      if (ext == L".avif" || ext == L".AVIF") DecodeAvif(path); else
#endif
      Decode(path);
    }
    return std::cout.good() ? 0 : 1;
  } catch (const std::exception& error) { std::cerr << error.what(); return 1; }
}
}
#ifdef _WIN32
int wmain(int argc, wchar_t** argv) {
  if (argc != 3 || (std::wstring(argv[1]) != L"decode" && std::wstring(argv[1]) != L"fixture" && std::wstring(argv[1]) != L"fixture-avif")) return 2;
  const auto mode = std::wstring(argv[1]);
  return Run(mode == L"fixture" ? 1 : mode == L"fixture-avif" ? 2 : 0, argv[2]);
}
#else
int main(int argc, char** argv) {
  if (argc != 3 || (std::string(argv[1]) != "decode" && std::string(argv[1]) != "fixture" && std::string(argv[1]) != "fixture-avif")) return 2;
  const auto mode = std::string(argv[1]);
  return Run(mode == "fixture" ? 1 : mode == "fixture-avif" ? 2 : 0, argv[2]);
}
#endif
