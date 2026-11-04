# The pinned Windows WebView plugin keeps WinRT objects alive until DLL unload.
# Build private source overrides; the runner calls ShenViewShutdownWebView
# before deleting its engine. Remove this override once the pinned upstream
# plugin shuts down its dispatcher on the owning UI thread before engine teardown.
function(shenview_fix_webview_lifetime target)
  get_target_property(plugin_root ${target} SOURCE_DIR)
  set(output "${CMAKE_CURRENT_BINARY_DIR}/webview-lifetime")
  file(MAKE_DIRECTORY "${output}")
  file(READ "${plugin_root}/in_app_webview/in_app_webview_manager.cpp" manager)
  string(REPLACE "\r\n" "\n" manager "${manager}")
  set(original [=[    UnregisterClass(windowClass_.lpszClassName, nullptr);
    plugin = nullptr;
  }
}]=])
  set(replacement [=[    UnregisterClass(windowClass_.lpszClassName, nullptr);
    compositor_ = nullptr;
    graphics_context_ = nullptr;
    if (dispatcher_queue_controller_) {
      winrt::com_ptr<ABI::Windows::Foundation::IAsyncAction> shutdown;
      if (SUCCEEDED(dispatcher_queue_controller_->ShutdownQueueAsync(shutdown.put()))) {
        winrt::com_ptr<::IAsyncInfo> info;
        shutdown->QueryInterface(__uuidof(::IAsyncInfo), info.put_void());
        AsyncStatus status = AsyncStatus::Started;
        bool quitting = false;
        int quitCode = 0;
        while (info && SUCCEEDED(info->get_Status(&status)) && status == AsyncStatus::Started) {
          MSG message;
          while (PeekMessage(&message, nullptr, 0, 0, PM_REMOVE)) {
            if (message.message == WM_QUIT) {
              quitting = true;
              quitCode = static_cast<int>(message.wParam);
            } else {
              TranslateMessage(&message);
              DispatchMessage(&message);
            }
          }
          MsgWaitForMultipleObjectsEx(0, nullptr, 10, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
        }
        if (quitting) PostQuitMessage(quitCode);
      }
      dispatcher_queue_controller_ = nullptr;
    }
    rohelper_ = nullptr;
    valid_ = false;
    plugin = nullptr;
  }
}]=])
  string(FIND "${manager}" "${original}" found)
  if(found EQUAL -1)
    message(FATAL_ERROR "WebView manager changed; review the lifetime override")
  endif()
  string(REPLACE "${original}" "${replacement}" manager "${manager}")
  file(CONFIGURE OUTPUT "${output}/in_app_webview_manager.cpp" CONTENT "#include <windows.foundation.h>\n${manager}" @ONLY)

  file(READ "${plugin_root}/flutter_inappwebview_windows_plugin.cpp" plugin)
  string(REPLACE "\r\n" "\n" plugin "${plugin}")
  set(original [=[    webViewEnvironmentManager = nullptr;
    inAppWebViewManager = nullptr;
    inAppBrowserManager = nullptr;
    headlessInAppWebViewManager = nullptr;
    cookieManager = nullptr;]=])
  set(replacement [=[    ShenViewShutdownWebView();
    shenview_plugin = nullptr;]=])
  string(FIND "${plugin}" "${original}" found)
  if(found EQUAL -1)
    message(FATAL_ERROR "WebView plugin changed; review the lifetime override")
  endif()
  string(REPLACE "${original}" "${replacement}" plugin "${plugin}")
  set(original "    registrar->AddPlugin(std::move(plugin));")
  foreach(anchor "${original}" "namespace flutter_inappwebview_plugin")
    string(FIND "${plugin}" "${anchor}" found)
    if(found EQUAL -1)
      message(FATAL_ERROR "WebView registration changed; review the lifetime override")
    endif()
  endforeach()
  string(REPLACE "${original}" "    shenview_plugin = plugin.get();\n${original}" plugin "${plugin}")
  string(REPLACE "namespace flutter_inappwebview_plugin" "static flutter_inappwebview_plugin::FlutterInappwebviewWindowsPlugin* shenview_plugin = nullptr;\nnamespace flutter_inappwebview_plugin" plugin "${plugin}")
  string(PREPEND plugin "extern \"C\" __declspec(dllexport) void ShenViewShutdownWebView();\n")
  string(APPEND plugin [=[
extern "C" __declspec(dllexport) void ShenViewShutdownWebView() {
  auto* plugin = shenview_plugin;
  shenview_plugin = nullptr;
  if (!plugin) return;
  if (plugin->headlessInAppWebViewManager) plugin->headlessInAppWebViewManager->UnregisterMethodCallHandler();
  if (plugin->inAppBrowserManager) plugin->inAppBrowserManager->UnregisterMethodCallHandler();
  if (plugin->inAppWebViewManager) plugin->inAppWebViewManager->UnregisterMethodCallHandler();
  if (plugin->cookieManager) plugin->cookieManager->UnregisterMethodCallHandler();
  if (plugin->webViewEnvironmentManager) plugin->webViewEnvironmentManager->UnregisterMethodCallHandler();
  plugin->headlessInAppWebViewManager.reset();
  plugin->inAppBrowserManager.reset();
  plugin->inAppWebViewManager.reset();
  plugin->cookieManager.reset();
  plugin->webViewEnvironmentManager.reset();
}
]=])
  file(CONFIGURE OUTPUT "${output}/flutter_inappwebview_windows_plugin.cpp" CONTENT "${plugin}" @ONLY)

  get_target_property(sources ${target} SOURCES)
  foreach(source "in_app_webview/in_app_webview_manager.cpp" "flutter_inappwebview_windows_plugin.cpp")
    if(NOT "${source}" IN_LIST sources)
      message(FATAL_ERROR "WebView sources changed; review the lifetime override")
    endif()
  endforeach()
  list(REMOVE_ITEM sources "in_app_webview/in_app_webview_manager.cpp" "flutter_inappwebview_windows_plugin.cpp")
  list(APPEND sources "${output}/in_app_webview_manager.cpp" "${output}/flutter_inappwebview_windows_plugin.cpp")
  set_property(TARGET ${target} PROPERTY SOURCES "${sources}")
  target_include_directories(${target} PRIVATE "${plugin_root}" "${plugin_root}/in_app_webview")
endfunction()
