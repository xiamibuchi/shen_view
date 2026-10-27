# 原生 HDR 显示

## 显示链路

输入解码为线性浮点 Rec.709，经源原色和白点转换后交给原生表面。
Windows 使用 D3D11 / DirectComposition 的 scRGB FP16，必须同时通过当前输出 HDR 状态与
swap chain 色彩空间检查；macOS 使用独立 CAMetalLayer 和 EDR，依据当前屏幕实际 headroom。
图像不经过 Flutter 普通图像表面，交互仍由 Flutter 处理。macOS 链路尚未完成实机验收。

EXR/Radiance 的场景线性值没有唯一显示亮度意图。当前参考白为 203 cd/m²，
Windows scRGB 的 1.0 对应 80 cd/m²，输出乘以 203/80；macOS 保留相对 SDR 参考白的 1.0。
负色彩分量与大于 1 的高光保留，最终显示器变换交给 DWM/ColorSync。
Windows 按当前输出峰值软压缩高光，峰值不足时下调参考白。

## 输入与 SDR 回退

- HDR/EXR 使用源色度及 Bradford 白点适配，未标注时按线性 Rec.709 解释。
- PQ/HLG 从 PNG、AVIF/HEIF 元数据识别并转为线性浮点；Gain Map 通过对应 JPEG、AVIF、HEIF helper 重建。
- Gain Map 的 SDR 显示始终使用文件基础图，只有原生 HDR 显示请求增益重建，避免 SDR 整体发白。
- 通用 HDR/EXR SDR 回退在线性光中做 Reinhard 后转 sRGB，尚未复用原生 HDR 源原色矩阵。
- RAW 使用传感器线性显影，共用曝光规则见 [RAW 解码](raw-decoding.md)。
- Dolby Vision 依赖 ffprobe 元数据和 FFmpeg/libplacebo RPU；Profile 7 增强层未接入，只能回退基础层。

当前不提供可调参考白、曝光或完整 ICC 软打样与打印色彩管理。

## 交互与回退

设置 → 图像与 HDR 按图片类型控制原生主图显示，不改变格式识别、RAW 曝光、缩略图或原图另存。
关闭或不支持 HDR、helper 缺失、超预算、设备移除与原生异常时保留 SDR 图像。
相同输出失败后不循环解码，重新加载、换图或输出变化后可重试。

几何跟随 Flutter 布局变换和裁剪，不用持续 ticker 驱动静止图片。切屏或设备变化重建对应输出。
菜单、面板浮层、失焦和其他页面期间临时使用 SDR，避免原生表面遮挡 UI，恢复时可能有亮度变化。
单页、双页与非分块长图可用原生 HDR；连续阅读和分块长图使用 SDR。
透明内容使用 premultiplied alpha，HDR 成功后隐藏同一张 SDR 底图，避免重复混合。

像素、帧缓存和解码进程均有预算，切图和卸载释放请求及原生资源。
SDR 预览与原生 HDR 层共享文件版本对应的浮点源帧，显示能力变化只重建输出，
不强制重新解码同一源图。可用的缩略图缓存及文件基础 SDR 图优先显示，
共享 HDR 解码不要求这些缩略图等待主图。
Dolby 静态解码由独立 helper 串行复用 Vulkan/libplacebo 设备与渲染器；逐文件清理
源解码器、图像与纹理，保留设备及着色器。取消在实际 CPU/GPU 工作结束后确认，
仍受全局解码并发与字节预算约束；内存压力丢弃 GPU 状态，空闲 30 秒退出。
HDR 视频首帧通过有界 RGBA16 原始数据传输，直接转成内部线性浮点帧，
不再经过 PNG 编解码。helper 响应校验请求身份、尺寸、长度及 BT.2020/PQ 格式；
无 helper 的开发环境仍可用 FFmpeg CLI 输出同精度原始数据。
输出预算见 [解码器](../../apps/viewer/lib/src/application/hdr_decoder.dart)，屏幕能力见
[显示服务](../../apps/viewer/lib/src/application/hdr_display_service.dart)。
实屏亮度、跨屏、DPI、热插拔和恢复另验，FP16 回读与 SDR 截图只证明各自链路。
测试命令见 [验证入口](../development/validation.md#hdr-专项)，样本与画质校验见
[HDR 样本](../../apps/viewer/testdata/formats/HDR.md)。

平台依据：[Microsoft Advanced Color](https://learn.microsoft.com/en-us/windows/win32/direct3darticles/high-dynamic-range)、
[Apple Metal HDR](https://developer.apple.com/documentation/metal/hdr_content)。
