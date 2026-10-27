// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get externalOpen => '用其他程序打开';

  @override
  String get externalOpenChoose => '选择其他程序…';

  @override
  String get externalOpenLoading => '正在读取可用程序…';

  @override
  String get externalOpenNoApplications => '没有关联的程序';

  @override
  String get externalOpenListFailed => '无法读取可用程序';

  @override
  String get externalOpenSaveCopy => '保存副本后用其他程序打开';

  @override
  String externalOpenFailed(String message) {
    return '用其他程序打开失败：$message';
  }

  @override
  String get photoMute => '静音';

  @override
  String get photoAudioRetry => '声音播放失败，点击重试';

  @override
  String get photoUnmute => '开启声音';

  @override
  String photoAudioTrack(int number) {
    return '音轨 $number';
  }

  @override
  String get icoVariant => '图标版本';

  @override
  String get svgStaticPreview => 'SVG 已切换为静态预览。动画不会播放，字体和部分效果可能有差异。';

  @override
  String get histogram => '直方图';

  @override
  String get histogramLuminance => '亮度';

  @override
  String get histogramRgbDescription => '红、绿、蓝通道分布';

  @override
  String get histogramLoading => '正在计算直方图…';

  @override
  String get histogramUnavailable => '暂时无法生成直方图';

  @override
  String get histogramEmpty => '没有可统计的可见像素';

  @override
  String get histogramRetry => '重试';

  @override
  String get histogramRed => 'R';

  @override
  String get histogramGreen => 'G';

  @override
  String get histogramBlue => 'B';

  @override
  String get histogramSampleNote => '基于 SDR 预览采样';

  @override
  String get histogramAnimationNote => '基于 SDR 预览采样 · 动图首帧';

  @override
  String get appTitle => '神羊看图';

  @override
  String get appDescription =>
      '神羊看图（ShenView）是一款用于浏览本地图片与文件夹的桌面看图工具，可以查看照片、长图和压缩包中的漫画。';

  @override
  String get settings => '设置';

  @override
  String get toolbarMode => '工具栏模式';

  @override
  String get toolbarModeDescription => '普通模式下，工具栏固定在内容上方；悬浮模式下，工具栏覆盖在图片上。';

  @override
  String get normalMode => '普通';

  @override
  String get floatingMode => '悬浮';

  @override
  String get originalSize => '实际大小';

  @override
  String get sortOrder => '文件排序方式';

  @override
  String get sortOrderDescription =>
      '用于普通目录；“文件夹顺序”会尝试跟随 Windows 已打开的资源管理器窗口。压缩包内单独排序，默认文件名升序，不支持“文件夹顺序”。';

  @override
  String get archiveSortSettings => '压缩包排序设置';

  @override
  String get archiveSortLink => '压缩包';

  @override
  String get fileNameSortMode => '文件名排序规则';

  @override
  String get fileNameSortModeDescription =>
      '用于普通目录和压缩包。文件名不含扩展名的部分相同时，按扩展名的字母顺序排序。';

  @override
  String get fileNameSortNatural => '自然排序';

  @override
  String get fileNameSortNaturalTooltip => '按数字大小比较主文件名，例如升序时 2 在 10 前。';

  @override
  String get fileNameSortLexicographic => '普通字符串排序';

  @override
  String get fileNameSortLexicographicTooltip => '逐字符比较主文件名，例如升序时 10 在 2 前。';

  @override
  String get recursiveFolderBrowsing => '递归浏览子文件夹';

  @override
  String get folderContinuousReading => '连续浏览子文件夹';

  @override
  String get folderContinuousReadingDescription =>
      '将当前打开的文件夹及其子文件夹中的图片合并为一个浏览列表，可搭配任意查看方式。关闭后按文件夹分别浏览。';

  @override
  String get recursiveFolderBrowsingDescription =>
      '关闭时只浏览当前文件夹，隐藏普通子文件夹和底部目录导航，已固定的目录栏保留。开启后最多扫描 3 层、5000 张图片和 1000 个目录。';

  @override
  String get scanUnknownExtensions => '扫描未知扩展名文件';

  @override
  String get scanUnknownExtensionsDescription =>
      '关闭时只按扩展名识别图片，扫描更快。开启后还会读取文件头，识别没有常见扩展名的图片。';

  @override
  String get watchFolderChanges => '自动刷新文件夹';

  @override
  String get watchFolderChangesDescription =>
      '当前文件夹中的文件新增、删除或修改后，等待 2 秒无变化再刷新列表；窗口重新获得焦点时也会刷新。递归浏览时包含子文件夹，关闭后停止监听文件变化。';

  @override
  String scanProgress(int folders, int images) {
    return '正在扫描… $folders 个文件夹 / $images 张图片';
  }

  @override
  String scanSkippedFolders(int count) {
    return '$count 个文件夹无法读取';
  }

  @override
  String get emptyFolder => '此文件夹中没有图片';

  @override
  String get emptyRecursiveFolder => '当前文件夹及子文件夹中没有图片';

  @override
  String get showThumbnailFileNames => '显示缩略图文件名';

  @override
  String get showThumbnailFileNamesDescription =>
      '关闭后隐藏缩略图下方的文件名，选中状态和无障碍标签保持不变。';

  @override
  String get showBottomBar => '显示底部栏';

  @override
  String get showBottomBarDescription => '显示底部的图片信息、缩放和全屏操作。关闭后，缩略图条保持原有显示状态。';

  @override
  String get readingDirection => '阅读方向';

  @override
  String get leftToRight => '从左到右';

  @override
  String get rightToLeftManga => '从右到左';

  @override
  String get comicLayoutDirection => '连续排列方向';

  @override
  String get verticalContinuous => '纵向连续';

  @override
  String get horizontalLeftToRight => '从左到右';

  @override
  String get horizontalRightToLeft => '从右到左';

  @override
  String get doublePageCoverAlone => '双页模式封面单独显示';

  @override
  String get comicPageGap => '连续阅读页间距';

  @override
  String get comicGapNone => '无';

  @override
  String get comicGapTight => '紧凑';

  @override
  String get comicGapStandard => '标准';

  @override
  String get comicGapLoose => '宽松';

  @override
  String get comicGapCustom => '自定义';

  @override
  String get defaultOption => '默认';

  @override
  String get selectImageOrComic => '选择图片或漫画';

  @override
  String get selectImageFolder => '选择图片文件夹';

  @override
  String get dropToOpen => '松开以打开图片、文件夹或漫画';

  @override
  String get parentFolder => '上级文件夹';

  @override
  String get recursiveScanLimit => '递归扫描已达到安全上限';

  @override
  String get folderNotOpened => '未打开文件夹';

  @override
  String get language => '语言';

  @override
  String get theme => '主题';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get systemLanguage => '跟随系统';

  @override
  String get simplifiedChinese => '简体中文';

  @override
  String get english => 'English';

  @override
  String get copy => '复制';

  @override
  String get delete => '删除';

  @override
  String get print => '打印';

  @override
  String get openImage => '打开图片';

  @override
  String get openFolder => '打开文件夹';

  @override
  String get copyImagePath => '复制图片路径';

  @override
  String get openImagePath => '打开图片路径';

  @override
  String get viewMode => '查看方式';

  @override
  String get viewOrder => '查看顺序';

  @override
  String get zoomMode => '尺寸适配';

  @override
  String get singlePage => '单页';

  @override
  String get doublePage => '双页';

  @override
  String get longImage => '长图';

  @override
  String get comic => '连续阅读';

  @override
  String get autoZoom => '适应窗口';

  @override
  String get focusZoom => '换图时保持缩放比例';

  @override
  String get widthPriority => '适应宽度';

  @override
  String get heightPriority => '适应高度';

  @override
  String get keepZoomPosition => '同时保持查看位置';

  @override
  String get zoomCenter => '缩放中心';

  @override
  String get zoomCenterPointer => '鼠标位置';

  @override
  String get zoomCenterViewport => '视口中心';

  @override
  String get comicUniformSize => '统一页面宽高';

  @override
  String get readingBaseSize => '阅读基准大小（100%）';

  @override
  String get fileSystemOrder => '文件夹顺序';

  @override
  String get fileNameAscending => '文件名升序';

  @override
  String get fileNameDescending => '文件名降序';

  @override
  String get fileSizeAscending => '文件大小升序';

  @override
  String get fileSizeDescending => '文件大小降序';

  @override
  String get modifiedNewest => '修改时间最新';

  @override
  String get modifiedOldest => '修改时间最早';

  @override
  String get windowAlwaysOnTop => '窗口置顶';

  @override
  String get cancelAlwaysOnTop => '取消置顶';

  @override
  String get moreActions => '更多操作';

  @override
  String get moreZoomOptions => '更多缩放操作';

  @override
  String get minimize => '最小化';

  @override
  String get restore => '还原';

  @override
  String get maximize => '最大化';

  @override
  String get close => '关闭';

  @override
  String get cancel => '取消';

  @override
  String get rotateClockwise => '顺时针旋转';

  @override
  String get flipHorizontally => '水平翻转';

  @override
  String get showThumbnails => '显示缩略图';

  @override
  String get hideThumbnails => '隐藏缩略图';

  @override
  String get showInfo => '显示信息';

  @override
  String get information => '信息';

  @override
  String get hideInfo => '隐藏信息';

  @override
  String get zoomToWindow => '适应窗口';

  @override
  String get actualSize => '实际大小';

  @override
  String get fullscreen => '全屏';

  @override
  String get enterBorderless => '进入无边框模式';

  @override
  String get exitBorderless => '退出无边框模式';

  @override
  String get exitFullscreen => '退出全屏';

  @override
  String get zoomOut => '缩小';

  @override
  String get zoomIn => '放大';

  @override
  String get previousImage => '上一个';

  @override
  String get nextImage => '下一个';

  @override
  String get closeInfoPanel => '关闭信息面板';

  @override
  String get noImage => '暂无图片';

  @override
  String get format => '格式';

  @override
  String get fileName => '文件名';

  @override
  String get size => '大小';

  @override
  String get modifiedTime => '修改时间';

  @override
  String get dimensions => '尺寸';

  @override
  String get orientation => '方向';

  @override
  String get path => '路径';

  @override
  String get additionalMetadata => '附加元数据';

  @override
  String get readingDimensionsFailed => '尺寸 / 方向读取失败';

  @override
  String get readingDimensions => '正在读取尺寸 / 方向…';

  @override
  String get readingMetadataFailed => '元数据读取失败';

  @override
  String get unreadableImageMetadata => '无法读取图片元数据';

  @override
  String get imageProperties => '图像属性';

  @override
  String get basicInformation => '基本信息';

  @override
  String get renameFile => '重命名文件';

  @override
  String get rename => '重命名';

  @override
  String get renameUnavailable => '当前文件无法编辑';

  @override
  String get renameTargetExists => '目标文件已存在';

  @override
  String get invalidFileName => '文件名无效';

  @override
  String get animationInformation => '动画信息';

  @override
  String get frames => '帧数';

  @override
  String get frameRate => '帧率';

  @override
  String get duration => '总时长';

  @override
  String get loopCount => '循环';

  @override
  String get infiniteLoop => '循环';

  @override
  String playCount(Object value) {
    return '播放 $value 次';
  }

  @override
  String get cameraInformation => '相机信息';

  @override
  String get captureTime => '拍摄时间';

  @override
  String get photoTitle => '标题';

  @override
  String get photoDescription => '描述';

  @override
  String get photoCreator => '作者';

  @override
  String get photoCopyright => '版权';

  @override
  String get photoRating => '评分';

  @override
  String get photoKeywords => '关键词';

  @override
  String get photoRejected => '已拒绝';

  @override
  String get photoAuto => '自动';

  @override
  String get photoManual => '手动';

  @override
  String get flashFired => '已闪光';

  @override
  String get flashNotFired => '未闪光';

  @override
  String get flashUnavailable => '无闪光灯';

  @override
  String get flashRedEye => '防红眼';

  @override
  String get device => '拍摄设备';

  @override
  String get lens => '镜头';

  @override
  String get aperture => '光圈';

  @override
  String get shutterSpeed => '快门速度';

  @override
  String get iso => 'ISO';

  @override
  String get focalLength => '焦距';

  @override
  String get exposureCompensation => '曝光补偿';

  @override
  String get whiteBalance => '白平衡';

  @override
  String get flash => '闪光灯';

  @override
  String get location => '位置信息';

  @override
  String get codec => '编解码器';

  @override
  String get colorSpace => '色彩空间';

  @override
  String get colorDepth => '色彩深度';

  @override
  String get alphaChannel => '透明度';

  @override
  String get hasAlpha => '包含 Alpha 通道';

  @override
  String get opaque => '不透明';

  @override
  String get vectorInformation => '矢量信息';

  @override
  String get physicalSize => '物理尺寸';

  @override
  String get viewBox => 'ViewBox';

  @override
  String get nodeCount => '节点数量';

  @override
  String get orientationNormal => '正常（方向 1）';

  @override
  String get orientationHorizontalMirror => '水平镜像（方向 2）';

  @override
  String get orientationRotate180 => '旋转 180°（方向 3）';

  @override
  String get orientationVerticalMirror => '垂直镜像（方向 4）';

  @override
  String get orientationMirrorRotate270 => '镜像并旋转 270°（方向 5）';

  @override
  String get orientationRotate90 => '旋转 90°（方向 6）';

  @override
  String get orientationMirrorRotate90 => '镜像并旋转 90°（方向 7）';

  @override
  String get orientationRotate270 => '旋转 270°（方向 8）';

  @override
  String orientationUnknown(Object value) {
    return '未知（方向 $value）';
  }

  @override
  String get selectContainer => '选择文件夹或压缩包，开始阅读漫画';

  @override
  String get cannotDecodeAnimatedImage => '无法解码动图';

  @override
  String imageParseFailed(Object name) {
    return '无法解析 $name';
  }

  @override
  String printPreviewFailed(Object error) {
    return '打印预览失败：$error';
  }

  @override
  String printFailed(Object error) {
    return '打印失败：$error';
  }

  @override
  String get parsingCapabilities => '支持的图片格式';

  @override
  String get acknowledge => '知道了';

  @override
  String get deleteCurrentImageQuestion => '删除图片';

  @override
  String deleteCurrentImageDescription(Object name) {
    return '删除“$name”后，文件将被移入回收站。';
  }

  @override
  String get moveToRecycleBin => '移入回收站';

  @override
  String get deleteFailed => '无法移入回收站';

  @override
  String get printPreview => '打印预览';

  @override
  String get customMarginLabel => '自定义页边距';

  @override
  String get printer => '打印机';

  @override
  String get defaultPrinter => '默认打印机';

  @override
  String get readingPrinters => '正在读取打印机…';

  @override
  String get printerListUnavailable => '打印机列表不可用';

  @override
  String get portrait => '纵向';

  @override
  String get landscape => '横向';

  @override
  String get paperSize => '纸张大小';

  @override
  String get margins => '页边距';

  @override
  String get customMarginHint => '0 到 50 mm，最多 1 位小数';

  @override
  String get customMarginInvalid => '请输入 0 到 50 之间的数字。';

  @override
  String get noMargin => '无';

  @override
  String get narrowMargin => '最小';

  @override
  String get normalMargin => '自定义';

  @override
  String get fitMode => '适应方式';

  @override
  String get fitPage => '适应页面';

  @override
  String get fillPage => '填充页面';

  @override
  String get fitPageDescription => '完整显示图片并保持比例，部分区域可能留白。';

  @override
  String get fillPageDescription => '按比例铺满可打印区域，边缘可能被裁切。';

  @override
  String get actualSizeDescription => '按图片原始尺寸打印，可能超出可打印区域。';

  @override
  String get printAction => '打印';

  @override
  String get play => '播放';

  @override
  String get pause => '暂停';

  @override
  String get archiveFormat => '压缩包';

  @override
  String get unknownFormat => '未知';

  @override
  String bytes(Object value) {
    return '$value';
  }

  @override
  String get decoderFlutterCodec => 'Flutter 编解码器';

  @override
  String get decoderDartImageSvg => 'Dart image / SVG 渲染器';

  @override
  String get decoderArchive => '7-Zip 原生引擎；按需读取';

  @override
  String get decoderImageMagickJxl => 'ImageMagick（JPEG XL）';

  @override
  String get decoderWindowsWic => 'Windows WIC → ImageMagick 回退';

  @override
  String get decoderMacImageIo => 'macOS Image I/O → ImageMagick 回退';

  @override
  String get decoderImageMagickFallback => 'ImageMagick 回退';

  @override
  String get decoderUnavailable => '未注册解码器';

  @override
  String get invalidPngApng => '不是有效的 PNG/APNG 文件';

  @override
  String get archiveLimitExceeded => '压缩包超过安全处理限制';

  @override
  String get archiveTimeout => '压缩包处理超时';

  @override
  String get sevenZipMissing => '归档读取组件不可用，请重新安装完整发行包后重试';

  @override
  String get unsafeArchivePath => '压缩包包含越界路径或链接';

  @override
  String get archiveOpening => '打开中…';

  @override
  String get archiveEmpty => '压缩包内没有可浏览的图片';

  @override
  String get archiveEncrypted => '压缩包需要密码，请输入密码后重试';

  @override
  String get archiveCorrupt => '压缩包已损坏或使用了不支持的压缩算法';

  @override
  String get archiveUnsupported => '压缩包格式不受支持';

  @override
  String get archiveIoError => '无法读取压缩包，请检查文件权限或磁盘空间';

  @override
  String get archiveRetry => '重试';

  @override
  String get showInExplorer => '在资源管理器中显示';

  @override
  String get archiveReadOnly => '压缩包内为只读浏览';

  @override
  String get clipboardUnavailable => '当前平台暂不支持复制到系统剪贴板';

  @override
  String get recycleBinUnavailable => '当前平台暂不支持回收站';

  @override
  String get pixelReadFailed => '无法读取图片像素';

  @override
  String get animatedReadLimit => '动图超过文件读取限制';

  @override
  String get imageReadLimit => '图片文件超过读取限制，请使用长图模式或较小的图片';

  @override
  String get decoderUnavailableError =>
      '扩展解码器不可用，请重新安装完整发行包或设置 SHENVIEW_MAGICK';

  @override
  String get decodeTimeout => '图片解析超时，可以重试或切换下一张';

  @override
  String get decodeMemoryLimit => '图片超过解码内存限制，请使用适应窗口或长图模式';

  @override
  String decodeFailed(Object error) {
    return '解析失败：$error';
  }

  @override
  String get archiveSettings => '压缩包';

  @override
  String get archiveSettingsDescription => '章节与换包、预加载、内存与磁盘缓存。';

  @override
  String get archiveReading => '包内阅读';

  @override
  String get archiveContinuousReading => '跨章节连续浏览';

  @override
  String get archiveContinuousReadingDescription =>
      '将压缩包内各章节的图片合并为一个浏览列表。关闭后只浏览当前章节。';

  @override
  String get directoryImages => '本目录图片';

  @override
  String get chapterDirectory => '章节目录';

  @override
  String get browseDirectory => '浏览目录';

  @override
  String get showDirectoryPanel => '展开目录面板';

  @override
  String get hideDirectoryPanel => '收起目录面板';

  @override
  String get chooseLocation => '选择目录或压缩包';

  @override
  String get previousLocation => '上一项';

  @override
  String get nextLocation => '下一项';

  @override
  String get chooseChapter => '选择章节';

  @override
  String get previousChapter => '上一章';

  @override
  String get nextChapter => '下一章';

  @override
  String get directoryNavigationVisible => '显示目录导航';

  @override
  String get directoryNavigationVisibleDescription =>
      '显示左侧目录面板，也可通过状态栏切换。“外观”和“浏览”中的此设置同步生效。';

  @override
  String get pinDirectory => '固定目录栏';

  @override
  String get pinDirectoryDescription =>
      '将目录面板停靠在左侧，没有子目录或尚未打开内容时仍保留。拖动右边缘可调整宽度；取消固定后浮动显示。';

  @override
  String get directoryNotOpened => '尚未打开文件夹';

  @override
  String get directoryNotOpenedDescription => '打开文件夹后，这里将显示目录和压缩包。';

  @override
  String get directoryNoChildren => '没有子文件夹或压缩包。';

  @override
  String resizeDirectoryPanel(String undoShortcut) {
    return '拖动调整宽度，双击恢复默认；Esc 取消拖动，左右键微调，$undoShortcut 撤销';
  }

  @override
  String get unpinDirectory => '取消固定目录面板';

  @override
  String get searchDirectory => '搜索目录与章节';

  @override
  String get clearDirectorySearch => '清除目录搜索';

  @override
  String get noMatchingDirectory => '没有匹配的目录或章节';

  @override
  String get directoryReadFailed => '部分目录读取失败，请重新展开重试。';

  @override
  String get archiveAutoAdvance => '首尾翻页切换相邻压缩包';

  @override
  String get archiveAutoAdvanceDescription =>
      '从文件夹打开压缩包后，在末页继续向后翻可打开下一压缩包，在首页继续向前翻可打开上一压缩包。仅切换同一文件夹中的压缩包。';

  @override
  String get archiveSortOrder => '包内排序';

  @override
  String get archiveSortDescription => '查看顺序独立于普通目录；文件名排序规则与“浏览”设置一致。';

  @override
  String get archivePrefetchMode => '预加载';

  @override
  String get archivePrefetchDescription => '提前准备当前查看方式即将显示的图片，资源不足时自动减少或暂停。';

  @override
  String get archivePrefetchAutomatic => '自动';

  @override
  String get archivePrefetchConservative => '保守';

  @override
  String get archivePrefetchOff => '关闭预加载';

  @override
  String get archiveMemoryBudget => '压缩包图片内存上限';

  @override
  String get archiveMemoryDescription =>
      '根据可用内存自动调整，也可手动设为 32 到 1024 MiB。资源不足时会降低实际用量。';

  @override
  String get archiveBudgetAutomatic => '自动（推荐）';

  @override
  String get archiveBudgetCustom => '自定义';

  @override
  String get archiveMemoryInvalid => '请输入 32 到 1024 之间的整数。';

  @override
  String get archiveCache => '磁盘缓存';

  @override
  String get archivePersistCache => '保留普通包缓存';

  @override
  String get archivePersistDescription =>
      '在容量和保留期限内缓存未加密的压缩包。加密压缩包的缓存会在关闭后清理，密码不会保存。';

  @override
  String get archiveDiskBudget => '缓存容量上限';

  @override
  String get archiveDiskDescription => '所有压缩包共用此容量上限。正在使用的缓存会在使用结束后清理。';

  @override
  String get archiveRetention => '保留期限';

  @override
  String get archiveRetentionDescription => '超过期限或已经失效的缓存会自动清理。';

  @override
  String get archiveRetentionDay => '天';

  @override
  String get archiveCacheUsage => '已用缓存';

  @override
  String get archiveCacheUnknown => '正在统计…';

  @override
  String get archiveClearCache => '清理缓存';

  @override
  String get archiveCacheClearFailed => '缓存清理失败，请重试。';

  @override
  String get archiveCacheCleared => '已清理未使用的缓存，其余缓存会在使用结束后清理。';

  @override
  String get archivePasswordTitle => '输入压缩包密码';

  @override
  String get archivePasswordHint => '密码';

  @override
  String get archivePasswordDescription => '密码仅用于本次会话，不会保存。';

  @override
  String get archivePasswordShow => '显示密码';

  @override
  String get archivePasswordHide => '隐藏密码';

  @override
  String get archivePasswordOpen => '打开';

  @override
  String get archivePasswordWrong => '密码不正确，请重新输入。';

  @override
  String get archivePasswordUnverified => '无法验证密码或数据，请检查密码，或重新获取一份压缩包。';

  @override
  String get archivePasswordUnsupported => '此加密方式暂不受支持，请先解密后打开。';

  @override
  String get archiveReadingDirectory => '正在读取目录…';

  @override
  String get archivePreparingPage => '正在准备图片…';

  @override
  String get archiveCancelOpening => '取消打开';

  @override
  String get archiveRetryPage => '重试此页';

  @override
  String get archivePerformanceNormal => '正常：按方向和距离预加载';

  @override
  String get archivePerformanceConservative => '保守：仅保留邻近页';

  @override
  String get archivePerformanceOnDemand => '按需：仅准备当前可见内容';

  @override
  String get archiveSourceChanged => '压缩包已更改，请重新打开。';

  @override
  String get archiveVolumeMissing => '压缩包需要其他分卷，请补齐分卷后重新打开。';

  @override
  String get archiveResourceInsufficient => '可用资源不足，请关闭其他图片或清理缓存后重试。';

  @override
  String get archiveBrowseContainers => '此处没有图片，可进入章节或子压缩包继续浏览。';

  @override
  String get saveOriginalImage => '另存为';

  @override
  String get animationControls => '动图播放控制';

  @override
  String get previousFrame => '上一帧';

  @override
  String get nextFrame => '下一帧';

  @override
  String get animationProgress => '播放进度';

  @override
  String get animationSpeed => '播放速度';

  @override
  String get animationRestart => '从头播放';

  @override
  String get animationLoopFile => '遵循文件';

  @override
  String get animationLoopInfinite => '无限循环';

  @override
  String get animationLoopOnce => '播放一次';

  @override
  String get animationLoopMode => '循环方式';

  @override
  String get animationAutoPlay => '打开动图时自动播放';

  @override
  String get animationAutoPlayDescription => '打开动图时自动播放；关闭后停在首帧。';

  @override
  String get animationDefaultLoopDescription => '打开动图时使用此循环方式，可在播放条中临时调整。';

  @override
  String get animationDefaultSpeed => '默认播放倍速';

  @override
  String get animationDefaultSpeedDescription => '打开动图时使用此倍速，播放条中的调整仅用于当前动图。';

  @override
  String get animationControlsDisplay => '播放条显示方式';

  @override
  String get animationControlsDisplayDescription =>
      '选择自动隐藏后，播放中 2 秒无操作会隐藏播放条，鼠标移到画面底部即可显示。隐藏后仍可按空格播放或暂停。';

  @override
  String get animationControlsAutoHide => '自动隐藏';

  @override
  String get animationControlsAlways => '始终显示';

  @override
  String get animationControlsHidden => '隐藏';

  @override
  String animationFramePosition(int frame, int count) {
    return '第 $frame / $count 帧';
  }

  @override
  String get autoPlayTitle => '自动播放';

  @override
  String get autoPlayStart => '开始自动播放';

  @override
  String get autoPlayPause => '暂停自动播放';

  @override
  String get autoPlayStop => '停止自动播放';

  @override
  String get autoPlayOptions => '自动播放设置';

  @override
  String get autoPlayInterval => '播放间隔（秒）';

  @override
  String get autoPlaySpeed => '滚动速度（像素／秒）';

  @override
  String get autoPlayLoop => '循环播放';

  @override
  String get autoPlayAnimation => '遇到动图';

  @override
  String get autoPlayCompleteOnce => '至少播放一遍';

  @override
  String get autoPlayFixedInterval => '按固定间隔切换';

  @override
  String get autoPlayStay => '停留在动图';

  @override
  String get autoPlayWaiting => '等待动图播放完成';

  @override
  String get autoPlayPaused => '已暂停';

  @override
  String get autoPlayScrolling => '自动滚动';

  @override
  String get autoPlayScope => '当前浏览列表 · 不自动跨目录或压缩包';

  @override
  String get autoPlaySave => '保存';

  @override
  String get animationLabel => '动图';

  @override
  String get autoPlayAdvancing => '自动换图';

  @override
  String autoPlayCountdown(String seconds) {
    return '$seconds 秒后换图';
  }

  @override
  String autoPlayScrollRate(String speed) {
    return '$speed 像素／秒';
  }

  @override
  String get autoPlayInvalidInterval => '请输入 0.5 到 3600 之间的数字';

  @override
  String get autoPlayIntervalHint => '0.5 到 3600 秒，最多 1 位小数';

  @override
  String get autoPlayInvalidSpeed => '请输入 5 到 1000 之间的数字';

  @override
  String get autoPlayStatusDisplay => '状态面板显示方式';

  @override
  String get autoPlayStatusDisplayDescription =>
      '选择自动隐藏后，播放中 2 秒无操作会淡出状态面板，鼠标移到画面右上角即可显示。暂停、键盘聚焦或打开设置时保持可见。';
}
