include(ExternalProject)
get_filename_component(SHENVIEW_HDR_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(SHENVIEW_HDR_BUILD "${SHENVIEW_HDR_ROOT}/build/hdr-codecs")
ExternalProject_Add(shenview_hdr_helpers
  SOURCE_DIR "${SHENVIEW_HDR_ROOT}/native/hdr_codecs"
  DOWNLOAD_COMMAND ""
  CONFIGURE_COMMAND ""
  BUILD_COMMAND powershell.exe -NoProfile -ExecutionPolicy Bypass
    -File "${SHENVIEW_HDR_ROOT}/tool/build/build_hdr_codecs.ps1"
    -Generator "${CMAKE_GENERATOR}" -Architecture x64
  BUILD_ALWAYS TRUE
  BUILD_BYPRODUCTS
    "${SHENVIEW_HDR_BUILD}/bin/viewer_avif_animation.exe"
    "${SHENVIEW_HDR_BUILD}/bin/viewer_gainmap.exe"
    "${SHENVIEW_HDR_BUILD}/bin/viewer_heif_gainmap.exe"
    "${SHENVIEW_HDR_BUILD}/bin/viewer_raw.exe"
  INSTALL_COMMAND ""
)
add_dependencies(${BINARY_NAME} shenview_hdr_helpers)
install(PROGRAMS "${SHENVIEW_HDR_BUILD}/bin/viewer_avif_animation.exe"
  "${SHENVIEW_HDR_BUILD}/bin/viewer_gainmap.exe" "${SHENVIEW_HDR_BUILD}/bin/viewer_raw.exe"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/codecs" COMPONENT Runtime)
install(PROGRAMS "${SHENVIEW_HDR_BUILD}/bin/viewer_heif_gainmap.exe"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/codecs/imagemagick" COMPONENT Runtime)
install(DIRECTORY "${SHENVIEW_HDR_BUILD}/licenses/hdr"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/codecs/licenses" COMPONENT Runtime)
