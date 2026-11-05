# Windows 原生依赖 SDK

Windows x64 使用 `third_party/native-sdk.lock.json` 固定第三方开发 SDK。SDK 提供 Release
库、头文件、可迁移的 CMake 导入配置、FFmpeg 运行组件及许可。五个自有 helper 始终从
当前提交编译，SDK 不包含这些程序。应用版本与 SDK 版本独立。

## 使用

默认 `Auto` 模式下载锁定版本，先验证压缩包 SHA256，再解压并校验完整文件清单。下载
失败、哈希错误、架构不符或构建配方变化均中止；不会改用最新版本或自动回退源码构建。
下载保存在 `build/native-sdk/`，后续构建校验并复用。

MSVC 必须不低于 HDR SDK 记录的编译器版本，使用动态 CRT、x64、Release。FFmpeg worker
仍需要兼容的 x64 MinGW GCC；库通过 DLL 导入库链接，不把生产端编译器的文件哈希作为
消费端的版本约束。每个 helper 的本地构建身份仍追踪本机工具链。
生产端固定使用 VS2022，避免托管 runner 的最新编译器补丁提高消费端最低要求；
重新链接验收与应用构建使用当前默认工具链，验证较新工具链能消费该 SDK。

需要调试第三方库、使用较旧工具链或构建尚未发布的 SDK 时，可明确选择源码模式：

```powershell
$env:SHENVIEW_NATIVE_BUILD_MODE = "Source"
./tool/build/build_hdr_codecs.ps1
./tool/build/build_ffmpeg.ps1
Remove-Item Env:SHENVIEW_NATIVE_BUILD_MODE
```

独立脚本也支持 `-DependencyMode Source`。SDK 模式不改变 macOS 构建流程；macOS 仍从
源码构建对应平台的依赖。Windows SDK 不能用于 macOS 或 Windows ARM64 原生链接。

## 更新依赖

构建配方由 `third_party/native-sdk/recipe.json` 列出。身份包含选定的 HDR 依赖锁、
库构建配置、FFmpeg profile/补丁/包锁和 SDK 打包脚本；文本换行统一后计算，避免
Windows/Linux 检出方式不同导致失效。自有 helper 源码、普通文档和 runner 镜像编号
不属于第三方 SDK 配方。需要主动重建同版本依赖时，修改配方并递增 SDK 版本。

1. 修改依赖或配方，在 SDK 锁中递增 `version`，将两个组件的 `sha256` 设为 `null`。
2. 在仓库根更新配方摘要：

   ```powershell
   . ./tool/paths.ps1
   . ./tool/build/native_sdk.ps1
   $lock = Get-Content third_party/native-sdk.lock.json -Raw | ConvertFrom-Json
   $lock.recipeSha256 = Get-NativeSdkRecipeKey
   $lock | ConvertTo-Json -Depth 5 | Set-Content third_party/native-sdk.lock.json -Encoding utf8
   ```

3. 提交 PR。仅新版本且配方改变时允许构建候选 SDK；普通 PR 使用已发布版本。
   候选包在独立 runner 从源码构建，随后重新链接 helper；Windows 应用 job 下载候选
   压缩包，重新校验并编译当前代码，执行原有完整检查及便携包烟测。
4. PR 合入受保护的 `release/*` 或 `main` 后，`Publish dependency SDK` 从该提交构建
   并发布 `native-sdk-v<version>`。SDK 标为预发布，不替换应用 Latest，也不覆盖已有版本。
   写入 GitHub 的权限仅授予发布 job；PR job 没有发布权限。
5. 通过后续 PR 将发布附件的 SHA256 填入锁文件。该 PR 验证正式下载路径；通过后普通
   PR 不再启动第三方源码构建 job。发布与补齐锁之间的普通 PR 会因待发布锁而中止，
   不会反复从源码构建。

两个 SDK 压缩包只包含开发和运行所需文件；相应 HDR/FFmpeg 源码及构建配方作为独立
sources 附件发布。libplacebo 的 MSYS2 对应源码包包含原始源码、补丁及 PKGBUILD，
单独锁定其哈希并核对关联的二进制包。FFmpeg 包锁保留其他 MSYS2 依赖的版本、哈希和上游来源；新依赖需同时
核对许可及对应源码交付要求。SDK 源码附件不替代应用发布时的许可验收。

## 本地候选包验收

源码构建后生成候选包：

```powershell
 $generator = (Get-Content third_party/native-sdk/recipe.json -Raw | ConvertFrom-Json).hdrGenerator
./tool/build/build_hdr_codecs.ps1 -DependencyMode Source -Generator $generator
./tool/build/build_ffmpeg.ps1 -DependencyMode Source
./tool/build/package_native_sdk.ps1 -Component hdr
./tool/build/package_native_sdk.ps1 -Component ffmpeg
$version = (Get-Content third_party/native-sdk.lock.json -Raw | ConvertFrom-Json).version
./tool/ci/native-sdk.ps1 -CandidateDirectory "artifacts/native-sdk/$version"
```

候选包默认位于 `artifacts/native-sdk/<version>/`。`SHENVIEW_NATIVE_SDK_ROOT` 可指定
已经解压的候选目录，其下必须有 `hdr/`、`ffmpeg/`。该覆盖路径用于本地或同次 CI 的
候选包，仍校验配方和文件清单；正式依赖通过锁中的压缩包哈希校验。

变更配方时需验证：空目录链接、不同路径（含空格及中文）、损坏/缺失/多余文件、
错误架构和非法 ZIP 路径；继续运行完整 Flutter 检查、Windows 构建、CTest、HDR 视频
烟测及独立便携包验包。下载、解压、链接分开计时，不能用本地链接耗时代表整条 CI。
