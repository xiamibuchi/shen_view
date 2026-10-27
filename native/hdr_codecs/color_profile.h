#pragma once
#include <lcms2.h>
#include <cmath>
#include <cstdint>
#include <memory>
#include <stdexcept>
#include <vector>

namespace viewer {
using Profile = std::unique_ptr<void, decltype(&cmsCloseProfile)>;

inline cmsHPROFILE LinearProfile(int gamut) {
  const cmsCIExyY white{.3127, .329, 1};
  const cmsCIExyYTRIPLE primaries[] = {
    {{.64, .33, 1}, {.30, .60, 1}, {.15, .06, 1}},
    {{.68, .32, 1}, {.265, .69, 1}, {.15, .06, 1}},
    {{.708, .292, 1}, {.17, .797, 1}, {.131, .046, 1}},
  };
  if (gamut < 0 || gamut > 2) throw std::runtime_error("Unsupported gain map gamut");
  auto* curve = cmsBuildGamma(nullptr, 1);
  if (!curve) throw std::bad_alloc();
  cmsToneCurve* curves[]{curve, curve, curve};
  auto profile = cmsCreateRGBProfile(&white, &primaries[gamut], curves);
  cmsFreeToneCurve(curve);
  return profile;
}

// ISO gain values apply in the base image's linear RGB space. Converting to a
// different gamut before applying per-channel gains changes their meaning.
class ProfileLinearizer {
 public:
  explicit ProfileLinearizer(const std::vector<uint8_t>& bytes) {
    if (bytes.empty() || bytes.size() > 4 * 1024 * 1024) throw std::runtime_error("ICC budget");
    Profile input(cmsOpenProfileFromMem(bytes.data(), static_cast<cmsUInt32Number>(bytes.size())), cmsCloseProfile);
    if (!input || cmsGetColorSpace(input.get()) != cmsSigRgbData || !cmsIsMatrixShaper(input.get()))
      throw std::runtime_error("Unsupported gain map ICC profile");
    double best = 1e9;
    Profile output(nullptr, cmsCloseProfile);
    for (int candidate = 0; candidate < 3; ++candidate) {
      Profile reference(LinearProfile(candidate), cmsCloseProfile);
      if (!reference) throw std::runtime_error("Linear ICC profile");
      double error = 0;
      for (auto tag : {cmsSigRedColorantTag, cmsSigGreenColorantTag, cmsSigBlueColorantTag}) {
        const auto* a = static_cast<const cmsCIEXYZ*>(cmsReadTag(input.get(), tag));
        const auto* b = static_cast<const cmsCIEXYZ*>(cmsReadTag(reference.get(), tag));
        if (!a || !b) throw std::runtime_error("ICC colorants missing");
        error += std::pow(a->X - b->X, 2) + std::pow(a->Y - b->Y, 2) + std::pow(a->Z - b->Z, 2);
      }
      if (error < best) { best = error; gamut_ = candidate; output = std::move(reference); }
    }
    // Unknown calibrated/LUT gamuts fall back to the authored SDR image instead
    // of silently treating them as sRGB during HDR reconstruction.
    if (best > .0005) throw std::runtime_error("Unsupported gain map ICC gamut");
    transform_ = cmsCreateTransform(input.get(), TYPE_RGB_FLT, output.get(), TYPE_RGB_FLT,
        INTENT_RELATIVE_COLORIMETRIC, cmsFLAGS_NOOPTIMIZE);
    if (!transform_) throw std::runtime_error("ICC linear transform");
  }
  ~ProfileLinearizer() { if (transform_) cmsDeleteTransform(transform_); }
  ProfileLinearizer(const ProfileLinearizer&) = delete;
  ProfileLinearizer& operator=(const ProfileLinearizer&) = delete;
  int gamut() const { return gamut_; }
  void Convert(float* pixels, uint32_t count) const { cmsDoTransform(transform_, pixels, pixels, count); }
 private:
  cmsHTRANSFORM transform_ = nullptr;
  int gamut_ = 0;
};
}
