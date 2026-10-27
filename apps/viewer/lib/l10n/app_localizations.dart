import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @externalOpen.
  ///
  /// In zh, this message translates to:
  /// **'用其他程序打开'**
  String get externalOpen;

  /// No description provided for @externalOpenChoose.
  ///
  /// In zh, this message translates to:
  /// **'选择其他程序…'**
  String get externalOpenChoose;

  /// No description provided for @externalOpenLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在读取可用程序…'**
  String get externalOpenLoading;

  /// No description provided for @externalOpenNoApplications.
  ///
  /// In zh, this message translates to:
  /// **'没有关联的程序'**
  String get externalOpenNoApplications;

  /// No description provided for @externalOpenListFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取可用程序'**
  String get externalOpenListFailed;

  /// No description provided for @externalOpenSaveCopy.
  ///
  /// In zh, this message translates to:
  /// **'保存副本后用其他程序打开'**
  String get externalOpenSaveCopy;

  /// No description provided for @externalOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'用其他程序打开失败：{message}'**
  String externalOpenFailed(String message);

  /// No description provided for @photoMute.
  ///
  /// In zh, this message translates to:
  /// **'静音'**
  String get photoMute;

  /// No description provided for @photoAudioRetry.
  ///
  /// In zh, this message translates to:
  /// **'声音播放失败，点击重试'**
  String get photoAudioRetry;

  /// No description provided for @photoUnmute.
  ///
  /// In zh, this message translates to:
  /// **'开启声音'**
  String get photoUnmute;

  /// No description provided for @photoAudioTrack.
  ///
  /// In zh, this message translates to:
  /// **'音轨 {number}'**
  String photoAudioTrack(int number);

  /// No description provided for @icoVariant.
  ///
  /// In zh, this message translates to:
  /// **'图标版本'**
  String get icoVariant;

  /// No description provided for @svgStaticPreview.
  ///
  /// In zh, this message translates to:
  /// **'SVG 已切换为静态预览。动画不会播放，字体和部分效果可能有差异。'**
  String get svgStaticPreview;

  /// No description provided for @histogram.
  ///
  /// In zh, this message translates to:
  /// **'直方图'**
  String get histogram;

  /// No description provided for @histogramLuminance.
  ///
  /// In zh, this message translates to:
  /// **'亮度'**
  String get histogramLuminance;

  /// No description provided for @histogramRgbDescription.
  ///
  /// In zh, this message translates to:
  /// **'红、绿、蓝通道分布'**
  String get histogramRgbDescription;

  /// No description provided for @histogramLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在计算直方图…'**
  String get histogramLoading;

  /// No description provided for @histogramUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法生成直方图'**
  String get histogramUnavailable;

  /// No description provided for @histogramEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有可统计的可见像素'**
  String get histogramEmpty;

  /// No description provided for @histogramRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get histogramRetry;

  /// No description provided for @histogramRed.
  ///
  /// In zh, this message translates to:
  /// **'R'**
  String get histogramRed;

  /// No description provided for @histogramGreen.
  ///
  /// In zh, this message translates to:
  /// **'G'**
  String get histogramGreen;

  /// No description provided for @histogramBlue.
  ///
  /// In zh, this message translates to:
  /// **'B'**
  String get histogramBlue;

  /// No description provided for @histogramSampleNote.
  ///
  /// In zh, this message translates to:
  /// **'基于 SDR 预览采样'**
  String get histogramSampleNote;

  /// No description provided for @histogramAnimationNote.
  ///
  /// In zh, this message translates to:
  /// **'基于 SDR 预览采样 · 动图首帧'**
  String get histogramAnimationNote;

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'神羊看图'**
  String get appTitle;

  /// No description provided for @appDescription.
  ///
  /// In zh, this message translates to:
  /// **'神羊看图（ShenView）是一款用于浏览本地图片与文件夹的桌面看图工具，可以查看照片、长图和压缩包中的漫画。'**
  String get appDescription;

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @toolbarMode.
  ///
  /// In zh, this message translates to:
  /// **'工具栏模式'**
  String get toolbarMode;

  /// No description provided for @toolbarModeDescription.
  ///
  /// In zh, this message translates to:
  /// **'普通模式下，工具栏固定在内容上方；悬浮模式下，工具栏覆盖在图片上。'**
  String get toolbarModeDescription;

  /// No description provided for @normalMode.
  ///
  /// In zh, this message translates to:
  /// **'普通'**
  String get normalMode;

  /// No description provided for @floatingMode.
  ///
  /// In zh, this message translates to:
  /// **'悬浮'**
  String get floatingMode;

  /// No description provided for @originalSize.
  ///
  /// In zh, this message translates to:
  /// **'实际大小'**
  String get originalSize;

  /// No description provided for @sortOrder.
  ///
  /// In zh, this message translates to:
  /// **'文件排序方式'**
  String get sortOrder;

  /// No description provided for @sortOrderDescription.
  ///
  /// In zh, this message translates to:
  /// **'用于普通目录；“文件夹顺序”会尝试跟随 Windows 已打开的资源管理器窗口。压缩包内单独排序，默认文件名升序，不支持“文件夹顺序”。'**
  String get sortOrderDescription;

  /// No description provided for @archiveSortSettings.
  ///
  /// In zh, this message translates to:
  /// **'压缩包排序设置'**
  String get archiveSortSettings;

  /// No description provided for @archiveSortLink.
  ///
  /// In zh, this message translates to:
  /// **'压缩包'**
  String get archiveSortLink;

  /// No description provided for @fileNameSortMode.
  ///
  /// In zh, this message translates to:
  /// **'文件名排序规则'**
  String get fileNameSortMode;

  /// No description provided for @fileNameSortModeDescription.
  ///
  /// In zh, this message translates to:
  /// **'用于普通目录和压缩包。文件名不含扩展名的部分相同时，按扩展名的字母顺序排序。'**
  String get fileNameSortModeDescription;

  /// No description provided for @fileNameSortNatural.
  ///
  /// In zh, this message translates to:
  /// **'自然排序'**
  String get fileNameSortNatural;

  /// No description provided for @fileNameSortNaturalTooltip.
  ///
  /// In zh, this message translates to:
  /// **'按数字大小比较主文件名，例如升序时 2 在 10 前。'**
  String get fileNameSortNaturalTooltip;

  /// No description provided for @fileNameSortLexicographic.
  ///
  /// In zh, this message translates to:
  /// **'普通字符串排序'**
  String get fileNameSortLexicographic;

  /// No description provided for @fileNameSortLexicographicTooltip.
  ///
  /// In zh, this message translates to:
  /// **'逐字符比较主文件名，例如升序时 10 在 2 前。'**
  String get fileNameSortLexicographicTooltip;

  /// No description provided for @recursiveFolderBrowsing.
  ///
  /// In zh, this message translates to:
  /// **'递归浏览子文件夹'**
  String get recursiveFolderBrowsing;

  /// No description provided for @folderContinuousReading.
  ///
  /// In zh, this message translates to:
  /// **'连续浏览子文件夹'**
  String get folderContinuousReading;

  /// No description provided for @folderContinuousReadingDescription.
  ///
  /// In zh, this message translates to:
  /// **'将当前打开的文件夹及其子文件夹中的图片合并为一个浏览列表，可搭配任意查看方式。关闭后按文件夹分别浏览。'**
  String get folderContinuousReadingDescription;

  /// No description provided for @recursiveFolderBrowsingDescription.
  ///
  /// In zh, this message translates to:
  /// **'关闭时只浏览当前文件夹，隐藏普通子文件夹和底部目录导航，已固定的目录栏保留。开启后最多扫描 3 层、5000 张图片和 1000 个目录。'**
  String get recursiveFolderBrowsingDescription;

  /// No description provided for @scanUnknownExtensions.
  ///
  /// In zh, this message translates to:
  /// **'扫描未知扩展名文件'**
  String get scanUnknownExtensions;

  /// No description provided for @scanUnknownExtensionsDescription.
  ///
  /// In zh, this message translates to:
  /// **'关闭时只按扩展名识别图片，扫描更快。开启后还会读取文件头，识别没有常见扩展名的图片。'**
  String get scanUnknownExtensionsDescription;

  /// No description provided for @watchFolderChanges.
  ///
  /// In zh, this message translates to:
  /// **'自动刷新文件夹'**
  String get watchFolderChanges;

  /// No description provided for @watchFolderChangesDescription.
  ///
  /// In zh, this message translates to:
  /// **'当前文件夹中的文件新增、删除或修改后，等待 2 秒无变化再刷新列表；窗口重新获得焦点时也会刷新。递归浏览时包含子文件夹，关闭后停止监听文件变化。'**
  String get watchFolderChangesDescription;

  /// No description provided for @scanProgress.
  ///
  /// In zh, this message translates to:
  /// **'正在扫描… {folders} 个文件夹 / {images} 张图片'**
  String scanProgress(int folders, int images);

  /// No description provided for @scanSkippedFolders.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个文件夹无法读取'**
  String scanSkippedFolders(int count);

  /// No description provided for @emptyFolder.
  ///
  /// In zh, this message translates to:
  /// **'此文件夹中没有图片'**
  String get emptyFolder;

  /// No description provided for @emptyRecursiveFolder.
  ///
  /// In zh, this message translates to:
  /// **'当前文件夹及子文件夹中没有图片'**
  String get emptyRecursiveFolder;

  /// No description provided for @showThumbnailFileNames.
  ///
  /// In zh, this message translates to:
  /// **'显示缩略图文件名'**
  String get showThumbnailFileNames;

  /// No description provided for @showThumbnailFileNamesDescription.
  ///
  /// In zh, this message translates to:
  /// **'关闭后隐藏缩略图下方的文件名，选中状态和无障碍标签保持不变。'**
  String get showThumbnailFileNamesDescription;

  /// No description provided for @showBottomBar.
  ///
  /// In zh, this message translates to:
  /// **'显示底部栏'**
  String get showBottomBar;

  /// No description provided for @showBottomBarDescription.
  ///
  /// In zh, this message translates to:
  /// **'显示底部的图片信息、缩放和全屏操作。关闭后，缩略图条保持原有显示状态。'**
  String get showBottomBarDescription;

  /// No description provided for @readingDirection.
  ///
  /// In zh, this message translates to:
  /// **'阅读方向'**
  String get readingDirection;

  /// No description provided for @leftToRight.
  ///
  /// In zh, this message translates to:
  /// **'从左到右'**
  String get leftToRight;

  /// No description provided for @rightToLeftManga.
  ///
  /// In zh, this message translates to:
  /// **'从右到左'**
  String get rightToLeftManga;

  /// No description provided for @comicLayoutDirection.
  ///
  /// In zh, this message translates to:
  /// **'连续排列方向'**
  String get comicLayoutDirection;

  /// No description provided for @verticalContinuous.
  ///
  /// In zh, this message translates to:
  /// **'纵向连续'**
  String get verticalContinuous;

  /// No description provided for @horizontalLeftToRight.
  ///
  /// In zh, this message translates to:
  /// **'从左到右'**
  String get horizontalLeftToRight;

  /// No description provided for @horizontalRightToLeft.
  ///
  /// In zh, this message translates to:
  /// **'从右到左'**
  String get horizontalRightToLeft;

  /// No description provided for @doublePageCoverAlone.
  ///
  /// In zh, this message translates to:
  /// **'双页模式封面单独显示'**
  String get doublePageCoverAlone;

  /// No description provided for @comicPageGap.
  ///
  /// In zh, this message translates to:
  /// **'连续阅读页间距'**
  String get comicPageGap;

  /// No description provided for @comicGapNone.
  ///
  /// In zh, this message translates to:
  /// **'无'**
  String get comicGapNone;

  /// No description provided for @comicGapTight.
  ///
  /// In zh, this message translates to:
  /// **'紧凑'**
  String get comicGapTight;

  /// No description provided for @comicGapStandard.
  ///
  /// In zh, this message translates to:
  /// **'标准'**
  String get comicGapStandard;

  /// No description provided for @comicGapLoose.
  ///
  /// In zh, this message translates to:
  /// **'宽松'**
  String get comicGapLoose;

  /// No description provided for @comicGapCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get comicGapCustom;

  /// No description provided for @defaultOption.
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get defaultOption;

  /// No description provided for @selectImageOrComic.
  ///
  /// In zh, this message translates to:
  /// **'选择图片或漫画'**
  String get selectImageOrComic;

  /// No description provided for @selectImageFolder.
  ///
  /// In zh, this message translates to:
  /// **'选择图片文件夹'**
  String get selectImageFolder;

  /// No description provided for @dropToOpen.
  ///
  /// In zh, this message translates to:
  /// **'松开以打开图片、文件夹或漫画'**
  String get dropToOpen;

  /// No description provided for @parentFolder.
  ///
  /// In zh, this message translates to:
  /// **'上级文件夹'**
  String get parentFolder;

  /// No description provided for @recursiveScanLimit.
  ///
  /// In zh, this message translates to:
  /// **'递归扫描已达到安全上限'**
  String get recursiveScanLimit;

  /// No description provided for @folderNotOpened.
  ///
  /// In zh, this message translates to:
  /// **'未打开文件夹'**
  String get folderNotOpened;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @theme.
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get themeDark;

  /// No description provided for @systemLanguage.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get systemLanguage;

  /// No description provided for @simplifiedChinese.
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get simplifiedChinese;

  /// No description provided for @english.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @copy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get copy;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @print.
  ///
  /// In zh, this message translates to:
  /// **'打印'**
  String get print;

  /// No description provided for @openImage.
  ///
  /// In zh, this message translates to:
  /// **'打开图片'**
  String get openImage;

  /// No description provided for @openFolder.
  ///
  /// In zh, this message translates to:
  /// **'打开文件夹'**
  String get openFolder;

  /// No description provided for @copyImagePath.
  ///
  /// In zh, this message translates to:
  /// **'复制图片路径'**
  String get copyImagePath;

  /// No description provided for @openImagePath.
  ///
  /// In zh, this message translates to:
  /// **'打开图片路径'**
  String get openImagePath;

  /// No description provided for @viewMode.
  ///
  /// In zh, this message translates to:
  /// **'查看方式'**
  String get viewMode;

  /// No description provided for @viewOrder.
  ///
  /// In zh, this message translates to:
  /// **'查看顺序'**
  String get viewOrder;

  /// No description provided for @zoomMode.
  ///
  /// In zh, this message translates to:
  /// **'尺寸适配'**
  String get zoomMode;

  /// No description provided for @singlePage.
  ///
  /// In zh, this message translates to:
  /// **'单页'**
  String get singlePage;

  /// No description provided for @doublePage.
  ///
  /// In zh, this message translates to:
  /// **'双页'**
  String get doublePage;

  /// No description provided for @longImage.
  ///
  /// In zh, this message translates to:
  /// **'长图'**
  String get longImage;

  /// No description provided for @comic.
  ///
  /// In zh, this message translates to:
  /// **'连续阅读'**
  String get comic;

  /// No description provided for @autoZoom.
  ///
  /// In zh, this message translates to:
  /// **'适应窗口'**
  String get autoZoom;

  /// No description provided for @focusZoom.
  ///
  /// In zh, this message translates to:
  /// **'换图时保持缩放比例'**
  String get focusZoom;

  /// No description provided for @widthPriority.
  ///
  /// In zh, this message translates to:
  /// **'适应宽度'**
  String get widthPriority;

  /// No description provided for @heightPriority.
  ///
  /// In zh, this message translates to:
  /// **'适应高度'**
  String get heightPriority;

  /// No description provided for @keepZoomPosition.
  ///
  /// In zh, this message translates to:
  /// **'同时保持查看位置'**
  String get keepZoomPosition;

  /// No description provided for @zoomCenter.
  ///
  /// In zh, this message translates to:
  /// **'缩放中心'**
  String get zoomCenter;

  /// No description provided for @zoomCenterPointer.
  ///
  /// In zh, this message translates to:
  /// **'鼠标位置'**
  String get zoomCenterPointer;

  /// No description provided for @zoomCenterViewport.
  ///
  /// In zh, this message translates to:
  /// **'视口中心'**
  String get zoomCenterViewport;

  /// No description provided for @comicUniformSize.
  ///
  /// In zh, this message translates to:
  /// **'统一页面宽高'**
  String get comicUniformSize;

  /// No description provided for @readingBaseSize.
  ///
  /// In zh, this message translates to:
  /// **'阅读基准大小（100%）'**
  String get readingBaseSize;

  /// No description provided for @fileSystemOrder.
  ///
  /// In zh, this message translates to:
  /// **'文件夹顺序'**
  String get fileSystemOrder;

  /// No description provided for @fileNameAscending.
  ///
  /// In zh, this message translates to:
  /// **'文件名升序'**
  String get fileNameAscending;

  /// No description provided for @fileNameDescending.
  ///
  /// In zh, this message translates to:
  /// **'文件名降序'**
  String get fileNameDescending;

  /// No description provided for @fileSizeAscending.
  ///
  /// In zh, this message translates to:
  /// **'文件大小升序'**
  String get fileSizeAscending;

  /// No description provided for @fileSizeDescending.
  ///
  /// In zh, this message translates to:
  /// **'文件大小降序'**
  String get fileSizeDescending;

  /// No description provided for @modifiedNewest.
  ///
  /// In zh, this message translates to:
  /// **'修改时间最新'**
  String get modifiedNewest;

  /// No description provided for @modifiedOldest.
  ///
  /// In zh, this message translates to:
  /// **'修改时间最早'**
  String get modifiedOldest;

  /// No description provided for @windowAlwaysOnTop.
  ///
  /// In zh, this message translates to:
  /// **'窗口置顶'**
  String get windowAlwaysOnTop;

  /// No description provided for @cancelAlwaysOnTop.
  ///
  /// In zh, this message translates to:
  /// **'取消置顶'**
  String get cancelAlwaysOnTop;

  /// No description provided for @moreActions.
  ///
  /// In zh, this message translates to:
  /// **'更多操作'**
  String get moreActions;

  /// No description provided for @moreZoomOptions.
  ///
  /// In zh, this message translates to:
  /// **'更多缩放操作'**
  String get moreZoomOptions;

  /// No description provided for @minimize.
  ///
  /// In zh, this message translates to:
  /// **'最小化'**
  String get minimize;

  /// No description provided for @restore.
  ///
  /// In zh, this message translates to:
  /// **'还原'**
  String get restore;

  /// No description provided for @maximize.
  ///
  /// In zh, this message translates to:
  /// **'最大化'**
  String get maximize;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @rotateClockwise.
  ///
  /// In zh, this message translates to:
  /// **'顺时针旋转'**
  String get rotateClockwise;

  /// No description provided for @flipHorizontally.
  ///
  /// In zh, this message translates to:
  /// **'水平翻转'**
  String get flipHorizontally;

  /// No description provided for @showThumbnails.
  ///
  /// In zh, this message translates to:
  /// **'显示缩略图'**
  String get showThumbnails;

  /// No description provided for @hideThumbnails.
  ///
  /// In zh, this message translates to:
  /// **'隐藏缩略图'**
  String get hideThumbnails;

  /// No description provided for @showInfo.
  ///
  /// In zh, this message translates to:
  /// **'显示信息'**
  String get showInfo;

  /// No description provided for @information.
  ///
  /// In zh, this message translates to:
  /// **'信息'**
  String get information;

  /// No description provided for @hideInfo.
  ///
  /// In zh, this message translates to:
  /// **'隐藏信息'**
  String get hideInfo;

  /// No description provided for @zoomToWindow.
  ///
  /// In zh, this message translates to:
  /// **'适应窗口'**
  String get zoomToWindow;

  /// No description provided for @actualSize.
  ///
  /// In zh, this message translates to:
  /// **'实际大小'**
  String get actualSize;

  /// No description provided for @fullscreen.
  ///
  /// In zh, this message translates to:
  /// **'全屏'**
  String get fullscreen;

  /// No description provided for @enterBorderless.
  ///
  /// In zh, this message translates to:
  /// **'进入无边框模式'**
  String get enterBorderless;

  /// No description provided for @exitBorderless.
  ///
  /// In zh, this message translates to:
  /// **'退出无边框模式'**
  String get exitBorderless;

  /// No description provided for @exitFullscreen.
  ///
  /// In zh, this message translates to:
  /// **'退出全屏'**
  String get exitFullscreen;

  /// No description provided for @zoomOut.
  ///
  /// In zh, this message translates to:
  /// **'缩小'**
  String get zoomOut;

  /// No description provided for @zoomIn.
  ///
  /// In zh, this message translates to:
  /// **'放大'**
  String get zoomIn;

  /// No description provided for @previousImage.
  ///
  /// In zh, this message translates to:
  /// **'上一个'**
  String get previousImage;

  /// No description provided for @nextImage.
  ///
  /// In zh, this message translates to:
  /// **'下一个'**
  String get nextImage;

  /// No description provided for @closeInfoPanel.
  ///
  /// In zh, this message translates to:
  /// **'关闭信息面板'**
  String get closeInfoPanel;

  /// No description provided for @noImage.
  ///
  /// In zh, this message translates to:
  /// **'暂无图片'**
  String get noImage;

  /// No description provided for @format.
  ///
  /// In zh, this message translates to:
  /// **'格式'**
  String get format;

  /// No description provided for @fileName.
  ///
  /// In zh, this message translates to:
  /// **'文件名'**
  String get fileName;

  /// No description provided for @size.
  ///
  /// In zh, this message translates to:
  /// **'大小'**
  String get size;

  /// No description provided for @modifiedTime.
  ///
  /// In zh, this message translates to:
  /// **'修改时间'**
  String get modifiedTime;

  /// No description provided for @dimensions.
  ///
  /// In zh, this message translates to:
  /// **'尺寸'**
  String get dimensions;

  /// No description provided for @orientation.
  ///
  /// In zh, this message translates to:
  /// **'方向'**
  String get orientation;

  /// No description provided for @path.
  ///
  /// In zh, this message translates to:
  /// **'路径'**
  String get path;

  /// No description provided for @additionalMetadata.
  ///
  /// In zh, this message translates to:
  /// **'附加元数据'**
  String get additionalMetadata;

  /// No description provided for @readingDimensionsFailed.
  ///
  /// In zh, this message translates to:
  /// **'尺寸 / 方向读取失败'**
  String get readingDimensionsFailed;

  /// No description provided for @readingDimensions.
  ///
  /// In zh, this message translates to:
  /// **'正在读取尺寸 / 方向…'**
  String get readingDimensions;

  /// No description provided for @readingMetadataFailed.
  ///
  /// In zh, this message translates to:
  /// **'元数据读取失败'**
  String get readingMetadataFailed;

  /// No description provided for @unreadableImageMetadata.
  ///
  /// In zh, this message translates to:
  /// **'无法读取图片元数据'**
  String get unreadableImageMetadata;

  /// No description provided for @imageProperties.
  ///
  /// In zh, this message translates to:
  /// **'图像属性'**
  String get imageProperties;

  /// No description provided for @basicInformation.
  ///
  /// In zh, this message translates to:
  /// **'基本信息'**
  String get basicInformation;

  /// No description provided for @renameFile.
  ///
  /// In zh, this message translates to:
  /// **'重命名文件'**
  String get renameFile;

  /// No description provided for @rename.
  ///
  /// In zh, this message translates to:
  /// **'重命名'**
  String get rename;

  /// No description provided for @renameUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前文件无法编辑'**
  String get renameUnavailable;

  /// No description provided for @renameTargetExists.
  ///
  /// In zh, this message translates to:
  /// **'目标文件已存在'**
  String get renameTargetExists;

  /// No description provided for @invalidFileName.
  ///
  /// In zh, this message translates to:
  /// **'文件名无效'**
  String get invalidFileName;

  /// No description provided for @animationInformation.
  ///
  /// In zh, this message translates to:
  /// **'动画信息'**
  String get animationInformation;

  /// No description provided for @frames.
  ///
  /// In zh, this message translates to:
  /// **'帧数'**
  String get frames;

  /// No description provided for @frameRate.
  ///
  /// In zh, this message translates to:
  /// **'帧率'**
  String get frameRate;

  /// No description provided for @duration.
  ///
  /// In zh, this message translates to:
  /// **'总时长'**
  String get duration;

  /// No description provided for @loopCount.
  ///
  /// In zh, this message translates to:
  /// **'循环'**
  String get loopCount;

  /// No description provided for @infiniteLoop.
  ///
  /// In zh, this message translates to:
  /// **'循环'**
  String get infiniteLoop;

  /// No description provided for @playCount.
  ///
  /// In zh, this message translates to:
  /// **'播放 {value} 次'**
  String playCount(Object value);

  /// No description provided for @cameraInformation.
  ///
  /// In zh, this message translates to:
  /// **'相机信息'**
  String get cameraInformation;

  /// No description provided for @captureTime.
  ///
  /// In zh, this message translates to:
  /// **'拍摄时间'**
  String get captureTime;

  /// No description provided for @photoTitle.
  ///
  /// In zh, this message translates to:
  /// **'标题'**
  String get photoTitle;

  /// No description provided for @photoDescription.
  ///
  /// In zh, this message translates to:
  /// **'描述'**
  String get photoDescription;

  /// No description provided for @photoCreator.
  ///
  /// In zh, this message translates to:
  /// **'作者'**
  String get photoCreator;

  /// No description provided for @photoCopyright.
  ///
  /// In zh, this message translates to:
  /// **'版权'**
  String get photoCopyright;

  /// No description provided for @photoRating.
  ///
  /// In zh, this message translates to:
  /// **'评分'**
  String get photoRating;

  /// No description provided for @photoKeywords.
  ///
  /// In zh, this message translates to:
  /// **'关键词'**
  String get photoKeywords;

  /// No description provided for @photoRejected.
  ///
  /// In zh, this message translates to:
  /// **'已拒绝'**
  String get photoRejected;

  /// No description provided for @photoAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动'**
  String get photoAuto;

  /// No description provided for @photoManual.
  ///
  /// In zh, this message translates to:
  /// **'手动'**
  String get photoManual;

  /// No description provided for @flashFired.
  ///
  /// In zh, this message translates to:
  /// **'已闪光'**
  String get flashFired;

  /// No description provided for @flashNotFired.
  ///
  /// In zh, this message translates to:
  /// **'未闪光'**
  String get flashNotFired;

  /// No description provided for @flashUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'无闪光灯'**
  String get flashUnavailable;

  /// No description provided for @flashRedEye.
  ///
  /// In zh, this message translates to:
  /// **'防红眼'**
  String get flashRedEye;

  /// No description provided for @device.
  ///
  /// In zh, this message translates to:
  /// **'拍摄设备'**
  String get device;

  /// No description provided for @lens.
  ///
  /// In zh, this message translates to:
  /// **'镜头'**
  String get lens;

  /// No description provided for @aperture.
  ///
  /// In zh, this message translates to:
  /// **'光圈'**
  String get aperture;

  /// No description provided for @shutterSpeed.
  ///
  /// In zh, this message translates to:
  /// **'快门速度'**
  String get shutterSpeed;

  /// No description provided for @iso.
  ///
  /// In zh, this message translates to:
  /// **'ISO'**
  String get iso;

  /// No description provided for @focalLength.
  ///
  /// In zh, this message translates to:
  /// **'焦距'**
  String get focalLength;

  /// No description provided for @exposureCompensation.
  ///
  /// In zh, this message translates to:
  /// **'曝光补偿'**
  String get exposureCompensation;

  /// No description provided for @whiteBalance.
  ///
  /// In zh, this message translates to:
  /// **'白平衡'**
  String get whiteBalance;

  /// No description provided for @flash.
  ///
  /// In zh, this message translates to:
  /// **'闪光灯'**
  String get flash;

  /// No description provided for @location.
  ///
  /// In zh, this message translates to:
  /// **'位置信息'**
  String get location;

  /// No description provided for @codec.
  ///
  /// In zh, this message translates to:
  /// **'编解码器'**
  String get codec;

  /// No description provided for @colorSpace.
  ///
  /// In zh, this message translates to:
  /// **'色彩空间'**
  String get colorSpace;

  /// No description provided for @colorDepth.
  ///
  /// In zh, this message translates to:
  /// **'色彩深度'**
  String get colorDepth;

  /// No description provided for @alphaChannel.
  ///
  /// In zh, this message translates to:
  /// **'透明度'**
  String get alphaChannel;

  /// No description provided for @hasAlpha.
  ///
  /// In zh, this message translates to:
  /// **'包含 Alpha 通道'**
  String get hasAlpha;

  /// No description provided for @opaque.
  ///
  /// In zh, this message translates to:
  /// **'不透明'**
  String get opaque;

  /// No description provided for @vectorInformation.
  ///
  /// In zh, this message translates to:
  /// **'矢量信息'**
  String get vectorInformation;

  /// No description provided for @physicalSize.
  ///
  /// In zh, this message translates to:
  /// **'物理尺寸'**
  String get physicalSize;

  /// No description provided for @viewBox.
  ///
  /// In zh, this message translates to:
  /// **'ViewBox'**
  String get viewBox;

  /// No description provided for @nodeCount.
  ///
  /// In zh, this message translates to:
  /// **'节点数量'**
  String get nodeCount;

  /// No description provided for @orientationNormal.
  ///
  /// In zh, this message translates to:
  /// **'正常（方向 1）'**
  String get orientationNormal;

  /// No description provided for @orientationHorizontalMirror.
  ///
  /// In zh, this message translates to:
  /// **'水平镜像（方向 2）'**
  String get orientationHorizontalMirror;

  /// No description provided for @orientationRotate180.
  ///
  /// In zh, this message translates to:
  /// **'旋转 180°（方向 3）'**
  String get orientationRotate180;

  /// No description provided for @orientationVerticalMirror.
  ///
  /// In zh, this message translates to:
  /// **'垂直镜像（方向 4）'**
  String get orientationVerticalMirror;

  /// No description provided for @orientationMirrorRotate270.
  ///
  /// In zh, this message translates to:
  /// **'镜像并旋转 270°（方向 5）'**
  String get orientationMirrorRotate270;

  /// No description provided for @orientationRotate90.
  ///
  /// In zh, this message translates to:
  /// **'旋转 90°（方向 6）'**
  String get orientationRotate90;

  /// No description provided for @orientationMirrorRotate90.
  ///
  /// In zh, this message translates to:
  /// **'镜像并旋转 90°（方向 7）'**
  String get orientationMirrorRotate90;

  /// No description provided for @orientationRotate270.
  ///
  /// In zh, this message translates to:
  /// **'旋转 270°（方向 8）'**
  String get orientationRotate270;

  /// No description provided for @orientationUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知（方向 {value}）'**
  String orientationUnknown(Object value);

  /// No description provided for @selectContainer.
  ///
  /// In zh, this message translates to:
  /// **'选择文件夹或压缩包，开始阅读漫画'**
  String get selectContainer;

  /// No description provided for @cannotDecodeAnimatedImage.
  ///
  /// In zh, this message translates to:
  /// **'无法解码动图'**
  String get cannotDecodeAnimatedImage;

  /// No description provided for @imageParseFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法解析 {name}'**
  String imageParseFailed(Object name);

  /// No description provided for @printPreviewFailed.
  ///
  /// In zh, this message translates to:
  /// **'打印预览失败：{error}'**
  String printPreviewFailed(Object error);

  /// No description provided for @printFailed.
  ///
  /// In zh, this message translates to:
  /// **'打印失败：{error}'**
  String printFailed(Object error);

  /// No description provided for @parsingCapabilities.
  ///
  /// In zh, this message translates to:
  /// **'支持的图片格式'**
  String get parsingCapabilities;

  /// No description provided for @acknowledge.
  ///
  /// In zh, this message translates to:
  /// **'知道了'**
  String get acknowledge;

  /// No description provided for @deleteCurrentImageQuestion.
  ///
  /// In zh, this message translates to:
  /// **'删除图片'**
  String get deleteCurrentImageQuestion;

  /// No description provided for @deleteCurrentImageDescription.
  ///
  /// In zh, this message translates to:
  /// **'删除“{name}”后，文件将被移入回收站。'**
  String deleteCurrentImageDescription(Object name);

  /// No description provided for @moveToRecycleBin.
  ///
  /// In zh, this message translates to:
  /// **'移入回收站'**
  String get moveToRecycleBin;

  /// No description provided for @deleteFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法移入回收站'**
  String get deleteFailed;

  /// No description provided for @printPreview.
  ///
  /// In zh, this message translates to:
  /// **'打印预览'**
  String get printPreview;

  /// No description provided for @customMarginLabel.
  ///
  /// In zh, this message translates to:
  /// **'自定义页边距'**
  String get customMarginLabel;

  /// No description provided for @printer.
  ///
  /// In zh, this message translates to:
  /// **'打印机'**
  String get printer;

  /// No description provided for @defaultPrinter.
  ///
  /// In zh, this message translates to:
  /// **'默认打印机'**
  String get defaultPrinter;

  /// No description provided for @readingPrinters.
  ///
  /// In zh, this message translates to:
  /// **'正在读取打印机…'**
  String get readingPrinters;

  /// No description provided for @printerListUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'打印机列表不可用'**
  String get printerListUnavailable;

  /// No description provided for @portrait.
  ///
  /// In zh, this message translates to:
  /// **'纵向'**
  String get portrait;

  /// No description provided for @landscape.
  ///
  /// In zh, this message translates to:
  /// **'横向'**
  String get landscape;

  /// No description provided for @paperSize.
  ///
  /// In zh, this message translates to:
  /// **'纸张大小'**
  String get paperSize;

  /// No description provided for @margins.
  ///
  /// In zh, this message translates to:
  /// **'页边距'**
  String get margins;

  /// No description provided for @customMarginHint.
  ///
  /// In zh, this message translates to:
  /// **'0 到 50 mm，最多 1 位小数'**
  String get customMarginHint;

  /// No description provided for @customMarginInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入 0 到 50 之间的数字。'**
  String get customMarginInvalid;

  /// No description provided for @noMargin.
  ///
  /// In zh, this message translates to:
  /// **'无'**
  String get noMargin;

  /// No description provided for @narrowMargin.
  ///
  /// In zh, this message translates to:
  /// **'最小'**
  String get narrowMargin;

  /// No description provided for @normalMargin.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get normalMargin;

  /// No description provided for @fitMode.
  ///
  /// In zh, this message translates to:
  /// **'适应方式'**
  String get fitMode;

  /// No description provided for @fitPage.
  ///
  /// In zh, this message translates to:
  /// **'适应页面'**
  String get fitPage;

  /// No description provided for @fillPage.
  ///
  /// In zh, this message translates to:
  /// **'填充页面'**
  String get fillPage;

  /// No description provided for @fitPageDescription.
  ///
  /// In zh, this message translates to:
  /// **'完整显示图片并保持比例，部分区域可能留白。'**
  String get fitPageDescription;

  /// No description provided for @fillPageDescription.
  ///
  /// In zh, this message translates to:
  /// **'按比例铺满可打印区域，边缘可能被裁切。'**
  String get fillPageDescription;

  /// No description provided for @actualSizeDescription.
  ///
  /// In zh, this message translates to:
  /// **'按图片原始尺寸打印，可能超出可打印区域。'**
  String get actualSizeDescription;

  /// No description provided for @printAction.
  ///
  /// In zh, this message translates to:
  /// **'打印'**
  String get printAction;

  /// No description provided for @play.
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get pause;

  /// No description provided for @archiveFormat.
  ///
  /// In zh, this message translates to:
  /// **'压缩包'**
  String get archiveFormat;

  /// No description provided for @unknownFormat.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get unknownFormat;

  /// No description provided for @bytes.
  ///
  /// In zh, this message translates to:
  /// **'{value}'**
  String bytes(Object value);

  /// No description provided for @decoderFlutterCodec.
  ///
  /// In zh, this message translates to:
  /// **'Flutter 编解码器'**
  String get decoderFlutterCodec;

  /// No description provided for @decoderDartImageSvg.
  ///
  /// In zh, this message translates to:
  /// **'Dart image / SVG 渲染器'**
  String get decoderDartImageSvg;

  /// No description provided for @decoderArchive.
  ///
  /// In zh, this message translates to:
  /// **'7-Zip 原生引擎；按需读取'**
  String get decoderArchive;

  /// No description provided for @decoderImageMagickJxl.
  ///
  /// In zh, this message translates to:
  /// **'ImageMagick（JPEG XL）'**
  String get decoderImageMagickJxl;

  /// No description provided for @decoderWindowsWic.
  ///
  /// In zh, this message translates to:
  /// **'Windows WIC → ImageMagick 回退'**
  String get decoderWindowsWic;

  /// No description provided for @decoderMacImageIo.
  ///
  /// In zh, this message translates to:
  /// **'macOS Image I/O → ImageMagick 回退'**
  String get decoderMacImageIo;

  /// No description provided for @decoderImageMagickFallback.
  ///
  /// In zh, this message translates to:
  /// **'ImageMagick 回退'**
  String get decoderImageMagickFallback;

  /// No description provided for @decoderUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'未注册解码器'**
  String get decoderUnavailable;

  /// No description provided for @invalidPngApng.
  ///
  /// In zh, this message translates to:
  /// **'不是有效的 PNG/APNG 文件'**
  String get invalidPngApng;

  /// No description provided for @archiveLimitExceeded.
  ///
  /// In zh, this message translates to:
  /// **'压缩包超过安全处理限制'**
  String get archiveLimitExceeded;

  /// No description provided for @archiveTimeout.
  ///
  /// In zh, this message translates to:
  /// **'压缩包处理超时'**
  String get archiveTimeout;

  /// No description provided for @sevenZipMissing.
  ///
  /// In zh, this message translates to:
  /// **'归档读取组件不可用，请重新安装完整发行包后重试'**
  String get sevenZipMissing;

  /// No description provided for @unsafeArchivePath.
  ///
  /// In zh, this message translates to:
  /// **'压缩包包含越界路径或链接'**
  String get unsafeArchivePath;

  /// No description provided for @archiveOpening.
  ///
  /// In zh, this message translates to:
  /// **'打开中…'**
  String get archiveOpening;

  /// No description provided for @archiveEmpty.
  ///
  /// In zh, this message translates to:
  /// **'压缩包内没有可浏览的图片'**
  String get archiveEmpty;

  /// No description provided for @archiveEncrypted.
  ///
  /// In zh, this message translates to:
  /// **'压缩包需要密码，请输入密码后重试'**
  String get archiveEncrypted;

  /// No description provided for @archiveCorrupt.
  ///
  /// In zh, this message translates to:
  /// **'压缩包已损坏或使用了不支持的压缩算法'**
  String get archiveCorrupt;

  /// No description provided for @archiveUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'压缩包格式不受支持'**
  String get archiveUnsupported;

  /// No description provided for @archiveIoError.
  ///
  /// In zh, this message translates to:
  /// **'无法读取压缩包，请检查文件权限或磁盘空间'**
  String get archiveIoError;

  /// No description provided for @archiveRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get archiveRetry;

  /// No description provided for @showInExplorer.
  ///
  /// In zh, this message translates to:
  /// **'在资源管理器中显示'**
  String get showInExplorer;

  /// No description provided for @archiveReadOnly.
  ///
  /// In zh, this message translates to:
  /// **'压缩包内为只读浏览'**
  String get archiveReadOnly;

  /// No description provided for @clipboardUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前平台暂不支持复制到系统剪贴板'**
  String get clipboardUnavailable;

  /// No description provided for @recycleBinUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前平台暂不支持回收站'**
  String get recycleBinUnavailable;

  /// No description provided for @pixelReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取图片像素'**
  String get pixelReadFailed;

  /// No description provided for @animatedReadLimit.
  ///
  /// In zh, this message translates to:
  /// **'动图超过文件读取限制'**
  String get animatedReadLimit;

  /// No description provided for @imageReadLimit.
  ///
  /// In zh, this message translates to:
  /// **'图片文件超过读取限制，请使用长图模式或较小的图片'**
  String get imageReadLimit;

  /// No description provided for @decoderUnavailableError.
  ///
  /// In zh, this message translates to:
  /// **'扩展解码器不可用，请重新安装完整发行包或设置 SHENVIEW_MAGICK'**
  String get decoderUnavailableError;

  /// No description provided for @decodeTimeout.
  ///
  /// In zh, this message translates to:
  /// **'图片解析超时，可以重试或切换下一张'**
  String get decodeTimeout;

  /// No description provided for @decodeMemoryLimit.
  ///
  /// In zh, this message translates to:
  /// **'图片超过解码内存限制，请使用适应窗口或长图模式'**
  String get decodeMemoryLimit;

  /// No description provided for @decodeFailed.
  ///
  /// In zh, this message translates to:
  /// **'解析失败：{error}'**
  String decodeFailed(Object error);

  /// No description provided for @archiveSettings.
  ///
  /// In zh, this message translates to:
  /// **'压缩包'**
  String get archiveSettings;

  /// No description provided for @archiveSettingsDescription.
  ///
  /// In zh, this message translates to:
  /// **'章节与换包、预加载、内存与磁盘缓存。'**
  String get archiveSettingsDescription;

  /// No description provided for @archiveReading.
  ///
  /// In zh, this message translates to:
  /// **'包内阅读'**
  String get archiveReading;

  /// No description provided for @archiveContinuousReading.
  ///
  /// In zh, this message translates to:
  /// **'跨章节连续浏览'**
  String get archiveContinuousReading;

  /// No description provided for @archiveContinuousReadingDescription.
  ///
  /// In zh, this message translates to:
  /// **'将压缩包内各章节的图片合并为一个浏览列表。关闭后只浏览当前章节。'**
  String get archiveContinuousReadingDescription;

  /// No description provided for @directoryImages.
  ///
  /// In zh, this message translates to:
  /// **'本目录图片'**
  String get directoryImages;

  /// No description provided for @chapterDirectory.
  ///
  /// In zh, this message translates to:
  /// **'章节目录'**
  String get chapterDirectory;

  /// No description provided for @browseDirectory.
  ///
  /// In zh, this message translates to:
  /// **'浏览目录'**
  String get browseDirectory;

  /// No description provided for @showDirectoryPanel.
  ///
  /// In zh, this message translates to:
  /// **'展开目录面板'**
  String get showDirectoryPanel;

  /// No description provided for @hideDirectoryPanel.
  ///
  /// In zh, this message translates to:
  /// **'收起目录面板'**
  String get hideDirectoryPanel;

  /// No description provided for @chooseLocation.
  ///
  /// In zh, this message translates to:
  /// **'选择目录或压缩包'**
  String get chooseLocation;

  /// No description provided for @previousLocation.
  ///
  /// In zh, this message translates to:
  /// **'上一项'**
  String get previousLocation;

  /// No description provided for @nextLocation.
  ///
  /// In zh, this message translates to:
  /// **'下一项'**
  String get nextLocation;

  /// No description provided for @chooseChapter.
  ///
  /// In zh, this message translates to:
  /// **'选择章节'**
  String get chooseChapter;

  /// No description provided for @previousChapter.
  ///
  /// In zh, this message translates to:
  /// **'上一章'**
  String get previousChapter;

  /// No description provided for @nextChapter.
  ///
  /// In zh, this message translates to:
  /// **'下一章'**
  String get nextChapter;

  /// No description provided for @directoryNavigationVisible.
  ///
  /// In zh, this message translates to:
  /// **'显示目录导航'**
  String get directoryNavigationVisible;

  /// No description provided for @directoryNavigationVisibleDescription.
  ///
  /// In zh, this message translates to:
  /// **'显示左侧目录面板，也可通过状态栏切换。“外观”和“浏览”中的此设置同步生效。'**
  String get directoryNavigationVisibleDescription;

  /// No description provided for @pinDirectory.
  ///
  /// In zh, this message translates to:
  /// **'固定目录栏'**
  String get pinDirectory;

  /// No description provided for @pinDirectoryDescription.
  ///
  /// In zh, this message translates to:
  /// **'将目录面板停靠在左侧，没有子目录或尚未打开内容时仍保留。拖动右边缘可调整宽度；取消固定后浮动显示。'**
  String get pinDirectoryDescription;

  /// No description provided for @directoryNotOpened.
  ///
  /// In zh, this message translates to:
  /// **'尚未打开文件夹'**
  String get directoryNotOpened;

  /// No description provided for @directoryNotOpenedDescription.
  ///
  /// In zh, this message translates to:
  /// **'打开文件夹后，这里将显示目录和压缩包。'**
  String get directoryNotOpenedDescription;

  /// No description provided for @directoryNoChildren.
  ///
  /// In zh, this message translates to:
  /// **'没有子文件夹或压缩包。'**
  String get directoryNoChildren;

  /// No description provided for @resizeDirectoryPanel.
  ///
  /// In zh, this message translates to:
  /// **'拖动调整宽度，双击恢复默认；Esc 取消拖动，左右键微调，{undoShortcut} 撤销'**
  String resizeDirectoryPanel(String undoShortcut);

  /// No description provided for @unpinDirectory.
  ///
  /// In zh, this message translates to:
  /// **'取消固定目录面板'**
  String get unpinDirectory;

  /// No description provided for @searchDirectory.
  ///
  /// In zh, this message translates to:
  /// **'搜索目录与章节'**
  String get searchDirectory;

  /// No description provided for @clearDirectorySearch.
  ///
  /// In zh, this message translates to:
  /// **'清除目录搜索'**
  String get clearDirectorySearch;

  /// No description provided for @noMatchingDirectory.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的目录或章节'**
  String get noMatchingDirectory;

  /// No description provided for @directoryReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'部分目录读取失败，请重新展开重试。'**
  String get directoryReadFailed;

  /// No description provided for @archiveAutoAdvance.
  ///
  /// In zh, this message translates to:
  /// **'首尾翻页切换相邻压缩包'**
  String get archiveAutoAdvance;

  /// No description provided for @archiveAutoAdvanceDescription.
  ///
  /// In zh, this message translates to:
  /// **'从文件夹打开压缩包后，在末页继续向后翻可打开下一压缩包，在首页继续向前翻可打开上一压缩包。仅切换同一文件夹中的压缩包。'**
  String get archiveAutoAdvanceDescription;

  /// No description provided for @archiveSortOrder.
  ///
  /// In zh, this message translates to:
  /// **'包内排序'**
  String get archiveSortOrder;

  /// No description provided for @archiveSortDescription.
  ///
  /// In zh, this message translates to:
  /// **'查看顺序独立于普通目录；文件名排序规则与“浏览”设置一致。'**
  String get archiveSortDescription;

  /// No description provided for @archivePrefetchMode.
  ///
  /// In zh, this message translates to:
  /// **'预加载'**
  String get archivePrefetchMode;

  /// No description provided for @archivePrefetchDescription.
  ///
  /// In zh, this message translates to:
  /// **'提前准备当前查看方式即将显示的图片，资源不足时自动减少或暂停。'**
  String get archivePrefetchDescription;

  /// No description provided for @archivePrefetchAutomatic.
  ///
  /// In zh, this message translates to:
  /// **'自动'**
  String get archivePrefetchAutomatic;

  /// No description provided for @archivePrefetchConservative.
  ///
  /// In zh, this message translates to:
  /// **'保守'**
  String get archivePrefetchConservative;

  /// No description provided for @archivePrefetchOff.
  ///
  /// In zh, this message translates to:
  /// **'关闭预加载'**
  String get archivePrefetchOff;

  /// No description provided for @archiveMemoryBudget.
  ///
  /// In zh, this message translates to:
  /// **'压缩包图片内存上限'**
  String get archiveMemoryBudget;

  /// No description provided for @archiveMemoryDescription.
  ///
  /// In zh, this message translates to:
  /// **'根据可用内存自动调整，也可手动设为 32 到 1024 MiB。资源不足时会降低实际用量。'**
  String get archiveMemoryDescription;

  /// No description provided for @archiveBudgetAutomatic.
  ///
  /// In zh, this message translates to:
  /// **'自动（推荐）'**
  String get archiveBudgetAutomatic;

  /// No description provided for @archiveBudgetCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get archiveBudgetCustom;

  /// No description provided for @archiveMemoryInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入 32 到 1024 之间的整数。'**
  String get archiveMemoryInvalid;

  /// No description provided for @archiveCache.
  ///
  /// In zh, this message translates to:
  /// **'磁盘缓存'**
  String get archiveCache;

  /// No description provided for @archivePersistCache.
  ///
  /// In zh, this message translates to:
  /// **'保留普通包缓存'**
  String get archivePersistCache;

  /// No description provided for @archivePersistDescription.
  ///
  /// In zh, this message translates to:
  /// **'在容量和保留期限内缓存未加密的压缩包。加密压缩包的缓存会在关闭后清理，密码不会保存。'**
  String get archivePersistDescription;

  /// No description provided for @archiveDiskBudget.
  ///
  /// In zh, this message translates to:
  /// **'缓存容量上限'**
  String get archiveDiskBudget;

  /// No description provided for @archiveDiskDescription.
  ///
  /// In zh, this message translates to:
  /// **'所有压缩包共用此容量上限。正在使用的缓存会在使用结束后清理。'**
  String get archiveDiskDescription;

  /// No description provided for @archiveRetention.
  ///
  /// In zh, this message translates to:
  /// **'保留期限'**
  String get archiveRetention;

  /// No description provided for @archiveRetentionDescription.
  ///
  /// In zh, this message translates to:
  /// **'超过期限或已经失效的缓存会自动清理。'**
  String get archiveRetentionDescription;

  /// No description provided for @archiveRetentionDay.
  ///
  /// In zh, this message translates to:
  /// **'天'**
  String get archiveRetentionDay;

  /// No description provided for @archiveCacheUsage.
  ///
  /// In zh, this message translates to:
  /// **'已用缓存'**
  String get archiveCacheUsage;

  /// No description provided for @archiveCacheUnknown.
  ///
  /// In zh, this message translates to:
  /// **'正在统计…'**
  String get archiveCacheUnknown;

  /// No description provided for @archiveClearCache.
  ///
  /// In zh, this message translates to:
  /// **'清理缓存'**
  String get archiveClearCache;

  /// No description provided for @archiveCacheClearFailed.
  ///
  /// In zh, this message translates to:
  /// **'缓存清理失败，请重试。'**
  String get archiveCacheClearFailed;

  /// No description provided for @archiveCacheCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清理未使用的缓存，其余缓存会在使用结束后清理。'**
  String get archiveCacheCleared;

  /// No description provided for @archivePasswordTitle.
  ///
  /// In zh, this message translates to:
  /// **'输入压缩包密码'**
  String get archivePasswordTitle;

  /// No description provided for @archivePasswordHint.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get archivePasswordHint;

  /// No description provided for @archivePasswordDescription.
  ///
  /// In zh, this message translates to:
  /// **'密码仅用于本次会话，不会保存。'**
  String get archivePasswordDescription;

  /// No description provided for @archivePasswordShow.
  ///
  /// In zh, this message translates to:
  /// **'显示密码'**
  String get archivePasswordShow;

  /// No description provided for @archivePasswordHide.
  ///
  /// In zh, this message translates to:
  /// **'隐藏密码'**
  String get archivePasswordHide;

  /// No description provided for @archivePasswordOpen.
  ///
  /// In zh, this message translates to:
  /// **'打开'**
  String get archivePasswordOpen;

  /// No description provided for @archivePasswordWrong.
  ///
  /// In zh, this message translates to:
  /// **'密码不正确，请重新输入。'**
  String get archivePasswordWrong;

  /// No description provided for @archivePasswordUnverified.
  ///
  /// In zh, this message translates to:
  /// **'无法验证密码或数据，请检查密码，或重新获取一份压缩包。'**
  String get archivePasswordUnverified;

  /// No description provided for @archivePasswordUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'此加密方式暂不受支持，请先解密后打开。'**
  String get archivePasswordUnsupported;

  /// No description provided for @archiveReadingDirectory.
  ///
  /// In zh, this message translates to:
  /// **'正在读取目录…'**
  String get archiveReadingDirectory;

  /// No description provided for @archivePreparingPage.
  ///
  /// In zh, this message translates to:
  /// **'正在准备图片…'**
  String get archivePreparingPage;

  /// No description provided for @archiveCancelOpening.
  ///
  /// In zh, this message translates to:
  /// **'取消打开'**
  String get archiveCancelOpening;

  /// No description provided for @archiveRetryPage.
  ///
  /// In zh, this message translates to:
  /// **'重试此页'**
  String get archiveRetryPage;

  /// No description provided for @archivePerformanceNormal.
  ///
  /// In zh, this message translates to:
  /// **'正常：按方向和距离预加载'**
  String get archivePerformanceNormal;

  /// No description provided for @archivePerformanceConservative.
  ///
  /// In zh, this message translates to:
  /// **'保守：仅保留邻近页'**
  String get archivePerformanceConservative;

  /// No description provided for @archivePerformanceOnDemand.
  ///
  /// In zh, this message translates to:
  /// **'按需：仅准备当前可见内容'**
  String get archivePerformanceOnDemand;

  /// No description provided for @archiveSourceChanged.
  ///
  /// In zh, this message translates to:
  /// **'压缩包已更改，请重新打开。'**
  String get archiveSourceChanged;

  /// No description provided for @archiveVolumeMissing.
  ///
  /// In zh, this message translates to:
  /// **'压缩包需要其他分卷，请补齐分卷后重新打开。'**
  String get archiveVolumeMissing;

  /// No description provided for @archiveResourceInsufficient.
  ///
  /// In zh, this message translates to:
  /// **'可用资源不足，请关闭其他图片或清理缓存后重试。'**
  String get archiveResourceInsufficient;

  /// No description provided for @archiveBrowseContainers.
  ///
  /// In zh, this message translates to:
  /// **'此处没有图片，可进入章节或子压缩包继续浏览。'**
  String get archiveBrowseContainers;

  /// No description provided for @saveOriginalImage.
  ///
  /// In zh, this message translates to:
  /// **'另存为'**
  String get saveOriginalImage;

  /// No description provided for @animationControls.
  ///
  /// In zh, this message translates to:
  /// **'动图播放控制'**
  String get animationControls;

  /// No description provided for @previousFrame.
  ///
  /// In zh, this message translates to:
  /// **'上一帧'**
  String get previousFrame;

  /// No description provided for @nextFrame.
  ///
  /// In zh, this message translates to:
  /// **'下一帧'**
  String get nextFrame;

  /// No description provided for @animationProgress.
  ///
  /// In zh, this message translates to:
  /// **'播放进度'**
  String get animationProgress;

  /// No description provided for @animationSpeed.
  ///
  /// In zh, this message translates to:
  /// **'播放速度'**
  String get animationSpeed;

  /// No description provided for @animationRestart.
  ///
  /// In zh, this message translates to:
  /// **'从头播放'**
  String get animationRestart;

  /// No description provided for @animationLoopFile.
  ///
  /// In zh, this message translates to:
  /// **'遵循文件'**
  String get animationLoopFile;

  /// No description provided for @animationLoopInfinite.
  ///
  /// In zh, this message translates to:
  /// **'无限循环'**
  String get animationLoopInfinite;

  /// No description provided for @animationLoopOnce.
  ///
  /// In zh, this message translates to:
  /// **'播放一次'**
  String get animationLoopOnce;

  /// No description provided for @animationLoopMode.
  ///
  /// In zh, this message translates to:
  /// **'循环方式'**
  String get animationLoopMode;

  /// No description provided for @animationAutoPlay.
  ///
  /// In zh, this message translates to:
  /// **'打开动图时自动播放'**
  String get animationAutoPlay;

  /// No description provided for @animationAutoPlayDescription.
  ///
  /// In zh, this message translates to:
  /// **'打开动图时自动播放；关闭后停在首帧。'**
  String get animationAutoPlayDescription;

  /// No description provided for @animationDefaultLoopDescription.
  ///
  /// In zh, this message translates to:
  /// **'打开动图时使用此循环方式，可在播放条中临时调整。'**
  String get animationDefaultLoopDescription;

  /// No description provided for @animationDefaultSpeed.
  ///
  /// In zh, this message translates to:
  /// **'默认播放倍速'**
  String get animationDefaultSpeed;

  /// No description provided for @animationDefaultSpeedDescription.
  ///
  /// In zh, this message translates to:
  /// **'打开动图时使用此倍速，播放条中的调整仅用于当前动图。'**
  String get animationDefaultSpeedDescription;

  /// No description provided for @animationControlsDisplay.
  ///
  /// In zh, this message translates to:
  /// **'播放条显示方式'**
  String get animationControlsDisplay;

  /// No description provided for @animationControlsDisplayDescription.
  ///
  /// In zh, this message translates to:
  /// **'选择自动隐藏后，播放中 2 秒无操作会隐藏播放条，鼠标移到画面底部即可显示。隐藏后仍可按空格播放或暂停。'**
  String get animationControlsDisplayDescription;

  /// No description provided for @animationControlsAutoHide.
  ///
  /// In zh, this message translates to:
  /// **'自动隐藏'**
  String get animationControlsAutoHide;

  /// No description provided for @animationControlsAlways.
  ///
  /// In zh, this message translates to:
  /// **'始终显示'**
  String get animationControlsAlways;

  /// No description provided for @animationControlsHidden.
  ///
  /// In zh, this message translates to:
  /// **'隐藏'**
  String get animationControlsHidden;

  /// No description provided for @animationFramePosition.
  ///
  /// In zh, this message translates to:
  /// **'第 {frame} / {count} 帧'**
  String animationFramePosition(int frame, int count);

  /// No description provided for @autoPlayTitle.
  ///
  /// In zh, this message translates to:
  /// **'自动播放'**
  String get autoPlayTitle;

  /// No description provided for @autoPlayStart.
  ///
  /// In zh, this message translates to:
  /// **'开始自动播放'**
  String get autoPlayStart;

  /// No description provided for @autoPlayPause.
  ///
  /// In zh, this message translates to:
  /// **'暂停自动播放'**
  String get autoPlayPause;

  /// No description provided for @autoPlayStop.
  ///
  /// In zh, this message translates to:
  /// **'停止自动播放'**
  String get autoPlayStop;

  /// No description provided for @autoPlayOptions.
  ///
  /// In zh, this message translates to:
  /// **'自动播放设置'**
  String get autoPlayOptions;

  /// No description provided for @autoPlayInterval.
  ///
  /// In zh, this message translates to:
  /// **'播放间隔（秒）'**
  String get autoPlayInterval;

  /// No description provided for @autoPlaySpeed.
  ///
  /// In zh, this message translates to:
  /// **'滚动速度（像素／秒）'**
  String get autoPlaySpeed;

  /// No description provided for @autoPlayLoop.
  ///
  /// In zh, this message translates to:
  /// **'循环播放'**
  String get autoPlayLoop;

  /// No description provided for @autoPlayAnimation.
  ///
  /// In zh, this message translates to:
  /// **'遇到动图'**
  String get autoPlayAnimation;

  /// No description provided for @autoPlayCompleteOnce.
  ///
  /// In zh, this message translates to:
  /// **'至少播放一遍'**
  String get autoPlayCompleteOnce;

  /// No description provided for @autoPlayFixedInterval.
  ///
  /// In zh, this message translates to:
  /// **'按固定间隔切换'**
  String get autoPlayFixedInterval;

  /// No description provided for @autoPlayStay.
  ///
  /// In zh, this message translates to:
  /// **'停留在动图'**
  String get autoPlayStay;

  /// No description provided for @autoPlayWaiting.
  ///
  /// In zh, this message translates to:
  /// **'等待动图播放完成'**
  String get autoPlayWaiting;

  /// No description provided for @autoPlayPaused.
  ///
  /// In zh, this message translates to:
  /// **'已暂停'**
  String get autoPlayPaused;

  /// No description provided for @autoPlayScrolling.
  ///
  /// In zh, this message translates to:
  /// **'自动滚动'**
  String get autoPlayScrolling;

  /// No description provided for @autoPlayScope.
  ///
  /// In zh, this message translates to:
  /// **'当前浏览列表 · 不自动跨目录或压缩包'**
  String get autoPlayScope;

  /// No description provided for @autoPlaySave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get autoPlaySave;

  /// No description provided for @animationLabel.
  ///
  /// In zh, this message translates to:
  /// **'动图'**
  String get animationLabel;

  /// No description provided for @autoPlayAdvancing.
  ///
  /// In zh, this message translates to:
  /// **'自动换图'**
  String get autoPlayAdvancing;

  /// No description provided for @autoPlayCountdown.
  ///
  /// In zh, this message translates to:
  /// **'{seconds} 秒后换图'**
  String autoPlayCountdown(String seconds);

  /// No description provided for @autoPlayScrollRate.
  ///
  /// In zh, this message translates to:
  /// **'{speed} 像素／秒'**
  String autoPlayScrollRate(String speed);

  /// No description provided for @autoPlayInvalidInterval.
  ///
  /// In zh, this message translates to:
  /// **'请输入 0.5 到 3600 之间的数字'**
  String get autoPlayInvalidInterval;

  /// No description provided for @autoPlayIntervalHint.
  ///
  /// In zh, this message translates to:
  /// **'0.5 到 3600 秒，最多 1 位小数'**
  String get autoPlayIntervalHint;

  /// No description provided for @autoPlayInvalidSpeed.
  ///
  /// In zh, this message translates to:
  /// **'请输入 5 到 1000 之间的数字'**
  String get autoPlayInvalidSpeed;

  /// No description provided for @autoPlayStatusDisplay.
  ///
  /// In zh, this message translates to:
  /// **'状态面板显示方式'**
  String get autoPlayStatusDisplay;

  /// No description provided for @autoPlayStatusDisplayDescription.
  ///
  /// In zh, this message translates to:
  /// **'选择自动隐藏后，播放中 2 秒无操作会淡出状态面板，鼠标移到画面右上角即可显示。暂停、键盘聚焦或打开设置时保持可见。'**
  String get autoPlayStatusDisplayDescription;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
