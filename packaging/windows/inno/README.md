# Inno Setup 7 验证包

安装器源码放在 packaging/windows/inno/；发布入口放在 tool/release/，验证放在 tool/check/。
路径统一读取 tool/paths.ps1，不另建 Flutter 应用。编译器和暂存在 build/packaging/，
交付包和报告在 artifacts/installers/inno7/，均不提交二进制。

## 构建与验证

从仓库根运行，使用官方 Inno Setup 7.1.0 的 ISCC.exe：

~~~powershell
./tool/release/package_windows_inno.ps1 -Compiler ISCC.exe
./tool/release/package_windows_inno.ps1 -Validation
./tool/check/windows_inno_smoke.ps1 -BuildDirectory artifacts/installers/inno7/0.1.0.1/validation
./tool/check/windows_inno_transactions.ps1 -BuildDirectory artifacts/installers/inno7/0.1.0.1/validation
./tool/check/windows_inno_ui.ps1 -Installer artifacts/installers/inno7/0.1.0.1/validation/ShenView-0.1.0.1-windows-x64-inno7-validation.exe -Execute
./tool/check/windows_inno_failure_ui.ps1 -Installer artifacts/installers/inno7/0.1.0.1/validation/ShenView-0.1.0.1-windows-x64-inno7-validation.exe
~~~

默认编译器缓存为 build/packaging/tools/inno-7.1.0/ISCC.exe，版本通过 --version 确认。
入口组装 apps/viewer/build/windows/x64/runner/Release 与 x64 VC Runtime，检查必要文件
及随包 EXE/DLL 的 PE 架构；不会重新构建 Flutter 应用，发布前应另行构建最新应用。
已有组装目录可传 -PayloadDirectory 显式复用；传入不存在的目录时，先构建 HDR/RAW 原生组件并重新组装 codecs，再从 Release 生成新载荷。
已有预览 EXE 正在运行时，可传 -OutputDirectory 输出到另一个产物目录，不覆盖占用中的文件。
-Version 可覆盖四段包版本用于升级验证，不改变应用本身的版本资源。
完整 Windows 分发使用 tool/release/package_windows.ps1，将相同载荷用于 EXE、ZIP、MSIX 和渠道清单。
该入口通过 -ReleaseBuild 生成标准 setup.exe 名称；指定签名证书时，在嵌入前逐层签名执行程序。

preview 包使用普通权限前端、管理员引擎，默认所有用户安装到 Program Files/ShenView。
validation 包使用独立安装身份、快捷方式名称和用户数据，不操作真实格式关联。
自动安装测试只接受 validation 包，在唯一的 build/packaging/ 子目录中执行。
组件布局变动时，界面验证另加 -VerifyCodecs：安装后以仅含 System32 的 PATH 验证随包解码、Nikon/Sony RAW 拍摄时间和压缩包读取，启动应用打开 PSD，并保留截图与已加载模块清单。

## 实现

- frontend.iss 编译安装界面与卸载器；卸载器从临时副本启动，避免卸载时占用自身。
- engine.iss 部署应用并注册系统卸载入口；前端异步等待最终状态，不以启动进程退出判断成功。
- uninstall-worker.iss 是内嵌的轻量 Inno 执行程序，由卸载界面解包并提权调用；它能在删除前备份未被占用的卸载记录。
- transaction.iss 保存受管理文件、安装记录、关联和快捷方式；异常时恢复原状态，恢复失败时保留恢复副本并报告其位置。
- recovery-storage.iss 在 ProgramData/ShenView/Installer/Transactions 下创建独立 GUID 目录，只允许系统和管理员访问，拒绝目录链接；成功提交或恢复后删除，恢复未完成时保留。
- purge.iss 在完全卸载前备份安装目录及当前用户数据，删除受阻时恢复文件和空目录；拒绝跟随目录链接删除外部内容。
- common.iss 集中目录、版本和归属校验；preferences.iss 合并原用户 JSON 的语言字段，使用共享锁与原子替换。
- appearance.iss 用系统绘图 API 统一原生按钮、文字操作、格式页签和完成图标，保留按钮键盘、焦点、默认操作及模态行为，不使用第三方皮肤或付费 UI DLL。
- format-dialog.iss 管理打开方式弹窗及临时选择，关闭时释放控件和绘图回调。

