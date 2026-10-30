# 第三方依赖

dependencies.lock.json 是原生源码、resvg/NuGet 工具和 Windows 运行组件的来源及 SHA256 清单。
CMake 通过 cmake/dependencies.cmake 声明 FetchContent 依赖；Flutter 工程中的
tool/install_svg_codecs.dart 从同一清单获取平台工具。

更新依赖时同时更新固定来源与哈希，验证受影响平台构建，并保留上游许可证。
实际源码和构建产物写入仓库根 build/，不提交下载或解压目录。

libaom 使用官方发布的固定 tarball；Gitiles 按请求生成的归档元数据会变化，
因此不使用其即时归档作为固定 SHA256 的来源。

tool/build/install_windows_codecs.ps1 按清单下载并解包 ImageMagick 与 Windows 7-Zip，
缓存于 build/windows-codecs/，不运行安装程序。ImageMagick 安装包由固定版本的
innoextract 解包。Windows 构建和打包默认使用这些运行组件，打包时仍可通过
ImageMagickDirectory / SevenZipDirectory 显式指定供应目录，并复制运行文件和许可。
FFmpeg 的固定源码、Windows 依赖包及播放裁剪配置位于 ffmpeg/；构建、分发与
跨平台限制见 [FFmpeg 运行组件](ffmpeg/README.md)。
