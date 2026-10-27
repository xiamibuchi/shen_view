import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show mapEquals;

import '../application/app_config_store.dart';
import 'comic_layout_direction.dart';
import 'animation_timeline.dart';
import 'folder_browse_mode.dart';
import 'sort_order.dart';
import 'view_scale_mode.dart';
import 'viewer_mode.dart';
import 'auto_play_settings.dart';
import 'viewer_interaction_settings.dart';
import 'picked_color.dart';
import 'viewer_shortcuts.dart';
import 'thumbnail_prefetch_mode.dart';

export 'sort_order.dart';
export 'viewer_interaction_settings.dart';
export 'thumbnail_prefetch_mode.dart';

enum InstanceMode { singleProcess, multiProcess }

enum ToolbarMode { floating, normal }

enum ViewerThemeMode { system, light, dark }

enum ReadingDirection { leftToRight, rightToLeft }

enum ArchivePrefetchMode { automatic, conservative, off }

enum AnimationControlsMode { autoHide, always, hidden }

class ViewerSettings {
  static const defaultDirectoryPanelWidth = 360.0;
  static const minDirectoryPanelWidth = 240.0;
  static const maxDirectoryPanelWidth = 600.0;
  static const defaultComicPageGap = 8.0;
  static const minComicPageGap = 0.0;
  static const maxComicPageGap = 48.0;
  static const configSchemaVersion = 1;

  const ViewerSettings({
    this.shortcutOverrides = const {},
    this.localeCode = 'system',
    this.instanceMode = InstanceMode.singleProcess,
    this.themeMode = ViewerThemeMode.dark,
    this.toolbarMode = ToolbarMode.normal,
    this.defaultViewerMode = ViewerMode.single,
    this.defaultScaleModes = const {},
    this.sortOrder = SortOrder.nameAscending,
    this.fileNameSortMode = FileNameSortMode.natural,
    this.browseMode = FolderBrowseMode.currentFolder,
    bool? folderContinuousReading,
    this.scanUnknownExtensions = false,
    this.watchFolderChanges = true,
    this.recentOpenEnabled = true,
    this.recentOpenLimit = 20,
    this.openRecentOnNewWindow = false,
    this.readingDirection = ReadingDirection.leftToRight,
    this.comicLayoutDirection = ComicLayoutDirection.vertical,
    this.alwaysOnTop = false,
    this.doublePageFirstAlone = true,
    this.doublePageWideAlone = true,
    this.doublePageSplitWide = false,
    this.comicPageGap = defaultComicPageGap,
    this.comicUniformSize = true,
    this.showThumbnailFileNames = true,
    this.thumbnailPrefetchMode = ThumbnailPrefetchMode.automatic,
    this.showBottomBar = true,
    this.showDirectoryPanel = true,
    this.pinDirectoryPanel = false,
    this.directoryPanelWidth = defaultDirectoryPanelWidth,
    this.autoHdr = true,
    this.autoPlay = const AutoPlaySettings(),
    this.animationAutoPlay = true,
    this.animationLoopMode = AnimationLoopMode.file,
    this.animationSpeed = 1.0,
    this.animationControlsMode = AnimationControlsMode.autoHide,
    this.colorPickerFormat = ColorCopyFormat.hex,
    this.hdrLinear = true,
    this.hdrPqHlg = true,
    this.hdrGainMap = true,
    this.hdrRaw = true,
    this.hdrDolbyVision = true,
    this.archiveContinuousReading = true,
    this.archiveAutoAdvance = false,
    SortOrder archiveSortOrder = SortOrder.nameAscending,
    this.archivePrefetchMode = ArchivePrefetchMode.automatic,
    this.archivePersistCache = true,
    this.archiveMemoryBudgetMiB = 0,
    this.archiveDiskBudgetMiB = 2048,
    this.archiveCacheRetentionDays = 7,
    this.interaction = const ViewerInteractionSettings(),
  }) : archiveSortOrder = archiveSortOrder == SortOrder.fileSystem
           ? SortOrder.nameAscending
           : archiveSortOrder,
       folderContinuousReading = browseMode == FolderBrowseMode.currentFolder
           ? (folderContinuousReading ?? false)
           : browseMode == FolderBrowseMode.recursiveFlat;

