# 原生构建耗时对照

2026-11-05 在 Windows 本机测量，AMD Ryzen 7 9700X，8 核 / 16 逻辑处理器。
使用同一套 Visual Studio、SDK 和 CMake，Release 配置及 `--parallel 4`。
本机结果不代表 GitHub 托管 runner 的总耗时。

| 场景 | 耗时 | 范围 |
| --- | ---: | --- |
| 修改前清理后的编译 | 74.2 秒 | 四个 helper 依次构建 |
| 修改后清理后的编译 | 45.3 秒 | 单一汇总目标，LibRaw / LittleCMS 启用 `/MP4` |
| 修改后完整冷构建脚本 | 121.3 秒 | 包含源码准备、首次配置、编译和产物校验 |
| 修改一个 helper 后的脚本 | 4.0 秒 | 仅重编 `gainmap_main.obj` 并重新链接 |

前两项都先执行 CMake `clean`，单独计时编译，不把下载及配置时间混入比较。
第三项包含完整流程，不能直接与前两项比较。第四项修改 `gainmap_main.cpp`，
对比构建前后所有 `.obj` / `.lib` 的修改时间，确认第三方库没有重编译；测量后恢复源码并重建。
本次对照没有改动解码算法、依赖版本、SIMD 或发布优化等级。

## 本地构建

`tool/build/build_hdr_codecs.ps1` 使用 `viewer_hdr_helpers` 汇总目标。`-Parallel` 默认 4，
首次配置时同时传给自有库的 MSVC `/MP`；libaom 保留上游已有的编译选项。
提高并行数前应测量 CPU、内存和嵌套并行，不能把更多进程等同于更短耗时。

第三方依赖身份包含 CMake 配置、依赖锁、构建脚本、编译器、SDK 和架构。
完整产物身份另包含 helper 源码。输出清单、哈希、依赖身份和本地构建状态都有效时，
helper 改动直接进入 CMake 构建，不主动重新配置。CMake 自行维护其配置依赖。
显式重复配置会重写 libaom 的部分生成文件，因此不能用它代替增量构建入口。

缺少本地构建状态或 CMake 配置、依赖身份变化、产物缺失或损坏时，脚本清理自己的
`build/hdr-codecs` 后重新构建。`build-state.json` 仅用于本地构建树，不随缓存或 artifact 传递。

## CI

`native-build.yml` 的 HDR / FFmpeg 两个矩阵 job 使用独立 runner。产物校验成功后保存缓存，
并上传当前运行的 helper / SDK artifact。Windows 应用 job 下载并再次校验这些文件后，
继续执行 Release 构建、完整 Flutter 测试、原生烟测和便携包验包。
预热工作流复用相同的两个 job，但不上传供应用构建使用的 artifact。
缓存键另含 runner 镜像版本，用于隔离缓存；产物身份保留实际编译器哈希、CMake、SDK、
架构及源码配置约束，不要求两个 job 的镜像编号相同。

拆分 job 减少串行等待，不减少编译总工作量；需计入额外 runner 初始化及 artifact 传输。
原生 job 的构建耗时保留在 Actions 摘要和各自诊断 artifact 的 `native-timings.jsonl`。
该轮对照未引入版本化 SDK 发布，也未调整 FFmpeg 编解码白名单或移除测试。

## 版本化 SDK

2026-11-05 在同一本机对完整脚本另做对照。源码与 SDK 两组分别并行运行 HDR/FFmpeg；
包含配置、准备和产物校验，不是纯编译时间。SDK 组移走原始构建树，从含空格和中文的
目录重新链接；确认 HDR CMake 没有第三方库目标，FFmpeg 不执行 configure/make。

| 组件 | 源码构建脚本 | 已解压 SDK 的 helper 构建脚本 |
| --- | ---: | ---: |
| HDR | 166.2 秒 | 12.0 秒 |
| FFmpeg | 233.2 秒 | 3.7 秒 |

本机单独解压及校验：HDR 0.18 秒、FFmpeg 0.50 秒。开发 SDK ZIP 约为 12.3 MiB 和
22.0 MiB；对应源码另行分发，不计入普通 PR 下载量。上述数据不包含从 GitHub 下载
SDK，也不包含 Flutter 构建、测试、runner 初始化及打包时间。云端收益需按已发布 SDK
的普通 PR 实测，不能由本机数据直接换算。维护与更新步骤见[原生 SDK](native-sdk.md)。
