# 压缩包分发许可

读取流程、固实包与缓存见 [压缩包实现](../architecture/archives.md)。

## 发行版本的依据

helper 编译接口和 macOS 引擎版本以 [CMake 输入](../../native/archive_helper/CMakeLists.txt) 为准。
Windows DLL 从构建环境复制，发行包 licenses/7zip/ENGINE.txt 记录实际版本与对应官方源码地址；
头文件版本不能代替运行引擎版本，开发用 7z.exe 也不代表随包 DLL。
升级同时核对各平台实际输入和打包记录，按 [验证说明](../development/validation.md) 回归。

## 商业使用与分发

官方允许将 7-Zip 的 EXE 或 DLL 用在商业应用中，无需注册或购买授权。
7z.dll 的主要许可证为 LGPL 2.1 或更高版本，部分代码附 BSD 许可证和
unRAR 限制；这不是仅采用公有领域 LZMA SDK 的方案。

分发时应保留版权及相关许可文本，在文档中说明使用了 7-Zip、其 LGPL 许可，
并提供项目和源码获取地址。打包已附带 LGPL 2.1 全文、7-Zip 源码及实际引擎的
许可、unRAR 说明，以及来源和版本记录。使用修改过的引擎时，官方原版源码地址
不能替代修改版的对应源码和构建资料。

LGPL 不要求将无关的 ShenView 主程序整体改成开源许可；但对应 LGPL 组件、
修改、源码提供方式及用户替换/重新链接该组件的权利仍需满足许可要求。
viewer_archive 引用了 7-Zip 接口和辅助代码，macOS 还编译了该项目的辅助源码；
发行者也应为 helper 中受 LGPL 覆盖的部分提供对应源码、改动及构建说明。
单独附带 DLL 许可不能代替这些义务。当前仓库源码和本地相对路径本身不等于
面向接收者的有效源码分发或书面提供承诺，正式发布时需落实获取方式。

unRAR 附加限制禁止利用相关源码重建 RAR 压缩算法或开发 RAR 兼容压缩器；
ShenView 当前仅用于读取/解压 RAR。它不禁止商业应用读取 RAR。

参考：[官方许可](https://www.7-zip.org/license.txt)、
[商业应用 FAQ](https://www.7-zip.org/faq.html)、
[官方下载](https://www.7-zip.org/download.html)、
[LGPL 2.1 全文](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html)。