界面布局、控件状态和交互要求见[安装器设计](../../../docs/design/windows-installer/README.md)。
格式清单从应用 tool/export_windows_formats.dart 导出；打包检查主程序 FileDescription、ProductName 均为 ShenView。

操作成功后仅刷新当前用户、本安装路径的旧显示名称缓存，并通知 Windows 更新关联；迁移同时移除旧路径的名称缓存。
执行期间提供“完成后关闭”，Alt+F4 和窗口关闭请求采用相同行为：最小化后继续操作，成功后正常退出，失败或存在完成警告时重新显示结果，不强制终止执行程序。
失败使用独立结果页，区分未修改文件、已恢复和恢复未完成，显示原因并提供日志与关闭入口；返回重试只回到原选项，不直接再次执行。恢复未完成时隐藏重试并提供恢复副本入口，副本路径同时写入状态记录。
恢复期间显示明确的恢复状态并隐藏安装百分比；等待超过五分钟仍继续等待执行结果，不因超时提前开放重试。进程崩溃后的恢复边界见发布边界。
安装、重装和卸载前按当前安装及目标目录枚举全部应用/解码进程，包括无窗口的后台进程。
存在进程时确认正常关闭窗口并等待进程真正退出；后台进程未退出则提示手动关闭后重试。
不会关闭其他目录中的开发版，也不强制结束未响应的应用。静默调用遇到进程直接失败，执行程序会再次检查。
重装可更换目录，必须先确认新旧位置；禁止新旧目录互相包含，也不覆盖另一份已有安装。
部署新目录后复制未被载荷管理的设置和数据；复制失败或重解析点跳过，原文件保留，并在完成结果及日志说明。
安装成功后更新已有桌面和开始菜单快捷方式、系统卸载入口及关联，再仅按旧清单清理旧安装；旧目录的个人文件保留。
外置 LocalAppData 用户数据不随安装根移动。静默迁移通过前端显式 ROOT，或执行程序 MIGRATE=1 触发。
卸载留下用户数据时写入归属标记，之后可在原位置重新安装；不会把未标记的普通非空文件夹当成用户数据目录。
卸载页仅以文字显示当前安装位置，长路径自动换行，不提供目录输入框或浏览操作。卸载默认保留数据，可勾选“同时删除设置、阅读记录和缓存”；交互执行前再次显示安装目录及完整清理范围并确认。
完全卸载删除安装目录中的所有文件与空目录，以及当前用户 LocalAppData/ShenView 内的设置、历史、缓存和 WebView2 数据；
保留其中独立 MSIX 渠道的数据，不搜索其他用户配置、外部自选缓存目录或共享临时目录。图片库本身不在清理范围内，安装目录内的个人文件除外。
同时移除本安装的系统卸载记录、关联注册项，以及桌面和开始菜单中目标仍指向本安装的快捷方式，包括改名后的入口。
完全卸载先备份全部清理范围；无法读取、存在重解析点或删除受阻时报告失败，必要时恢复。静默卸载可显式传 /PURGE=1。
提权后需保持原用户身份，切换到另一管理员账号时拒绝完全卸载，避免误清理该管理员的数据。
完全卸载的本次执行日志放在当前用户临时目录，便于删除应用数据后继续传递状态和定位异常。
已有程序文件但安装记录缺失时，读取 ShenView 的产品、公司及原始文件名资源后提供“修复安装”确认。
修复先在原位置完成，再支持换目录；静默修复必须显式 REPAIR=1。验证身份只修复带自身数据归属标记的目录。
具体准备失败原因会保留；状态使用 UTF-16 INI 原子替换，防止跨进程读取半条状态或截断中文。读取端短暂占用状态文件时，写入端限时重试，避免已完成部署但前端一直等待。
前端将每次执行日志保留在原用户 LocalAppData/ShenView/installer-logs，失败时提供查看入口；验证版使用独立目录。
失败界面验证覆盖首装准备失败、部署失败、恢复失败、卸载失败与延后关闭，检查返回选项后的选择保留、结果按钮间距及真实退出码；支持英文和工作区高度模拟，恢复失败的副本保留为验证证据。
验证版提供部署、数据、关联、快捷方式、清理和卸载阶段的故障注入，正式包不启用这些入口。完全卸载的外置测试用户数据固定在验证安装目录旁的 .user-data 目录中。

