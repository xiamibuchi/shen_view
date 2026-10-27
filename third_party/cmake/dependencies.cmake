include_guard(GLOBAL)
include(FetchContent)
function(shenview_declare_dependency name)
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../dependencies.lock.json")
  file(READ "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../dependencies.lock.json" SHENVIEW_DEPENDENCY_LOCK)
  string(JSON url GET "${SHENVIEW_DEPENDENCY_LOCK}" sources ${name} url)
  string(JSON sha256 GET "${SHENVIEW_DEPENDENCY_LOCK}" sources ${name} sha256)
  string(JSON source_subdir ERROR_VARIABLE no_subdir GET "${SHENVIEW_DEPENDENCY_LOCK}" sources ${name} sourceSubdir)
  set(extra)
  if(NOT no_subdir)
    list(APPEND extra SOURCE_SUBDIR "${source_subdir}")
  endif()
  FetchContent_Declare(${name}
    URL "${url}"
    URL_HASH "SHA256=${sha256}"
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    ${extra})
endfunction()
