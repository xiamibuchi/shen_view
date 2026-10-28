# 开发入门

按以下步骤准备环境并运行 ShenView。提交规则见 [Git 工作流](git-workflow.md)，配置位置与常见问题见[配置排查](troubleshooting.md)。

## 准备工具

| 工具 | 要求 |
| --- | --- |
| Flutter / Dart | Flutter 3.47.8 stable / Dart 3.13.7，或更高的兼容稳定版 |
| Git / Git LFS | 获取源码、测试资料并运行仓库 hooks |
| CMake | 构建原生组件 |
| Windows 工具链 | Visual Studio C++ 工具链、Windows SDK、7-Zip、Git Bash、兼容的 x64 MinGW GCC（如 TDM GCC x64） |
| macOS 工具链 | Xcode、Clang、make；原生链路需在 Mac 上构建验收 |

将 Flutter、CMake 和 Windows 使用的 MinGW GCC 加入 PATH。SDK 约束以
[pubspec.yaml](../../apps/viewer/pubspec.yaml) 为准，Dart 依赖版本以 `pubspec.lock` 为准。

## 准备仓库

克隆仓库后，从仓库根目录执行一次：

```sh
git config --local core.hooksPath .githooks
git lfs install --local --skip-repo
git lfs pull
```

`--skip-repo` 保留仓库维护的 hooks，只配置本地 LFS filters。测试资料使用 Git LFS，
缺少实际文件时重新执行 `git lfs pull`。

Flutter/Dart 命令在 `apps/viewer/` 执行；仓库级构建、检查和打包脚本从仓库根调用。
目录职责见[项目结构](../architecture/project-layout.md)。

## 构建与运行

### Windows

首次构建从仓库根目录执行：

```powershell
cd apps/viewer
flutter pub get
flutter build windows --release --no-pub
cd ../..
powershell -ExecutionPolicy Bypass -File tool/build/build_archive_helper.ps1
powershell -ExecutionPolicy Bypass -File tool/build/build_hdr_codecs.ps1
```

Flutter 构建会准备归档、SVG、AVIF 和 FFmpeg 后端，固定依赖会自动下载并校验。
FFmpeg 首次构建需要 Git Bash、MinGW GCC 和 7-Zip。上面的独立脚本也准备原生测试与探针使用的组件；
清理原生缓存后需重新构建。

之后在 `apps/viewer/` 中启动开发运行：

```powershell
flutter run -d windows
```

### macOS

先按[归档 helper](../../native/archive_helper/README.md)、[SVG 构建](../architecture/svg-rendering.md#构建与运行)
和 [HDR 构建](../../native/hdr_codecs/README.md)准备原生组件，然后在 `apps/viewer/` 中运行：

```sh
flutter pub get
flutter run -d macos
```

macOS 实机验证尚未完成。

### 编辑器

VS Code 使用 Flutter 扩展选择设备，主工程不交给 CMake Tools 自动接管。
个人路径与缓存问题见[配置排查](troubleshooting.md#移动仓库后构建异常)。

## 提交前检查

按 [AGENTS.md](../../AGENTS.md) 选择与改动相关的验证。完整检查从仓库根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File tool/check/check.ps1
```

静态检查、专项测试和视觉复核的说明集中在[验证入口](validation.md)。
提交格式、文件大小与 LFS 检查见 [Git 工作流](git-workflow.md)。

## 开发约定

### 代码与界面

静态规则以 [analysis_options.yaml](../../apps/viewer/analysis_options.yaml) 为准。
页面遵循[界面设计规范](../design/spec.md)，使用共享主题、控件和 Fluent 图标。
设计 lint 的范围与执行方式见[规则包说明](../../apps/viewer/tool/design_lints/README.md)；
`custom_lint` 需显式运行，不由 `analyze` 自动执行。

Flutter 默认控件仍引用 Material 图标，因此保留 `uses-material-design`。
移除前需覆盖默认返回、关闭、菜单与文字选择等路径，不能只看业务图标是否迁移完成。
视觉测试从应用资源加载字体，不依赖固定 SDK 或 Pub 缓存路径。

### 依赖与工程标识

依赖更新后检查实际解析结果，不用 `dependency_overrides` 跨越不兼容约束。
运行时许可按依赖闭包生成，开发依赖若被运行时传递引用仍需保留，流程见[许可维护](../release/open-source-licenses.md)。

显示名为 ShenView，仓库与 Dart 包名为 `shen_view`。修改品牌显示不顺带变更平台身份、
MethodChannel 或数据目录；这些标识以对应平台工程和源码为准。

## 自定义工具路径

脚本通过 PATH 和系统安装目录查找工具，不要求固定盘符。需要指定其他工具时使用对应入口支持的参数：

| 工具 | 环境变量或脚本参数 |
| --- | --- |
| Flutter SDK | `FLUTTER_ROOT`，或 `-Flutter` |
| Dart / CMake | `-Dart` / `-CMake` |
| FFmpeg 构建工具 | `-CompilerDirectory` / `-Bash` |
| 编解码器组装工具 | `-ImageMagickDirectory` / `-SevenZipDirectory` |
| 测试与探针使用的 7-Zip | `SHENVIEW_7ZIP` |

脚本入口与构建输出目录见[项目结构](../architecture/project-layout.md)。
