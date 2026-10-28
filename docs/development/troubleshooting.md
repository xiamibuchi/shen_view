# 配置存储与排查

## 配置位置

| 运行方式 | 配置文件 |
| --- | --- |
| Windows 普通安装版 | `%LOCALAPPDATA%/ShenView/settings.json` |
| Windows 便携版 / Scoop | 程序旁 `user-data/settings.json` |
| Windows 未带模式标记的开发运行 | 程序旁 `settings.json` |
| Windows MSIX | 包内应用可见的 `LocalAppData/ShenView/MSIX/settings.json` |
| macOS | 用户 `Library/Application Support/ShenView/settings.json`；沙箱下位于容器中 |

MSIX 路径受 Windows 包重定向管理。打包方式和数据保留规则见 [Windows 分发](../release/distribution.md)。
Debug 和 Release 可能使用不同配置，排查时先确认正在运行的可执行文件。

## 设置未保存或恢复默认

启动和浏览使用容错读取，损坏、超限或不可读的配置回退到默认值，读取本身不改写文件。
保存使用严格读取，持续读取失败或无写权限时保留已有文件并报告失败。

遇到设置未保存，先检查目标目录权限、可用空间及是否被其他程序独占，保留原文件用于排查。
配置缺失、损坏、只读或被占用等场景可运行 `tool/check/windows_config_smoke.ps1`，
它使用独立程序副本，不操作用户配置。多窗口写入机制见[共享数据](../guide/multi-instance.md#共享数据)。

字段与默认值直接查 [ViewerSettings](../../apps/viewer/lib/src/domain/viewer_settings.dart)，
文件读写及容错查 [AppConfigStore](../../apps/viewer/lib/src/application/app_config_store.dart)。
不另外维护配置格式表或手工编辑指南。

## 移动仓库后构建异常

重新打开目录，在 `apps/viewer/` 执行 `flutter pub get`。旧绝对路径缓存通过
`flutter clean` 后重建，不手改生成文件。个人 SDK 路径、主题与生成器放在编辑器用户设置中。
