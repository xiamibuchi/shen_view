# 开发环境与维护

## 环境与构建

将 Flutter 和 CMake 加入 PATH；Windows 安装 Visual Studio C++ 工具链与 7-Zip。
工具路径通过 PATH 和系统安装目录查找，不要求固定盘符。Flutter 也可由 FLUTTER_ROOT
指定 SDK 根目录；脚本的 -Flutter、-Dart、-CMake 等参数支持显式指定工具。
FFmpeg 构建需将兼容的 x64 MinGW GCC 加入 PATH，或传 -CompilerDirectory；
Git Bash 根据 Git 安装位置查找，也可传 -Bash。编解码器组装支持
-ImageMagickDirectory 和 -SevenZipDirectory，测试与探针的 7-Zip 可由 SHENVIEW_7ZIP 指定。
当前提供 Windows 和 macOS 工程，macOS 原生链路需在 Mac 上构建验收。
开发 SDK 版本见 [项目 README](../../README.md)，依赖锁定版本以 pubspec.lock 为准。

Windows 从仓库根准备应用与原生组件：

~~~powershell
cd apps/viewer
flutter pub get
flutter build windows --release --no-pub
cd ../..
powershell -ExecutionPolicy Bypass -File tool/build/build_archive_helper.ps1
powershell -ExecutionPolicy Bypass -File tool/build/build_hdr_codecs.ps1
~~~

