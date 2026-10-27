# Windows 打包与分发

Windows x64 已接入 Inno Setup 7 EXE、MSIX、ZIP、WinGet 和 Scoop。最低系统版本声明为
Windows 10 2004（10.0.19041）；最低版本实机、干净环境和可信签名安装仍需发布验收。
macOS 的 DMG、Homebrew Cask 保留在后续范围，尚未实现；不生成 MSI。

EXE 与独立[验证包入口](../../packaging/windows/inno/README.md)共用 Inno 源码。
正式下载地址、项目许可和可信证书未提供时，只生成 unsigned 包及渠道模板，不对外发布。
Inno 验证包将主程序直接放在安装根目录，使用单一 uninstall.exe 卸载入口；支持旧预览 app/ 结构转换和显式完全卸载。
新安装不生成 install.ini，安装状态使用 Windows 卸载记录；恢复副本集中在受限的 ProgramData/ShenView/Installer/Transactions 临时目录。
Windows 运行包按加载边界组织组件：ImageMagick 及共享 HEIF 读取器位于 codecs/imagemagick/，压缩包引擎位于 codecs/archive/；核心启动 DLL 保留在应用根目录。

## 本地打包

环境需要 Flutter、Visual Studio C++ 工具链、Windows SDK、Inno Setup 7 和 7-Zip。
原生组件沿用现有构建脚本，完整发布文件包含 Flutter、VC Runtime、解码器、归档 helper
和对应许可。复杂 SVG 依赖 Microsoft Edge WebView2 Runtime，目前不随包安装。

~~~powershell
powershell -ExecutionPolicy Bypass -File tool/release/package_windows.ps1 -Unsigned -InnoCompiler ISCC.exe
~~~

从仓库根调用打包入口。版本统一读取 apps/viewer/pubspec.yaml 的 major.minor.patch+build，Windows 包和渠道使用四段版本。
结果写入 artifacts/releases/<四段版本>/windows-x64/unsigned/：

| 输出 | 用途 |
| --- | --- |
| *-setup.exe | 所有用户安装的 Inno 安装器，点击安装后请求管理员权限 |
| *.msix | 包身份与完整格式声明；未签名包不能直接安装 |
| *-portable.zip | 解压整个目录运行，包含独立 user-data |
| channel-templates/winget/ | 引用 EXE 的 inno 清单模板，目录参数使用 /ROOT |
| channel-templates/scoop/ | 引用 ZIP、持久化 user-data 的模板 |
| SHA256SUMS.txt、release.json | 最终文件哈希、版本与打包信息 |

已有最新 Flutter Release 和原生组件时可用 -SkipBuild -SkipCodecs；这两个参数不会检查
输入是否对应最新源码，正式发布应运行完整打包。-Flutter、-InnoCompiler、-WindowsSdkBin、
-RuntimeDirectory 可指定本机工具路径。生成配置和暂存文件位于 build/packaging/。

显式复用已验证的干净载荷可传 -PayloadDirectory；此时跳过应用与编解码器构建，并校验
主程序固定版本资源与发布版本一致。输入目录不能位于会被清空的 windows-x64 暂存目录，
不能包含用户设置、便携模式标记或卸载状态。EXE、MSIX、ZIP 均使用该载荷副本。

## 安装、升级和数据

Inno 提供中英文选项、进度与结果页面；默认安装到
64 位 Program Files/ShenView，主程序直接放在安装根目录。
开始菜单入口默认创建，桌面快捷方式可选，完成页可启动应用及前往 Windows 默认应用。
默认注册图片候选，压缩包和漫画候选为可选组件。

安装位置支持原位重装与迁移，卸载界面不提供目录选择。
盘符根目录、回收站、Windows、ProgramData、Common Files、WindowsApps、系统保留目录、
目录链接、网络路径及设备路径不能作为安装位置。手动输入、浏览选择和静默 /ROOT= 使用同一策略。
安装根路径最长 160 个字符，为随包组件的相对路径保留空间。
安装和卸载记录位于 HKLM，快捷方式对所有用户可见。旧的仅当前用户安装需先卸载，设置会保留。

修改程序前备份受管理文件、卸载记录、关联和快捷方式；失败时恢复，恢复未完成时保留副本并展示位置。
程序正在运行时要求先关闭；静默安装不强制关闭，返回失败。重装保留实际格式选择和快捷方式，
迁移成功后更新路径并移除旧版本受管理文件；安装器不接管无关非空目录。
卸载默认保留用户数据，可显式选择完全卸载。恢复范围与待验证项见 Inno 维护说明。

| 运行方式 | 设置与历史所在目录 | 归档缓存 |
| --- | --- | --- |
| EXE / WinGet | %LOCALAPPDATA%/ShenView | 同目录 cache/ 下 |
| MSIX | 包内应用可见的 LocalAppData/ShenView/MSIX | 同目录 cache/ 下 |
| ZIP / Scoop | 程序旁 user-data/ | user-data/cache/ 下 |
| 未带模式标记的开发运行 | 程序旁 | 程序旁 cache/ 下 |

