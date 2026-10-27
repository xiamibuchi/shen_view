# 第三方依赖

dependencies.lock.json 是现有原生源码下载及 resvg/NuGet 工具的来源和 SHA256 清单。
CMake 通过 cmake/dependencies.cmake 声明 FetchContent 依赖；Flutter 工程中的
tool/install_svg_codecs.dart 从同一清单获取平台工具。

更新依赖时同时更新固定来源与哈希，验证受影响平台构建，并保留上游许可证。
实际源码和构建产物写入仓库根 build/，不提交下载或解压目录。

libaom 使用官方发布的固定 tarball；Gitiles 按请求生成的归档元数据会变化，
因此不使用其即时归档作为固定 SHA256 的来源。

ImageMagick 与 Windows 7-Zip 运行引擎目前仍由打包脚本的显式供应目录提供；
本清单尚未把它们转换为自动下载的运行包。现有打包流程继续复制其运行文件和许可。
FFmpeg 的固定源码、Windows 依赖包及播放裁剪配置位于 ffmpeg/；构建、分发与
跨平台限制见 [FFmpeg 运行组件](ffmpeg/README.md)。
