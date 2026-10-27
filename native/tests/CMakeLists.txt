cmake_minimum_required(VERSION 3.14)
project(native_decode_queue_test LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_package(Threads REQUIRED)
add_executable(native_decode_queue_test native_decode_queue_test.cpp)
target_link_libraries(native_decode_queue_test PRIVATE Threads::Threads)
enable_testing()
add_test(NAME native_decode_queue COMMAND native_decode_queue_test)

# Test-only proxy: records real helper invocations without production hooks.
if(WIN32)
  add_executable(raw_helper_trace raw_helper_trace.cpp)
endif()
