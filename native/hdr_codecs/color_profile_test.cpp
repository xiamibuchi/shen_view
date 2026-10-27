#include "color_profile.h"
#include <iostream>
#include <filesystem>

int main(int argc, char** argv) {
  try {
    for (int gamut = 0; gamut < 3; ++gamut) {
      viewer::Profile profile(viewer::LinearProfile(gamut), cmsCloseProfile);
      cmsUInt32Number size = 0;
      cmsSaveProfileToMem(profile.get(), nullptr, &size);
      std::vector<uint8_t> bytes(size);
      cmsSaveProfileToMem(profile.get(), bytes.data(), &size);
      viewer::ProfileLinearizer transform(bytes);
      float pixels[]{.25f, .5f, 1.5f};
      transform.Convert(pixels, 1);
      if (transform.gamut() != gamut || std::abs(pixels[0] - .25f) > .001f ||
          std::abs(pixels[1] - .5f) > .001f || std::abs(pixels[2] - 1.5f) > .001f)
        throw std::runtime_error("Gain map ICC gamut/linear highlight regression");
    }
    viewer::Profile srgb(cmsCreate_sRGBProfile(), cmsCloseProfile);
    if (argc == 3 && std::string(argv[1]) == "--fixtures") {
      viewer::Profile p3(viewer::LinearProfile(1), cmsCloseProfile);
      const auto* curve = cmsReadTag(srgb.get(), cmsSigRedTRCTag);
      for (auto tag : {cmsSigRedTRCTag, cmsSigGreenTRCTag, cmsSigBlueTRCTag}) {
        if (!cmsWriteTag(p3.get(), tag, curve)) throw std::runtime_error("Fixture TRC");
      }
      auto* name = cmsMLUalloc(nullptr, 1);
      cmsMLUsetASCII(name, "en", "US", "Display P3");
      cmsWriteTag(p3.get(), cmsSigProfileDescriptionTag, name);
      cmsMLUsetASCII(name, "en", "US", "ShenView synthetic fixture, CC0");
      cmsWriteTag(p3.get(), cmsSigCopyrightTag, name);
      cmsMLUfree(name);
      const auto path = std::filesystem::path(argv[2]) / "display_p3.icc";
      if (!cmsSaveProfileToFile(p3.get(), path.string().c_str())) throw std::runtime_error("Fixture output");
    }
    cmsUInt32Number size = 0; cmsSaveProfileToMem(srgb.get(), nullptr, &size);
    std::vector<uint8_t> bytes(size); cmsSaveProfileToMem(srgb.get(), bytes.data(), &size);
    viewer::ProfileLinearizer transform(bytes);
    float rgb[]{.5f, .5f, .5f}; transform.Convert(rgb, 1);
    if (std::abs(rgb[0] - .21404f) > .001f) throw std::runtime_error("ICC TRC not applied");
    bool rejected = false;
    try { viewer::ProfileLinearizer invalid(std::vector<uint8_t>{1, 2, 3}); }
    catch (...) { rejected = true; }
    if (!rejected) throw std::runtime_error("Invalid ICC accepted");
    std::cout << "ICC sRGB/P3/Rec.2020, TRC, highlights and invalid-profile checks passed\n";
    return 0;
  } catch (const std::exception& e) { std::cerr << e.what(); return 1; }
}
