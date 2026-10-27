# 动态照片合成样本

由 tool/generate_photo_media_fixtures.cjs 使用本机完整版 FFmpeg 的 color、testsrc2、sine
信号生成，生成时需要 libx264/libx265/libaom-av1；这些编码器不随应用分发。
不包含设备原片或第三方照片。所有样本可以按 ShenView 仓库许可证使用。

motion-h264/hevc/av1.jpg 覆盖旧式 XMP 偏移；motion-directory.jpg 覆盖容器目录、
主图 padding 和视频后的其他数据；motion-samsung.jpg 覆盖带厂商标记的拼接方式，
它是结构合成样本，不是 Samsung 原机拍摄文件。motion-heic.heic 使用 mpvd 数据盒。
motion-multiple-audio.jpg 包含 AAC 和 Opus 两条音轨；motion-offset.jpg 的视频比音轨
晚开始 0.5 秒，用于验证起始偏移下的逐帧跳转和声音播放。

sequence.heic 与 single.heic 使用 msf1 品牌和 pict 时序轨；sequence-alpha-depth.heic
包含主轨、auxv 灰度透明度轨、auxv 深度轨、auxl 引用和样本描述 auxi 类型，透明度
约为 50%。它们用于时序播放验证，不用于证明所有 HEIF 项目模型及静态封面兼容。

PQ/HLG 的 10 bit HEVC 和 PQ AV1 样本使用前期播放组件调研的自生成信号流，
可通过 FFMPEG_RESEARCH_FIXTURES 指定这些 MP4 所在目录后复现包装过程。
