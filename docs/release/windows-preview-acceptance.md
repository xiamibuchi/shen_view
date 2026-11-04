# Windows 预览版验收

本页对应 v0.1.0 的发布前置任务。完成以实际环境、输入包和验收证据为准；
测试通过不自动代表整个 Issue 完成。版本发布入口见[打包与分发](distribution.md)。

| 任务 | 自动验证覆盖 | 仍需单独确认 |
| --- | --- | --- |
| [#1 最低系统与干净环境](https://github.com/xiamibuchi/shen_view/issues/1) | Windows Release 构建、图片像素烟测、随包解码器与依赖检查 | Windows 10 2004（19041）x64、无开发工具链、离线运行及 WebView2 缺失 |
| [#2 安装、升级与卸载](https://github.com/xiamibuchi/shen_view/issues/2) | 独立验证身份的安装、重装、迁移、运行中阻止、数据保留/清理和故障恢复 | 正式身份的机器级关联、UAC、旧 NSIS 安装、真实跨版本升级及崩溃恢复边界 |
| [#3 HDR 与 SDR 回退](https://github.com/xiamibuchi/shen_view/issues/3) | HDR 解码及策略测试、FP16 回读、透明合成、当前屏幕能力门控与 SDR 回退 | HDR 开/关下的实屏高光、切图、跨 HDR/SDR 屏幕、热插拔及恢复 |
| [#4 许可与分发](https://github.com/xiamibuchi/shen_view/issues/4) | 随包许可、依赖版本、构建配方和来源清单核对 | 项目已采用 Apache-2.0；仍需落实第三方对应源码、签名方案和实际下载渠道 |

## 证据与输入

每次验收使用独立的 artifacts/ 子目录，记录源码 commit、系统和驱动版本、
应用/安装包版本与 SHA256、样本、命令、退出码、截图及未覆盖范围。
复用旧载荷时同时记录载荷来源与主程序哈希，不将它写成当前源码的新构建。
测试日志和截图不提交到源码；汇总报告必须区分通过、失败和待验。

完整静态检查、单元/Widget 测试、Release 构建与图片烟测使用
[Windows 真机回归入口](../development/windows-regression.md)。
HDR 原生与样本验证使用[验证入口](../development/validation.md#hdr-专项)。
原生队列测试只证明调度与取消行为，不证明显示或安装兼容性。

## 安装验证

先用[Inno 独立验证包](../../packaging/windows/inno/README.md)运行 smoke、transactions、
交互及失败界面验证。各入口顺序执行，避免共用验证注册表身份和快捷方式。
验证包不注册真实图片关联，不能据此勾选正式机器级关联的验收。

正式安装、升级和完全卸载在一次性干净环境运行；已有日常安装的机器不用于
自动覆盖安装或完全卸载验收。完整分发的 windows_packaging_smoke.ps1 在已有安装记录
时应保留保护行为，必要时仅用 -SkipMachineInstall 检查其余部分并记录跳过。

## 最低系统与 HDR

Windows 11 上通过测试不等于 Windows 10 19041 可运行，安装器和 MSIX 的最低版本声明
也不是兼容性证据。不能通过修改声明或隐藏跳过来替代最低版本实机验证。
仅将 PATH 缩减为 System32 不能排除系统已安装的运行时和开发工具影响。

SDR 设备上的 FP16 和 DirectComposition 探针只能证明相应像素/表面链路。
当前输出为 SDR 时，应验证 HDR 上传被拒绝且 SDR 图片仍可见；没有 HDR 设备时，
实屏项目保持待验。HDR 实屏步骤见[样本说明](../../apps/viewer/testdata/formats/HDR.md)。

## 发布决策

项目自身使用根目录的 [Apache-2.0 LICENSE](../../LICENSE)，第三方组件仍按各自许可分发。核对对象包括 Flutter 的
NOTICES.Z、原生 codecs/licenses、FFmpeg 依赖与构建配方，以及实际打包版本的源码来源。
对应源码的交付还应覆盖自有 helper、上游修改及重建所需资料；仅列仓库相对路径
或通用项目主页不作为完成证据。详见[许可维护](open-source-licenses.md)和
[压缩包分发许可](archive-licensing.md)。

当前 CI 仅构建未签名 Windows 便携 ZIP；版本 PR 合入 main 后创建 Release 草稿，
公开发布前仍需完成验收，流程见[分支与 CI](../development/branches-and-ci.md)。
发布说明需明确 ZIP 及其中 EXE 的未签名状态、未知发布者提示、
WebView2 依赖和已知限制；不将未签名 MSIX 作为可直接安装的普通下载。
不能要求用户关闭系统安全防护。可信签名与正式渠道提交按[分发文档](distribution.md)验收。

前置项有失败或未验时保留为版本待办。CI 只能自动执行已明确的检查，不能把硬件、
最低系统或维护者决策的待验项变成通过。

## 缺少最低系统或 HDR 设备时

最低系统兼容性可用目标版本的 Windows 虚拟机验证启动、解码及运行时依赖，不必寻找旧实体机。
虚拟机的图形驱动与物理显卡不同，结果应标明虚拟化环境；Windows 11 上的测试不覆盖 Windows 10。
[Windows Sandbox](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-overview)
可提供不含宿主已安装软件的临时环境，适合检查便携包依赖，但不能作为指定旧版 Windows 的测试结果。

没有 HDR 屏幕时，继续验证 HDR 样本的解码值、色彩映射、FP16 回读、透明合成、屏幕能力门控和 SDR 回退。
这些结果不覆盖显示器亮度、色准、HDR/SDR 跨屏、热插拔和休眠恢复；后者需设备实测或外部测试者的可追溯报告。
外部报告应包含包版本和哈希、系统与显卡驱动、显示器型号、HDR 开关状态、样本和操作步骤。

预览版说明分别列出已验证环境和待验证功能。缺少设备的项目保持待验，不把最低版本声明或 HDR 解码成功写成实屏验收通过。
需要调整发布门槛时，先更新对应 Milestone 的验收范围及对外说明；脚本不自动放行未验项。
