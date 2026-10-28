# Git 工作流

首次配置 hooks 和下载测试资料见[准备仓库](getting-started.md#准备仓库)。本页说明提交格式、文件大小规则及检查工具。

## 检查工具环境

需安装 Git LFS。Windows 使用 Git for Windows 自带的 Git Bash；macOS 和 Linux 使用
系统 `sh` 与 Bash 3.2 或更新版本。这些检查无需 Node.js、Python 或 PowerShell。
hook 的 LF 换行由 `.gitattributes` 固定。

## 提交格式

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

### 自动检查

本地 hook 与 GitHub Actions 共用 `tool/check/commit_message.sh`。Actions 在 Windows、
macOS 和 Linux 上运行测试，并检查 push、PR 中新增的非合并提交，不追溯已有提交。
新分支与默认分支比较；手动触发时检查 HEAD 相对第一父提交新增的提交。真正的 merge
commit 跳过首行格式检查，其包含的普通提交仍会在 Actions 中检查。

### 验证提交检查工具

在 Git Bash、macOS 或 Linux 终端中运行：

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

### 验证大小与 LFS 检查工具

在 Git Bash、macOS 或 Linux 终端中运行：

```sh
bash tool/check/staged_files_test.sh
```

测试使用临时本地 Git/LFS 仓库，验证提交前拦截、暂存区属性，以及测试资料上传、克隆、
拉取后的逐字节一致性，不连接 GitHub。当前 Actions 仍只检查提交信息，尚未接入大小
检查；未来执行图片测试的工作流需在 checkout 中启用 `lfs: true`。
