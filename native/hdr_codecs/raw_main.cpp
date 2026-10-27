#include <libraw/libraw.h>
#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <vector>
#include <cmath>
#include <sstream>
#include <ctime>
#include <iomanip>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

void Check(int result) {
  if (result != LIBRAW_SUCCESS) throw std::runtime_error(libraw_strerror(result));
}
struct OutputLimit {
  unsigned width = 0, height = 0;
  uint64_t pixels = 16ULL * 1024 * 1024;
  double scale(unsigned w, unsigned h) const {
    double result = 1;
    if (width) result = std::min(result, double(width) / w);
    if (height) result = std::min(result, double(height) / h);
    return std::min(result, std::sqrt(double(pixels) / (uint64_t(w) * h)));
  }
};
std::string JsonString(const char* value) {
  std::ostringstream out; out << '"';
  for (const unsigned char* p = reinterpret_cast<const unsigned char*>(value); *p; ++p) {
    if (*p == '"' || *p == '\\') out << '\\' << *p;
    else if (*p >= 32) out << *p;
  }
  return out.str() + '"';
}
void Inspect(LibRaw& raw) {
  const auto& s = raw.imgdata.sizes;
  const auto& other = raw.imgdata.other;
  const bool turned = s.flip & 4;
  unsigned previewBytes = 0;
  for (int i = 0; i < raw.imgdata.thumbs_list.thumbcount; ++i)
    previewBytes = std::max(previewBytes, raw.imgdata.thumbs_list.thumblist[i].tlength);
  std::cout << "{\"width\":" << (turned ? s.height : s.width)
            << ",\"height\":" << (turned ? s.width : s.height)
            << ",\"make\":" << JsonString(raw.imgdata.idata.make)
            << ",\"model\":" << JsonString(raw.imgdata.idata.model)
            << ",\"iso\":" << other.iso_speed
            << ",\"exposureTime\":" << other.shutter
            << ",\"fNumber\":" << other.aperture
            << ",\"focalLength\":" << other.focal_len
            << ",\"lensModel\":" << JsonString(raw.imgdata.lens.Lens)
            << ",\"creator\":" << JsonString(other.artist)
            << ",\"rawPreviewBytes\":" << previewBytes;
  // LibRaw parses EXIF with mktime. Reverse that with localtime, without
  // inventing a timezone for camera clocks that did not record one.
  if (other.timestamp > 0) {
    if (const auto* date = std::localtime(&other.timestamp)) {
      std::cout << ",\"dateTimeOriginal\":\"" << std::put_time(date, "%Y:%m:%d %H:%M:%S") << '"';
    }
  }
  const auto& gps = other.parsed_gps;
  if (gps.gpsparsed && (gps.latref == 'N' || gps.latref == 'S') &&
      (gps.longref == 'E' || gps.longref == 'W')) {
    std::cout << ",\"gpsLatitude\":\"" << gps.latitude[0] << ", " << gps.latitude[1] << ", " << gps.latitude[2]
              << "\",\"gpsLatitudeRef\":\"" << gps.latref
              << "\",\"gpsLongitude\":\"" << gps.longitude[0] << ", " << gps.longitude[1] << ", " << gps.longitude[2]
              << "\",\"gpsLongitudeRef\":\"" << gps.longref << '"';
  }
  std::cout << '}';
}
void Preview(LibRaw& raw) {
  // Extract the largest rendition; Flutter decodes JPEG at the target size.
  // This never unpacks sensor pixels. Failed extraction is handled by Dart.
  int selected = -1;
  uint64_t bestArea = 0;
  auto& list = raw.imgdata.thumbs_list;
  for (int i = 0; i < list.thumbcount; ++i) {
    const auto& t = list.thumblist[i];
    if (!t.twidth || !t.theight || t.tlength > 32U * 1024 * 1024) continue;
    const int flip = t.tflip == 0xffff ? raw.imgdata.sizes.flip : t.tflip;
    const unsigned w = flip & 4 ? t.theight : t.twidth;
    const unsigned h = flip & 4 ? t.twidth : t.theight;
    const uint64_t area = uint64_t(w) * h;
    if (selected < 0 || area > bestArea) {
      selected = i; bestArea = area;
    }
  }
  if (selected < 0) { std::cout << "FVRAWP1 NONE\n"; return; }
  const auto& t = list.thumblist[selected];
  const int flip = t.tflip == 0xffff ? raw.imgdata.sizes.flip : t.tflip;
  Check(raw.unpack_thumb_ex(selected));
  raw.imgdata.sizes.flip = flip;
  int error = 0;
  auto* bitmap = raw.dcraw_make_mem_thumb(&error);
  std::unique_ptr<libraw_processed_image_t, decltype(&LibRaw::dcraw_clear_mem)> image(bitmap, LibRaw::dcraw_clear_mem);
  Check(error);
  if (!bitmap || bitmap->data_size > 32U * 1024 * 1024) throw std::runtime_error("RAW preview budget");
  const bool jpeg = bitmap->type == LIBRAW_IMAGE_JPEG;
  const std::string profileMarker("ICC_PROFILE");
  const bool hasProfile = jpeg && std::search(bitmap->data, bitmap->data + bitmap->data_size,
      profileMarker.begin(), profileMarker.end()) != bitmap->data + bitmap->data_size;
  // Preserve an embedded ICC profile. Unprofiled Adobe/wide-gamut previews
  // cannot safely be handed to an sRGB renderer, so use sensor development.
  const int color = raw.imgdata.color.ExifColorSpace;
  if (!hasProfile && color != LIBRAW_COLORSPACE_Unknown &&
      color != LIBRAW_COLORSPACE_NotFound && color != LIBRAW_COLORSPACE_sRGB) {
    std::cout << "FVRAWP1 NONE\n"; return;
  }
  if (!jpeg && (bitmap->type != LIBRAW_IMAGE_BITMAP || bitmap->bits != 8 || bitmap->colors != 3))
    throw std::runtime_error("Unsupported RAW preview");
  std::cout << "FVRAWP1 " << (jpeg ? "JPEG" : "RGB8") << ' '
            << raw.imgdata.thumbnail.twidth << ' ' << raw.imgdata.thumbnail.theight
            << ' ' << flip << ' ' << bitmap->data_size << '\n';
  std::cout.write(reinterpret_cast<const char*>(bitmap->data), bitmap->data_size);
}
class ViewerRaw : public LibRaw {
 public:
  bool linear = false;
  unsigned linearWidth = 0, linearHeight = 0, sourceWidth = 0, sourceHeight = 0;
  std::vector<float> linearPixels;
  OutputLimit limit;
  void normalizeDisplayExposure() {
    // LibRaw's automatic brightness is suppressed by highlight recovery and
    // only applied by its bitmap writer. Derive one exposure from the full
    // developed RGB histogram so SDR and the unclipped float path agree.
    const auto* histogram = get_internal_data_pointer()->output_data.histogram;
    if (!histogram || !histogramPixels) return;
    const uint64_t tail = std::max<uint64_t>(1, histogramPixels / 100);
    int white = 0;
    for (int c = 0; c < 3; ++c) {
      uint64_t total = 0;
      int bin = 8191;
      for (; bin > 32; --bin) {
        total += histogram[c][bin];
        if (total >= tail) break;
      }
      white = std::max(white, bin);
    }
    // Ignore an empty/near-black frame and never reduce an already exposed
    // image. A four-stop limit avoids amplifying noise without bound.
    const double exposure = white <= 32 || white == 8191
        ? 1.0 : std::clamp(8192.0 / white, 1.0, 16.0);
    imgdata.params.bright = static_cast<float>(exposure);
    for (auto& value : linearPixels) value *= static_cast<float>(exposure);
  }
 protected:
  uint64_t histogramPixels = 0;
  void convert_to_rgb_loop(float matrix[3][4]) override {
    histogramPixels = uint64_t(imgdata.sizes.width) * imgdata.sizes.height;
    if (linear) {
      sourceWidth = imgdata.sizes.width; sourceHeight = imgdata.sizes.height;
      if (!sourceWidth || !sourceHeight || imgdata.idata.colors < 1 || imgdata.idata.colors > 4 ||
          static_cast<uint64_t>(sourceWidth) * sourceHeight > 100 * 1024 * 1024)
        throw std::runtime_error("RAW linear pixel budget");
      const int flip = imgdata.sizes.flip;
      const unsigned w = flip & 4 ? sourceHeight : sourceWidth;
      const unsigned h = flip & 4 ? sourceWidth : sourceHeight;
      const double scale = limit.scale(w, h);
      linearWidth = std::max(1U, static_cast<unsigned>(w * scale));
      linearHeight = std::max(1U, static_cast<unsigned>(h * scale));
      linearPixels.resize(static_cast<size_t>(linearWidth) * linearHeight * 3);
      for (unsigned y = 0; y < linearHeight; ++y) for (unsigned x = 0; x < linearWidth; ++x) {
        const unsigned x0 = x * w / linearWidth, x1 = std::max(x0 + 1, (x + 1) * w / linearWidth);
        const unsigned y0 = y * h / linearHeight, y1 = std::max(y0 + 1, (y + 1) * h / linearHeight);
        double sensor[4]{};
        for (unsigned sy = y0; sy < y1; ++sy) for (unsigned sx = x0; sx < x1; ++sx) {
          unsigned px = flip & 4 ? sy : sx, py = flip & 4 ? sx : sy;
          if (flip & 1) px = sourceWidth - 1 - px;
          if (flip & 2) py = sourceHeight - 1 - py;
          for (int c = 0; c < imgdata.idata.colors; ++c)
            sensor[c] += imgdata.image[static_cast<size_t>(py) * sourceWidth + px][c];
        }
        const double divisor = static_cast<double>(x1 - x0) * (y1 - y0) * 65535.0;
        for (int c = 0; c < 3; ++c) {
          double value = 0;
          for (int source = 0; source < imgdata.idata.colors; ++source)
            value += matrix[c][source] * sensor[source];
          linearPixels[(static_cast<size_t>(y) * linearWidth + x) * 3 + c] = static_cast<float>(value / divisor);
        }
      }
    }
    LibRaw::convert_to_rgb_loop(matrix);
  }
};
int Develop(const std::filesystem::path& path, const std::string& command, OutputLimit limit) {
  try {
#ifdef _WIN32
    _setmode(_fileno(stdout), _O_BINARY);
#endif
    if (std::filesystem::file_size(path) > 512ULL * 1024 * 1024) throw std::runtime_error("RAW input budget");
    const bool linear = command == "decode-linear";
    ViewerRaw raw; raw.linear = linear; raw.limit = limit;
    auto& p = raw.imgdata.params;
    p.output_bps = 16; p.output_color = 1; p.use_camera_wb = 1;
    p.use_camera_matrix = 1; p.user_qual = 3; // Full-resolution AHD, not embedded preview.
    p.no_auto_bright = 1; p.highlight = 3;
    p.gamm[0] = linear ? 1.0 : 1.0 / 2.4;
    p.gamm[1] = linear ? 1.0 : 12.92;
    raw.imgdata.rawparams.max_raw_memory_mb = 768;
#ifdef _WIN32
    Check(raw.open_file(path.c_str()));
#else
    Check(raw.open_file(path.c_str()));
#endif
    if (command == "info") { Inspect(raw); return std::cout.good() ? 0 : 1; }
    if (command == "preview") { Preview(raw); return std::cout.good() ? 0 : 1; }
    const auto& sizes = raw.imgdata.sizes;
    if (static_cast<uint64_t>(sizes.raw_width) * sizes.raw_height > 100 * 1024 * 1024) throw std::runtime_error("RAW sensor pixel budget");
    Check(raw.unpack());
    Check(raw.dcraw_process());
    raw.normalizeDisplayExposure();
    if (linear) {
      if (raw.linearPixels.empty() || raw.sourceWidth != raw.imgdata.sizes.width ||
          raw.sourceHeight != raw.imgdata.sizes.height)
        throw std::runtime_error("Unsupported RAW linear geometry");
      std::cout << "FVHDR32 " << raw.linearWidth << ' ' << raw.linearHeight << '\n';
      for (size_t i = 0; i < raw.linearPixels.size(); i += 3) {
        const float pixel[] = {raw.linearPixels[i], raw.linearPixels[i + 1], raw.linearPixels[i + 2], 1};
        std::cout.write(reinterpret_cast<const char*>(pixel), sizeof(pixel));
      }
      return std::cout.good() ? 0 : 1;
    }
    int error = 0;
    auto* bitmap = raw.dcraw_make_mem_image(&error);
    std::unique_ptr<libraw_processed_image_t, decltype(&LibRaw::dcraw_clear_mem)> image(bitmap, LibRaw::dcraw_clear_mem);
    Check(error);
    if (!bitmap || bitmap->type != LIBRAW_IMAGE_BITMAP || bitmap->bits != 16 || bitmap->colors != 3) throw std::runtime_error("RAW bitmap layout");
    const unsigned w = bitmap->width, h = bitmap->height;
    if (!w || !h || bitmap->data_size != static_cast<uint64_t>(w) * h * 6) throw std::runtime_error("RAW bitmap size");
    const double scale = limit.scale(w, h);
    const unsigned ow = std::max(1U, static_cast<unsigned>(w * scale));
    const unsigned oh = std::max(1U, static_cast<unsigned>(h * scale));
    std::cout << "FVRAW16 " << ow << ' ' << oh << '\n';
    const auto* pixels = reinterpret_cast<const uint16_t*>(bitmap->data);
    // Box downsample after demosaic, so thumbnail quality follows full development.
    for (unsigned y = 0; y < oh; ++y) for (unsigned x = 0; x < ow; ++x) {
      const unsigned x0 = x * w / ow, x1 = std::max(x0 + 1, (x + 1) * w / ow);
      const unsigned y0 = y * h / oh, y1 = std::max(y0 + 1, (y + 1) * h / oh);
      uint64_t sums[3]{};
      for (unsigned sy = y0; sy < y1; ++sy) for (unsigned sx = x0; sx < x1; ++sx)
        for (int c = 0; c < 3; ++c) sums[c] += pixels[(sy * w + sx) * 3 + c];
      const uint64_t count = static_cast<uint64_t>(x1 - x0) * (y1 - y0);
      for (int c = 0; c < 3; ++c) {
        const auto v = static_cast<uint16_t>(sums[c] / count);
        const char out[2] = {static_cast<char>(v & 255), static_cast<char>(v >> 8)};
        std::cout.write(out, 2);
      }
    }
    return std::cout.good() ? 0 : 1;
  } catch (const std::exception& e) { std::cerr << e.what(); return 1; }
}
#ifdef _WIN32
int wmain(int argc, wchar_t** argv) {
  if (argc != 3 && argc != 5) return 2;
  const auto wide = std::wstring(argv[1]);
  std::string command;
  for (const auto c : wide) { if (c > 127) return 2; command.push_back(static_cast<char>(c)); }
  OutputLimit limit;
  if (argc == 5) { limit.width = static_cast<unsigned>(_wtoi(argv[3])); limit.height = static_cast<unsigned>(_wtoi(argv[4])); }
  if (command == "decode-linear") limit.pixels = 4ULL * 1024 * 1024;
  if (command != "decode" && command != "decode-linear" && command != "preview" && command != "info") return 2;
  return Develop(argv[2], command, limit);
}
#else
int main(int argc, char** argv) {
  if (argc != 3 && argc != 5) return 2;
  const std::string command(argv[1]);
  OutputLimit limit;
  if (argc == 5) { limit.width = static_cast<unsigned>(std::atoi(argv[3])); limit.height = static_cast<unsigned>(std::atoi(argv[4])); }
  if (command == "decode-linear") limit.pixels = 4ULL * 1024 * 1024;
  if (command != "decode" && command != "decode-linear" && command != "preview" && command != "info") return 2;
  return Develop(argv[2], command, limit);
}
#endif