  final String localeCode;
  final Map<String, ViewerShortcutBinding> shortcutOverrides;
  final ColorCopyFormat colorPickerFormat;
  final InstanceMode instanceMode;
  final ViewerThemeMode themeMode;
  final ToolbarMode toolbarMode;
  final ViewerMode defaultViewerMode;
  final Map<ViewerMode, ViewScaleMode> defaultScaleModes;

  ViewScaleMode defaultScaleModeFor(
    ViewerMode mode, {
    ComicLayoutDirection? direction,
  }) {
    final explicit = defaultScaleModes[mode];
    if (explicit != null) return explicit;
    return switch (mode) {
      ViewerMode.longImage => ViewScaleMode.fitWidth,
      ViewerMode.comic =>
        (direction ?? comicLayoutDirection) == ComicLayoutDirection.vertical
            ? ViewScaleMode.fitWidth
            : ViewScaleMode.fitHeight,
      _ => ViewScaleMode.autoFit,
    };
  }

  final SortOrder sortOrder;
  final FileNameSortMode fileNameSortMode;
  final FolderBrowseMode browseMode;
  final bool folderContinuousReading;
  final bool scanUnknownExtensions;

  /// Watches the open folder and refreshes the image list after external
  /// changes. When off, the app never touches the file system watcher.
  final bool watchFolderChanges;
  final bool recentOpenEnabled;
  final int recentOpenLimit;
  final bool openRecentOnNewWindow;

  final ReadingDirection readingDirection;
  final ComicLayoutDirection comicLayoutDirection;
  final bool alwaysOnTop;
  final bool doublePageFirstAlone;
  final bool doublePageWideAlone;
  final bool doublePageSplitWide;
  final double comicPageGap;
  final bool comicUniformSize;
  final bool showThumbnailFileNames;
  final ThumbnailPrefetchMode thumbnailPrefetchMode;
  final bool showBottomBar;
  final bool showDirectoryPanel;
  final bool pinDirectoryPanel;
  final double directoryPanelWidth;
  final bool autoHdr;
  final AutoPlaySettings autoPlay;
  final bool animationAutoPlay;
  final AnimationLoopMode animationLoopMode;
  final double animationSpeed;
  final AnimationControlsMode animationControlsMode;
  final bool hdrLinear;
  final bool hdrPqHlg;
  final bool hdrGainMap;
  final bool hdrRaw;
  final bool hdrDolbyVision;
  final bool archiveContinuousReading;
  final bool archiveAutoAdvance;
  final SortOrder archiveSortOrder;
  final ArchivePrefetchMode archivePrefetchMode;
  final bool archivePersistCache;

  /// Zero uses the automatic budget; custom limits range from 32 to 1024 MiB.
  final int archiveMemoryBudgetMiB;
  final int archiveDiskBudgetMiB;
  final int archiveCacheRetentionDays;
  final ViewerInteractionSettings interaction;

  static Future<ViewerSettings> load({AppConfigStore? store}) async {
    final configStore = store ?? AppConfigStore();
    final config = await configStore.readOrEmpty();
    try {
      return _fromConfig(config);
    } catch (error, stack) {
      developer.log(
        'Unable to parse settings; using defaults.',
        name: 'ShenView.config',
        error: error,
        stackTrace: stack,
      );
      return const ViewerSettings();
    }
  }

