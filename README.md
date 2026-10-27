# 神羊看图 · ShenView

> 把目光，留给图片。
>
> Your pictures, in focus.

神羊看图（ShenView）是一款用于浏览本地图片与文件夹的桌面看图工具，可以查看照片、长图和压缩包中的漫画。

- **顺手浏览文件夹**：目录导航、递归浏览、自然排序、网格总览与底部胶片栏。
- **选择查看方式**：单页、双页、长图与连续阅读，搭配独立的尺寸适配和自动播放。
- **直接阅读压缩包**：浏览 ZIP、CBZ、RAR、CBR 中的图片，无需事先手动解压。
- **细看动图**：暂停、逐帧、时间定位、倍速与循环控制。
- **查看图片细节**：颜色拾取、图片信息，以及兼容条件下的原生 HDR 显示与 SDR 回退。
- **适应阅读环境**：浅色、深色主题，全屏与无边框查看。

ShenView is a desktop image viewer for browsing local pictures and folders. It supports photos, long images and comics stored in archives.

品牌图标与生成方式见 [品牌资源](branding/README.md)；应用商店文案：[简体中文](docs/release/store-listing.zh-CN.md) / [English](docs/release/store-listing.en-US.md)。

## 开发状态

Windows 支持 Windows 10 2004（19041）及以上版本，架构为 x64。
Windows Release、原生解码与核心交互已有验证；macOS 实机验证和最终验收未完成。
HDR 效果需在兼容图片、解码链路和显示设备上验收。当前提供 Windows 与 macOS 工程，没有 Linux runner。

## 运行

开发环境为 Flutter 3.47.8 stable / Dart 3.13.7 或更高的兼容稳定版。
将 Flutter 加入 PATH，从仓库根进入应用工程运行：

~~~powershell
cd apps/viewer
flutter pub get
flutter run -d windows
~~~

macOS 使用 flutter run -d macos。原生组件、VS Code 配置和干净构建步骤见
[开发环境](docs/development/getting-started.md)。

## 文档

[完整文档索引](docs/README.md) 按功能使用、技术实现、设计规范、开发与验证、发布资料分类。

- [浏览与阅读](docs/guide/zoom-and-view-modes.md)、[目录导航](docs/guide/folder-navigation.md)、[打开与窗口](docs/guide/window-and-file-operations.md)
- [图片解码](docs/architecture/image-decoding.md)、[资源与缓存](docs/architecture/resources.md)、[压缩包](docs/architecture/archives.md)
- [界面设计规范](docs/design/spec.md)、[品牌资源](branding/README.md)
- [验证入口](docs/development/validation.md)、[Windows 回归](docs/development/windows-regression.md)
- [分发范围](docs/release/distribution.md)、[开源许可维护](docs/release/open-source-licenses.md)

## 验证与主题预览

日常修改按 [AGENTS.md](AGENTS.md) 选择验证范围。完整检查从仓库根调用：

~~~powershell
powershell -ExecutionPolicy Bypass -File tool/check/check.ps1
~~~

在 apps/viewer/ 运行 light/dark 并排主题预览：

~~~powershell
flutter run --dart-define=SHENVIEW_THEME_DEMO=true
~~~

Release 也支持 ShenView.exe --theme-demo。预览只用于视觉评审，真实交互以查看器为准。

## 工程结构

- apps/viewer/：Flutter 桌面应用，含 Windows/macOS 平台工程、资源、测试和应用工具。
- native/：自研原生 helper 与平台桥接；third_party/：第三方依赖锁定与构建配方。
- branding/：品牌图标源文件；docs/：使用、架构、设计、开发与发布文档。
- tool/build/、tool/check/、tool/release/：仓库级构建、检查和发布入口；packaging/：安装与渠道配置。

官网建立时放在 apps/website/，独立安装依赖、构建和部署。目录规则见[项目结构](docs/architecture/project-layout.md)。
仓库及 Dart 包名为 shen_view，显示名为 ShenView。
build/、artifacts/ 及各工程自身的构建缓存由 Git 忽略，不作为应用资源或正式测试输入。
