# 分支、检查与版本发布

main 保存已交付基线，release/<major.minor.patch> 承接一个 Milestone 的开发。
当前版本使用 release/0.1.0，不另设 develop。main 与 release/* 都要求通过 PR 合并。

## 日常开发

1. 从目标 release 分支创建 feat/、fix/、build/、ci/ 等工作分支。
2. PR 指向该 release 分支，标题使用 Conventional Commits；普通提交也遵循现有格式。
3. PR checks 通过、讨论解决后 squash merge，合并标题使用 PR 标题。
4. 版本验收完成后，从 release 分支向 main 创建发布 PR，使用 merge commit 合并。
5. 发布完成后，从最新 main 创建下一版本分支，在工作分支中修改 pubspec.yaml，再通过 PR 合入。

紧急修复从 main 创建 release/补丁版本，再创建 fix 工作分支；经 PR 修复和发布后，
通过另一个 PR 将修复移入正在开发的版本。可 cherry-pick 修复提交，但不得直接推送受保护分支。
修改版本文件属于 PR 内容，不在发布工作流中提交版本号。未发布版本的剩余任务继续留在其 Milestone。

## 合并门禁

GitHub ruleset 对 main 与 release/* 强制 PR、PR checks 与 PR policy 成功、目标分支最新、讨论已解决，
禁止强推和删除；没有日常 bypass。个人维护暂不要求其他人批准，不等于允许跳过 CI。
可使用更新分支按钮同步 base；不要依赖本地 hook 替代服务端规则。
受保护分支规则模板位于 .github/rulesets/protected-branches.json；需由有权限的维护者应用到仓库，
提交 JSON 本身不会自动启用规则。必需检查名必须与实际 Actions job 的 PR checks、PR policy 一致。

规则启用前先运行首个 PR，确认检查名称和 runner 可用；将 GitHub Actions 设为该检查的预期提供方。
不要求线性历史，因为版本 PR 使用 merge commit。版本分支不自动删除，工作分支合并后可手动清理。

## PR 检查与便携包

Pull request checks 对 main、release/* 的 PR 执行。工作流始终启动，内部仅允许
README.md、docs/ 下普通 Markdown 说明跳过 Windows；混合改动、空差异和未识别路径完整执行。
重命名同时检查旧、新路径，避免源文件移入 docs 后漏检。

- PR policy 检查标题、目标版本和 Windows 可表示的版本范围。main 只接受同仓库的匹配版本分支。
- PR policy 独立执行，修改标题或正文只重跑规则检查，不取消或重跑 Windows 构建。
- Windows/macOS/Linux 验证提交检查工具及 PR 新增的普通提交。
- Windows 构建先下载 LFS 样本，使用锁定 Flutter，生成本地化与许可排除表并检查漂移。
- 检查本 PR 修改的 Dart 文件格式；custom_lint、analyze、Flutter 测试仍覆盖整个工程。
- Quick checks 在 Ubuntu 执行格式、生成文件、custom_lint 和 analyze，与 Windows 构建并行。
  Windows 继续运行全部 Flutter 测试和原生、便携包验证；任一任务失败都会拦截 PR checks。
  发布工作流不传 static-checked，因此合并提交仍在 Windows 重新运行完整检查。
- 构建 Release 与随包解码器，明确指定测试用 ImageMagick，避免关键用例因缺依赖跳过。
- 完整测试前单独解码 Dolby Vision 样本；原生失败日志保留 Vulkan 与解码阶段错误。
- 执行原生队列测试，生成 unsigned Windows x64 portable ZIP，解压后检查版本、哈希、
  许可、便携标记和空用户目录，并在仅系统 PATH 下运行随包解码样本。
- PR checks 汇总，代码检查失败、取消或意外跳过均不能合并；仅允许计划明确批准的文档跳过。
- 构建各阶段耗时写入 Actions 摘要和 artifacts/ci/windows-timings.jsonl。

Windows runner 使用 windows-2025；Flutter 和 Actions 固定版本/提交，第三方构建输入按锁文件校验。
MSYS2 安装前更新软件包数据库与基础工具；GCC、Mesa 和托管 runner 工具随供应方更新，
实际包版本记录在诊断 artifact 的 msys-packages.txt；目前不承诺字节级可重复构建。
云端通过 MSYS2 Mesa Lavapipe 执行 Vulkan 解码测试，设置 SHENVIEW_ALLOW_SOFTWARE_VULKAN=1
显式允许软件设备；FFmpeg 对照测试也使用同一设备。Mesa 仅为 CI 依赖，不随便携包分发。
管理员进程会忽略 Vulkan 的驱动环境变量，因此 CI 在临时 runner 的注册表登记软件驱动，
构建前检查实例创建和设备枚举，结束后移除登记；不修改开发者本机注册表。
这覆盖解码计算与取消/重建逻辑，真实显卡性能、HDR 显示及驱动兼容仍需实机验收。
含非 ASCII 文本的 PowerShell 脚本使用 UTF-8 BOM，CI 另用 Windows PowerShell 5.1 解析检查。
下载缓存之外，复用 HDR/RAW/AVIF helper 及 FFmpeg 运行组件和 SDK。缓存键包括对应源码、
依赖锁、补丁、构建脚本、编译器、CMake/SDK 和 runner 镜像版本；每次使用前校验文件清单、
SHA256 与必要许可证，缺失或损坏则重建。不缓存 Flutter、CMake 和 FFmpeg 的中间对象目录。
Windows 的 AVIF 与 HDR helper 统一使用 build/hdr-codecs，构建、测试和打包不再分别编译 AVIF。
FFmpeg helper 源码变化仅重编 helper，底层库复用已校验的 SDK；依赖或工具链变化完整重建。
Warm native dependencies 在 main/release 原生构建输入变化后预热分支缓存，也可手动执行。
PR 缓存受 GitHub 分支作用域限制，不作为其他 PR 的公共依赖来源。损坏的远端缓存应在
Actions 中删除；本次运行仍从源码重建。缓存不是源码或发布渠道。
PR 代码在无发布密钥、contents: read 的托管 runner 执行，不使用 pull_request_target 构建 PR。
fork 首次工作流可能需要 GitHub 的运行批准。

每个 PR 的便携包 artifact 名含 PR 编号和 run ID，保留 14 天。它是测试包，不代表发布通过。
诊断 artifact 另含日志、源码 SHA、工具链版本及 FFmpeg/helper 运行组件，便于复现云端原生错误。

本地入口：

~~~powershell
powershell -ExecutionPolicy Bypass -File tool/ci/windows.ps1
powershell -ExecutionPolicy Bypass -File tool/release/package_windows_portable.ps1
~~~

独立便携入口复用完整打包脚本的载荷准备逻辑，但不生成 Inno、MSIX 或渠道清单，
不需要安装器编译器、MSIX 工具或证书。首次执行仍需要开发入门列出的构建工具。
输出位于 artifacts/releases/<Windows四段版本>/windows-x64/portable-ci/。
支持 -PayloadDirectory 复用已验证的干净载荷；此时不能声称重新构建了应用。

windows.ps1 默认执行完整流程，也可用 -Phase Prepare/Build/Test/Package 分段复验。
Test 默认包含完整静态检查和测试；-StaticChecked 仅用于已有独立静态检查门禁的 PR 工作流。

## Release 草稿

release 分支的发布 PR 合入 main 后，Draft Windows release 对 merge_commit_sha 重新执行
同一套检查和打包。它不复用 PR artifact，也不因关闭未合并的 PR 而发包。
创建草稿的 job 才有 contents: write，检查构建 job 保持只读权限。

草稿固定目标 SHA，附便携 ZIP、SHA256SUMS.txt 和 release.json，标记为 unsigned preview。
不自动公开、不自动将构建号提交回仓库，不借助工作流创建的 tag 触发第二个工作流。
同一 SHA 的草稿可重跑更新；已有公开 Release、不同 SHA 的草稿或冲突 tag 均拒绝覆盖。
若发布失败，重跑原始工作流；更改已合并代码仍必须通过新的版本 PR。

公开前需人工完成发布说明、最低 Windows/干净环境、HDR 实屏及第三方许可与对应源码交付。
当前 GitHub 自动源码 ZIP 和便携 ZIP 均不能替代完整第三方源码交付。
验收未完成时保留草稿；签名、Inno/MSIX/macOS 分发不在这条便携流水线范围。
首次将流水线合入版本分支不会创建 Release，只有其后向 main 合并发布 PR 才触发。

## 版本

唯一版本来源为 apps/viewer/pubspec.yaml 的 major.minor.patch+build；各字段为 0–65535，
Git tag 使用 vmajor.minor.patch，Windows 文件版本使用 major.minor.patch.build。
当前脚本不接受 rc 等预发布后缀；预览属性通过 Release prerelease 标记表达。

| 变更 | 处理 |
| --- | --- |
| 新功能/下一阶段交付 | 通常提升 minor，如 0.1.0 → 0.2.0 |
| 已发布版本 bugfix | 提升 patch，如 0.1.0 → 0.1.1 |
| 依赖、构建、打包修复，需要重新发给用户 | 提升 patch，不能覆盖原版本附件 |
| 仅 CI/文档维护、不重新发包 | 不强制提升产品版本 |
| 同一尚未发布目标的候选包 | 可提升 build，记录 SHA，artifact 名区分每轮构建 |

build 不参与 SemVer 优先级，不能只增加它来表达已发布版本的用户修复。
提交类型不直接决定版本提升；在 PR 中明确是否发包和影响范围。每个公开版本和 tag 只使用一次。

依据：[GitHub rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)、
[合并事件](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)、
[SemVer](https://semver.org/)。
