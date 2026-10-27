# flutter_inappwebview_windows 0.6.0 uses DEPENDS with the TARGET signature of
# add_custom_command. That argument has always been ignored; CMake 3.31+ warns
# unless the plugin explicitly selects the legacy behavior. Set the default in
# this plugin directory only, before its cmake_policy(VERSION ...) call. The
# generated plugin loader and the shared Pub cache must remain untouched.
# Remove this compatibility hook when the upstream build script is corrected.
if(POLICY CMP0175)
  set(CMAKE_POLICY_DEFAULT_CMP0175 OLD)
endif()
