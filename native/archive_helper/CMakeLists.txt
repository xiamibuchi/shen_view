cmake_minimum_required(VERSION 3.22)
project(viewer_archive_helper LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/bin")
include("${CMAKE_CURRENT_LIST_DIR}/../../third_party/cmake/dependencies.cmake")
shenview_declare_dependency(viewer_7zip)
FetchContent_MakeAvailable(viewer_7zip)
add_executable(viewer_archive archive_helper.cpp)
target_include_directories(viewer_archive PRIVATE "${viewer_7zip_SOURCE_DIR}/CPP")
if(WIN32)
  target_compile_definitions(viewer_archive PRIVATE UNICODE _UNICODE NOMINMAX)
  target_link_libraries(viewer_archive PRIVATE ole32 oleaut32)
  find_program(VIEWER_7ZIP_TOOL NAMES 7z 7zz HINTS "$ENV{ProgramW6432}/7-Zip" "$ENV{ProgramFiles}/7-Zip")
  if(VIEWER_7ZIP_TOOL)
    get_filename_component(VIEWER_7ZIP_DIRECTORY "${VIEWER_7ZIP_TOOL}" DIRECTORY)
  endif()
  find_file(VIEWER_7ZIP_ENGINE NAMES 7z.dll
    HINTS "${VIEWER_7ZIP_DIRECTORY}" "$ENV{ProgramW6432}/7-Zip" "$ENV{ProgramFiles}/7-Zip"
    DOC "7-Zip engine to package")
  if(NOT EXISTS "${VIEWER_7ZIP_ENGINE}")
    message(FATAL_ERROR "Set VIEWER_7ZIP_ENGINE to the redistributable 7z.dll")
  endif()
  add_custom_command(TARGET viewer_archive POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${VIEWER_7ZIP_ENGINE}" "$<TARGET_FILE_DIR:viewer_archive>/7z.dll")
else()
  target_sources(viewer_archive PRIVATE "${viewer_7zip_SOURCE_DIR}/CPP/Common/MyWindows.cpp")
  target_link_libraries(viewer_archive PRIVATE ${CMAKE_DL_LIBS})
  find_program(VIEWER_MAKE NAMES gmake make REQUIRED)
  # The official shared-library bundle includes ZIP, RAR/RAR5, 7Z and TAR.
  set(engine_source "${viewer_7zip_SOURCE_DIR}/CPP/7zip/Bundles/Format7zF")
  if(APPLE)
    find_program(VIEWER_LIPO lipo REQUIRED)
    set(engine_architectures ${CMAKE_OSX_ARCHITECTURES})
    if(NOT engine_architectures)
      set(engine_architectures ${CMAKE_SYSTEM_PROCESSOR})
    endif()
    set(engine_libraries)
    foreach(engine_arch IN LISTS engine_architectures)
      add_custom_target(viewer_archive_engine_${engine_arch} ALL
        COMMAND ${VIEWER_MAKE} -f makefile.gcc -j2 CC=clang CXX=clang++
          O=_viewer_${engine_arch} USE_CLANG=1 "MY_ARCH=-arch ${engine_arch}"
        WORKING_DIRECTORY "${engine_source}")
      add_dependencies(viewer_archive viewer_archive_engine_${engine_arch})
      list(APPEND engine_libraries "${engine_source}/_viewer_${engine_arch}/7z.so")
    endforeach()
    add_custom_command(TARGET viewer_archive POST_BUILD
      COMMAND ${VIEWER_LIPO} -create ${engine_libraries}
        -output "$<TARGET_FILE_DIR:viewer_archive>/7z.so")
  else()
    add_custom_target(viewer_archive_engine ALL
      COMMAND ${VIEWER_MAKE} -f makefile.gcc -j2 CC=clang CXX=clang++ O=_viewer USE_CLANG=1
      WORKING_DIRECTORY "${engine_source}")
    add_dependencies(viewer_archive viewer_archive_engine)
    add_custom_command(TARGET viewer_archive POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${engine_source}/_viewer/7z.so" "$<TARGET_FILE_DIR:viewer_archive>/7z.so")
  endif()
endif()
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/licenses/7zip")
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/licenses/LGPL-2.1.txt" "${CMAKE_BINARY_DIR}/licenses/7zip/LGPL-2.1.txt" COPYONLY)
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/licenses/SOURCES.txt" "${CMAKE_BINARY_DIR}/licenses/7zip/SOURCES.txt" COPYONLY)
configure_file("${viewer_7zip_SOURCE_DIR}/DOC/License.txt" "${CMAKE_BINARY_DIR}/licenses/7zip/License.txt" COPYONLY)
configure_file("${viewer_7zip_SOURCE_DIR}/DOC/unRarLicense.txt" "${CMAKE_BINARY_DIR}/licenses/7zip/unRarLicense.txt" COPYONLY)
if(WIN32)
  get_filename_component(engine_directory "${VIEWER_7ZIP_ENGINE}" DIRECTORY)
  if(EXISTS "${engine_directory}/License.txt")
    configure_file("${engine_directory}/License.txt"
      "${CMAKE_BINARY_DIR}/licenses/7zip/Engine-License.txt" COPYONLY)
  endif()
endif()
