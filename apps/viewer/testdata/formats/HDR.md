# HDR 测试图片

本页维护 HDR 样本、生成方法与画质校验；显示机制见
[HDR 显示文档](../../../../docs/architecture/hdr-rendering.md)，执行命令见
[验证入口](../../../../docs/development/validation.md#hdr-专项)。

命名总则和普通格式见 [README.md](README.md)，相机 RAW 单独列于 [RAW.md](RAW.md)。

| 文件 | 输入特征与验证内容 |
| --- | --- |
| hdr_highlights.hdr / hdr_highlights.exr | 0.18、1、2、4、8、16 六阶线性高光；RGBE/EXR 与 SDR 映射 |
| hdr_rec2020.exr | 显式 Rec.2020 色度；原色矩阵与白点适配 |
| hdr_transparent.exr | 线性浮点透明图；HDR 透明合成与回退 |
| hdr_pq.png / hdr_pq_alpha.png / hdr_pq.avif | PQ、BT.2020；逐通道核对 0/100/203/400/700/1000 nits 六阶亮度和颜色；alpha 为 0/0.5/1，检查仅预乘一次 |
| hdr_hlg.png / hdr_hlg.avif | HLG、BT.2020，参考 1000-nit 显示；核对六阶亮度和色域转换；AVIF 容许有损量化误差 |
| hdr_gain_map.jpg | Ultra HDR JPEG、ISO 21496 Gain Map；逐通道核对自有六阶图重建值，容许 5% 加 0.03 的有损误差 |
| hdr_gain_map.avif | libavif/AOM ISO 21496 tmap AVIF；关联图层重建 |
| hdr_gain_map.heic / hdr_gain_map.heif | HEVC tmap HEIF；主图、dimg 增益图及元数据联合重建 |
| hdr_dovi_p81.hevc | 自有 Profile 8.1 单层 Dolby Vision 静帧；RPU 解析、有效高光和解码兼容性，尚无认证 Dolby 显示参考 |
| hdr_gradient.hdr / hdr_gradient.exr | 512×270 旧渐变兼容样本；定量亮度请用自有阶梯图，大图解码性能基准使用 format_static.png |

## 自动化用例

- test/native_format_pipeline_test.dart：格式、元数据、尺寸、透明度和 SDR 解码。
- test/format_rendering_test.dart：真实资源入口核对 PQ/HLG PNG/AVIF 的 SDR 六阶参考像素，防止错误伽马或重复映射。
- test/hdr_avif_color_test.dart：用独立的 FFmpeg/AV1 解码链路核对 PQ/HLG AVIF 的色彩标记和全部 18 个色块的三个通道，避免生成器与查看器使用同一解码器而共同掩盖错误。
- test/hdr_rendering_test.dart：线性高光、色域、方向、显示层交互和失败回退。
- test/hdr_color_profile_test.dart：原色矩阵、白点和损坏元数据。
- test/raw_developer_test.dart：RAW 显影、浮点范围和方向。
- test/hdr_second_phase_test.dart：PQ/HLG、AVIF/HEIF、Gain Map 重建、Dolby Vision 和 HDR10 导出。
- test/gain_map_sdr_test.dart：HEIC/HEIF/AVIF/JPEG 主图和缩略图使用 SDR 基础图，禁止在 SDR 路径应用增益重建。
- integration_test/hdr_display_test.dart：原生 FP16 回读、scRGB 合成与 SDR/HDR 门控。
- integration_test/gain_map_display_test.dart：真实 HEIF 主图/缩略图与基础图逐像素比较，实际关闭自动 HDR 并核对原生图层释放，保存渲染截图。
- integration_test/raw_display_test.dart：真实窗口打开 raw_canon_white_paper.cr2，验证白纸背景亮度，切换自动 HDR 并核对 SDR 底图，保存查看器截图。

## 生成与验证

```powershell
dart run tool/generate_hdr_fixtures.dart
dart run tool/generate_raw_fixture.dart
dart run tool/generate_heif_gainmap_fixture.dart
flutter test
flutter test integration_test/hdr_display_test.dart -d windows
flutter test integration_test/gain_map_display_test.dart -d windows
flutter test integration_test/raw_display_test.dart -d windows
powershell -ExecutionPolicy Bypass -File tool/build/build_hdr_codecs.ps1
```

HEIF 生成器使用仓库中的 format_alpha.heif 构造确定性 tmap 容器，同时输出 .heic 与 .heif。它复用原图的辅助透明度图作为合成增益图，所以 HDR 主体会被刻意增亮；此图只作容器/解码和 SDR 回退回归，不作真实 HDR 曝光标准。运行时 helper 解码两个关联 HEVC 图像；组件缺失或输入损坏时只对该图片回退 SDR。SDR 输出应与 format_alpha.heif 基础图一致。

HDR 屏应区分高于参考白的阶梯，SDR 回退会压缩高光。SDR 截图不能证明原生 HDR 的实际亮度；Windows HDR 实屏与 macOS EDR 仍需对应硬件验收。

PNG 定量亮度误差上限为 0.01（以 203 nits 为 1）；有损 AVIF 为参考值的 2% 加 0.01；这些是像素链路容差，不是显示器物理亮度容差。HEIF 合成增益图验证容器、关联解码和 SDR 原图保留，没有真实摄影 HDR 的独立亮度真值。

## 如何校验 PQ / HLG AVIF 的颜色

`hdr_pq.avif` 和 `hdr_hlg.avif` 都是 384×192 的三行六列色块图：

- 上排：黑色至亮白的中性灰阶，设计亮度依次为 0、100、203、400、700、1000 nits。上排出现红色或紫色不是正常的亮度映射差异。
- 中排：橙色，由暗至亮。
- 下排：蓝色，由暗至亮。

PQ 的彩色行先以线性 Rec.709 设计，再转换到 BT.2020；HLG 的彩色行直接以 BT.2020 设计，使用 1000-nit 参考显示模型，最高亮度色块还存在名义信号范围裁切。因此两张图的彩色行不要求完全相同。

安装带 AV1 解码和 zscale 的 FFmpeg / ffprobe 后，在仓库根运行：

```powershell
dart run tool/verify_hdr_avif.dart
flutter test test/hdr_avif_color_test.dart test/format_rendering_test.dart test/hdr_second_phase_test.dart
```

独立脚本读取 AVIF 中实际标记的矩阵和范围，解码为 16-bit RGB 信号，与另行实现的 PQ / HLG 公式逐通道比较全部 18 个色块中心。最大归一化信号误差限为 0.004，同时检查 BT.2020、PQ / HLG、BT.2020 NCL、full range 和 10-bit YCbCr 4:2:0 标记。测试也核对查看器的浮点亮度及 SDR 输出，不能仅以成功打开作为通过条件。

脚本生成以下本地文件：

- `artifacts/hdr-color-check/verification.json`：输入标记、预期和实际信号、最大误差及通过状态。
- `artifacts/hdr-color-check/hdr_pq-reference-sdr.png`
- `artifacts/hdr-color-check/hdr_hlg-reference-sdr.png`

两张参考 PNG 使用当前查看器的线性 Rec.709 逐通道 Reinhard → sRGB 策略；灰阶 8-bit 值约为 0、156、188、213、228、235。可用它们检查图案、色相和查看器的 SDR 回退。其他软件可采用不同的正确 HDR 映射，所以不要求 Windows 预览、Photos 或 HDR 截图与这两张 SDR PNG 逐像素一致。HDR 输出还需要在开启 HDR 的屏幕上验收，高光实际亮度的定量验证需要测量设备。

2026-10-20 修正了旧 AVIF 样本的生成方式：旧文件使用 12-bit GBR 和 limited-range 标记，ImageMagick 自己解码时未暴露其与 FFmpeg 的结果差异，独立检查最大信号误差约为 PQ 0.064、HLG 0.089。现在显式转换为 10-bit YCbCr BT.2020 NCL、full range 后编码 AV1 Main；独立校验误差降为 PQ 0.00108 以下、HLG 0.00072 以下。重新生成后，文件预览程序可能仍缓存旧缩略图，需重新选择图片或刷新目录再对照；尚未据此宣称 Windows 预览或物理 HDR 屏幕已验收。
