# Windows 预览版源码与下载说明

下载渠道为 [GitHub Releases](https://github.com/xiamibuchi/shen_view/releases)。
每个应用版本提供便携 ZIP、版本清单、许可快照、源码索引和校验文件。
源码通过固定提交及集中源码 Release 提供，不随每个应用版本重复上传；官网、WinGet、Scoop 和 MSIX 分发留待后续。
预览版暂不签名，不以购买代码签名证书作为发布条件。

## 下载与运行

下载该版本的 windows-x64-portable.zip，完整解压后运行 ShenView.exe；不要在 ZIP 内直接启动。
配置和缓存存放在 user-data 中，更新前自行备份。复杂 SVG 需要 Microsoft Edge WebView2 Runtime；
无运行时环境使用静态 SVG 回退。最低系统为 Windows 10 2004（19041）x64。

ZIP 内的 ShenView 程序未进行受信任的发布者签名，可能出现 SmartScreen 警告。
若另外提供未签名 EXE 安装器，UAC 可能显示“未知发布者”；安装器仍须完成独立验收。
不要求用户关闭 SmartScreen、杀毒软件或系统安全策略。SHA256 可用于核对文件完整性，不能替代发布者签名。
只从本仓库的 Release 下载，按与 ZIP 同名的 .sha256 文件核对应用包。
SOURCES-SHA256SUMS.txt 校验本版本的源码索引和许可快照；远程源码归档的 SHA256 及大小记录在 SOURCES.json。

## 固定源码链接

SOURCES.json 将源码资料绑定到应用 ZIP 的 SHA256 和源码提交，区分 location=remote 的归档链接与
location=local 的许可快照。应用 Release 说明直接列出源码链接和本页的固定提交链接，不另上传 SOURCES.md。
普通用户只需便携 ZIP；需要源码时，按索引获取对应提交及覆盖组件的归档，不使用 main、latest 或上游主页代替精确版本。

| 来源 | 范围与重建入口 |
| --- | --- |
| SOURCES.json 中的 source.url / archiveUrl | 对应应用提交的 Git 源码和下载链接，包含 native/、third_party/、tool/、应用代码和构建说明。查看 docs/development/getting-started.md；archive helper 使用 native/archive_helper/CMakeLists.txt，HDR helpers 使用 native/hdr_codecs/CMakeLists.txt，视频 helper 使用 native/hdr_video/。不另上传 ShenView source.zip。 |
| native-sdk-v1.0.1 的 shenview-hdr-sources-windows-x64.zip | 实际锁定 SDK 的依赖源码：LibRaw 0.22.3、libjpeg-turbo、libavif、libaom、Little CMS、libultrahdr，以及 recipe/ 中的构建配方。SDK 的版本和二进制哈希由 third_party/native-sdk.lock.json 固定。 |
| native-sdk-v1.0.1 的 shenview-ffmpeg-sources-windows-x64.zip | 实际 SDK 的 FFmpeg 9.0.2 源码树、FFmpeg 补丁与构建配方，以及 msys2/ 内精确匹配 libplacebo 二进制的源码包。构建配置见 recipe/ffmpeg/profile.sh 与 build-windows.sh。源码树已应用 FFmpeg 补丁时不要重复应用；从 pristine 上游源码重建则由脚本应用。 |
| third-party-sources-v1 的 7z2605-src.tar.xz | 7-Zip 26.05 引擎及 helper 所用的上游接口、辅助代码。保留 LGPL、BSD 和 unRAR 声明；自有 helper 源码在 ShenView 对应提交中，不能将其中上游代码重新声明为 Apache-2.0。 |
| third-party-sources-v1 的 ImageMagick-7.1.2-34-Windows.7z | 官方同版本完整 Windows 源码，包括 ImageMagick、Configure 与 Dependencies；用于重建及重新链接委托库。按归档内 Configure 的构建说明及 ImageMagick 的 Windows release 配方构建 Q16/HDRI/x64/dynamic 版本。其中 LibRaw 0.22.2 与自建 helper 的 0.22.3 分别交付，不能互相代替。 |
| ShenView-版本-notices.zip | 从实际应用 ZIP 提取的 LICENSE、Flutter NOTICES.Z 和 codecs/licenses/，保留原始第三方许可、例外、来源和构建配方。SOURCES.json 记录每份许可文件的哈希。 |

这里的“版本”为 Windows 四段版本。集中源码附件保留原始归档、文件名和哈希，不覆盖已被应用版本引用的归档。
对应固定下载位置为 [native-sdk-v1.0.1](https://github.com/xiamibuchi/shen_view/releases/tag/native-sdk-v1.0.1)
和 [third-party-sources-v1](https://github.com/xiamibuchi/shen_view/releases/tag/third-party-sources-v1)，准确链接以 SOURCES.json 为准。
GitHub 源码下载内的 Git LFS 测试样本可能是指针；运行样本测试需从对应提交执行 git lfs pull。
这不影响 native/ 和第三方覆盖代码的源码交付。构建工具、Windows SDK 与 Visual Studio 需按各自条款另行安装，
不在此处承诺字节级可重复构建。

ImageMagick 的 Windows 源码归档包含上游各仓库的完整检出及构建配置，不能只取通用 Unix 源码包代替。
二进制使用的 Dependencies 为 2026.10.13.2113（d38cb0f91e91357c3b299087f17a6b27cc05d056），
归档检出与该 tag 一致。Configure 二进制来自 2026.09.21.1729；归档包含 Git 历史，
重建这个工具前先在 Configure 目录执行 git checkout --detach 2026.09.21.1729，使用对应源码而非较新的默认检出。
本版发行使用 VS 2026 / v145；可在 VS 开发者命令提示符构建 Configure/Configure.sln，
然后按上游发行脚本的 Configure 工作目录和参数 /VS2026 /installedSupport /deprecated /hdri /Q16 /x64 /dynamic
生成并构建解决方案。需要从源码修改或重链接委托库时，
使用归档内 Dependencies 的源码与 Configure 项目，不要用 download-dependencies 脚本重新覆盖成预编译依赖。
完整配置逻辑及上游构建命令保留在 Configure/src/ 和 ImageMagick/.github/workflows/release.yml 中。
此处交付上游构建资料；本项目未另行验收完整 ImageMagick 源码的重建结果。

## 许可与替换

ShenView 自有代码采用根目录 Apache-2.0；第三方文件继续使用各自原有许可，不适用统一重新授权。
自建 LibRaw 使用其 CDDL 路径；ImageMagick 内的库按该 Windows 包的 NOTICE 和原始源码许可分别处理。
FFmpeg 的本项目配置未启用 GPL/nonfree，按实际构建和依赖许可交付；附带多个 COPYING 文件不代表启用了所有许可选项。

随包 FFmpeg 共享库、7z.dll 和 ImageMagick 委托库未加完整性强制或签名绑定，可在副本中替换为 ABI 兼容版本。
可按相应许可为修改、调试这些组件而重新链接或重建使用它们的程序；本项目不额外禁止此类调试或逆向。
若上游将 LGPL 委托库静态合入动态模块，完整 ImageMagick/Dependencies/Configure 源码资料用于重建该模块，
不能把“存在 DLL”当作所有内部库均为独立动态链接的证明。有关许可、专利及例外以各组件原文为准。

## 维护与发布

在干净的应用构建提交上运行：

~~~powershell
powershell -ExecutionPolicy Bypass -File tool/release/package_windows_sources.ps1 -ReleaseDirectory <便携包目录>
~~~

脚本校验包版本、提交和 SHA256；依赖二进制哈希变化而未更新源码锁时直接失败。
输出目录必须为空，避免把旧方案的大源码附件混入当前应用 Release。
远程归档先下载到共享缓存，校验完整 SHA256 和归档可读性，再写入索引；应用产物不复制这些归档。
上传草稿前另核对 GitHub 上的源码提交、已公开源码 Release、附件大小及摘要，失效或被替换的链接会阻止草稿更新。
使用第三方自定义二进制时，必须同时更新准确源码及构建资料，不能复用官方源码的交付结论。
第三方更新同时维护 third_party/release-sources.lock.json，并核对归档内容与实际随包版本、修改和链接方式。

第三方源码先上传到本仓库的集中源码 Release，校验后公开，再更新源码锁中的固定链接。
保留 upstreamUrl 作为上游来源记录；不能仅删除附件并指向外部主页，源码的长期可用性仍由本项目维护。
更改源码归档时创建新的 SDK 或集中源码版本；不覆盖旧版本附件。

release 分支合入 main 后，Release 流程生成源码索引和许可快照并创建未签名预发布草稿；日常 PR 不下载这些大归档。
应用 Release 共 6 个附件：应用 ZIP、同名 .zip.sha256、release.json、版本 notices.zip、SOURCES.json、SOURCES-SHA256SUMS.txt。
草稿保留固定源码链接及重建说明；仍需检查验收结果、已知限制与附件完整性，再人工公开。
渠道模板如以后启用，应引用固定版本的 /releases/download/v版本/文件名，使用最终附件哈希，不能指向可变的 latest 下载。

Source delivery: SOURCES.json links the exact application commit and reusable dependency source archives in this repository.
Remote archives are verified against the SHA256 and sizes in that index; SOURCES-SHA256SUMS.txt covers the local index and notices snapshot.
Source availability, patches and rebuilding materials remain required. Original third-party licenses remain in effect.
The application is unsigned; checksums verify integrity, not publisher identity. Do not disable system security protections.
