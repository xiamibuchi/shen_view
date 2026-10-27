# 开源许可维护

关于页按组件展示许可，同一组件的不同声明全部保留，仅去掉重复文本。
视觉与交互规则见 [设计规范](../design/spec.md)。

## 收集来源

- Flutter、Dart 包和 Flutter 引擎内嵌组件：读取 Flutter 打包的 NOTICES，经 LicenseRegistry 提供。
- 原生组件：读取可执行文件旁的 codecs/licenses；Windows 和 macOS 的已有打包位置一致。
- 7zip、resvg 按目录聚合；hdr 下按组件文件名前缀分组。
- ImageMagick 的 NOTICE 按原有组件标题分节，保留节内全文及可能存在的前言，使 libheif、
  libde265 等委托解码库可搜索。无法识别分节时保留整份文件。
- 不扫描系统安装的软件，也不联网下载许可。未随当前应用打包的可选外部程序不纳入此列表。
- 源文件仍随安装包完整提供；界面展示不替代对应组件的其他分发义务。

## 开发依赖

Flutter SDK 的默认 NOTICES 收集会遍历 package_config，包含开发包。应用列表使用生成的
license_exclusions.g.dart 排除仅开发依赖及其专属内嵌许可名，不修改 Flutter 生成的原始
NOTICES。生成器从 package_graph 的根包沿普通 dependencies 求运行时闭包，开发专属集合
再扣除运行时许可名；即使包列在 dev_dependencies，只要运行时也引用它（例如 archive），
仍保留其许可。Flutter 引擎内嵌第三方组件不是 Dart 开发依赖，不因名称陌生而删除。

更新依赖并执行 flutter pub get 后，运行：

```powershell
dart run tool/generate_license_exclusions.dart
```

生成后运行 test/third_party_licenses_test.dart，检查排除表与当前依赖图一致。
许可视图的回归入口为 test/licenses_page_test.dart 和 test/licenses_visual_test.dart。

## 打包

Windows 完整分发继续运行 tool/build/package_windows_codecs.ps1；它将原生许可目录和程序一起
放到 Release/codecs。HDR CMake 同时收集 libaom 的 LICENSE 和 PATENTS。
macOS 的 archive/SVG 构建脚本将已打包组件的许可放在 Contents/MacOS/codecs/licenses。
新增原生组件时，必须在对应构建流程收集实际分发版本的许可；列表会随目录内容更新。
