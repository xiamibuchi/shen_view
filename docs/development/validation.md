# 验证入口与验收边界

仓库级 PowerShell 入口从仓库根调用；Flutter/Dart 命令及 test/、testdata/ 路径
以 apps/viewer/ 为工作目录。以下原生 CMake 命令从仓库根执行。日常修改按 [AGENTS.md](../../AGENTS.md) 选择最小充分验证，
完整发布再覆盖全部检查及对应平台专项。测试缺少原生 helper 而跳过时，不能计为实际解码通过。

## 完整检查

先按 [开发环境](getting-started.md) 准备原生组件，再运行：

~~~powershell
powershell -ExecutionPolicy Bypass -File tool/check/check.ps1
~~~

脚本依次执行 custom_lint、analyze 和单元/Widget 测试，全部通过才返回 0。
原生构建、集成和实屏效果另验，Windows 总流程见 [真机回归](windows-regression.md)。

## 专项入口

| 领域 | 测试或工具 |
| --- | --- |
| 归档条目与固实包 | test/archive_session_test.dart、test/solid_archive_batch_test.dart、test/archive_disk_batch_test.dart、test/comic_archive_formats_test.dart |
| 归档画布与导航 | test/archive_viewer_integration_test.dart、test/archive_navigation_test.dart |
| 调度和预算 | test/decode_scheduler_test.dart、test/image_resource_budget_test.dart、test/image_resource_cancellation_test.dart |
| 缩略图 | test/thumbnail_prefetch_service_test.dart、test/thumbnail_prefetch_settings_test.dart、test/resource_image_recovery_test.dart |
| 平台解码 | test/platform_image_decoder_test.dart、integration_test/native_decode_queue_test.dart |
| RAW | test/raw_preview_test.dart、test/raw_developer_test.dart、integration_test/raw_display_test.dart、integration_test/raw_actual_size_test.dart |
| HDR | test/hdr_rendering_test.dart、test/hdr_display_policy_test.dart、integration_test/hdr_display_test.dart、integration_test/hdr_type_settings_test.dart |
| SVG | test/svg_routing_test.dart、test/svg_widget_routing_test.dart、test/svg_fallback_test.dart、integration_test/svg_browser_test.dart |
| 配置与多进程 | test/config_resilience_test.dart、test/windows_persistence_concurrency_test.dart、test/app_instance_coordinator_test.dart |
| 界面与 IME | test/style_review_test.dart、test/settings_page_test.dart、integration_test/settings_ime_test.dart |

完整 Windows 集成测试从仓库根运行 tool/check/windows_integration.ps1。
入口会传入真实样本目录，并使用下方原生测试构建出的 RAW 追踪代理；需先准备 HDR helper。
单元测试和集成构建顺序执行，避免运行中的 helper 占用链接输出。

原生队列 C++ 测试复用生产队列：

~~~powershell
cmake -S native/tests -B build/native-tests -A x64
cmake --build build/native-tests --config Release
./build/native-tests/Release/native_decode_queue_test.exe
~~~

Windows 平台通道和 SVG 实测需要明确的样本目录：

~~~powershell
$fixtures = (Resolve-Path testdata/formats).Path
flutter test integration_test/native_decode_queue_test.dart -d windows --dart-define=NATIVE_DECODER_FIXTURES=$fixtures
$svgFixtures = (Resolve-Path testdata/svg).Path
$svgOutput = Join-Path (Get-Location).Path '../../artifacts/svg-routing/native'
flutter test integration_test/svg_browser_test.dart -d windows --dart-define=SVG_FIXTURES=$svgFixtures --dart-define=SVG_ARTIFACTS=$svgOutput
~~~

RAW 100% 专项另需 RAW_TRACE_HELPER 和 RAW_TRACE_LOG，代理逐字节转发实际 LibRaw 输出并记录调用，
缺少追踪 helper 的测试会跳过。测试视图模拟四档 DPI，不能写成四种物理屏幕验收。
RAW 的曝光与原尺寸断言以测试为准。

## HDR 专项

准备原生 helper 后，按改动范围选择运行：

~~~powershell
flutter test test/hdr_rendering_test.dart test/hdr_color_profile_test.dart test/gain_map_sdr_test.dart
flutter test integration_test/hdr_display_test.dart -d windows
flutter test integration_test/gain_map_display_test.dart -d windows
flutter test integration_test/hdr_type_settings_test.dart -d windows
dart run tool/verify_hdr_avif.dart
~~~

macOS 对应显示测试使用 -d macos，并另验 EDR 与窗口行为。
原生集成检查 FP16 回读、屏幕门控、释放和 SDR 底图一致性；SDR 设备上的 Debug 探针
只验证表面创建，不能报告 HDR 屏幕可用。
样本生成、已知亮度、PQ/HLG 独立解码比较与合成 Gain Map 的适用范围见
[HDR 样本](../../apps/viewer/testdata/formats/HDR.md)，显示机制见 [HDR 显示](../architecture/hdr-rendering.md)。

## 视觉复核

设置以下变量可重新导出相关 Widget 测试截图：

| 测试 | 输出目录变量 |
| --- | --- |
| style_review_test.dart | STYLE_CAPTURE_DIR |
| settings_page_test.dart | SETTINGS_CAPTURE_DIR |
| shared_viewer_components_test.dart | SHARED_UI_CAPTURE_DIR |
| app_notification_test.dart | NOTIFICATION_CAPTURE_DIR |
| color_picker_viewer_test.dart | COLOR_PICKER_CAPTURE_DIR |
| image_histogram_test.dart | HISTOGRAM_CAPTURE_DIR |
| archive_viewer_integration_test.dart | ARCHIVE_VIEWER_CAPTURE_DIR |

实际查看深浅主题、宽窄布局、文字缩放和加载/空/错误/成功状态，检查正文对齐、
最小间距、按钮尺寸、遮挡、截断、焦点与按下组合。原生最小窗口为 600 × 460，
Widget 测试中的 440 px 等尺寸属于额外布局压力测试。

## 探针与性能

工具包括 format_probe.dart、performance_probe.dart、folder_scan_probe.dart、
directory_navigation_probe.dart、archive_performance_probe.dart、archive_solid_probe.dart 和 decode_worker_probe.dart。
它们测量各自的后端或合成负载，不能直接替代真实查看器的首帧、翻页 P50/P95、CPU/RSS 和 GPU 测量。

归档冷暖缓存、普通与固实包分别统计；模拟数据不代表真实漫画吞吐。
原生 HDR 的 FP16 回读和 SDR 截图不证明显示器 HDR 亮度保真，
macOS 编译、WKWebView、EDR、Finder 和签名权限需在 Mac 上验证。

截图、日志、探针报告和构建产物写入 Git 忽略的 artifacts/ 或 build/，不作为文档永久附件。
文档保留输入、命令、断言和待验证范围，历史测试数量与单机耗时通过 Git 历史追溯。