安装测试结果写入包目录的 smoke-results.json，事务验证写入 transaction-results.json；界面测试生成截图、文字留白测量及 ui-results.json。

## 发布边界

正式 EXE 与独立验证包共用本目录源码，由 tool/release/package_windows.ps1 统一生成渠道产物。
验证包使用独立身份；正式下载地址、元数据和可信证书未齐备时，仅生成本地未签名产物。
UAC 提权程序名为 ShenView-Setup.exe，卸载提权程序名为 ShenView-Uninstall.exe，版本资源标注 ShenView。AppPublisher 和
VersionInfoCompany 只是产品信息，不提供签名信任；UAC 的“未知发布者”需要受信任的
Authenticode 代码签名。正式分发应签名内层引擎、维护程序、卸载执行程序及最外层安装包。
NSIS 旧记录不自动接管。上线前仍需完成旧 NSIS 记录迁移、跨权限通信的身份认证、进程崩溃/断电后的自动恢复、
真实机器级关联、另一管理员账号下的 UAC、最低系统、跨屏 DPI 与读屏验收。
格式初始选择读取本安装的 Capabilities、ProgID 命令和 OpenWithProgids，校验目标程序路径，不修改 Windows UserChoice。
快捷方式读取实际目标；程序损坏、无法检查现状时才回退到记住的安装任务。验证版在独立 HKCU 子树模拟相同关联结构，不向 Windows 注册格式。
恢复副本不放在安装目录旁；验证版使用 LocalAppData/ShenView-Inno7-Validation 下的独立事务目录。阶段异常恢复通过不等于断电恢复通过。
当前 Inno 没有原生 ARM64 引擎；Windows 11 ARM64 依赖 x64 模拟，尚未做 ARM 实机验收。

## 安装目录

ShenView.exe、DLL、codecs/、data/ 直接部署在所选安装根目录，不增加 app/ 层。
安装状态使用 Windows 卸载注册表记录：版本复用 DisplayVersion，界面语言和安装任务使用 Inno 的记录名，不另写 install.ini 或 layout 标记。
格式关联和快捷方式优先读取现状；旧 install.ini 仅作迁移兼容，成功重装后删除。目录归属由卸载记录中的 InstallLocation 确认；记录损坏时走产品资源校验与显式修复。
payload-files.txt 区分载荷和用户自行存入的文件；
uninstall.exe 是唯一卸载入口，可直接运行，也由 Windows“已安装的应用”调用。安装目录不再包含 maintain.exe。
卸载器内嵌可提权执行程序，关闭 Inno 重复的原生卸载器生成，不再生成 unins000.exe/.dat。
更新旧预览版时兼容 app/ 结构，将应用文件移至根目录，更新快捷方式与关联路径，清理旧受管理文件、
maintain.exe、原生卸载器和冗余 shenview-install-root 标记。用户自行存入旧 app/ 的文件复制到新位置，无法复制的保留原处；失败时通过快照恢复。
原生 Inno 的 DAT 是外部卸载记录，不能通过拼接进 EXE 保留其原有工作方式；此处采用移除重复链路的方式精简。

data/ 与 flutter_windows.dll 是 Flutter 发布产物；各插件 DLL、WebView2Loader、pdfium、VC Runtime
为原生功能提供运行依赖；codecs/ 包含图片、RAW、动图、SVG、压缩包解码器及其模块、配置和许可证。
ImageMagick 的 DLL、模块、配置及共享 libheif 的读取器位于 codecs/imagemagick/；压缩包读取器与 7z.dll 位于 codecs/archive/。
子进程按各自的加载目录携带 VC Runtime，主程序的启动依赖仍在根目录。旧版平铺路径保留查找兼容，升级时仅按旧载荷清单移除已迁走的文件；失败则恢复。
安装清单排除调试符号与解码器原发行包的 unins* 文件。目前沿用完整编解码与 VC Runtime 运行集，
尚未完成逐模块依赖裁剪，不能声称每个 DLL 都不可移除。不同子进程的 DLL 搜索位置也不宜凭文件名去重。
