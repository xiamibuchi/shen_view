#include <avif/avif.h>
#include <lcms2.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

namespace {
constexpr uint32_t kMaxPixels = 16 * 1024 * 1024;
constexpr int kMaxFrames = 10000;
using Decoder = std::unique_ptr<avifDecoder, decltype(&avifDecoderDestroy)>;
using Image = std::unique_ptr<avifImage, decltype(&avifImageDestroy)>;

void Check(avifResult result) {
  if (result != AVIF_RESULT_OK) throw std::runtime_error(avifResultToString(result));
}

struct FileReader {
  avifIO io{};
  std::ifstream file;
  std::vector<uint8_t> buffer;
  explicit FileReader(const std::filesystem::path& path) : file(path, std::ios::binary) {
    if (!file) throw std::runtime_error("Cannot open AVIF file");
    io.sizeHint = std::filesystem::file_size(path);
    io.data = this;
    io.destroy = [](avifIO* io) { delete static_cast<FileReader*>(io->data); };
    io.read = [](avifIO* io, uint32_t flags, uint64_t offset, size_t size, avifROData* out) {
      if (flags != 0 || offset > io->sizeHint) return AVIF_RESULT_IO_ERROR;
      auto* reader = static_cast<FileReader*>(io->data);
      size = static_cast<size_t>(std::min<uint64_t>(size, io->sizeHint - offset));
      try {
        reader->buffer.resize(size);
        reader->file.clear();
        reader->file.seekg(static_cast<std::streamoff>(offset));
        if (size) reader->file.read(reinterpret_cast<char*>(reader->buffer.data()), size);
        if (!reader->file) return AVIF_RESULT_IO_ERROR;
        out->data = reader->buffer.data();
        out->size = size;
        return AVIF_RESULT_OK;
      } catch (...) {
        return AVIF_RESULT_IO_ERROR;
      }
    };
  }
};

Decoder Open(const std::filesystem::path& path, uint32_t maxPixels) {
  if (std::filesystem::file_size(path) > 128 * 1024 * 1024)
    throw std::runtime_error("AVIF file budget exceeded");
  Decoder decoder(avifDecoderCreate(), avifDecoderDestroy);
  if (!decoder) throw std::bad_alloc();
  decoder->maxThreads = 2;
  decoder->imageSizeLimit = std::min(kMaxPixels, maxPixels);
  decoder->imageDimensionLimit = 65536;
  decoder->imageCountLimit = kMaxFrames;
  decoder->allowProgressive = AVIF_FALSE;
  // libavif's fopen-based reader loses non-ASCII Windows paths. Keep native
  // filesystem paths and a reusable bounded buffer without loading the file.
  auto reader = std::make_unique<FileReader>(path);
  avifDecoderSetIO(decoder.get(), &reader->io);
  reader.release();
  Check(avifDecoderParse(decoder.get()));
  if (decoder->imageSequenceTrackPresent) {
    Check(avifDecoderSetSource(decoder.get(), AVIF_DECODER_SOURCE_TRACKS));
    Check(avifDecoderParse(decoder.get()));
  }
  return decoder;
}

void Describe(avifDecoder* d) {
  std::cout << "{\"width\":" << d->image->width << ",\"height\":" << d->image->height
            << ",\"depth\":" << d->image->depth << ",\"alpha\":" << (d->alphaPresent ? "true" : "false")
            << ",\"sequence\":" << (d->imageSequenceTrackPresent ? "true" : "false")
            << ",\"repetitions\":" << d->repetitionCount << ",\"durations\":[";
  for (int i = 0; i < d->imageCount; ++i) {
    avifImageTiming timing{};
    Check(avifDecoderNthImageTiming(d, i, &timing));
    if (i) std::cout << ',';
    const double ms = timing.duration * 1000;
    if (!std::isfinite(ms) || ms < 0 || ms > 2147483647)
      throw std::runtime_error("Invalid AVIF timing");
    std::cout << std::llround(ms);
  }
  std::cout << "]}\n" << std::flush;
}

double Linear(double v, int transfer) {
  switch (transfer) {
    case AVIF_TRANSFER_CHARACTERISTICS_LINEAR: return v;
    case AVIF_TRANSFER_CHARACTERISTICS_BT470M: return std::pow(v, 2.2);
    case AVIF_TRANSFER_CHARACTERISTICS_BT470BG: return std::pow(v, 2.8);
    case AVIF_TRANSFER_CHARACTERISTICS_BT709:
    case AVIF_TRANSFER_CHARACTERISTICS_BT601:
    case AVIF_TRANSFER_CHARACTERISTICS_BT2020_10BIT:
    case AVIF_TRANSFER_CHARACTERISTICS_BT2020_12BIT:
      return v < .081 ? v / 4.5 : std::pow((v + .099) / 1.099, 1 / .45);
    case AVIF_TRANSFER_CHARACTERISTICS_PQ: {
      const double p = std::pow(v, 32.0 / 2523);
      return 10000 / 203.0 * std::pow(std::max(p - 3424.0 / 4096, 0.0) /
          (2413.0 / 128 - 2392.0 / 128 * p), 16384.0 / 2610);
    }
    case AVIF_TRANSFER_CHARACTERISTICS_HLG:
      return v <= .5 ? v * v / 3 : (std::exp((v - .55991073) / .17883277) + .28466892) / 12;
    case AVIF_TRANSFER_CHARACTERISTICS_SRGB:
    case AVIF_TRANSFER_CHARACTERISTICS_UNSPECIFIED:
    case AVIF_TRANSFER_CHARACTERISTICS_UNKNOWN:
      return v <= .04045 ? v / 12.92 : std::pow((v + .055) / 1.055, 2.4);
    default: throw std::runtime_error("Unsupported AVIF transfer characteristics");
  }
}

class ColorTransform {
 public:
  explicit ColorTransform(const avifImage* image) : context_(cmsCreateContext(nullptr, nullptr)) {
    if (!context_) throw std::bad_alloc();
    try {
      transfer_ = image->transferCharacteristics;
      hdr_ = image->icc.size == 0 && (transfer_ == 16 || transfer_ == 18);
      cmsHPROFILE input = nullptr;
      if (image->icc.size) {
        if (image->icc.size > 4 * 1024 * 1024) throw std::runtime_error("ICC budget exceeded");
        input = cmsOpenProfileFromMemTHR(context_, image->icc.data, static_cast<cmsUInt32Number>(image->icc.size));
      } else {
        float p[8];
        avifColorPrimariesGetValues(image->colorPrimaries, p);
        cmsCIExyY white{p[6], p[7], 1};
        cmsCIExyYTRIPLE primaries{{p[0], p[1], 1}, {p[2], p[3], 1}, {p[4], p[5], 1}};
        std::vector<float> samples(4096);
        for (size_t i = 0; i < samples.size(); ++i)
          samples[i] = static_cast<float>(hdr_ ? double(i) / 4095 : Linear(double(i) / 4095, transfer_));
        // A tabulated identity curve clamps HDR values above 1. Use a true
        // linear curve so highlights reach the SDR tone mapper unclipped.
        cmsToneCurve* curve = hdr_ ? cmsBuildGamma(context_, 1) :
            cmsBuildTabulatedToneCurveFloat(context_, static_cast<cmsUInt32Number>(samples.size()), samples.data());
        if (!curve) throw std::runtime_error("AVIF tone curve");
        cmsToneCurve* curves[]{curve, curve, curve};
        input = cmsCreateRGBProfileTHR(context_, &white, &primaries, curves);
        cmsFreeToneCurve(curve);
      }
      if (!input) throw std::runtime_error("Invalid AVIF color profile");
      cmsCIExyY white{.3127, .329, 1};
      cmsCIExyYTRIPLE primaries{{.64, .33, 1}, {.30, .60, 1}, {.15, .06, 1}};
      cmsToneCurve* curve = cmsBuildGamma(context_, 1);
      cmsToneCurve* curves[]{curve, curve, curve};
      cmsHPROFILE output = cmsCreateRGBProfileTHR(context_, &white, &primaries, curves);
      cmsFreeToneCurve(curve);
      transform_ = output ? cmsCreateTransformTHR(context_, input, TYPE_RGB_FLT, output, TYPE_RGB_FLT,
          INTENT_RELATIVE_COLORIMETRIC, cmsFLAGS_NOOPTIMIZE) : nullptr;
      cmsCloseProfile(input);
      if (output) cmsCloseProfile(output);
      if (!transform_) throw std::runtime_error("AVIF color transform");
    } catch (...) {
      cmsDeleteContext(context_);
      throw;
    }
  }
  ~ColorTransform() { cmsDeleteTransform(transform_); cmsDeleteContext(context_); }
  void Convert(float* rgb, uint32_t count) const {
    if (hdr_) {
      for (uint32_t i = 0; i < count; ++i) {
        for (int c = 0; c < 3; ++c) rgb[i * 3 + c] = static_cast<float>(Linear(rgb[i * 3 + c], transfer_));
        if (transfer_ == 18) {
          const double y = .2627 * rgb[i * 3] + .6780 * rgb[i * 3 + 1] + .0593 * rgb[i * 3 + 2];
          const double gain = 1000 / 203.0 * std::pow(std::max(y, 0.0), .2);
          for (int c = 0; c < 3; ++c) rgb[i * 3 + c] *= static_cast<float>(gain);
        }
      }
    }
    cmsDoTransform(transform_, rgb, rgb, count);
    for (uint32_t i = 0; i < count * 3; ++i) {
      double v = std::max(0.0f, rgb[i]);
      if (hdr_) v /= 1 + v;
      rgb[i] = static_cast<float>(v <= .0031308 ? 12.92 * v : 1.055 * std::pow(v, 1 / 2.4) - .055);
    }
  }
 private:
  cmsContext context_ = nullptr;
  cmsHTRANSFORM transform_ = nullptr;
  int transfer_ = 13;
  bool hdr_ = false;
};

void Frame(avifDecoder* decoder, uint32_t index) {
  Check(avifDecoderNthImage(decoder, index));
  const avifImage* image = decoder->image;
  Image view(avifImageCreateEmpty(), avifImageDestroy);
  if (!view) throw std::bad_alloc();
  if (image->transformFlags & AVIF_TRANSFORM_CLAP) {
    avifCropRect crop{};
    Check(avifCropRectFromCleanApertureBox(&crop, &image->clap, image->width, image->height, &decoder->diag) ?
        AVIF_RESULT_OK : AVIF_RESULT_INVALID_ARGUMENT);
    Check(avifImageSetViewRect(view.get(), image, &crop));
    image = view.get();
  }
  avifRGBImage rgb{};
  avifRGBImageSetDefaults(&rgb, image);
  rgb.depth = 16;
  rgb.format = AVIF_RGB_FORMAT_RGBA;
  rgb.alphaPremultiplied = AVIF_FALSE;
  rgb.maxThreads = 2;
  std::vector<uint16_t> pixels(size_t(image->width) * image->height * 4);
  rgb.pixels = reinterpret_cast<uint8_t*>(pixels.data());
  rgb.rowBytes = image->width * 8;
  Check(avifImageYUVToRGB(image, &rgb));
  const auto* original = decoder->image;
  const int rotation = (original->transformFlags & AVIF_TRANSFORM_IROT) ? original->irot.angle : 0;
  const bool mirror = (original->transformFlags & AVIF_TRANSFORM_IMIR) != 0;
  const uint32_t width = rotation % 2 ? image->height : image->width;
  const uint32_t height = rotation % 2 ? image->width : image->height;
  ColorTransform color(original);
  std::vector<uint8_t> output(size_t(width) * height * 4);
  std::vector<float> row(size_t(image->width) * 3);
  for (uint32_t y = 0; y < image->height; ++y) {
    for (uint32_t x = 0; x < image->width; ++x)
      for (int c = 0; c < 3; ++c) row[x * 3 + c] = pixels[(size_t(y) * image->width + x) * 4 + c] / 65535.0f;
    color.Convert(row.data(), image->width);
    for (uint32_t x = 0; x < image->width; ++x) {
      uint32_t dx = x, dy = y;
      if (rotation == 1) { dx = y; dy = image->width - 1 - x; }
      if (rotation == 2) { dx = image->width - 1 - x; dy = image->height - 1 - y; }
      if (rotation == 3) { dx = image->height - 1 - y; dy = x; }
      if (mirror) {
        if (original->imir.axis == 0) dy = height - 1 - dy;
        else dx = width - 1 - dx;
      }
      const size_t at = (size_t(dy) * width + dx) * 4;
      output[at + 3] = static_cast<uint8_t>((pixels[(size_t(y) * image->width + x) * 4 + 3] + 128) / 257);
      for (int c = 0; c < 3; ++c)
        output[at + c] = static_cast<uint8_t>(std::lround(std::clamp(row[x * 3 + c], 0.0f, 1.0f) * output[at + 3]));
    }
  }
  std::cout << "FRAME " << width << ' ' << height << ' ' << output.size() << '\n';
  std::cout.write(reinterpret_cast<const char*>(output.data()), output.size());
  std::cout.flush();
}

void Fixture(const std::filesystem::path& path, int repeats, int depth, int transfer, const std::string& kind) {
  const bool single = kind == "single";
  const bool progressive = kind == "progressive";
  Image image(avifImageCreate(48, 32, depth, AVIF_PIXEL_FORMAT_YUV444), avifImageDestroy);
  image->colorPrimaries = transfer == 16 || transfer == 18 ? AVIF_COLOR_PRIMARIES_BT2020 : AVIF_COLOR_PRIMARIES_BT709;
  image->transferCharacteristics = static_cast<avifTransferCharacteristics>(transfer);
  image->matrixCoefficients = AVIF_MATRIX_COEFFICIENTS_IDENTITY;
  if (kind == "icc") {
    cmsHPROFILE profile = cmsCreate_sRGBProfile();
    cmsUInt32Number size = 0;
    cmsSaveProfileToMem(profile, nullptr, &size);
    std::vector<uint8_t> icc(size);
    cmsSaveProfileToMem(profile, icc.data(), &size);
    cmsCloseProfile(profile);
    Check(avifImageSetProfileICC(image.get(), icc.data(), size));
  }
  std::unique_ptr<avifEncoder, decltype(&avifEncoderDestroy)> encoder(avifEncoderCreate(), avifEncoderDestroy);
  encoder->maxThreads = 2;
  encoder->speed = 10;
  encoder->quality = 100;
  encoder->qualityAlpha = 100;
  encoder->timescale = 1000;
  encoder->repetitionCount = repeats;
  if (progressive) encoder->extraLayerCount = 1;
  avifRGBImage rgb{};
  avifRGBImageSetDefaults(&rgb, image.get());
  rgb.depth = 16; rgb.format = AVIF_RGB_FORMAT_RGBA; rgb.rowBytes = 48 * 8;
  std::vector<uint16_t> pixels(48 * 32 * 4);
  rgb.pixels = reinterpret_cast<uint8_t*>(pixels.data());
  const int colors[3][3]{{50000, 10000, 5000}, {10000, 50000, 5000}, {5000, 10000, 50000}};
  for (int frame = 0; frame < (single ? 1 : progressive ? 2 : 3); ++frame) {
    if (progressive) encoder->quality = frame == 0 ? 30 : 100;
    for (int i = 0; i < 48 * 32; ++i) {
      for (int c = 0; c < 3; ++c) pixels[i * 4 + c] = static_cast<uint16_t>(colors[progressive ? 0 : frame][c]);
      pixels[i * 4 + 3] = i % 48 < 24 ? 32768 : 65535;
    }
    Check(avifImageRGBToYUV(image.get(), &rgb));
    Check(avifEncoderAddImage(encoder.get(), image.get(), (frame + 1) * 100, AVIF_ADD_IMAGE_FLAG_NONE));
  }
  avifRWData encoded = AVIF_DATA_EMPTY;
  Check(avifEncoderFinish(encoder.get(), &encoded));
  std::ofstream file(path, std::ios::binary);
  file.write(reinterpret_cast<const char*>(encoded.data), encoded.size);
  avifRWDataFree(&encoded);
  if (!file) throw std::runtime_error("AVIF fixture write failed");
}

int Run(const std::vector<std::filesystem::path>& args) {
  try {
    if (args.size() < 3) throw std::runtime_error("Expected probe, serve or fixture and a path");
    const auto mode = args[1].string();
    if (mode == "fixture") {
      Fixture(args[2], args.size() > 3 ? std::stoi(args[3].string()) : -1,
          args.size() > 4 ? std::stoi(args[4].string()) : 8,
          args.size() > 5 ? std::stoi(args[5].string()) : 13, args.size() > 6 ? args[6].string() : "");
      return 0;
    }
    const auto limit = args.size() > 3 ? std::stoul(args[3].string()) : kMaxPixels;
    auto decoder = Open(args[2], static_cast<uint32_t>(std::min<unsigned long>(kMaxPixels, limit)));
    Describe(decoder.get());
    if (mode == "probe") return 0;
    if (mode != "serve") throw std::runtime_error("Unknown AVIF command");
    // One request produces one frame. Paused animations consume no CPU or pipe buffers.
    std::string command;
    while (std::getline(std::cin, command)) {
      if (command == "close") break;
      if (command.size() > 16) throw std::runtime_error("Invalid AVIF command");
      size_t end = 0;
      const int index = std::stoi(command, &end);
      if (end != command.size() || index < 0 || index >= decoder->imageCount)
        throw std::runtime_error("Invalid AVIF frame index");
      Frame(decoder.get(), static_cast<uint32_t>(index));
    }
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
}  // namespace

#ifdef _WIN32
int wmain(int argc, wchar_t** argv) {
  _setmode(_fileno(stdout), _O_BINARY);
  _setmode(_fileno(stdin), _O_BINARY);
  return Run(std::vector<std::filesystem::path>(argv, argv + argc));
}
#else
int main(int argc, char** argv) {
  return Run(std::vector<std::filesystem::path>(argv, argv + argc));
}
#endif
