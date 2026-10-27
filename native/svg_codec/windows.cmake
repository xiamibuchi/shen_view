# Pinned build-time codec artifacts; no user-installed rendering extensions.
function(shenview_svg_flutter_configuration)
  include("${CMAKE_SOURCE_DIR}/flutter/ephemeral/generated_config.cmake")
  set(FLUTTER_ROOT "${FLUTTER_ROOT}" PARENT_SCOPE)
  if(DEFINED FLUTTER_TARGET_PLATFORM)
    set(FLUTTER_TARGET_PLATFORM "${FLUTTER_TARGET_PLATFORM}" PARENT_SCOPE)
  endif()
endfunction()
shenview_svg_flutter_configuration()
set(SHENVIEW_SVG_ROOT "${CMAKE_CURRENT_LIST_DIR}/../..")
get_filename_component(SHENVIEW_SVG_ROOT "${SHENVIEW_SVG_ROOT}" ABSOLUTE)
if(CMAKE_GENERATOR_PLATFORM STREQUAL "ARM64" OR FLUTTER_TARGET_PLATFORM STREQUAL "windows-arm64")
  set(SHENVIEW_SVG_ARCH arm64)
else()
  set(SHENVIEW_SVG_ARCH x64)
endif()
execute_process(
  COMMAND "${FLUTTER_ROOT}/bin/cache/dart-sdk/bin/dart.exe"
    "${SHENVIEW_SVG_ROOT}/apps/viewer/tool/install_svg_codecs.dart"
    --output "${SHENVIEW_SVG_ROOT}/build/svg-codecs" --arch ${SHENVIEW_SVG_ARCH}
  WORKING_DIRECTORY "${SHENVIEW_SVG_ROOT}/apps/viewer"
  RESULT_VARIABLE SHENVIEW_SVG_RESULT
)
if(NOT SHENVIEW_SVG_RESULT EQUAL 0)
  message(FATAL_ERROR "Could not provision the pinned SVG codec")
endif()
set(NUGET "${SHENVIEW_SVG_ROOT}/build/svg-codecs/tools/nuget.exe" CACHE FILEPATH "Local pinned NuGet for WebView2" FORCE)
