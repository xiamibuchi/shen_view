# Windows 真机回归

使用实际 Release 包检查启动、切图、F5 和图片像素；静态检查与 Widget 测试不能替代这一层。
测试复制或生成独立输入，不修改原始样本，输出写入 artifacts/windows-regression/。

仓库级 PowerShell 入口从仓库根调用；-InputPath 的相对路径以 apps/viewer/ 为基准。

## 一键回归

~~~powershell
powershell -ExecutionPolicy Bypass -File tool/check/windows_regression.ps1
~~~

默认生成素材，执行 custom_lint、analyze 和单元/Widget 测试，构建 Release、打包原生解码器，
再进行普通图片、JXL、APNG、AVIF、HEIC、HEIF、长图及 CBR 的黑盒烟测。report.json 汇总各步。

~~~powershell
# 复用已有 Release，仍运行静态检查、测试与烟测
powershell -ExecutionPolicy Bypass -File tool/check/windows_regression.ps1 -SkipBuild
# 额外运行 Windows 集成测试
powershell -ExecutionPolicy Bypass -File tool/check/windows_regression.ps1 -RunIntegration
~~~

SkipBuild 要求已有 Release 可执行文件，不能证明当前代码重新构建成功；
仅显式 SkipSmoke 才跳过显示断言。默认不运行集成测试，RunIntegration 的设备问题会记录在日志中。
集成入口需先准备 HDR helper 和 native/tests 的 RAW 追踪代理，步骤见
[验证入口](validation.md#专项入口)。各测试文件独立启动 Flutter，结果写入 integration/。

## 独立烟测

~~~powershell
Push-Location apps/viewer
flutter build windows --release --no-pub
Pop-Location
powershell -ExecutionPolicy Bypass -File tool/build/package_windows_codecs.ps1
powershell -ExecutionPolicy Bypass -File tool/check/windows_smoke_test.ps1 -InputPath testdata/formats/format_static.jxl -ExpectedImage visible
powershell -ExecutionPolicy Bypass -File tool/check/windows_smoke_test.ps1 -InputPath testdata/formats/format_long.png -ExpectedImage long -SkipNavigation -OutputDirectory ../../artifacts/windows-smoke-long
~~~

ExpectedImage 可选 none、red、visible、long；默认 none 只检查流程，
需要按样本选择像素断言，避免仅凭进程存活判为图片可见。
NavigateToLast 用于检查最后一张和胶片栏跟随；SkipNavigation 用于只验初始长图比例。

默认 CaptureMethod=window 使用目标窗口句柄捕获，不混入其他前台窗口。
部分 Flutter GPU 窗口的 PrintWindow 可能只返回背景，此时可显式使用
CaptureMethod=desktop，将测试窗口置前并裁取屏幕区域，再查看实际截图及像素结果。
desktop 模式会短暂改变前台窗口，不能将纯背景捕获直接判作解码失败。

## 专项工具

- tool/check/windows_config_smoke.ps1：配置缺失、损坏、不可读、超限、只读与实例存储不可用。
- tool/check/windows_instance_smoke.ps1：文件转发、最小化恢复、多进程、模式切回与崩溃恢复。
- integration_test/settings_ime_test.dart：画布与可编辑文本之间的原生 IME 关联。

其他解码、队列和视觉测试见 [验证入口](validation.md)。打印需要真实桌面会话验证应用内预览、
参数错误、打印机选择及平台打印服务，不依赖 Windows Photos。

## 已知平台边界

Windows runner 禁用 Impeller，并在销毁阶段保护 controller/engine 空指针。
flutter run 出现 Lost connection to device 时应先检查应用崩溃及原生日志。

Windows 默认用 ExcludeSemantics 隔离已观察到的动态菜单、Tooltip 和 OverlayPortal
组合触发的 AXTree 引擎问题。升级 Flutter 后需单独复验：

~~~powershell
flutter build windows --dart-define=SHENVIEW_ENABLE_WINDOWS_SEMANTICS=true
~~~

该隔离影响 Windows 辅助功能语义树覆盖，不能据鼠标键盘可用宣称完整可访问性验收。

发布候选在不同 Windows 版本、物理 DPI、显卡与 HDR 显示器上运行。
FP16、SDR 像素、模拟 DPI 和黑盒烟测各证明不同范围，HDR 亮度、跨屏、热插拔和恢复另验。
