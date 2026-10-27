# FFmpeg 播放组件

source.lock.json 固定 FFmpeg 9.0.2 官方源码及 SHA256；windows-packages.lock.json
固定 MinGW 依赖二进制包的来源与 SHA256。profile.sh 是运行能力清单，不启用网络协议、
视频压缩编码器、采集设备或 ffplay。PNG、rawvideo、PCM 编码器用于解码结果传输，
不提供视频导出功能。zscale、libplacebo 保留原有 HDR 读取路径。
`patches/libplacebo-lazy-vulkan.patch` 将 libplacebo 的 GPU 初始化延迟到实际格式协商，
避免 FFmpeg 为探测滤镜连接而解析临时图时额外创建一次 Vulkan 设备。
构建脚本自动应用，补丁纳入构建身份并随许可证中的构建配方分发。

在仓库根运行 tool/build/build_ffmpeg.ps1。需要 Git Bash、TDM GCC x64、7-Zip；
脚本校验下载，构建共享库，递归收集 PE 导入依赖，拒绝缺失的非系统 DLL。
产物位于 build/ffmpeg/windows-x64/runtime/，manifest.json 记录构建身份及二进制哈希。
Windows Flutter 构建自动校验并复制组件到 codecs/ffmpeg/，发行打包流程另将许可复制到
codecs/licenses/ffmpeg/，供应用「第三方许可」读取。

运行时优先使用随包组件，不要求用户安装 FFmpeg 或设置 PATH。开发和测试仍支持
SHENVIEW_FFMPEG / SHENVIEW_FFPROBE 显式替换，随后才尝试开发产物和系统 PATH。
共享库不静态链接进 ShenView，可用 ABI 兼容的修改版本替换；随包携带完整许可、
来源、哈希和构建配方。分发自定义依赖时，供应方必须一并提供对应源码及构建信息。

应用只对照片容器中的视频或 HEIF 时序轨启动播放。FFprobe 有输出上限和取消机制；
视频帧通过持续进程按需读取，最多保留一帧待转换数据，不把整段视频解码进内存。
音频通过另一条 FFmpeg PCM 流进入平台输出队列，队列最多 250 ms，暂停、跳转、
切图、窗口销毁会重置输出并终止相应进程。照片默认静音，可在播放条开启声音及选择音轨。
HDR 动态预览映射为 sRGB；原有静态 HDR 查看仍使用原来的高精度路径。

静态 Dolby Vision 使用 native/hdr_video/ 的 viewer_hdr_video helper，动态链接
同一组 FFmpeg/libplacebo 库，跨任务复用 Vulkan 设备及渲染器。逐图片释放解码器、
源文件与纹理；取消通过独立控制消息处理，实际工作结束后才回复。客户端串行派发，
服从现有两进程任务配额；空闲 30 秒退出，内存压力可只清理 GPU 状态。
输出为 packed RGBA16 little-endian、full-range BT.2020/PQ，32 字节协议头定义在
helper 与 Dart 客户端中；像素长度严格为 width×height×8，最大 32 MiB。
PQ/HLG 视频首帧的 CLI 路径也使用原始 RGBA16，不经过 PNG。

Windows 构建入口自动编译 helper，manifest.json 的 workerIdentity 单独追踪源码及
构建脚本哈希，helper 更新不强制重编 FFmpeg。helper 源码随运行组件构建配方提供。
其他平台可用 native/hdr_video/CMakeLists.txt 对接 pkg-config 中匹配的 FFmpeg 9 /
libplacebo 7.360 组件；macOS 仍需完成下述依赖封装、签名和 Vulkan 实机验收。

macOS 的音频输出接口使用 AVAudioEngine，定位器预留 Contents/Helpers/ffmpeg 和
ffprobe。当前自动构建、依赖锁定及打包产物仅验证 Windows x64，不能直接使用 Windows
DLL 作为 macOS 组件。macOS 分发需要另外锁定对应架构的依赖，按同一 profile 从源码
构建 dylib，收集依赖并修正 rpath，随应用签名、公证；libplacebo 的 Vulkan 路径还需
验证 MoltenVK。未完成这些步骤前，macOS 仍依赖显式配置的开发组件，不视为发布完成。

已知边界：不是所有 HEIF 文件内的多张图片都有时间轴；只有时序轨才作为动画。
辅助轨依据 auxl/thmb 引用和 auxi 类型区分，透明度序列才与主序列合成；深度图不播放。
不同时间基、编辑列表、复杂派生图像、增益图、各厂商私有 Motion Photo 及 Dolby Vision
配置仍需原始样本逐项验证。标准合成样本的通过不能代表所有手机或所有 HEIF 类型。
