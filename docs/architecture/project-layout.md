# 项目结构

ShenView 使用一个产品仓库。桌面应用与未来官网各自安装依赖、构建和发布。

| 目录 | 职责 |
| --- | --- |
| apps/viewer/ | Flutter 桌面应用；包含 Windows/macOS runner、应用资源、Dart 测试及应用专用工具 |
| apps/website/ | 官网工程建立时使用；尚未创建 |
| native/ | 自研原生 helper、平台桥接及 native/tests 原生测试 |
| third_party/ | 上游来源、固定版本、哈希、构建配方及必要补丁 |
| branding/ | 品牌 SVG 源文件及其生成资源 |
| docs/ | 使用、架构、设计、开发和发布资料 |
| packaging/ | 平台安装器、渠道模板及发布资源 |
| tool/build/ | 原生构建、品牌资源生成、运行组件组装 |
| tool/check/ | 完整检查、Windows 回归与打包验证 |
| tool/release/ | 安装包和发布清单生成 |

Flutter/Dart 命令在 apps/viewer/ 执行。仓库级 PowerShell 入口从仓库根调用，
通过 tool/paths.ps1 获取仓库、应用、原生构建和产物目录；macOS 构建脚本通过
tool/paths.sh 获取相同的目录关系。工作目录不作为仓库位置的判断依据。

应用的资源声明、本地 Dart 工具依赖和语言生成配置均以 apps/viewer/ 为根。
品牌源文件由 branding/ 维护；应用使用的位图、ICO 和 macOS 图标由生成脚本写入
应用资源目录。官网建立后从相同品牌源文件生成所需资源。

独立原生构建缓存位于仓库根 build/；Flutter 输出仍在 apps/viewer/build/。
安装包和报告位于仓库根 artifacts/。这些目录由 Git 忽略，源码目录 tool/build/
仍须提交。发布包内的文件布局由各平台打包流程决定，不照搬源码目录。

原生第三方来源集中在 [依赖锁定文件](../../third_party/dependencies.lock.json)，
CMake 和 SVG 安装工具从中读取下载地址与 SHA256。应用 Dart 依赖继续使用
apps/viewer/pubspec.lock。新增网站使用自己的依赖清单和锁定文件。

FFmpeg 的精简配置、固定源码和 Windows 依赖清单位于 third_party/ffmpeg/，
平台组装规则位于 native/ffmpeg/，构建入口为 tool/build/build_ffmpeg.ps1。
产物在 build/ffmpeg/windows-x64/runtime/，校验后组装到应用 codecs/ffmpeg/。
大型下载、二进制和解压源码保存在构建缓存中；平台验证范围见
[运行组件说明](../../third_party/ffmpeg/README.md)。

公开使用说明可由官网构建读取 docs/guide/；内部架构与开发资料继续保留在对应目录。
存在实际跨工程代码复用时再建立 packages/。官网需要独立权限或由独立团队维护时，
可以再拆分仓库。