MSIX 数据受 Windows 包文件系统重定向和卸载策略管理，不能把其可见路径当成普通安装版路径。
Scoop 使用 persist 保留 user-data，并通过 current 稳定路径注册候选，避免版本目录升级后失效。
旧开发目录的设置不自动迁移到安装版；需要保留时应在首次启动前复制 settings.json 到目标目录。

## 文件关联

格式列表从 FormatDetector 导出，排除视频扩展名，安装器、MSIX 与设置共用同一来源。
注册只添加“打开方式”候选，不改写 UserChoice。默认应用由用户在 Windows 设置中选择。

设置 → 通用 → 系统集成 → 文件关联，可逐项选择图片、压缩包和漫画格式，应用后生效，
也可打开 Windows 默认应用。MSIX 的候选由包清单管理，设置仅展示状态及系统设置入口。
文件关联属于系统状态，不参与应用偏好恢复默认。

普通安装版使用固定身份；每个便携目录使用独立身份，取消时校验当前路径和命令所有权。
所有用户安装的候选注册在 HKLM；设置内修改会启动提权助手并触发 UAC，影响所有用户。
默认应用仍由各用户选择。便携版仅注册当前用户，不请求管理员权限。
便携版删除或移动前应在设置中取消全部候选并应用，移动后重新注册。删除文件不会触发卸载清理。
Inno 复用应用自身的无界面注册命令，Scoop 卸载调用同一清理入口；更新 Scoop 时不移除候选。

## 正式签名与渠道清单

尚无正式下载地址、主页、软件许可及证书时，只生成本地 unsigned 产物与模板，不发布外部仓库。
正式发布需要真实元数据、CurrentUser/My 中带私钥的代码签名证书，以及与证书 Subject
一致的 MSIX Publisher。软件许可需由项目方确定；随包第三方许可不能代替项目自身许可。

~~~powershell
powershell -ExecutionPolicy Bypass -File tool/release/package_windows.ps1 -CertificateThumbprint <证书指纹> -Publisher "<证书 Subject>" -DownloadBaseUrl "https://<发布目录>" -Homepage "https://<项目主页>" -License "<软件许可>"
~~~

签名流程先签应用 EXE/DLL，再依次签 Inno 卸载执行程序、卸载界面、安装执行程序和最外层包，
确保每个执行程序在被嵌入前完成签名；MSIX 最后签名，再计算最终哈希。
signed/ 与 unsigned/ 分开输出。元数据齐备且已签名才输出 channels/ 下的可提交清单，
否则保留 .in 模板；本脚本不上传文件、不创建仓库、不提交包管理器审核。
证书、私钥和密码不纳入源码。MSIX Publisher 和包身份正式启用后需要保持稳定。

## 验证

~~~powershell
powershell -ExecutionPolicy Bypass -File tool/check/check.ps1
powershell -ExecutionPolicy Bypass -File tool/check/windows_packaging_smoke.ps1 -ReleaseDirectory "<生成的 unsigned 或 signed 目录>"
powershell -ExecutionPolicy Bypass -File tool/check/windows_msix_smoke.ps1 -ReleaseDirectory "<生成的 unsigned 或 signed 目录>"
~~~

打包测试检查最终哈希、中文及空格路径、便携关联隔离、Scoop 实际安装/更新/卸载钩子、
MSIX 格式与组件声明，以及 Inno 静默安装、重装、卸载和 UserChoice 不变。安装部分需管理员权限，
已有安装记录时停止以保护现有安装；可显式传 -SkipMachineInstall 验其余部分。
加 -VerifyLaunch 会从最终 ZIP 启动便携和 Scoop 副本，检查实际图片像素并保存截图，需要交互桌面。
安装了 WinGet 时自动执行官方清单验证；模板中的发布占位符只在临时验证副本中替换为 example.invalid，
不下载或安装远程包。没有 WinGet 时明确记录跳过。Inno 的故障恢复和界面验证见独立验证入口。

MSIX 专项验证需要系统已开启开发者模式，不修改系统策略或证书信任。脚本解包最终 MSIX，
使用随机临时身份验证开发注册、版本更新、包身份激活、图片渲染及卸载；已有外置 MSIX 数据时
停止以保护用户数据。开发注册可能绕过 LocalAppData 重定向，测试新生成的数据移入验证目录
留存，不作为真实用户配置保留。开发注册验证不能替代可信签名安装。

发布前仍需干净 Windows 的最低版本、只读目录、磁盘不足、取消与失败恢复、多文件交付、
WebView2 缺失、离线格式覆盖及签名信誉验收。可信签名 MSIX 的安装/升级/卸载、真实
WinGet/Scoop 下载与升级流程须在正式元数据和证书就绪后执行，结构验证不能替代实机安装。
macOS 另验签名、公证、Gatekeeper、DMG、Applications 安装、文件授权及 helper 架构。

源定义见 packaging/windows/、packaging/channels/；入口为 tool/release/package_windows.ps1。
维护说明见 [开源许可](open-source-licenses.md)、[归档许可](archive-licensing.md)、
[实例模式](../guide/multi-instance.md) 和 [验证说明](../development/validation.md)。
