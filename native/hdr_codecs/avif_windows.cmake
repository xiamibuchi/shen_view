include(ExternalProject)
get_filename_component(SHENVIEW_AVIF_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(SHENVIEW_AVIF_BUILD "${SHENVIEW_AVIF_ROOT}/build/avif-codecs")
ExternalProject_Add(shenview_avif_helper
  SOURCE_DIR "${SHENVIEW_AVIF_ROOT}/native/hdr_codecs"
  BINARY_DIR "${SHENVIEW_AVIF_BUILD}"
  CMAKE_ARGS -DSHENVIEW_AVIF_ONLY=ON
  BUILD_COMMAND "${CMAKE_COMMAND}" --build <BINARY_DIR> --config Release
    --target viewer_avif_animation --parallel 2
  BUILD_ALWAYS TRUE
  BUILD_BYPRODUCTS "${SHENVIEW_AVIF_BUILD}/bin/viewer_avif_animation.exe"
  INSTALL_COMMAND ""
)
add_dependencies(${BINARY_NAME} shenview_avif_helper)
install(PROGRAMS "${SHENVIEW_AVIF_BUILD}/bin/viewer_avif_animation.exe"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/codecs" COMPONENT Runtime)
install(DIRECTORY "${SHENVIEW_AVIF_BUILD}/licenses/hdr"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/codecs/licenses" COMPONENT Runtime)
