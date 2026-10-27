get_filename_component(SHENVIEW_FFMPEG_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
execute_process(COMMAND powershell.exe -NoProfile -ExecutionPolicy Bypass
  -File "${SHENVIEW_FFMPEG_ROOT}/tool/build/build_ffmpeg.ps1"
  RESULT_VARIABLE SHENVIEW_FFMPEG_RESULT)
if(NOT SHENVIEW_FFMPEG_RESULT EQUAL 0)
  message(FATAL_ERROR "Failed to build the locked FFmpeg playback runtime")
endif()
install(DIRECTORY "${SHENVIEW_FFMPEG_ROOT}/build/ffmpeg/windows-x64/runtime/"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/codecs/ffmpeg" COMPONENT Runtime)
install(DIRECTORY "${SHENVIEW_FFMPEG_ROOT}/build/ffmpeg/windows-x64/runtime/licenses/"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/codecs/licenses/ffmpeg" COMPONENT Runtime)
