# 图片回归样本

格式兼容样本放在本目录，按用途命名，不再使用 `sample.*`。照片元数据专项样本及来源另见 [照片元数据样本](../photo_metadata/README.md)。

- `format_用途.扩展名`：普通图片、动画、长图、色彩配置和漫画容器。
- `raw_相机或场景.扩展名`：真实相机 RAW 或明确标注的自有 DNG。
- `hdr_信号或场景.扩展名`：线性 HDR、PQ、HLG、Gain Map、透明度等。

新增文件须加入 `test/format_fixture_catalog_test.dart` 并在本页或专题页说明预期结果。该清单检查命名、完整性、真实格式识别及所有已声明格式的覆盖；它本身不代表画质通过。

自有 AVIF 动画、单帧与渐进式样本由 `tool/generate_avif_fixtures.ps1` 生成；
需先构建 `viewer_avif_animation`，帧时长、像素及播放行为见 `test/avif_codec_test.dart`
和 `test/animation_viewer_test.dart`。

## 普通格式

| 样本 | 验证目的与当前断言 |
| --- | --- |
| format_multisize.ico / format_bitmap.ico / format_single.ico | 自有样本，由 `tool/generate_ico_fixtures.dart` 生成；覆盖 16–256 像素、多版本同尺寸、PNG/BMP、1/4/8/24/32 位与透明掩码。`ico_test.dart` 检查实际像素、版本缓存及缩略图；`ico_viewer_test.dart` 检查信息面板切换 |
| format_static.png / webp / jxl / avif | 同一 4096×2160 渐变。PNG 保留作 `tool/performance_probe.dart` 的大图解码基准；其余三种编码本身已很小。`format_rendering_test.dart` 走真实图片资源入口，检查三处固定 sRGB 参考色、方向、256×135 缩放比例和不透明度；每通道容差 6/255，覆盖有损量化和重采样 |
| format_static.jpg / tiff / dds | 同一渐变缩小为 512×270，分别保留 JPEG、16 位 TIFF 与 DXT1 DDS 编码；采用相同的颜色、方向、比例和不透明度断言 |
| format_static.bmp / psd | 同一渐变缩小为 512×270，保留 24 位真彩色 BMP、16 位 RGB PSD 的合成图与一个图层；采用相同的颜色、方向、比例和不透明度断言 |
| format_srgb_icc.png | 同一 512×270 渐变，保留原始 sRGB ICC 字节；同样检查颜色，不能仅凭存在 iCCP 判定色彩正确 |
| format_alpha.heic / heif | 700×476 恐龙与透明阴影。HEIF Gain Map 的 SDR 对照基础图；真实 Windows 集成测试逐像素对比主图和缩略图，另有格式/打开探针 |
| format_color_patches.svg | 自有 RGB 原色与半透明色块。`svg_image_test.dart` 实际离屏渲染并检查颜色、alpha，截图在 artifacts/formats/svg-patches.png |
| format_animated.gif / webp / apng | 大尺寸动画，格式探测与打开/帧数探针；尚无逐帧颜色参考断言 |
| format_animated_small.apng | 小尺寸 APNG 色卡，覆盖 acTL 动画标记探测；尚无逐帧颜色参考断言 |
| format_animated.avif / format_animated_finite.avif / format_animated_icc.avif | 自有三帧透明色块，覆盖变帧时长、无限/有限循环、ICC、逐帧颜色、跳转与播放控制 |
| format_animated_pq.avif / format_animated_hlg.avif | 自有 10/12 位色块动画，检查固定 HDR → SDR 映射、颜色与 alpha |
| format_single_frame.avif / format_progressive.avif | 单帧与渐进式静态 AVIF，不应识别为动画或显示播放条 |
| format_long.png | 1800×12000 长图；性能探针和真实窗口长图回归，不是绝对颜色参考 |
| format_comic.cbz | ZIP 漫画容器与路径/打开回归 |
| format_comic_zip.cbr | 故意将 ZIP 放入 .cbr，覆盖扩展名与容器不一致的兼容场景 |
| format_comic_rar.cbr | 真正的 RAR 漫画容器；7-Zip 路径与打开回归 |

RAW 样本、来源和验证强度见 [RAW.md](RAW.md)；HDR 标准、亮度参考和实屏边界见 [HDR.md](HDR.md)。`hdr_gradient.hdr/exr` 是旧的渐变兼容样本，已从 `sample.hdr/exr` 更名；定量 HDR 验收使用阶梯图。

`format_static.tiff` 使用 ZIP 压缩与水平差分预测，`hdr_gradient.exr` 使用 ZIP 压缩；
两者均为 512×270，分别保留 16 位整数与半浮点通道。仅改变无损压缩方式时，须比较
解码后的 32 位浮点 RGB 数据，确认逐字节一致。PSD 的合成图与图层均使用 RLE，兼容当前
ImageMagick 不支持 ZIP 合成图的限制。BMP 保留真彩色编码，避免调色板量化。

小尺寸样本可从保留的 4K 渐变或对应格式生成；以下命令在样本目录执行，输出至临时目录：

```powershell
magick format_static.png -resize 512x270 -type TrueColor -depth 8 -compress None $env:TEMP/format_static.bmp
magick format_static.tiff -resize 512x270 -clone 0 -compress RLE $env:TEMP/format_static.psd
magick format_static.png -resize 512x270 -define dds:mipmaps=0 -compress DXT1 $env:TEMP/format_static.dds
magick format_static.png -resize 512x270 -sampling-factor 4:4:4 -quality 95 $env:TEMP/format_static.jpg
magick format_static.png -resize 512x270 -depth 16 -define tiff:predictor=2 -compress Zip $env:TEMP/format_static.tiff
magick format_srgb_icc.png -resize 512x270 -define png:preserve-iCCP=true $env:TEMP/format_srgb_icc.png
magick hdr_gradient.hdr -resize 512x270 $env:TEMP/hdr_gradient.hdr
magick hdr_gradient.exr -resize 512x270 -compress Zip $env:TEMP/hdr_gradient.exr
```

## 运行

```powershell
flutter test
flutter test integration_test/raw_display_test.dart -d windows
flutter test integration_test/gain_map_display_test.dart -d windows
flutter test integration_test/hdr_display_test.dart -d windows
```

macOS 上将平台参数改为 `-d macos`，使用当地 Flutter 路径。真实解码用例需要仓库随包组件或已安装的 ImageMagick HDRI、LibRaw、Gain Map、FFmpeg 组件；缺失时会显示 skipped，不能作为画质验收通过。可设置 `SHENVIEW_MAGICK` 和组件对应环境变量指定位置。

`tool/format_probe.dart`、`windows_smoke_test.ps1` 是解码/可见性探针。探针成功只能证明该路径能打开图片，不代表亮度、色彩或 HDR 保真正确。定量断言与真实窗口测试分别负责这些结果；SDR 截图无法验证显示器实际 HDR 亮度，Windows HDR 与 macOS EDR 仍需实屏验收。
