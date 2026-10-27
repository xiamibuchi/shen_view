# 开发环境与维护

## 环境与构建

将 Flutter 和 CMake 加入 PATH；Windows 安装 Visual Studio C++ 工具链与 7-Zip。
工具路径通过 PATH 和系统安装目录查找，不要求固定盘符。Flutter 也可由 FLUTTER_ROOT
指定 SDK 根目录；脚本的 -Flutter、-Dart、-CMake 等参数支持显式指定工具。
FFmpeg 构建需将兼容的 x64 MinGW GCC 加入 PATH，或传 -CompilerDirectory；
Git Bash 根据 Git 安装位置查找，也可传 -Bash。编解码器组装支持
-ImageMagickDirectory 和 -SevenZipDirectory，测试与探针的 7-Zip 可由 SHENVIEW_7ZIP 指定。
当前提供 Windows 和 macOS 工程，macOS 原生链路需在 Mac 上构建验收。
开发 SDK 版本见 [项目 README](../../README.md)，依赖锁定版本以 pubspec.lock 为准。

Windows 从仓库根准备应用与原生组件：

~~~powershell
cd apps/viewer
flutter pub get
flutter build windows --release --no-pub
cd ../..
powershell -ExecutionPolicy Bypass -File tool/build/build_archive_helper.ps1
powershell -ExecutionPolicy Bypass -File tool/build/build_hdr_codecs.ps1
~~~

Flutter/Dart 命令在 apps/viewer/ 执行，仓库级脚本从仓库根调用。
应用构建输出位于 apps/viewer/build/，独立原生构建缓存位于仓库根 build/。
Windows Flutter 构建会准备 SVG、AVIF 和 FFmpeg 后端；首次构建 FFmpeg 还需要
Git Bash、TDM GCC x64 与 7-Zip，固定依赖会自动下载并校验。清理原生缓存后需重建 helper。
各组件的平台要求见 [归档 helper](../../native/archive_helper/README.md)、
[SVG 构建](../architecture/svg-rendering.md#构建与运行) 与
[HDR 构建](../../native/hdr_codecs/README.md)。检查命令见 [验证说明](validation.md)。

VS Code 使用 Flutter 扩展选择设备，主工程不交给 CMake Tools 自动接管。
个人 SDK 路径、主题与生成器放在用户设置。移动仓库后重新打开目录并执行 flutter pub get，
旧绝对路径缓存通过 flutter clean 后重建，不手改生成文件。

## 配置存储与排查

Windows 普通安装版配置为 %LOCALAPPDATA%/ShenView/settings.json；便携版和 Scoop
位于程序旁 user-data/settings.json，未带模式标记的开发运行仍放在程序旁。
MSIX 使用包内应用可见的 LocalAppData/ShenView/MSIX，受 Windows 包重定向管理。
打包方式和数据保留规则见 [Windows 分发](../release/distribution.md)。macOS 为用户
Library/Application Support/ShenView/settings.json，沙箱下位于容器中。
Debug 和 Release 可能使用不同配置，排查时先确认正在运行的可执行文件。

启动和浏览使用容错读取，损坏、超限或不可读的配置回退到默认值，读取本身不改写文件。
保存使用严格读取，持续读取失败或无写权限时保留已有文件并报告失败。
遇到设置未保存，先检查目标目录权限、可用空间及是否被其他程序独占，保留原文件用于排查。

配置缺失、损坏、只读或被占用等场景可运行 tool/check/windows_config_smoke.ps1，
它使用独立程序副本，不操作用户配置。多窗口写入机制见
[共享数据](../guide/multi-instance.md#共享数据)。

字段与默认值直接查 [ViewerSettings](../../apps/viewer/lib/src/domain/viewer_settings.dart)，
文件读写及容错查 [AppConfigStore](../../apps/viewer/lib/src/application/app_config_store.dart)。
不另外维护配置格式表或手工编辑指南。

## 代码约束

静态规则以 [analysis_options.yaml](../../apps/viewer/analysis_options.yaml) 为准。
页面使用共享主题、控件和 Fluent 图标；设计 lint 的范围与执行方式见
[规则包说明](../../apps/viewer/tool/design_lints/README.md)。custom_lint 需显式运行，不由 analyze 自动执行。
按改动范围选择验证的要求集中在 [AGENTS.md](../../AGENTS.md)。

## Material Icons

业务图标使用 Fluent，Flutter 默认控件仍引用 Material 图标，因此保留 uses-material-design。
移除前需覆盖默认返回、关闭、菜单与文字选择等路径，不能只看业务图标是否迁移完成。
视觉测试从应用资源加载字体，不依赖固定 SDK 或 Pub 缓存路径。

## 依赖与工程标识

依赖更新后先检查实际解析结果，不用 dependency_overrides 跨越不兼容约束。
运行时许可按依赖闭包生成，开发依赖若被运行时传递引用仍需保留，流程见
[许可维护](../release/open-source-licenses.md)。

显示名为 ShenView，仓库与 Dart 包名为 shen_view。修改品牌显示不顺带变更平台身份、
MethodChannel 或数据目录；这些标识以对应平台工程和源码为准。
