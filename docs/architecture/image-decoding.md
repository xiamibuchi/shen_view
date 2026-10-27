# 图片解码

图片通过 ImageResourceService 统一取得资源、预约预算并提交 DecodeScheduler，
按文件版本、目标尺寸和区域生成缓存键。解码成功包含创建首帧；创建 codec 成功但首帧失败仍会进入回退。

## 当前路由

| 格式或场景 | 解码路径 |
| --- | --- |
| JPEG、PNG、BMP 等常见静态图 | 优先 Flutter codec，失败后尝试适用的平台和 ImageMagick 后端 |
| ICO | Dart image 解码 PNG/BMP 内嵌版本，默认选择最大尺寸，同尺寸优先较高位深；信息面板列出并可切换版本 |
| GIF、WebP 动图 | Flutter 动画 codec；主图失败不会降为静态首帧 |
| APNG | 应用内 APNG codec，按需合成帧，处理透明叠加和帧处置 |
| TIFF、PSD、HEIC、HEIF、静态 AVIF、DDS | Windows WIC / macOS Image I/O 优先，失败回退 ImageMagick |
| AVIF 动画 | libavif helper 按需读取帧，Little CMS 转换为 sRGB |
| RAW | 主图优先 LibRaw 传感器显影，缩略图优先内嵌预览；失败保留兼容回退 |
| EXR、HDR | Windows 的 SDR 路径使用 ImageMagick；macOS 尝试原生浮点输出，失败后兼容回退 |
| JPEG XL | 固定使用随包 ImageMagick，不依赖用户安装的 WIC JXL codec |
| SVG | 普通内容使用 resvg；复杂主图按原始 XML/CSS 特性分流到系统 WebView |
| 归档图片 | ArchiveService 建立条目会话，按需取得文件租约后进入对应图片路径 |

区域解码、大型编码输入和预算会影响后端选择，普通格式也可能直接使用有界原生预览。
AVIF 是否显示播放控制取决于实际动画轨道及帧数；静态、单帧和渐进式 AVIF 不显示。
动画会话支持关键帧跳转，并持有压缩包文件租约直至进程退出。完整源尺寸的 AV1
参考帧与像素缓冲计入资源预算，超预算时不启动动画解码。PQ/HLG 动画使用固定
参考白和一致的映射回退到 SDR 播放，暂未接入原生 HDR 动画表面。
缩略图可使用静态首帧；动图主图保留动画语义。取消或预算不足不触发兼容后端重试。

RAW、SVG、HDR 各有独立处理，细节见 [RAW 解码](raw-decoding.md)、
[SVG 渲染](svg-rendering.md) 和 [HDR 显示](hdr-rendering.md)。

## 色彩与输出

Windows WIC 的 SDR 路径将嵌入 ICC 转为 sRGB。ImageMagick 兼容输出统一为 sRGB PNG32，
使用随包 sRGB.icc 转换并移除不再适用的源配置；ICC 转换使用相对色度意图和黑点补偿。
HDR/EXR 的 SDR 回退先在线性光中做 Reinhard 高光压缩，再转为 sRGB；RAW 保留自己的显影曝光策略。

JPEG／TIFF 没有 ICC，但 EXIF 明确标记 Adobe RGB 时，主图、缩略图和区域解码统一进入兼容路径，按 Adobe RGB 的传递函数及色域转换到 sRGB。嵌入 ICC 优先，XMP 旁车不参与像素色彩推断。没有明确标记的普通 RGB 保持原有 SDR 默认解释。

APNG 在合成后保留源 PNG 的 ICC、cICP、sRGB、gAMA 和 cHRM 描述，由 Flutter 创建带色彩信息的帧；没有色彩描述时保持默认 SDR 解释。原始 RGBA 传入 Flutter 前转换为预乘 alpha，合成画布仍保留直通 alpha。

HEIF Gain Map 使用基础图 ICC 时，先按 ICC 转为基础色域内的线性 RGB，再逐通道应用增益。常用 sRGB、Display P3、Rec.2020 矩阵／TRC 配置由 Little CMS 处理；不能识别的色域或 LUT 配置保留 SDR 回退，避免把其数值误当作 sRGB。没有 ICC 时沿用容器的 NCLX 描述。

原生 HDR 主图另走 Windows scRGB FP16 / macOS Metal EDR，缩略图和不支持 HDR 的场景继续使用 SDR 图像。

基础能力来源见 [解码注册表](../../apps/viewer/lib/src/application/decoder_registry.dart)，
实际请求、首帧和回退由 [资源服务](../../apps/viewer/lib/src/application/image_resource_service.dart) 处理。
共享请求、取消与缓存的机制集中见 [资源管理](resources.md)。

## 照片元数据

PhotoMetadataReader 对 JPEG、PNG、WebP 和经典 TIFF 按结构寻址，跳过像素数据读取 EXIF、ICC 和常用 XMP。单次结构读取预算为 4 MiB，XMP 包与旁车文件各限 2 MiB；损坏、越界或超预算的可选块不影响图片显示。PNG、WebP 的元数据位于像素数据之后时也能读取。HEIF／AVIF 的主图元数据由 libheif helper 提取，RAW 另由 LibRaw 补充容器解析不到的拍摄字段。

XMP 按命名空间识别属性和 RDF 数组，读取 UTF-8 文本，支持文件内元数据及同名 `.xmp`、`.扩展名.xmp` 旁车文件。旁车中的标题、描述、作者、版权、评分、关键词优先；相机拍摄参数以 EXIF 为准，XMP 补缺。不执行 XMP 显影参数、裁切、旋转编辑指令，也不修改源文件。旁车修改后重新打开或手动刷新图片读取。

信息面板保留拍摄时钟原有的时区、亚秒精度，按有理数格式化曝光与焦距，并读取 GPS 方向标记；缺失或非法值不补造。无 ICC 且无明确色彩标记时，元数据不宣称源文件嵌有 sRGB 配置。常用字段与真实设备样本回归见 [照片元数据样本](../../apps/viewer/testdata/photo_metadata/README.md)。

## 能力边界

不提供开放式解码插件系统、插件市场或用户安装后端的入口。默认格式覆盖依赖随包组件，
设置页的来源标签不代表逐文件、逐后端的动态探测结果。

没有通用 GPU 图片硬解、任意超大图无限清晰度或可供用户选择的格式后端优先级设置。
性能结论需在实际查看器链路测量；后端探针耗时不能当作首帧或翻页耗时。

测试样本见 [格式清单](../../apps/viewer/testdata/formats/README.md)，执行入口见 [验证说明](../development/validation.md)。