  static ViewerSettings _fromConfig(Map<String, dynamic> config) {
    final settings = _asMap(config['settings']);
    return ViewerSettings(
      shortcutOverrides: ViewerShortcutBindings.readOverrides(
        settings['shortcutOverrides'],
      ),
      interaction: ViewerInteractionSettings.fromJson(settings['interaction']),
      localeCode: _readLocaleCode(settings['localeCode']),
      instanceMode: _readEnum(
        InstanceMode.values,
        settings['instanceMode'],
        InstanceMode.singleProcess,
      ),
      themeMode: _readEnum(
        ViewerThemeMode.values,
        settings['themeMode'],
        ViewerThemeMode.dark,
      ),
      toolbarMode: _readEnum(
        ToolbarMode.values,
        settings['toolbarMode'],
        ToolbarMode.normal,
      ),
      defaultViewerMode: _readEnum(
        ViewerMode.values,
        settings['defaultViewerMode'],
        ViewerMode.single,
      ),
      defaultScaleModes: {
        for (final entry in _asMap(settings['defaultScaleModes']).entries)
          ?ViewerMode.values
              .where((mode) => mode.name == entry.key)
              .firstOrNull: _readEnum(
            ViewScaleMode.values,
            entry.value,
            ViewScaleMode.autoFit,
          ),
      },
      sortOrder: _readEnum(
        SortOrder.values,
        settings['sortOrder'],
        SortOrder.nameAscending,
      ),
      fileNameSortMode: _readEnum(
        FileNameSortMode.values,
        settings['fileNameSortMode'],
        FileNameSortMode.natural,
      ),
      browseMode: _readEnum(
        FolderBrowseMode.values,
        settings['folderBrowseMode'],
        FolderBrowseMode.currentFolder,
      ),
      folderContinuousReading: settings['folderContinuousReading'] == true,
      scanUnknownExtensions: settings['scanUnknownExtensions'] == true,
      watchFolderChanges: settings['watchFolderChanges'] != false,
      recentOpenEnabled: settings['recentOpenEnabled'] != false,
      recentOpenLimit: _readBudget(settings['recentOpenLimit'], 20, 5, 100),
      openRecentOnNewWindow: settings['openRecentOnNewWindow'] == true,
      readingDirection: _readEnum(
        ReadingDirection.values,
        settings['readingDirection'],
        ReadingDirection.leftToRight,
      ),
      comicLayoutDirection: _readEnum(
        ComicLayoutDirection.values,
        settings['comicLayoutDirection'],
        ComicLayoutDirection.vertical,
      ),
      alwaysOnTop: settings['alwaysOnTop'] == true,
      doublePageFirstAlone: settings['doublePageFirstAlone'] != false,
      doublePageWideAlone: settings['doublePageWideAlone'] != false,
      doublePageSplitWide: settings['doublePageSplitWide'] == true,
      comicPageGap: _readComicPageGap(settings['comicPageGap']),
      comicUniformSize: settings['comicUniformSize'] != false,
      showThumbnailFileNames: settings['showThumbnailFileNames'] != false,
      showBottomBar: settings['showBottomBar'] != false,
      showDirectoryPanel: settings['showDirectoryPanel'] != false,
      pinDirectoryPanel: settings['pinDirectoryPanel'] == true,
      directoryPanelWidth: normalizeDirectoryPanelWidth(
        settings['directoryPanelWidth'],
      ),
      autoHdr: settings['autoHdr'] != false,
      colorPickerFormat: ColorCopyFormat.fromSetting(
        settings['colorPickerFormat'],
      ),
      animationAutoPlay: settings['animationAutoPlay'] != false,
      animationLoopMode: _readEnum(
        AnimationLoopMode.values,
        settings['animationLoopMode'],
        AnimationLoopMode.file,
      ),
      autoPlay: AutoPlaySettings.fromJson(settings['autoPlay']),
      animationSpeed: normalizeAnimationSpeed(settings['animationSpeed']),
      animationControlsMode: _readEnum(
        AnimationControlsMode.values,
        settings['animationControlsMode'],
        AnimationControlsMode.autoHide,
      ),
      hdrLinear: settings['hdrLinear'] != false,
      hdrPqHlg: settings['hdrPqHlg'] != false,
      hdrGainMap: settings['hdrGainMap'] != false,
      hdrRaw: settings['hdrRaw'] != false,
      hdrDolbyVision: settings['hdrDolbyVision'] != false,
      archiveContinuousReading: settings['archiveContinuousReading'] != false,
      archiveAutoAdvance: settings['archiveAutoAdvance'] == true,
      archiveSortOrder: normalizeArchiveSortOrder(
        _readEnum(
          SortOrder.values,
          settings['archiveSortOrder'],
          SortOrder.nameAscending,
        ),
      ),
      archivePrefetchMode: _readEnum(
        ArchivePrefetchMode.values,
        settings['archivePrefetchMode'],
        ArchivePrefetchMode.automatic,
      ),
      thumbnailPrefetchMode: _readEnum(
        ThumbnailPrefetchMode.values,
        settings['thumbnailPrefetchMode'],
        ThumbnailPrefetchMode.automatic,
      ),
      archivePersistCache: settings['archivePersistCache'] != false,
      archiveMemoryBudgetMiB: _readBudget(
        settings['archiveMemoryBudgetMiB'],
        0,
        32,
        1024,
        automatic: true,
      ),
      archiveDiskBudgetMiB: _readBudget(
        settings['archiveDiskBudgetMiB'],
        2048,
        256,
        8192,
      ),
      archiveCacheRetentionDays: _readBudget(
        settings['archiveCacheRetentionDays'],
        7,
        1,
        30,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'shortcutOverrides': {
      for (final entry in shortcutOverrides.entries)
        entry.key: entry.value.toJson(),
    },
    'interaction': interaction.toJson(),
    'localeCode': localeCode,
    'instanceMode': instanceMode.name,
    'themeMode': themeMode.name,
    'toolbarMode': toolbarMode.name,
    'defaultViewerMode': defaultViewerMode.name,
    'defaultScaleModes': {
      for (final entry in defaultScaleModes.entries)
        entry.key.name: entry.value.name,
    },
    'sortOrder': sortOrder.name,
    'fileNameSortMode': fileNameSortMode.name,
    'folderBrowseMode': browseMode.name,
    'folderContinuousReading': folderContinuousReading,
    'scanUnknownExtensions': scanUnknownExtensions,
    'watchFolderChanges': watchFolderChanges,
    'recentOpenEnabled': recentOpenEnabled,
    'recentOpenLimit': recentOpenLimit,
    'openRecentOnNewWindow': openRecentOnNewWindow,
    'readingDirection': readingDirection.name,
    'comicLayoutDirection': comicLayoutDirection.name,
    'alwaysOnTop': alwaysOnTop,
    'doublePageFirstAlone': doublePageFirstAlone,
    'doublePageWideAlone': doublePageWideAlone,
    'doublePageSplitWide': doublePageSplitWide,
    'comicPageGap': comicPageGap,
    'comicUniformSize': comicUniformSize,
    'showThumbnailFileNames': showThumbnailFileNames,
    'showBottomBar': showBottomBar,
    'showDirectoryPanel': showDirectoryPanel,
    'pinDirectoryPanel': pinDirectoryPanel,
    'directoryPanelWidth': normalizeDirectoryPanelWidth(directoryPanelWidth),
    'autoHdr': autoHdr,
    'colorPickerFormat': colorPickerFormat.name,
    'animationAutoPlay': animationAutoPlay,
    'animationLoopMode': animationLoopMode.name,
    'autoPlay': autoPlay.toJson(),
    'animationSpeed': normalizeAnimationSpeed(animationSpeed),
    'animationControlsMode': animationControlsMode.name,
    'hdrLinear': hdrLinear,
    'hdrPqHlg': hdrPqHlg,
    'hdrGainMap': hdrGainMap,
    'hdrRaw': hdrRaw,
    'hdrDolbyVision': hdrDolbyVision,
    'archiveContinuousReading': archiveContinuousReading,
    'archiveAutoAdvance': archiveAutoAdvance,
    'archiveSortOrder': normalizeArchiveSortOrder(archiveSortOrder).name,
    'archivePrefetchMode': archivePrefetchMode.name,
    'thumbnailPrefetchMode': thumbnailPrefetchMode.name,
    'archivePersistCache': archivePersistCache,
    'archiveMemoryBudgetMiB': archiveMemoryBudgetMiB,
    'archiveDiskBudgetMiB': archiveDiskBudgetMiB,
    'archiveCacheRetentionDays': archiveCacheRetentionDays,
  };

  /// Merge only this window's edits into the latest committed settings.
  Future<void> save({AppConfigStore? store, ViewerSettings? previous}) async {
    final values = toJson();
    final before = previous?.toJson();
    await (store ?? AppConfigStore()).update((config) {
      config['schemaVersion'] = configSchemaVersion;
      final settings = _asMap(config['settings']);
      _mergeChanges(settings, values, before);
      config['settings'] = settings;
      return config;
    });
  }

  static void _mergeChanges(
    Map<String, dynamic> target,
    Map<String, dynamic> values,
    Map<String, dynamic>? before, {
    bool atomicValues = false,
  }) {
    if (before != null) {
      for (final key in before.keys) {
        if (!values.containsKey(key)) target.remove(key);
      }
    }
    for (final entry in values.entries) {
      if (before != null &&
          jsonEncode(before[entry.key]) == jsonEncode(entry.value)) {
        continue;
      }
      if (!atomicValues && entry.value is Map && before?[entry.key] is Map) {
        final nested = _asMap(target[entry.key]);
        _mergeChanges(
          nested,
          _asMap(entry.value),
          _asMap(before![entry.key]),
          atomicValues: entry.key == 'shortcutOverrides',
        );
        target[entry.key] = nested;
      } else {
        target[entry.key] = entry.value;
      }
    }
  }

  ViewerSettings copyWith({
    Map<String, ViewerShortcutBinding>? shortcutOverrides,
    ViewerInteractionSettings? interaction,
    String? localeCode,
    InstanceMode? instanceMode,
    ViewerThemeMode? themeMode,
    ToolbarMode? toolbarMode,
    ViewerMode? defaultViewerMode,
    Map<ViewerMode, ViewScaleMode>? defaultScaleModes,
    SortOrder? sortOrder,
    FileNameSortMode? fileNameSortMode,
    FolderBrowseMode? browseMode,
    bool? folderContinuousReading,
    bool? scanUnknownExtensions,
    bool? watchFolderChanges,
    bool? recentOpenEnabled,
    int? recentOpenLimit,
    bool? openRecentOnNewWindow,
    ReadingDirection? readingDirection,
    ComicLayoutDirection? comicLayoutDirection,
    bool? alwaysOnTop,
    bool? doublePageFirstAlone,
    bool? doublePageWideAlone,
    bool? doublePageSplitWide,
    double? comicPageGap,
    bool? comicUniformSize,
    bool? showThumbnailFileNames,
    bool? showBottomBar,
    bool? showDirectoryPanel,
    bool? pinDirectoryPanel,
    double? directoryPanelWidth,
    bool? autoHdr,
    ColorCopyFormat? colorPickerFormat,
    bool? animationAutoPlay,
    AnimationLoopMode? animationLoopMode,
    AutoPlaySettings? autoPlay,
    double? animationSpeed,
    AnimationControlsMode? animationControlsMode,
    bool? hdrLinear,
    bool? hdrPqHlg,
    bool? hdrGainMap,
    bool? hdrRaw,
    bool? hdrDolbyVision,
    bool? archiveContinuousReading,
    bool? archiveAutoAdvance,
    SortOrder? archiveSortOrder,
    ArchivePrefetchMode? archivePrefetchMode,
    ThumbnailPrefetchMode? thumbnailPrefetchMode,
    bool? archivePersistCache,
    int? archiveMemoryBudgetMiB,
    int? archiveDiskBudgetMiB,
    int? archiveCacheRetentionDays,
  }) {
    return ViewerSettings(
      shortcutOverrides: shortcutOverrides ?? this.shortcutOverrides,
      interaction: interaction ?? this.interaction,
      localeCode: localeCode ?? this.localeCode,
      instanceMode: instanceMode ?? this.instanceMode,
      themeMode: themeMode ?? this.themeMode,
      toolbarMode: toolbarMode ?? this.toolbarMode,
      defaultViewerMode: defaultViewerMode ?? this.defaultViewerMode,
      defaultScaleModes: defaultScaleModes ?? this.defaultScaleModes,
      sortOrder: sortOrder ?? this.sortOrder,
      fileNameSortMode: fileNameSortMode ?? this.fileNameSortMode,
      browseMode: browseMode ?? this.browseMode,
      folderContinuousReading:
          folderContinuousReading ?? this.folderContinuousReading,
      scanUnknownExtensions:
          scanUnknownExtensions ?? this.scanUnknownExtensions,
      watchFolderChanges: watchFolderChanges ?? this.watchFolderChanges,
      recentOpenEnabled: recentOpenEnabled ?? this.recentOpenEnabled,
      recentOpenLimit: recentOpenLimit ?? this.recentOpenLimit,
      openRecentOnNewWindow:
          openRecentOnNewWindow ?? this.openRecentOnNewWindow,
      readingDirection: readingDirection ?? this.readingDirection,
      comicLayoutDirection: comicLayoutDirection ?? this.comicLayoutDirection,
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      doublePageFirstAlone: doublePageFirstAlone ?? this.doublePageFirstAlone,
      doublePageWideAlone: doublePageWideAlone ?? this.doublePageWideAlone,
      doublePageSplitWide: doublePageSplitWide ?? this.doublePageSplitWide,
      comicPageGap: comicPageGap ?? this.comicPageGap,
      comicUniformSize: comicUniformSize ?? this.comicUniformSize,
      showThumbnailFileNames:
          showThumbnailFileNames ?? this.showThumbnailFileNames,
      showBottomBar: showBottomBar ?? this.showBottomBar,
      showDirectoryPanel: showDirectoryPanel ?? this.showDirectoryPanel,
      pinDirectoryPanel: pinDirectoryPanel ?? this.pinDirectoryPanel,
      directoryPanelWidth: directoryPanelWidth ?? this.directoryPanelWidth,
      autoHdr: autoHdr ?? this.autoHdr,
      colorPickerFormat: colorPickerFormat ?? this.colorPickerFormat,
      animationAutoPlay: animationAutoPlay ?? this.animationAutoPlay,
      animationLoopMode: animationLoopMode ?? this.animationLoopMode,
      autoPlay: autoPlay ?? this.autoPlay,
      animationSpeed: animationSpeed ?? this.animationSpeed,
      animationControlsMode:
          animationControlsMode ?? this.animationControlsMode,
      hdrLinear: hdrLinear ?? this.hdrLinear,
      hdrPqHlg: hdrPqHlg ?? this.hdrPqHlg,
      hdrGainMap: hdrGainMap ?? this.hdrGainMap,
      hdrRaw: hdrRaw ?? this.hdrRaw,
      hdrDolbyVision: hdrDolbyVision ?? this.hdrDolbyVision,
      archiveContinuousReading:
          archiveContinuousReading ?? this.archiveContinuousReading,
      archiveAutoAdvance: archiveAutoAdvance ?? this.archiveAutoAdvance,
      archiveSortOrder: archiveSortOrder ?? this.archiveSortOrder,
      archivePrefetchMode: archivePrefetchMode ?? this.archivePrefetchMode,
      thumbnailPrefetchMode:
          thumbnailPrefetchMode ?? this.thumbnailPrefetchMode,
      archivePersistCache: archivePersistCache ?? this.archivePersistCache,
      archiveMemoryBudgetMiB:
          archiveMemoryBudgetMiB ?? this.archiveMemoryBudgetMiB,
      archiveDiskBudgetMiB: archiveDiskBudgetMiB ?? this.archiveDiskBudgetMiB,
      archiveCacheRetentionDays:
          archiveCacheRetentionDays ?? this.archiveCacheRetentionDays,
    );
  }

  @override
  bool operator ==(Object other) =>
      // Keep this field list in sync with copyWith and save.
      other is ViewerSettings &&
      mapEquals(other.shortcutOverrides, shortcutOverrides) &&
      other.interaction == interaction &&
      other.localeCode == localeCode &&
      other.instanceMode == instanceMode &&
      other.themeMode == themeMode &&
      other.toolbarMode == toolbarMode &&
      other.defaultViewerMode == defaultViewerMode &&
      mapEquals(other.defaultScaleModes, defaultScaleModes) &&
      other.sortOrder == sortOrder &&
      other.fileNameSortMode == fileNameSortMode &&
      other.browseMode == browseMode &&
      other.folderContinuousReading == folderContinuousReading &&
      other.scanUnknownExtensions == scanUnknownExtensions &&
      other.watchFolderChanges == watchFolderChanges &&
      other.recentOpenEnabled == recentOpenEnabled &&
      other.recentOpenLimit == recentOpenLimit &&
      other.openRecentOnNewWindow == openRecentOnNewWindow &&
      other.readingDirection == readingDirection &&
      other.comicLayoutDirection == comicLayoutDirection &&
      other.alwaysOnTop == alwaysOnTop &&
      other.doublePageFirstAlone == doublePageFirstAlone &&
      other.doublePageWideAlone == doublePageWideAlone &&
      other.doublePageSplitWide == doublePageSplitWide &&
      other.comicPageGap == comicPageGap &&
      other.comicUniformSize == comicUniformSize &&
      other.showThumbnailFileNames == showThumbnailFileNames &&
      other.showBottomBar == showBottomBar &&
      other.showDirectoryPanel == showDirectoryPanel &&
      other.pinDirectoryPanel == pinDirectoryPanel &&
      other.directoryPanelWidth == directoryPanelWidth &&
      other.autoHdr == autoHdr &&
      other.colorPickerFormat == colorPickerFormat &&
      other.animationAutoPlay == animationAutoPlay &&
      other.animationLoopMode == animationLoopMode &&
      other.autoPlay == autoPlay &&
      other.animationSpeed == animationSpeed &&
      other.animationControlsMode == animationControlsMode &&
      other.hdrLinear == hdrLinear &&
      other.hdrPqHlg == hdrPqHlg &&
      other.hdrGainMap == hdrGainMap &&
      other.hdrRaw == hdrRaw &&
      other.hdrDolbyVision == hdrDolbyVision &&
      other.archiveContinuousReading == archiveContinuousReading &&
      other.archiveAutoAdvance == archiveAutoAdvance &&
      other.archiveSortOrder == archiveSortOrder &&
      other.archivePrefetchMode == archivePrefetchMode &&
      other.thumbnailPrefetchMode == thumbnailPrefetchMode &&
      other.archivePersistCache == archivePersistCache &&
      other.archiveMemoryBudgetMiB == archiveMemoryBudgetMiB &&
      other.archiveDiskBudgetMiB == archiveDiskBudgetMiB &&
      other.archiveCacheRetentionDays == archiveCacheRetentionDays;

  @override
  int get hashCode => Object.hashAll([
    Object.hashAllUnordered(
      shortcutOverrides.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
    interaction,
    localeCode,
    instanceMode,
    themeMode,
    toolbarMode,
    defaultViewerMode,
    Object.hashAll(ViewerMode.values.map((mode) => defaultScaleModes[mode])),
    sortOrder,
    fileNameSortMode,
    browseMode,
    folderContinuousReading,
    scanUnknownExtensions,
    watchFolderChanges,
    recentOpenEnabled,
    recentOpenLimit,
    openRecentOnNewWindow,
    readingDirection,
    comicLayoutDirection,
    alwaysOnTop,
    doublePageFirstAlone,
    doublePageWideAlone,
    doublePageSplitWide,
    comicPageGap,
    comicUniformSize,
    showThumbnailFileNames,
    showBottomBar,
    showDirectoryPanel,
    pinDirectoryPanel,
    directoryPanelWidth,
    autoHdr,
    colorPickerFormat,
    animationAutoPlay,
    animationLoopMode,
    autoPlay,
    animationSpeed,
    animationControlsMode,
    hdrLinear,
    hdrPqHlg,
    hdrGainMap,
    hdrRaw,
    hdrDolbyVision,
    archiveContinuousReading,
    archiveAutoAdvance,
    archiveSortOrder,
    archivePrefetchMode,
    thumbnailPrefetchMode,
    archivePersistCache,
    archiveMemoryBudgetMiB,
    archiveDiskBudgetMiB,
    archiveCacheRetentionDays,
  ]);

  static double normalizeDirectoryPanelWidth(Object? value) {
    if (value is! num || !value.isFinite) return defaultDirectoryPanelWidth;
    return value.toDouble().clamp(
      minDirectoryPanelWidth,
      maxDirectoryPanelWidth,
    );
  }
}

double normalizeAnimationSpeed(Object? value) =>
    value is num && animationPlaybackSpeeds.contains(value.toDouble())
    ? value.toDouble()
    : 1.0;

Map<String, dynamic> _asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

int _readBudget(
  Object? value,
  int fallback,
  int minimum,
  int maximum, {
  bool automatic = false,
}) {
  if (value is! num || !value.isFinite) return fallback;
  if (automatic && value == 0) return 0;
  return value.toInt().clamp(minimum, maximum);
}

double _readComicPageGap(Object? value) {
  if (value is! num || !value.isFinite) {
    return ViewerSettings.defaultComicPageGap;
  }
  return value
      .clamp(ViewerSettings.minComicPageGap, ViewerSettings.maxComicPageGap)
      .toDouble();
}

T _readEnum<T extends Enum>(List<T> values, Object? value, T fallback) {
  if (value is String) {
    for (final item in values) {
      if (item.name == value) return item;
    }
  }
  return fallback;
}

String _readLocaleCode(Object? value) => switch (value) {
  'zh' => 'zh',
  'en' => 'en',
  _ => 'system',
};
