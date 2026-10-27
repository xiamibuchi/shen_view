# 神羊看图 · ShenView 品牌资源

中文名称：**神羊看图**。英文名称：**ShenView**，保持 S、V 大写。

标语：**把目光，留给图片。 / Your pictures, in focus.**

并列名称写作“神羊看图 · ShenView”。介绍先说明本地图片与文件夹浏览，再介绍漫画、动图和 HDR。
HDR 保留图片、解码链路与显示设备兼容条件；平台、格式和隐私承诺须有发布包依据。
品牌色用于图标资源，界面使用自身的语义令牌。

## 图标源文件

| 文件 | 用途 |
| --- | --- |
| [app-icon.svg](app-icon.svg) | 彩色主图标，512 × 512 坐标，开放式羊角与风景负形 |
| [app-icon-small.svg](app-icon-small.svg) | 16 至 40 px 简化版，32 × 32 坐标，粗羊角、简化山峰、无太阳 |
| [mark-monochrome.svg](mark-monochrome.svg) | 透明底深青色单色标志 |
| [mark-monochrome-light.svg](mark-monochrome-light.svg) | 透明底暖白色单色标志 |
| png/ | 由上述 SVG 导出的 16 至 1024 px PNG 和两种单色 PNG |

配色：青绿 #169C91、深青 #174E58、暖白 #FFF8E9。小尺寸使用纯色青绿 #137F7D。
羊角使用开放弧线，不保留盘绕内圈；小图标扩大主体，保留明显间隙。

## 生成平台图标

安装 ImageMagick 后，在仓库根执行：

```powershell
powershell -ExecutionPolicy Bypass -File tool/build/generate_brand_icons.ps1
```

ImageMagick 不在 PATH 时，通过 -ImageMagick 指定 magick.exe 的完整路径。
脚本从 SVG 生成 PNG、Windows ICO 和 macOS AppIcon；平台资源不手工修改。
SVG 使用显式填充色和描边色，保证 Flutter 与导出工具的渲染颜色一致。

- Windows：apps/viewer/windows/runner/resources/app_icon.ico，包含 16、20、24、32、40、48、64、128、256 px。16 至 40 px 使用简化图形。
- macOS：apps/viewer/macos/Runner/Assets.xcassets/AppIcon.appiconset/，包含 16、32、64、128、256、512、1024 px；16、32 px 使用简化图形，并保留平台图标外围透明留白。
- 关于页使用 resvg 从彩色 SVG 导出的多倍率 PNG，逻辑尺寸为 52 px。在 apps/viewer/ 运行 `dart run tool/generate_ui_icons.dart` 更新 `assets/ui/app-icon.png` 及其 2×、3×、4× 资源；同一命令也生成底栏信息图标，运行时按主题着色。平台图标仍由上述 ImageMagick 脚本生成。

## 文案与预览

- [README](../README.md)：产品介绍、功能摘要与开发状态。
- [中文商店文案](../docs/release/store-listing.zh-CN.md) / [English store listing](../docs/release/store-listing.en-US.md)。
- [品牌预览](../docs/design/preview.html) / [预览图片](../docs/design/preview.png)。

产品显示名称和产物名已使用新品牌。Dart 包名 shen_view、内部 MethodChannel、
已有配置文件名和 Bundle ID 保持稳定，避免影响现有设置、缓存和平台身份。
