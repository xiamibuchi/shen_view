// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get externalOpen => 'Open with';

  @override
  String get externalOpenChoose => 'Choose another app…';

  @override
  String get externalOpenLoading => 'Loading apps…';

  @override
  String get externalOpenNoApplications => 'No associated apps';

  @override
  String get externalOpenListFailed => 'Could not load apps';

  @override
  String get externalOpenSaveCopy => 'Save a copy to open in another app';

  @override
  String externalOpenFailed(String message) {
    return 'Could not open in another app: $message';
  }

  @override
  String get photoMute => 'Mute';

  @override
  String get photoAudioRetry => 'Audio playback failed. Click to retry.';

  @override
  String get photoUnmute => 'Unmute';

  @override
  String photoAudioTrack(int number) {
    return 'Audio track $number';
  }

  @override
  String get icoVariant => 'Icon variant';

  @override
  String get svgStaticPreview =>
      'Showing a static SVG preview without animation. Fonts and some effects may look different.';

  @override
  String get histogram => 'Histogram';

  @override
  String get histogramLuminance => 'Luminance';

  @override
  String get histogramRgbDescription =>
      'Red, green and blue channel distributions';

  @override
  String get histogramLoading => 'Calculating histogram…';

  @override
  String get histogramUnavailable => 'Histogram is currently unavailable';

  @override
  String get histogramEmpty => 'No visible pixels to analyze';

  @override
  String get histogramRetry => 'Retry';

  @override
  String get histogramRed => 'R';

  @override
  String get histogramGreen => 'G';

  @override
  String get histogramBlue => 'B';

  @override
  String get histogramSampleNote => 'Sampled from the SDR preview';

  @override
  String get histogramAnimationNote =>
      'Sampled from the SDR preview · First animation frame';

  @override
  String get appTitle => 'ShenView';

  @override
  String get appDescription =>
      'ShenView is a desktop image viewer for browsing local pictures and folders. It supports photos, long images and comics stored in archives.';

  @override
  String get settings => 'Settings';

  @override
  String get toolbarMode => 'Toolbar mode';

  @override
  String get toolbarModeDescription =>
      'In Normal mode, the toolbar sits above the content. In Floating mode, it overlays the image.';

  @override
  String get normalMode => 'Normal';

  @override
  String get floatingMode => 'Floating';

  @override
  String get originalSize => 'Actual size';

  @override
  String get sortOrder => 'File sort order';

  @override
  String get sortOrderDescription =>
      'Applies to folders; Folder order follows an open Windows Explorer view when available. Archives use a separate order, defaulting to file name ascending, and do not support Folder order.';

  @override
  String get archiveSortSettings => 'Archive sorting settings';

  @override
  String get archiveSortLink => 'Archives';

  @override
  String get fileNameSortMode => 'File name sorting rule';

  @override
  String get fileNameSortModeDescription =>
      'Applies to folders and archives. Files with the same name before the extension are sorted alphabetically by extension.';

  @override
  String get fileNameSortNatural => 'Natural';

  @override
  String get fileNameSortNaturalTooltip =>
      'Compare numbers in the base filename by value; in ascending order, 2 comes before 10.';

  @override
  String get fileNameSortLexicographic => 'Plain string';

  @override
  String get fileNameSortLexicographicTooltip =>
      'Compare the base filename character by character; in ascending order, 10 comes before 2.';

  @override
  String get recursiveFolderBrowsing => 'Browse subfolders recursively';

  @override
  String get folderContinuousReading => 'Browse subfolders continuously';

  @override
  String get folderContinuousReadingDescription =>
      'Combine images in the opened folder and its subfolders into one list for any viewing mode. Turn off to browse folders separately.';

  @override
  String get recursiveFolderBrowsingDescription =>
      'When off, browse only the current folder. Subfolders and bottom directory navigation are hidden; a pinned directory panel stays visible. When on, scan up to 3 levels, 5,000 images and 1,000 folders.';

  @override
  String get scanUnknownExtensions => 'Scan files with unknown extensions';

  @override
  String get scanUnknownExtensionsDescription =>
      'When off, identify images by extension for faster scanning. When on, also read file headers to find images without a common extension.';

  @override
  String get watchFolderChanges => 'Refresh folder automatically';

  @override
  String get watchFolderChangesDescription =>
      'Refresh the list after file changes in the open folder stop for 2 seconds, and when the window regains focus. Include subfolders when browsing recursively. Turn off to stop watching for file changes.';

  @override
  String scanProgress(int folders, int images) {
    return 'Scanning… $folders folders / $images images';
  }

  @override
  String scanSkippedFolders(int count) {
    return '$count folders could not be read';
  }

  @override
  String get emptyFolder => 'No images in this folder';

  @override
  String get emptyRecursiveFolder =>
      'No images in this folder or its subfolders';

  @override
  String get showThumbnailFileNames => 'Show thumbnail file names';

  @override
  String get showThumbnailFileNamesDescription =>
      'When off, hide file names below thumbnails. Selection and accessibility labels stay unchanged.';

  @override
  String get showBottomBar => 'Show bottom bar';

  @override
  String get showBottomBarDescription =>
      'Show image information, zoom and fullscreen controls at the bottom. Turning this off leaves thumbnail strip visibility unchanged.';

  @override
  String get readingDirection => 'Reading direction';

  @override
  String get leftToRight => 'Left to right';

  @override
  String get rightToLeftManga => 'Right to left';

  @override
  String get comicLayoutDirection => 'Continuous layout direction';

  @override
  String get verticalContinuous => 'Vertical continuous';

  @override
  String get horizontalLeftToRight => 'Left to right';

  @override
  String get horizontalRightToLeft => 'Right to left';

  @override
  String get doublePageCoverAlone => 'Show the cover alone in double-page mode';

  @override
  String get comicPageGap => 'Continuous page spacing';

  @override
  String get comicGapNone => 'None';

  @override
  String get comicGapTight => 'Tight';

  @override
  String get comicGapStandard => 'Standard';

  @override
  String get comicGapLoose => 'Loose';

  @override
  String get comicGapCustom => 'Custom';

  @override
  String get defaultOption => 'Default';

  @override
  String get selectImageOrComic => 'Select an image or comic';

  @override
  String get selectImageFolder => 'Select an image folder';

  @override
  String get dropToOpen => 'Release to open an image, folder, or comic';

  @override
  String get parentFolder => 'Parent folder';

  @override
  String get recursiveScanLimit =>
      'The recursive scan safety limit has been reached';

  @override
  String get folderNotOpened => 'No folder opened';

  @override
  String get language => 'Language';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'Follow system';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get systemLanguage => 'Follow system';

  @override
  String get simplifiedChinese => '简体中文';

  @override
  String get english => 'English';

  @override
  String get copy => 'Copy';

  @override
  String get delete => 'Delete';

  @override
  String get print => 'Print';

  @override
  String get openImage => 'Open image';

  @override
  String get openFolder => 'Open folder';

  @override
  String get copyImagePath => 'Copy image path';

  @override
  String get openImagePath => 'Open file location';

  @override
  String get viewMode => 'View mode';

  @override
  String get viewOrder => 'Sort by';

  @override
  String get zoomMode => 'Image sizing';

  @override
  String get singlePage => 'Single page';

  @override
  String get doublePage => 'Double page';

  @override
  String get longImage => 'Long image';

  @override
  String get comic => 'Continuous reading';

  @override
  String get autoZoom => 'Fit to window';

  @override
  String get focusZoom => 'Keep zoom when changing images';

  @override
  String get widthPriority => 'Fit width';

  @override
  String get heightPriority => 'Fit height';

  @override
  String get keepZoomPosition => 'Also keep viewing position';

  @override
  String get zoomCenter => 'Zoom center';

  @override
  String get zoomCenterPointer => 'Pointer position';

  @override
  String get zoomCenterViewport => 'Viewport center';

  @override
  String get comicUniformSize => 'Uniform page size';

  @override
  String get readingBaseSize => 'Reading reference size (100%)';

  @override
  String get fileSystemOrder => 'Folder order';

  @override
  String get fileNameAscending => 'File name ascending';

  @override
  String get fileNameDescending => 'File name descending';

  @override
  String get fileSizeAscending => 'File size ascending';

  @override
  String get fileSizeDescending => 'File size descending';

  @override
  String get modifiedNewest => 'Modified newest';

  @override
  String get modifiedOldest => 'Modified oldest';

  @override
  String get windowAlwaysOnTop => 'Always on top';

  @override
  String get cancelAlwaysOnTop => 'Stop always on top';

  @override
  String get moreActions => 'More actions';

  @override
  String get moreZoomOptions => 'More zoom options';

  @override
  String get minimize => 'Minimize';

  @override
  String get restore => 'Restore';

  @override
  String get maximize => 'Maximize';

  @override
  String get close => 'Close';

  @override
  String get cancel => 'Cancel';

  @override
  String get rotateClockwise => 'Rotate clockwise';

  @override
  String get flipHorizontally => 'Flip horizontally';

  @override
  String get showThumbnails => 'Show thumbnails';

  @override
  String get hideThumbnails => 'Hide thumbnails';

  @override
  String get showInfo => 'Show information';

  @override
  String get information => 'Information';

  @override
  String get hideInfo => 'Hide information';

  @override
  String get zoomToWindow => 'Fit window';

  @override
  String get actualSize => 'Actual size';

  @override
  String get fullscreen => 'Fullscreen';

  @override
  String get enterBorderless => 'Enter borderless mode';

  @override
  String get exitBorderless => 'Exit borderless mode';

  @override
  String get exitFullscreen => 'Exit fullscreen';

  @override
  String get zoomOut => 'Zoom out';

  @override
  String get zoomIn => 'Zoom in';

  @override
  String get previousImage => 'Previous';

  @override
  String get nextImage => 'Next';

  @override
  String get closeInfoPanel => 'Close information panel';

  @override
  String get noImage => 'No image';

  @override
  String get format => 'Format';

  @override
  String get fileName => 'File name';

  @override
  String get size => 'Size';

  @override
  String get modifiedTime => 'Modified';

  @override
  String get dimensions => 'Dimensions';

  @override
  String get orientation => 'Orientation';

  @override
  String get path => 'Path';

  @override
  String get additionalMetadata => 'Additional metadata';

  @override
  String get readingDimensionsFailed =>
      'Failed to read dimensions / orientation';

  @override
  String get readingDimensions => 'Reading dimensions / orientation…';

  @override
  String get readingMetadataFailed => 'Failed to read metadata';

  @override
  String get unreadableImageMetadata => 'Unable to read image metadata';

  @override
  String get imageProperties => 'Image properties';

  @override
  String get basicInformation => 'Basic information';

  @override
  String get renameFile => 'Rename file';

  @override
  String get rename => 'Rename';

  @override
  String get renameUnavailable => 'This file cannot be edited';

  @override
  String get renameTargetExists => 'A file with this name already exists';

  @override
  String get invalidFileName => 'Invalid file name';

  @override
  String get animationInformation => 'Animation';

  @override
  String get frames => 'Frames';

  @override
  String get frameRate => 'Frame rate';

  @override
  String get duration => 'Duration';

  @override
  String get loopCount => 'Loop';

  @override
  String get infiniteLoop => 'Loop';

  @override
  String playCount(Object value) {
    return 'Play $value times';
  }

  @override
  String get cameraInformation => 'Camera';

  @override
  String get captureTime => 'Date taken';

  @override
  String get photoTitle => 'Title';

  @override
  String get photoDescription => 'Description';

  @override
  String get photoCreator => 'Author';

  @override
  String get photoCopyright => 'Copyright';

  @override
  String get photoRating => 'Rating';

  @override
  String get photoKeywords => 'Keywords';

  @override
  String get photoRejected => 'Rejected';

  @override
  String get photoAuto => 'Auto';

  @override
  String get photoManual => 'Manual';

  @override
  String get flashFired => 'Fired';

  @override
  String get flashNotFired => 'Did not fire';

  @override
  String get flashUnavailable => 'No flash';

  @override
  String get flashRedEye => 'Red-eye reduction';

  @override
  String get device => 'Device';

  @override
  String get lens => 'Lens';

  @override
  String get aperture => 'Aperture';

  @override
  String get shutterSpeed => 'Shutter speed';

  @override
  String get iso => 'ISO';

  @override
  String get focalLength => 'Focal length';

  @override
  String get exposureCompensation => 'Exposure compensation';

  @override
  String get whiteBalance => 'White balance';

  @override
  String get flash => 'Flash';

  @override
  String get location => 'Location';

  @override
  String get codec => 'Codec';

  @override
  String get colorSpace => 'Color space';

  @override
  String get colorDepth => 'Color depth';

  @override
  String get alphaChannel => 'Transparency';

  @override
  String get hasAlpha => 'Contains alpha channel';

  @override
  String get opaque => 'Opaque';

  @override
  String get vectorInformation => 'Vector information';

  @override
  String get physicalSize => 'Physical size';

  @override
  String get viewBox => 'ViewBox';

  @override
  String get nodeCount => 'Node count';

  @override
  String get orientationNormal => 'Normal (orientation 1)';

  @override
  String get orientationHorizontalMirror => 'Horizontal mirror (orientation 2)';

  @override
  String get orientationRotate180 => 'Rotate 180° (orientation 3)';

  @override
  String get orientationVerticalMirror => 'Vertical mirror (orientation 4)';

  @override
  String get orientationMirrorRotate270 =>
      'Mirror and rotate 270° (orientation 5)';

  @override
  String get orientationRotate90 => 'Rotate 90° (orientation 6)';

  @override
  String get orientationMirrorRotate90 =>
      'Mirror and rotate 90° (orientation 7)';

  @override
  String get orientationRotate270 => 'Rotate 270° (orientation 8)';

  @override
  String orientationUnknown(Object value) {
    return 'Unknown (orientation $value)';
  }

  @override
  String get selectContainer => 'Select a folder or archive to read a comic';

  @override
  String get cannotDecodeAnimatedImage => 'Unable to decode animated image';

  @override
  String imageParseFailed(Object name) {
    return 'Unable to parse $name';
  }

  @override
  String printPreviewFailed(Object error) {
    return 'Print preview failed: $error';
  }

  @override
  String printFailed(Object error) {
    return 'Print failed: $error';
  }

  @override
  String get parsingCapabilities => 'Supported image formats';

  @override
  String get acknowledge => 'OK';

  @override
  String get deleteCurrentImageQuestion => 'Delete image';

  @override
  String deleteCurrentImageDescription(Object name) {
    return 'Deleting “$name” moves the file to the system Recycle Bin/Trash.';
  }

  @override
  String get moveToRecycleBin => 'Move to Recycle Bin/Trash';

  @override
  String get deleteFailed => 'Unable to move to the system Recycle Bin/Trash';

  @override
  String get printPreview => 'Print preview';

  @override
  String get customMarginLabel => 'Custom margins';

  @override
  String get printer => 'Printer';

  @override
  String get defaultPrinter => 'Default printer';

  @override
  String get readingPrinters => 'Loading printers…';

  @override
  String get printerListUnavailable => 'Printer list unavailable';

  @override
  String get portrait => 'Portrait';

  @override
  String get landscape => 'Landscape';

  @override
  String get paperSize => 'Paper size';

  @override
  String get margins => 'Margins';

  @override
  String get customMarginHint => '0 to 50 mm, up to 1 decimal place';

  @override
  String get customMarginInvalid => 'Enter a number between 0 and 50.';

  @override
  String get noMargin => 'None';

  @override
  String get narrowMargin => 'Minimum';

  @override
  String get normalMargin => 'Custom';

  @override
  String get fitMode => 'Fit mode';

  @override
  String get fitPage => 'Fit page';

  @override
  String get fillPage => 'Fill page';

  @override
  String get fitPageDescription =>
      'Show the full image with its original proportions. Some blank space may remain.';

  @override
  String get fillPageDescription =>
      'Fill the printable area with the image\'s original proportions. Edges may be cropped.';

  @override
  String get actualSizeDescription =>
      'Print at the image\'s original size; it may exceed the printable area.';

  @override
  String get printAction => 'Print';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get archiveFormat => 'Archive';

  @override
  String get unknownFormat => 'Unknown';

  @override
  String bytes(Object value) {
    return '$value';
  }

  @override
  String get decoderFlutterCodec => 'Flutter codec';

  @override
  String get decoderDartImageSvg => 'Dart image / SVG renderer';

  @override
  String get decoderArchive => '7-Zip native engine; on-demand reading';

  @override
  String get decoderImageMagickJxl => 'ImageMagick (JPEG XL)';

  @override
  String get decoderWindowsWic => 'Windows WIC → ImageMagick fallback';

  @override
  String get decoderMacImageIo => 'macOS Image I/O → ImageMagick fallback';

  @override
  String get decoderImageMagickFallback => 'ImageMagick fallback';

  @override
  String get decoderUnavailable => 'Decoder not registered';

  @override
  String get invalidPngApng => 'This is not a valid PNG/APNG file';

  @override
  String get archiveLimitExceeded =>
      'The archive exceeds the safe processing limits';

  @override
  String get archiveTimeout => 'Archive processing timed out';

  @override
  String get sevenZipMissing =>
      'The archive reader is unavailable. Reinstall the full package and retry';

  @override
  String get unsafeArchivePath => 'The archive contains an unsafe path or link';

  @override
  String get archiveOpening => 'Opening…';

  @override
  String get archiveEmpty => 'This archive has no browsable images';

  @override
  String get archiveEncrypted =>
      'This archive requires a password. Enter it and retry';

  @override
  String get archiveCorrupt =>
      'The archive is damaged or uses an unsupported compression method';

  @override
  String get archiveUnsupported => 'This archive format is not supported';

  @override
  String get archiveIoError =>
      'The archive could not be read; check file permissions or disk space';

  @override
  String get archiveRetry => 'Retry';

  @override
  String get showInExplorer => 'Show in Explorer';

  @override
  String get archiveReadOnly => 'Archives are opened read-only';

  @override
  String get clipboardUnavailable =>
      'Copying to the system clipboard is not available on this platform';

  @override
  String get recycleBinUnavailable =>
      'The system Recycle Bin/Trash is not available on this platform';

  @override
  String get pixelReadFailed => 'Unable to read image pixels';

  @override
  String get animatedReadLimit => 'The animated image exceeds the read limit';

  @override
  String get imageReadLimit =>
      'The image exceeds the read limit; try long-image mode or a smaller image';

  @override
  String get decoderUnavailableError =>
      'The extended decoder is unavailable; reinstall the full package or set SHENVIEW_MAGICK';

  @override
  String get decodeTimeout =>
      'Image decoding timed out. Try again or move to the next image';

  @override
  String get decodeMemoryLimit =>
      'The image exceeds the decoding memory limit. Try fit-to-window or long-image mode';

  @override
  String decodeFailed(Object error) {
    return 'Decoding failed: $error';
  }

  @override
  String get archiveSettings => 'Archives';

  @override
  String get archiveSettingsDescription =>
      'Chapters, archive navigation, preloading, memory and disk cache.';

  @override
  String get archiveReading => 'Archive reading';

  @override
  String get archiveContinuousReading => 'Browse across chapters';

  @override
  String get archiveContinuousReadingDescription =>
      'Combine images from all chapters in the archive into one list. Turn off to browse only the current chapter.';

  @override
  String get directoryImages => 'Images in this folder';

  @override
  String get chapterDirectory => 'Chapter directory';

  @override
  String get browseDirectory => 'Browse directory';

  @override
  String get showDirectoryPanel => 'Show directory panel';

  @override
  String get hideDirectoryPanel => 'Hide directory panel';

  @override
  String get chooseLocation => 'Choose a folder or archive';

  @override
  String get previousLocation => 'Previous item';

  @override
  String get nextLocation => 'Next item';

  @override
  String get chooseChapter => 'Choose a chapter';

  @override
  String get previousChapter => 'Previous chapter';

  @override
  String get nextChapter => 'Next chapter';

  @override
  String get directoryNavigationVisible => 'Show directory navigation';

  @override
  String get directoryNavigationVisibleDescription =>
      'Show the directory panel on the left. Toggle it from the status bar; Appearance and Browsing share this setting.';

  @override
  String get pinDirectory => 'Pin directory panel';

  @override
  String get pinDirectoryDescription =>
      'Dock the directory panel on the left, even without subfolders or open content. Drag its right edge to resize. Unpin to use a floating panel.';

  @override
  String get directoryNotOpened => 'No folder opened';

  @override
  String get directoryNotOpenedDescription =>
      'Open a folder to browse its directories and archives here.';

  @override
  String get directoryNoChildren => 'No subfolders or archives.';

  @override
  String resizeDirectoryPanel(String undoShortcut) {
    return 'Drag to resize; double-click to reset. Esc cancels, arrow keys adjust, $undoShortcut undoes';
  }

  @override
  String get unpinDirectory => 'Unpin directory panel';

  @override
  String get searchDirectory => 'Search folders and chapters';

  @override
  String get clearDirectorySearch => 'Clear directory search';

  @override
  String get noMatchingDirectory => 'No matching folders or chapters';

  @override
  String get directoryReadFailed =>
      'Some folders could not be read. Expand them again to retry.';

  @override
  String get archiveAutoAdvance => 'Turn past ends to switch archives';

  @override
  String get archiveAutoAdvanceDescription =>
      'After opening an archive from a folder, turn past the last page to open the next archive, or back past the first to open the previous one. Only switches between archives in the same folder.';

  @override
  String get archiveSortOrder => 'Archive page order';

  @override
  String get archiveSortDescription =>
      'Viewing order is independent of folders; the file name sorting rule is shared with Browsing settings.';

  @override
  String get archivePrefetchMode => 'Preloading';

  @override
  String get archivePrefetchDescription =>
      'Prepare images ahead of time for the current viewing mode. Preloading slows or pauses automatically when resources are limited.';

  @override
  String get archivePrefetchAutomatic => 'Automatic';

  @override
  String get archivePrefetchConservative => 'Conservative';

  @override
  String get archivePrefetchOff => 'Off';

  @override
  String get archiveMemoryBudget => 'Archive image memory limit';

  @override
  String get archiveMemoryDescription =>
      'Adjust automatically to available memory or set a limit from 32 to 1024 MiB. Actual usage is reduced when resources are limited.';

  @override
  String get archiveBudgetAutomatic => 'Automatic (recommended)';

  @override
  String get archiveBudgetCustom => 'Custom';

  @override
  String get archiveMemoryInvalid =>
      'Enter a whole number between 32 and 1024.';

  @override
  String get archiveCache => 'Disk cache';

  @override
  String get archivePersistCache => 'Retain ordinary archive cache';

  @override
  String get archivePersistDescription =>
      'Cache unencrypted archives within the size and retention limits. Encrypted archive caches are cleared on close; passwords are never saved.';

  @override
  String get archiveDiskBudget => 'Cache size limit';

  @override
  String get archiveDiskDescription =>
      'All archives share this size limit. Cache files still in use are removed when no longer needed.';

  @override
  String get archiveRetention => 'Retention period';

  @override
  String get archiveRetentionDescription =>
      'Expired or invalid cache files are removed automatically.';

  @override
  String get archiveRetentionDay => 'days';

  @override
  String get archiveCacheUsage => 'Cache used';

  @override
  String get archiveCacheUnknown => 'Calculating…';

  @override
  String get archiveClearCache => 'Clear cache';

  @override
  String get archiveCacheClearFailed => 'Unable to clear the cache. Try again.';

  @override
  String get archiveCacheCleared =>
      'Unused cache cleared. Remaining cache files will be removed when no longer in use.';

  @override
  String get archivePasswordTitle => 'Enter archive password';

  @override
  String get archivePasswordHint => 'Password';

  @override
  String get archivePasswordDescription =>
      'The password is used only for this session and is never saved.';

  @override
  String get archivePasswordShow => 'Show password';

  @override
  String get archivePasswordHide => 'Hide password';

  @override
  String get archivePasswordOpen => 'Open';

  @override
  String get archivePasswordWrong => 'Incorrect password. Try again.';

  @override
  String get archivePasswordUnverified =>
      'Unable to verify the password or data. Check the password or get another copy of the archive.';

  @override
  String get archivePasswordUnsupported =>
      'This encryption method is not supported. Decrypt the archive before opening it.';

  @override
  String get archiveReadingDirectory => 'Reading archive directory…';

  @override
  String get archivePreparingPage => 'Preparing image…';

  @override
  String get archiveCancelOpening => 'Cancel opening';

  @override
  String get archiveRetryPage => 'Retry page';

  @override
  String get archivePerformanceNormal =>
      'Normal: preload by direction and distance';

  @override
  String get archivePerformanceConservative =>
      'Conservative: nearby pages only';

  @override
  String get archivePerformanceOnDemand => 'On demand: visible content only';

  @override
  String get archiveSourceChanged => 'The archive has changed. Open it again.';

  @override
  String get archiveVolumeMissing =>
      'The archive needs additional volumes. Obtain the missing volumes and reopen it.';

  @override
  String get archiveResourceInsufficient =>
      'Not enough resources. Close other images or clear the cache and retry.';

  @override
  String get archiveBrowseContainers =>
      'No images here. Open a chapter or nested archive to continue.';

  @override
  String get saveOriginalImage => 'Save as';

  @override
  String get animationControls => 'Animation playback';

  @override
  String get previousFrame => 'Previous frame';

  @override
  String get nextFrame => 'Next frame';

  @override
  String get animationProgress => 'Playback position';

  @override
  String get animationSpeed => 'Playback speed';

  @override
  String get animationRestart => 'Play from start';

  @override
  String get animationLoopFile => 'Follow file';

  @override
  String get animationLoopInfinite => 'Loop forever';

  @override
  String get animationLoopOnce => 'Play once';

  @override
  String get animationLoopMode => 'Loop mode';

  @override
  String get animationAutoPlay => 'Play animations when opened';

  @override
  String get animationAutoPlayDescription =>
      'Play animations when opened; when off, show the first frame.';

  @override
  String get animationDefaultLoopDescription =>
      'Default loop mode when opening an animation. Override it temporarily in the playback bar.';

  @override
  String get animationDefaultSpeed => 'Default playback speed';

  @override
  String get animationDefaultSpeedDescription =>
      'Use this speed when opening animations. Playback bar changes apply only to the current animation.';

  @override
  String get animationControlsDisplay => 'Playback bar visibility';

  @override
  String get animationControlsDisplayDescription =>
      'With Auto-hide, the playback bar hides after 2 seconds without interaction during playback. Move the pointer to the bottom of the image area to show it. Space still plays or pauses when the bar is hidden.';

  @override
  String get animationControlsAutoHide => 'Auto-hide';

  @override
  String get animationControlsAlways => 'Always visible';

  @override
  String get animationControlsHidden => 'Hidden';

  @override
  String animationFramePosition(int frame, int count) {
    return 'Frame $frame / $count';
  }

  @override
  String get autoPlayTitle => 'Auto play';

  @override
  String get autoPlayStart => 'Start auto play';

  @override
  String get autoPlayPause => 'Pause auto play';

  @override
  String get autoPlayStop => 'Stop auto play';

  @override
  String get autoPlayOptions => 'Auto play options';

  @override
  String get autoPlayInterval => 'Interval (seconds)';

  @override
  String get autoPlaySpeed => 'Scroll speed (pixels/second)';

  @override
  String get autoPlayLoop => 'Loop';

  @override
  String get autoPlayAnimation => 'Animated images';

  @override
  String get autoPlayCompleteOnce => 'Play at least once';

  @override
  String get autoPlayFixedInterval => 'Use fixed interval';

  @override
  String get autoPlayStay => 'Stay on animated images';

  @override
  String get autoPlayWaiting => 'Waiting for animation';

  @override
  String get autoPlayPaused => 'Paused';

  @override
  String get autoPlayScrolling => 'Auto scrolling';

  @override
  String get autoPlayScope =>
      'Current list · no automatic folder or archive switching';

  @override
  String get autoPlaySave => 'Save';

  @override
  String get animationLabel => 'Animation';

  @override
  String get autoPlayAdvancing => 'Auto advance';

  @override
  String autoPlayCountdown(String seconds) {
    return 'Next in $seconds s';
  }

  @override
  String autoPlayScrollRate(String speed) {
    return '$speed px/s';
  }

  @override
  String get autoPlayInvalidInterval => 'Enter a number between 0.5 and 3600';

  @override
  String get autoPlayIntervalHint => '0.5 to 3600 s, up to 1 decimal place';

  @override
  String get autoPlayInvalidSpeed => 'Enter a number between 5 and 1000';

  @override
  String get autoPlayStatusDisplay => 'Status panel display';

  @override
  String get autoPlayStatusDisplayDescription =>
      'With Auto-hide, the status panel fades out after 2 seconds without interaction during playback. Move the pointer to the upper-right of the image area to show it. Stays visible when paused, focused with the keyboard, or settings are open.';
}