Flutter/Dart 命令在 apps/viewer/ 执行，仓库级脚本从仓库根调用。
应用构建输出位于 apps/viewer/build/，独立原生构建缓存位于仓库根 build/。
Windows Flutter 构建会准备 SVG、AVIF 和 FFmpeg 后端；首次构建 FFmpeg 还需要
Git Bash、TDM GCC x64 与 7-Zip，固定依赖会自动下载并校验。清理原生缓存后需重建 helper。
各组件的平台要求见 [归档 helper](../../native/archive_helper/README.md)、
[SVG 构建](../architecture/svg-rendering.md#构建与运行) 与
[HDR 构建](../../native/hdr_codecs/README.md)。检查命令见 [验证说明](validation.md)。

VS Code 使用 Flutter 扩展选择设备，主工程不交给 CMake Tools 自动接管。
个人 SDK 路径、主题与生成器放在用户设置。移动仓库后重新打开目录并执行 flutter pub get，
旧绝对路径缓存通过 flutter clean 后重建，不手改生成文件。

## Git 提交格式

克隆仓库后执行以下命令，启用当前仓库的提交检查：

```sh
git config --local core.hooksPath .githooks
git lfs install --local --skip-repo
git lfs pull
```

需安装 Git LFS。Windows 使用 Git for Windows 自带的 Git Bash；macOS 和 Linux 使用
系统 `sh` 与 Bash 3.2 或更新版本。无需安装 Node.js、Python 或 PowerShell。hook 的 LF
换行由 `.gitattributes` 固定，`--skip-repo` 保留仓库维护的 hooks，只配置本地 LFS filters。

提交首行采用 `类型(范围): 描述`，范围可省略，描述支持中文：

```text
feat(viewer): 增加图片旋转
fix(hdr): 修复高光显示异常
docs: 更新运行说明
feat(api)!: 移除旧接口
```

类型为小写的 `feat`、`fix`、`docs`、`style`、`refactor`、`perf`、`test`、`build`、
`ci`、`chore` 或 `revert`。范围不能包含空白或嵌套括号；冒号后使用一个普通空格，
描述不能为空或带首尾空白。检查只约束首行，正文和 footer 不限；支持 UTF-8、BOM、
LF 和 CRLF。`fixup!`、`squash!` 提交须整理后再提交。

本地 hook 与 GitHub Actions 共用 `tool/check/commit_message.sh`。Actions 在 Windows、
macOS 和 Linux 上运行测试，并检查 push、PR 中新增的非合并提交，不追溯已有提交。
新分支与默认分支比较；手动触发时检查 HEAD 相对第一父提交新增的提交。真正的 merge
commit 跳过首行格式检查，其包含的普通提交仍会在 Actions 中检查。

在 Git Bash、macOS 或 Linux 终端中运行校验工具的测试：

```sh
sh tool/check/commit_message_test.sh
sh tool/check/commit_message.sh --range BASE HEAD
```

本地 hook 可被 `--no-verify` 绕过。若需阻止未通过检查的 PR 合并，须在 GitHub 分支规则中
将三个 `Commit message format` 检查设为必需，并限制直接推送和绕过权限。

## 文件大小与 Git LFS

`pre-commit` 调用 `tool/check/staged_files.sh`，检查暂存区中的新增、修改、重命名文件，
普通 Git 文件单个不能超过 20 MiB（20 × 1024 × 1024 字节）。检查读取 Git 对象大小，
不读取工作目录中的替代版本，也不依赖平台特有的文件大小命令；删除文件不会被拦截。
暂存 `.gitattributes` 规则变更时，会扩大到当前索引全部文件，防止已有文件漏转 LFS。

`apps/viewer/testdata/` 默认使用 LFS，包括图片、RAW、HDR、动图、视频、压缩包和 ICC。
其中 Markdown 文档、SVG、JSON、TXT 保留普通 Git；除 Markdown 使用 LF 外，文本测试
输入不转换换行符。应用图标、品牌资源和文档截图继续使用普通 Git，标为二进制；构建
产物、缓存、第三方下载内容不提交，正式安装包放在 Releases。其他目录若新增大型
设计源文件、媒体或模型，应按其具体路径添加 LFS 规则，不将所有二进制一律转入 LFS。

LFS 路径的暂存内容必须是规范指针，空文件采用 Git LFS 的空 Git blob 表示。合法的
LFS 文件不套用普通 Git 的 20 MiB 限额，但仍受 GitHub LFS 套餐限制。若提交被拦截，
根据提示缩小文件或配置 LFS，然后重新暂存：

```sh
git lfs install --local --skip-repo
git add --renormalize -- path/to/file
bash tool/check/staged_files.sh
```

`pre-push` 负责上传 LFS 对象，`post-checkout`、`post-merge`、`post-commit` 使用 Git LFS
标准 hooks。不要仅复制指针而遗漏实际对象；缺失资料可用 `git lfs pull` 恢复。现有资料
只在后续提交中转换为指针，不改写旧提交；工作目录保留实际内容。

在 Git Bash、macOS 或 Linux 终端中运行大小和 LFS 集成测试：

```sh
bash tool/check/staged_files_test.sh
```

测试使用临时本地 Git/LFS 仓库，验证提交前拦截、暂存区属性，以及测试资料上传、克隆、
拉取后的逐字节一致性，不连接 GitHub。当前 Actions 仍只检查提交信息，尚未接入大小
检查；未来执行图片测试的工作流需在 checkout 中启用 `lfs: true`。

## 配置存储与排查

Windows 普通安装版配置为 %LOCALAPPDATA%/ShenView/settings.json；便携版和 Scoop
位于程序旁 user-data/settings.json，未带模式标记的开发运行仍放在程序旁。
MSIX 使用包内应用可见的 LocalAppData/ShenView/MSIX，受 Windows 包重定向管理。
打包方式和数据保留规则见 [Windows 分发](../release/distribution.md)。macOS 为用户
Library/Application Support/ShenView/settings.json，沙箱下位于容器中。
Debug 和 Release 可能使用不同配置，排查时先确认正在运行的可执行文件。

启动和浏览使用容错读取，损坏、超限或不可读的配置回退到默认值，读取本身不改写文件。
保存使用严格读取，持续读取失败或无写权限时保留已有文件并报告失败。
遇到设置未保存，先检查目标目录权限、可用空间及是否被其他程序独占，保留原文件用于排查。

配置缺失、损坏、只读或被占用等场景可运行 tool/check/windows_config_smoke.ps1，
它使用独立程序副本，不操作用户配置。多窗口写入机制见
[共享数据](../guide/multi-instance.md#共享数据)。

字段与默认值直接查 [ViewerSettings](../../apps/viewer/lib/src/domain/viewer_settings.dart)，
文件读写及容错查 [AppConfigStore](../../apps/viewer/lib/src/application/app_config_store.dart)。
不另外维护配置格式表或手工编辑指南。

## 代码约束

静态规则以 [analysis_options.yaml](../../apps/viewer/analysis_options.yaml) 为准。
页面使用共享主题、控件和 Fluent 图标；设计 lint 的范围与执行方式见
[规则包说明](../../apps/viewer/tool/design_lints/README.md)。custom_lint 需显式运行，不由 analyze 自动执行。
按改动范围选择验证的要求集中在 [AGENTS.md](../../AGENTS.md)。

## Material Icons

业务图标使用 Fluent，Flutter 默认控件仍引用 Material 图标，因此保留 uses-material-design。
移除前需覆盖默认返回、关闭、菜单与文字选择等路径，不能只看业务图标是否迁移完成。
视觉测试从应用资源加载字体，不依赖固定 SDK 或 Pub 缓存路径。

## 依赖与工程标识

依赖更新后先检查实际解析结果，不用 dependency_overrides 跨越不兼容约束。
运行时许可按依赖闭包生成，开发依赖若被运行时传递引用仍需保留，流程见
[许可维护](../release/open-source-licenses.md)。

显示名为 ShenView，仓库与 Dart 包名为 shen_view。修改品牌显示不顺带变更平台身份、
MethodChannel 或数据目录；这些标识以对应平台工程和源码为准。
