import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../application/app_info.dart';
import '../application/file_association_service.dart';
import '../application/decoder_registry.dart';
import '../domain/comic_layout_direction.dart';
import '../domain/folder_browse_mode.dart';
import '../domain/viewer_settings.dart';
import '../domain/viewer_mode.dart';
import '../domain/view_scale_mode.dart';
import 'components/app_button.dart';
import 'components/app_description_link.dart';
import 'components/app_dialog.dart';
import 'components/app_icon_button.dart';
import 'components/app_input.dart';
import 'components/app_interactive_surface.dart';
import 'components/app_number_input_formatter.dart';
import 'components/app_search_text.dart';
import 'components/app_select.dart';
import 'components/app_slider.dart';
import 'components/app_shortcut_keycap.dart';
import 'components/app_switch.dart';
import 'components/app_text_action.dart';
import '../domain/animation_timeline.dart';
import '../domain/auto_play_settings.dart';
import 'animation_playback_bar.dart' show animationLoopLabel;
import 'components/app_tab_switch.dart';
import 'licenses_page.dart';
import 'file_associations_dialog.dart';
import 'localized_labels.dart';
import 'recent_open_page.dart';
import 'theme/app_styles.dart';
import 'theme/app_theme.dart';
import 'theme/app_tokens.dart';
import 'viewer_shortcuts.dart';
import 'shortcut_editor_dialog.dart';

const _contentMaxWidth = 760.0;
const _selectControlWidth = 220.0;

/// Page-gap choices. [custom] keeps the current pixel value and reveals the
/// slider instead of jumping to a preset.
enum _ComicGapPreset {
  none(0),
  tight(4),
  standard(8),
  loose(16),
  custom(null);

  const _ComicGapPreset(this.value);

  final double? value;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.settings,
    required this.onChanged,
    required this.decoderRegistry,
    this.archiveCacheUsageBytes,
    this.onClearArchiveCache,
    this.archivePerformanceStatus,
    this.onClearRecentOpen,
    this.onResetAll,
    this.shortcuts = ViewerShortcutBindings.defaults,
    super.key,
  });

  final ViewerSettings settings;
  final ValueChanged<ViewerSettings> onChanged;
  final ValueChanged<ViewerSettings>? onResetAll;
  final ViewerShortcutBindings shortcuts;
  final DecoderRegistry decoderRegistry;
  final int? archiveCacheUsageBytes;
  final Future<void> Function()? onClearArchiveCache;
  final String? archivePerformanceStatus;
  final Future<void> Function()? onClearRecentOpen;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

enum _SettingsSection {
  general,
  appearance,
  browsing,
  reading,
  interaction,
  playback,
  archives,
  image,
  shortcuts,
  about,
}

class _SettingsPageState extends State<SettingsPage> {
  late ViewerSettings _settings = widget.settings;
  _SettingsSection _selected = _SettingsSection.general;
  final _scrollControllers = {
    for (final section in _SettingsSection.values) section: ScrollController(),
  };
  final _pageStorage = PageStorageBucket();
  final _searchController = TextEditingController();
  final _shortcutSearchController = TextEditingController();
  String _shortcutQuery = '';
  final _searchContentKey = GlobalKey();
  final _searchTranslations = <String, String>{};
  int _searchGroupSerial = 0;
  int? _relatedSearchGroup;
  String? _lastSearchTarget;
  final _archiveSortTargetKey = GlobalKey();
  final _archiveSortFocus = FocusNode();
  String _query = '';
  bool _comicGapCustom = false;
  bool _formatsExpanded = false;
  int _playbackResetGeneration = 0;
  double? _comicGapDrag;
  bool _archiveMemoryCustom = false;
  bool _clearingArchiveCache = false;
  String? _archiveCacheMessage;
  String? _recentOpenMessage;
  final _archiveMemoryController = TextEditingController();
  final _archiveMemoryFormatter = AppNumberInputFormatter(integerDigits: 4);
  String? _archiveMemoryError;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchEditingChanged);
    _shortcutSearchController.addListener(_onShortcutSearchChanged);
  }

  @override
  void dispose() {
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    _searchController.dispose();
    _shortcutSearchController.dispose();
    _archiveSortFocus.dispose();
    _archiveMemoryController.dispose();
    super.dispose();
  }

  void _update(ViewerSettings settings, {bool resetAll = false}) {
    if (settings == _settings) return;
    setState(() => _settings = settings);
    final onChanged = resetAll
        ? widget.onResetAll ?? widget.onChanged
        : widget.onChanged;
    onChanged(settings);
  }

  String _copy(String zh, String en) {
    final localized = AppLocalizations.of(context)!.localeName.startsWith('zh')
        ? zh
        : en;
    _searchTranslations[zh.toLowerCase()] = localized;
    _searchTranslations[en.toLowerCase()] = localized;
    return localized;
  }

  // Generated localizations and inline bilingual copy share the same search
  // aliases. Keep title/description pairs together in this index.
  List<String> _localizedSearchLabels(AppLocalizations l10n) => [
    l10n.language,
    l10n.theme,
    l10n.toolbarMode,
    l10n.toolbarModeDescription,
    l10n.showBottomBar,
    l10n.showBottomBarDescription,
    l10n.showThumbnailFileNames,
    l10n.showThumbnailFileNamesDescription,
    l10n.directoryNavigationVisible,
    l10n.directoryNavigationVisibleDescription,
    l10n.pinDirectory,
    l10n.pinDirectoryDescription,
    l10n.recursiveFolderBrowsing,
    l10n.recursiveFolderBrowsingDescription,
    l10n.folderContinuousReading,
    l10n.folderContinuousReadingDescription,
    l10n.watchFolderChanges,
    l10n.watchFolderChangesDescription,
    l10n.scanUnknownExtensions,
    l10n.scanUnknownExtensionsDescription,
    l10n.sortOrder,
    l10n.sortOrderDescription,
    l10n.fileNameSortMode,
    l10n.fileNameSortModeDescription,
    l10n.archiveReading,
    l10n.archiveContinuousReading,
    l10n.archiveContinuousReadingDescription,
    l10n.archiveSortOrder,
    l10n.archiveSortDescription,
    l10n.archiveAutoAdvance,
    l10n.archiveAutoAdvanceDescription,
    l10n.archivePrefetchMode,
    l10n.archivePrefetchDescription,
    l10n.archiveMemoryBudget,
    l10n.archiveMemoryDescription,
    l10n.archiveCache,
    l10n.archivePersistCache,
    l10n.archivePersistDescription,
    l10n.archiveDiskBudget,
    l10n.archiveDiskDescription,
    l10n.archiveRetention,
    l10n.archiveRetentionDescription,
    l10n.archiveCacheUsage,
    l10n.doublePageCoverAlone,
    l10n.comicUniformSize,
    l10n.comicPageGap,
    l10n.animationAutoPlay,
    l10n.animationAutoPlayDescription,
    l10n.animationLoopMode,
    l10n.animationDefaultLoopDescription,
    l10n.animationDefaultSpeed,
    l10n.animationDefaultSpeedDescription,
    l10n.animationControlsDisplay,
    l10n.animationControlsDisplayDescription,
    l10n.parsingCapabilities,
  ];

  void _registerLocalizedSearchAliases() {
    final zh = _localizedSearchLabels(
      lookupAppLocalizations(const Locale('zh')),
    );
    final en = _localizedSearchLabels(
      lookupAppLocalizations(const Locale('en')),
    );
    final localized = _localizedSearchLabels(AppLocalizations.of(context)!);
    for (var index = 0; index < localized.length; index++) {
      _searchTranslations[zh[index].toLowerCase()] = localized[index];
      _searchTranslations[en[index].toLowerCase()] = localized[index];
    }
  }

  String _sectionLabel(_SettingsSection section) => switch (section) {
    _SettingsSection.general => _copy('通用', 'General'),
    _SettingsSection.appearance => _copy('外观', 'Appearance'),
    _SettingsSection.browsing => _copy('浏览', 'Browsing'),
    _SettingsSection.reading => _copy('查看与阅读', 'Viewing & reading'),
    _SettingsSection.interaction => _copy('操作', 'Interaction'),
    _SettingsSection.playback => _copy('播放', 'Playback'),
    _SettingsSection.archives => AppLocalizations.of(context)!.archiveSettings,
    _SettingsSection.image => _copy('图像与 HDR', 'Images & HDR'),
    _SettingsSection.shortcuts => _copy('快捷键', 'Shortcuts'),
    _SettingsSection.about => _copy('关于', 'About'),
  };

  String _sectionDescription(_SettingsSection section) => switch (section) {
    _SettingsSection.interaction => _copy(
      '滚轮、连续切图和图片切换动画。',
      'Wheel, repeated navigation and image transitions.',
    ),
    _SettingsSection.archives => AppLocalizations.of(
      context,
    )!.archiveSettingsDescription,
    _SettingsSection.general => _copy(
      '语言、窗口行为与最近打开记录。',
      'Language, window behavior and recent items.',
    ),
    _SettingsSection.appearance => _copy(
      '主题与界面元素的显示方式。',
      'Theme and how interface elements are shown.',
    ),
    _SettingsSection.browsing => _copy(
      '目录导航、浏览范围、扫描与排序。',
      'Directory navigation, browsing scope, scanning and sorting.',
    ),
    _SettingsSection.reading => _copy(
      '默认查看方式、尺寸适配与阅读排版。',
      'Default viewing mode, sizing and reading layout.',
    ),
    _SettingsSection.playback => _copy(
      '自动换图、自动滚动与动图播放。',
      'Automatic image changes, scrolling and animation playback.',
    ),
    _SettingsSection.image => _copy(
      '缩略图预加载、HDR 显示与支持的图片格式。',
      'Thumbnail preloading, HDR display and supported image formats.',
    ),
    _SettingsSection.shortcuts => _copy(
      '按功能名或按键搜索，点击键位修改。',
      'Search actions or keys, then click a binding to edit.',
    ),
    _SettingsSection.about => _copy(
      '版本信息、软件说明和开源许可。',
      'Version, software information and open-source licenses.',
    ),
  };

  IconData _sectionIcon(_SettingsSection section) => switch (section) {
    _SettingsSection.interaction => FluentIcons.cursor_20_regular,
    _SettingsSection.archives => FluentIcons.archive_20_regular,
    _SettingsSection.general => FluentIcons.options_20_regular,
    _SettingsSection.appearance => FluentIcons.color_20_regular,
    _SettingsSection.browsing => FluentIcons.folder_open_20_regular,
    _SettingsSection.reading => FluentIcons.book_open_20_regular,
    _SettingsSection.playback => FluentIcons.play_circle_20_regular,
    _SettingsSection.image => FluentIcons.image_20_regular,
    _SettingsSection.shortcuts => FluentIcons.keyboard_20_regular,
    _SettingsSection.about => FluentIcons.info_20_regular,
  };

  String _searchTerms(_SettingsSection section) => switch (section) {
    _SettingsSection.interaction => '操作 interaction 滚轮 wheel 触摸板 trackpad 滚动 scroll 切换 switch 翻页 navigation 连续 repeat 长按 hold 键盘 keyboard 频率 interval 速度 speed 动画 animation 过渡 transition 淡入 fade 滑动 slide 缩放 zoom 保持 keep 比例 scale 位置 position 中心 center 鼠标 pointer',
    _SettingsSection.archives => '首尾 同级 相邻 换包 next previous 压缩包 archive 章节 chapter 密码 password 预加载 prefetch preload 缓存 cache 内存 memory 磁盘 disk 容量 budget 连读 continuous 排序 sort',
    _SettingsSection.general => '通用 general 设置管理 management 恢复所有 重置 全部 reset all defaults 实例 进程 单进程 多进程 instance process single multi 语言 language 系统 system 中文 chinese english 窗口 window 置顶 always on top pin 最近 打开 recent history 历史 记录 清空 clear 启动 startup 恢复 restore 数量 limit 文件关联 association 打开方式 默认应用 default apps 压缩包 漫画 archive comic',
    _SettingsSection.appearance => '外观 appearance 主题 theme 深色 dark 浅色 light 界面 interface 工具栏 toolbar 模式 mode 悬浮 floating 普通 normal 底部栏 bottom bar 缩略图 thumbnail 文件名 file name 目录 directory 导航 navigation 显示 show visible 固定 pin',
    _SettingsSection.browsing => '显示 show visible 自然 natural 字符串 lexicographic 文件名 排序规则 固定 pin 目录 directory 导航 navigation 章节 chapter 连续 continuous 浏览 browsing 文件夹 folder 递归 recursive 子文件夹 subfolder 平铺 flat 压缩包 archive 未知扩展名 unknown extension 扫描 scan 自动刷新 refresh watch 监听 monitor 变化 change 排序 sort 顺序 order 名称 name 大小 size 修改时间 modified',
    _SettingsSection.reading => '单页 single page 长图 long image 尺寸匹配 查看 默认 default 查看方式 viewing mode 尺寸适配 sizing fit 缩放 zoom 适应窗口 实际大小 宽度 width 高度 height 阅读 reading 连续 continuous 统一 uniform 宽高 size 方向 direction 漫画 comic 双页 double page 封面 cover 宽图 wide 独占 alone 拆分 split 扫描 scan 触屏 touch 滑动 swipe Shift 页间距 gap spacing 无 none 标准 standard 自定义 custom 紧凑 tight 宽松 loose',
    _SettingsSection.playback => '单页 single page 双页 double 长图 long image 连续阅读 continuous 停留 dwell 秒 seconds 像素 pixels 播放 playback 自动播放 autoplay 自动换图 advancing 自动滚动 scrolling 间隔 interval 速度 speed 循环 loop 动图 animation gif webp apng 倍速 播放条 controls 状态面板 status 自动隐藏 hide 始终显示 always',
    _SettingsSection.image => '图像 image 缩略图 预览图 thumbnail 胶片栏 filmstrip 预加载 preloading preload prefetch 自动 automatic 保守 conservative 关闭 off 性能 performance 缓存 cache 解码 decoding 解析 parsing hdr 高动态范围 显示 display 格式 format jpeg png gif webp bmp tiff apng jxl heic avif raw gain map dolby vision pq hlg 元数据 metadata',
    _SettingsSection.shortcuts => '快捷键 shortcuts 键盘 keyboard 按键 key 空格 space 全屏 fullscreen 打印 print 颜色拾取 取色 color picker 网格 grid 缩略图 thumbnails 无边框 borderless 新建窗口 new window',
    _SettingsSection.about => '关于 about 软件说明 version 版本 开源 open source license 许可 第三方 third party imagemagick 7-zip flutter dart',
  };

  bool _matches(_SettingsSection section) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    if (section == _SettingsSection.shortcuts) {
      return _shortcutCategoryMatches ||
          _shortcutGroups().entries.any(
            (group) => group.value.any(
              (shortcut) => _shortcutMatches(group.key, shortcut),
            ),
          );
    }
    final terms = _searchTerms(section).toLowerCase();
    return query.split(RegExp(r'\s+')).every((term) => terms.contains(term));
  }

  void _onSearchEditingChanged() {
    final value = _searchController.value;
    // Let the IME finish pinyin/candidate composition before filtering or
    // rebuilding the results. A commit may change only the composing range,
    // so listen to the editing value instead of TextField.onChanged.
    if (value.composing.isValid && !value.composing.isCollapsed) return;
    _onSearchChanged(value.text);
  }

  void _onSearchChanged(String value) {
    if (_query == value) return;
    setState(() {
      _query = value;
      _relatedSearchGroup = null;
      if (value.trim().isEmpty) _lastSearchTarget = null;
      if (value.trim().isEmpty || _matches(_selected)) return;
      for (final section in _SettingsSection.values) {
        if (_matches(section)) {
          _selected = section;
          return;
        }
      }
      _lastSearchTarget = null;
    });
    _scheduleSearchLocation();
  }

  void _selectSection(_SettingsSection section) {
    setState(() {
      _selected = section;
      _relatedSearchGroup = null;
      _lastSearchTarget = null;
    });
    _scheduleSearchLocation();
  }

  void _scheduleSearchLocation() {
    final query = _query;
    final section = _selected;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || query != _query || section != _selected) return;
      final composing = _searchController.value.composing;
      if (query.trim().isEmpty ||
          (composing.isValid && !composing.isCollapsed)) {
        return;
      }
      _locateSearchResult();
    });
  }

  void _locateSearchResult() {
    final root = _searchContentKey.currentContext;
    if (root == null) return;
    final terms = AppSearchScope.terms(_query);
    final texts = <Element>[];
    void collect(Element element) {
      if (element.widget is AppSearchText ||
          element.widget is AppDescriptionLink) {
        texts.add(element);
        return;
      }
      element.visitChildren(collect);
    }

    String textOf(Element element) => switch (element.widget) {
      AppSearchText(:final data) => data,
      AppDescriptionLink(:final text) => text,
      _ => '',
    };

    root.visitChildElements(collect);
    bool containsTerm(String text) =>
        terms.any((term) => text.toLowerCase().contains(term));
    Element? target;
    for (final element in texts) {
      if (textOf(element).trim().toLowerCase() == _query.trim().toLowerCase()) {
        target = element;
        break;
      }
    }
    // Prefer the exact multi-keyword result before falling back to one term.
    // For example, 动图 倍速 should locate animation speed, not auto-play policy.
    for (final element in texts) {
      if (target != null) break;
      final text = textOf(element).toLowerCase();
      if (terms.every(text.contains)) {
        target = element;
        break;
      }
    }
    var related = false;
    for (final element in texts) {
      if (target != null) break;
      if (containsTerm(textOf(element))) {
        target = element;
        break;
      }
    }
    if (target == null) {
      // Bilingual labels also serve as aliases, e.g. wheel → 普通滚轮.
      final aliases = {
        for (final entry in _searchTranslations.entries)
          if (containsTerm(entry.key)) entry.value,
      };
      for (final element in texts) {
        if (aliases.contains(textOf(element))) {
          target = element;
          related = true;
          break;
        }
      }
    }
    // A keyword with no visible translation identifies only the category.
    final categoryOnly = target == null;
    if (categoryOnly) {
      target = root as Element;
      related = true;
    }
    int? groupOf(Element text) {
      int? group;
      text.visitAncestorElements((element) {
        final key = element.widget.key;
        if (key is ValueKey<String> &&
            key.value.startsWith('settings.searchGroup.')) {
          group = int.parse(key.value.split('.').last);
          return false;
        }
        return true;
      });
      return group;
    }

    var group = groupOf(target);
    // Group headings precede their card rather than being inside it.
    if (related && group == null) {
      for (final text in texts.skip(texts.indexOf(target) + 1)) {
        group = groupOf(text);
        if (group != null) break;
      }
    }
    final relatedGroup = categoryOnly ? -1 : (related ? group : null);
    if (_relatedSearchGroup != relatedGroup) {
      setState(() => _relatedSearchGroup = relatedGroup);
    }
    final identity = '${_selected.name}:${textOf(target)}';
    if (_lastSearchTarget == identity) return;
    _lastSearchTarget = identity;
    final render = target.findRenderObject();
    final scrollable = Scrollable.maybeOf(target);
    final viewport = scrollable?.context.findRenderObject();
    if (render is RenderBox && viewport is RenderBox) {
      final offset = render.localToGlobal(Offset.zero, ancestor: viewport);
      if (offset.dy >= 0 &&
          offset.dy + render.size.height <= viewport.size.height) {
        return;
      }
    }
    Scrollable.ensureVisible(
      target,
      alignment: 0.15,
      duration: const Duration(milliseconds: 200),
    );
  }

  void _openArchiveSortSettings() {
    _searchController.clear();
    setState(() {
      _query = '';
      _relatedSearchGroup = null;
      _lastSearchTarget = null;
      _selected = _SettingsSection.archives;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selected != _SettingsSection.archives) return;
      final target = _archiveSortTargetKey.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.15,
        duration: const Duration(milliseconds: 200),
      );
      _archiveSortFocus.requestFocus();
    });
  }

  bool _hasSectionSettings(_SettingsSection section) =>
      section != _SettingsSection.about;

  ViewerSettings _sectionDefaults(_SettingsSection section) {
    const defaults = ViewerSettings();
    return switch (section) {
      _SettingsSection.interaction => _settings.copyWith(
        interaction: defaults.interaction,
      ),
      _SettingsSection.general => _settings.copyWith(
        localeCode: defaults.localeCode,
        alwaysOnTop: defaults.alwaysOnTop,
        recentOpenEnabled: defaults.recentOpenEnabled,
        recentOpenLimit: defaults.recentOpenLimit,
        openRecentOnNewWindow: defaults.openRecentOnNewWindow,
        instanceMode: defaults.instanceMode,
      ),
      _SettingsSection.appearance => _settings.copyWith(
        themeMode: defaults.themeMode,
        toolbarMode: defaults.toolbarMode,
        showBottomBar: defaults.showBottomBar,
        showThumbnailFileNames: defaults.showThumbnailFileNames,
        showDirectoryPanel: defaults.showDirectoryPanel,
        pinDirectoryPanel: defaults.pinDirectoryPanel,
      ),
      _SettingsSection.browsing => _settings.copyWith(
        showDirectoryPanel: defaults.showDirectoryPanel,
        pinDirectoryPanel: defaults.pinDirectoryPanel,
        sortOrder: defaults.sortOrder,
        fileNameSortMode: defaults.fileNameSortMode,
        browseMode: defaults.browseMode,
        folderContinuousReading: defaults.folderContinuousReading,
        scanUnknownExtensions: defaults.scanUnknownExtensions,
        watchFolderChanges: defaults.watchFolderChanges,
      ),
      _SettingsSection.reading => _settings.copyWith(
        defaultViewerMode: defaults.defaultViewerMode,
        defaultScaleModes: defaults.defaultScaleModes,
        readingDirection: defaults.readingDirection,
        comicLayoutDirection: defaults.comicLayoutDirection,
        doublePageFirstAlone: defaults.doublePageFirstAlone,
        doublePageWideAlone: defaults.doublePageWideAlone,
        doublePageSplitWide: defaults.doublePageSplitWide,
        comicPageGap: defaults.comicPageGap,
        comicUniformSize: defaults.comicUniformSize,
      ),
      _SettingsSection.archives => _settings.copyWith(
        archiveContinuousReading: defaults.archiveContinuousReading,
        archiveAutoAdvance: defaults.archiveAutoAdvance,
        archiveSortOrder: defaults.archiveSortOrder,
        archivePrefetchMode: defaults.archivePrefetchMode,
        archivePersistCache: defaults.archivePersistCache,
        archiveMemoryBudgetMiB: defaults.archiveMemoryBudgetMiB,
        archiveDiskBudgetMiB: defaults.archiveDiskBudgetMiB,
        archiveCacheRetentionDays: defaults.archiveCacheRetentionDays,
      ),
      _SettingsSection.playback => _settings.copyWith(
        autoPlay: defaults.autoPlay,
        animationAutoPlay: defaults.animationAutoPlay,
        animationLoopMode: defaults.animationLoopMode,
        animationSpeed: defaults.animationSpeed,
        animationControlsMode: defaults.animationControlsMode,
      ),
      _SettingsSection.image => _settings.copyWith(
        thumbnailPrefetchMode: defaults.thumbnailPrefetchMode,
        autoHdr: defaults.autoHdr,
        hdrLinear: defaults.hdrLinear,
        hdrPqHlg: defaults.hdrPqHlg,
        hdrGainMap: defaults.hdrGainMap,
        hdrRaw: defaults.hdrRaw,
        hdrDolbyVision: defaults.hdrDolbyVision,
      ),
      _SettingsSection.shortcuts => _settings.copyWith(
        shortcutOverrides: {
          for (final entry in _settings.shortcutOverrides.entries)
            if (!entry.key.startsWith('${Theme.of(context).platform.name}.'))
              entry.key: entry.value,
        },
      ),
      _SettingsSection.about => _settings,
    };
  }

  bool get _sectionHasChanges => _sectionDefaults(_selected) != _settings;

  Future<void> _confirmReset({bool all = false}) async {
    if (all ? _settings == const ViewerSettings() : !_sectionHasChanges) return;
    final confirmed = await showDialog<bool>(
      context: context,
      requestFocus: true,
      builder: (dialogContext) {
        final tokens = ViewerThemeTokens.of(dialogContext);
        final label = _sectionLabel(_selected);
        return Dialog(
          insetPadding: const EdgeInsets.all(AppTokens.space5),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSearchText(
                    all
                        ? _copy('恢复所有设置？', 'Reset all settings?')
                        : _copy('恢复本页默认？', 'Reset this page?'),
                    style: AppTextStyles.sectionTitle.copyWith(
                      color: tokens.textPrimary,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: SingleChildScrollView(
                      primary: false,
                      child: AppSearchText(
                        all
                            ? _copy(
                                '将所有分类中的设置恢复为默认值，包括语言、外观、阅读与目录宽度。不会清除阅读进度或最近打开记录。缓存按恢复后的策略管理。更改会立即保存，生效时机以设置说明为准。',
                                'Restore every category to its defaults, including language, appearance, reading and directory width. Reading progress and recent items are kept. Cache follows the restored policy. Changes are saved immediately and take effect as described by each setting.',
                              )
                            : _copy(
                                '只重置「$label」分类中的设置，不清除各位置的阅读记录。更改会立即保存，生效时机以设置说明为准。',
                                'Only resets the “$label” settings. Reading records for each location are kept. Changes are saved immediately and take effect as described by each setting.',
                              ),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: tokens.textSecondary,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AppDialogActions(
                    children: [
                      AppButton(
                        label: AppLocalizations.of(dialogContext)!.cancel,
                        variant: AppButtonVariant.neutral,
                        autofocus: true,
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                      ),
                      AppButton(
                        label: all
                            ? _copy('恢复所有设置', 'Reset all')
                            : _copy('恢复默认', 'Reset'),
                        variant: AppButtonVariant.accent,
                        leadingIcon: FluentIcons.arrow_reset_20_regular,
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;
    if (all) {
      setState(() {
        _playbackResetGeneration++;
        _comicGapCustom = false;
        _comicGapDrag = null;
        _archiveMemoryCustom = false;
        _archiveMemoryError = null;
        _archiveMemoryController.clear();
      });
      _update(const ViewerSettings(), resetAll: true);
    } else {
      _resetSelected();
    }
  }

  void _resetSelected() {
    if (!_sectionHasChanges) return;
    if (_selected == _SettingsSection.playback) _playbackResetGeneration++;
    if (_comicGapCustom) setState(() => _comicGapCustom = false);
    if (_selected == _SettingsSection.archives) {
      _archiveMemoryCustom = false;
      _archiveMemoryError = null;
      _archiveMemoryController.clear();
    }
    _update(_sectionDefaults(_selected));
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    _searchTranslations.clear();
    _registerLocalizedSearchAliases();
    return AppSearchScope(
      query: _query,
      child: Scaffold(
        backgroundColor: tokens.appBackground,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final sidebarWidth = compact
                ? 64.0
                : constraints.maxWidth < 1000
                ? 224.0
                : 248.0;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSidebar(tokens, compact: compact, width: sidebarWidth),
                Expanded(child: _buildContentArea(tokens, compact: compact)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSidebar(
    ViewerThemeTokens tokens, {
    required bool compact,
    required double width,
  }) {
    return Container(
      width: width,
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 16,
        14,
        compact ? 12 : 16,
        12,
      ),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(right: BorderSide(color: tokens.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSidebarHeader(tokens, compact: compact),
          SizedBox(height: compact ? 10 : 16),
          if (!compact) ...[
            _buildSearchField(tokens),
            const SizedBox(height: 14),
          ],
          Expanded(child: _buildNavigation(tokens, compact: compact)),
          const SizedBox(height: AppTokens.space2),
          _buildResetAll(compact: compact),
          if (!compact) ...[
            const SizedBox(height: AppTokens.space2),
            Row(
              children: [
                Icon(
                  FluentIcons.checkmark_circle_16_regular,
                  size: 14,
                  color: tokens.textTertiary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: AppSearchText(
                    _copy('更改会立即保存', 'Changes are saved immediately'),
                    style: AppTextStyles.finePrint.copyWith(
                      color: tokens.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResetAll({required bool compact}) {
    final label = _copy('恢复所有设置', 'Reset all settings');
    final onPressed = _settings == const ViewerSettings()
        ? null
        : () => _confirmReset(all: true);
    if (compact) {
      return AppIconButton(
        key: const ValueKey('settings.resetAll'),
        icon: FluentIcons.arrow_reset_20_regular,
        tooltip: label,
        onPressed: onPressed,
      );
    }
    return AppButton(
      key: const ValueKey('settings.resetAll'),
      label: label,
      leadingIcon: FluentIcons.arrow_reset_20_regular,
      variant: AppButtonVariant.neutral,
      expand: true,
      tooltip: _copy(
        '恢复所有分类的默认值，保留阅读进度与最近打开记录。',
        'Reset every category to its defaults. Keep reading progress and recent items.',
      ),
      onPressed: onPressed,
    );
  }

  Widget _buildSidebarHeader(
    ViewerThemeTokens tokens, {
    required bool compact,
  }) {
    final canPop = Navigator.of(context).canPop();
    final back = canPop
        ? AppIconButton(
            icon: FluentIcons.chevron_left_20_regular,
            tooltip: _copy('返回', 'Back'),
            onPressed: () => Navigator.of(context).maybePop(),
          )
        : null;
    if (compact) {
      return SizedBox(
        height: 36,
        child: Center(
          child:
              back ??
              Icon(
                FluentIcons.settings_20_regular,
                size: 18,
                color: tokens.textSecondary,
              ),
        ),
      );
    }
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          if (back != null) ...[back, const SizedBox(width: 6)],
          Expanded(
            child: AppSearchText(
              _copy('设置', 'Settings'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.subtitle.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(ViewerThemeTokens tokens) => AppInput(
    key: const ValueKey('settings.search'),
    controller: _searchController,
    hint: _copy('搜索设置', 'Search settings'),
    leadingIcon: FluentIcons.search_20_regular,
    clearTooltip: _copy('清除搜索', 'Clear search'),
    onClear: _clearSearch,
  );

  Widget _buildNavigation(ViewerThemeTokens tokens, {required bool compact}) {
    const editable = [
      _SettingsSection.general,
      _SettingsSection.appearance,
      _SettingsSection.browsing,
      _SettingsSection.reading,
      _SettingsSection.interaction,
      _SettingsSection.playback,
      _SettingsSection.archives,
      _SettingsSection.image,
      _SettingsSection.shortcuts,
    ];
    const reference = [_SettingsSection.about];
    final items = <Widget>[
      for (final section in editable)
        if (_matches(section))
          _navigationItem(section, tokens, compact: compact),
      if (reference.any(_matches)) ...[
        if (compact)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              height: 1,
              color: tokens.border.withValues(alpha: 0.7),
            ),
          )
        else ...[
          Container(
            height: 1,
            margin: const EdgeInsets.fromLTRB(12, 16, 12, 8),
            color: tokens.border.withValues(alpha: 0.7),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: AppSearchText(
              _copy('参考', 'Reference'),
              style: AppTextStyles.finePrint.copyWith(
                color: tokens.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        for (final section in reference)
          if (_matches(section))
            _navigationItem(section, tokens, compact: compact),
      ],
    ];
    return ListView(padding: EdgeInsets.zero, children: items);
  }

  Widget _navigationItem(
    _SettingsSection section,
    ViewerThemeTokens tokens, {
    required bool compact,
  }) {
    final selected = section == _selected;
    final available = _matches(section);
    final label = _sectionLabel(section);
    final iconColor = selected
        ? tokens.accentStrong
        : available
        ? tokens.textSecondary
        : tokens.textDisabled;
    final textColor = selected
        ? tokens.textPrimary
        : available
        ? tokens.textSecondary
        : tokens.textDisabled;
    final item = AppInteractiveSurface(
      key: ValueKey('settings.nav.${section.name}'),
      selected: selected,
      radius: AppTokens.menuRadius,
      onTap: available ? () => _selectSection(section) : null,
      child: SizedBox(
        height: 40,
        child: compact
            ? Center(
                child: Icon(_sectionIcon(section), size: 18, color: iconColor),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(_sectionIcon(section), size: 18, color: iconColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppSearchText(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          color: textColor,
                          height: 1.2,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
    final padded = Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: item,
    );
    if (!compact) return padded;
    return Tooltip(message: label, child: padded);
  }

  Widget _buildContentArea(ViewerThemeTokens tokens, {required bool compact}) {
    _searchGroupSerial = 0;
    final content = _matches(_selected)
        ? SingleChildScrollView(
            key: PageStorageKey('settings.content.${_selected.name}'),
            controller: _scrollControllers[_selected],
            primary: false,
            padding: EdgeInsets.fromLTRB(
              compact ? 20 : 28,
              compact ? 14 : 24,
              compact ? 20 : 32,
              32,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DecoratedBox(
                      key: _searchContentKey,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          AppTokens.containerRadius,
                        ),
                        border: Border.all(
                          color: _relatedSearchGroup == -1
                              ? tokens.accentStrong
                              : tokens.accent.withValues(alpha: 0),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _buildSection(_selected, tokens),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        : _buildNoResults(tokens);
    return Column(
      children: [
        if (compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: _buildSearchField(tokens),
          ),
        if (_matches(_selected))
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 20 : 28,
              compact ? 14 : 24,
              compact ? 20 : 32,
              0,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                child: SizedBox(
                  width: double.infinity,
                  child: _buildHeader(tokens),
                ),
              ),
            ),
          ),
        if (_selected == _SettingsSection.shortcuts && _matches(_selected))
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 20 : 28,
              16,
              compact ? 20 : 32,
              0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                child: AppInput(
                  key: const ValueKey('settings.shortcuts.search'),
                  controller: _shortcutSearchController,
                  hint: _copy('搜索快捷键名称或按键', 'Search shortcut actions or keys'),
                  leadingIcon: FluentIcons.search_20_regular,
                  clearTooltip: _copy('清除快捷键搜索', 'Clear shortcut search'),
                  onClear: _shortcutSearchController.clear,
                ),
              ),
            ),
          ),
        Expanded(
          child: PageStorage(bucket: _pageStorage, child: content),
        ),
      ],
    );
  }

  Widget _buildNoResults(ViewerThemeTokens tokens) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.search_info_20_regular,
              size: 28,
              color: tokens.textTertiary,
            ),
            const SizedBox(height: AppTokens.space3),
            AppSearchText(
              _copy('没有匹配的设置', 'No matching settings'),
              style: AppTextStyles.bodyLarge.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            AppSearchText(
              _copy(
                '试试“主题”“缩略图”或“连续阅读”。',
                'Try “theme”, “thumbnail” or “continuous”.',
              ),
              textAlign: TextAlign.center,
              style: AppTextStyles.label.copyWith(color: tokens.textTertiary),
            ),
            const SizedBox(height: AppTokens.space4),
            AppButton(
              label: _copy('清除搜索', 'Clear search'),
              variant: AppButtonVariant.subtle,
              leadingIcon: FluentIcons.dismiss_20_regular,
              onPressed: _clearSearch,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ViewerThemeTokens tokens) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSearchText(
          _sectionLabel(_selected),
          style: AppTextStyles.pageTitle.copyWith(
            color: tokens.textPrimary,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        AppSearchText(
          _sectionDescription(_selected),
          style: AppTextStyles.bodySmall.copyWith(
            color: tokens.textTertiary,
            height: 1.5,
          ),
        ),
      ],
    );
    if (!_hasSectionSettings(_selected)) return title;
    final action = AppButton(
      key: const ValueKey('settings.resetSection'),
      label: _copy('恢复本页默认', 'Reset this page'),
      variant: AppButtonVariant.subtle,
      leadingIcon: FluentIcons.arrow_reset_20_regular,
      tooltip: _copy(
        _selected == _SettingsSection.shortcuts
            ? '恢复当前平台的全部默认快捷键。'
            : '仅重置本页设置；共用的目录导航偏好同步更新。',
        _selected == _SettingsSection.shortcuts
            ? 'Restore all default shortcuts for this platform.'
            : 'Only resets settings on this page; shared directory preferences stay in sync.',
      ),
      onPressed: _sectionHasChanges ? () => _confirmReset() : null,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 470) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 14), action],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            const SizedBox(width: 20),
            Padding(padding: const EdgeInsets.only(top: 2), child: action),
          ],
        );
      },
    );
  }

  List<Widget> _buildSection(
    _SettingsSection section,
    ViewerThemeTokens tokens,
  ) {
    switch (section) {
      case _SettingsSection.interaction:
        return _buildInteraction(tokens);
      case _SettingsSection.general:
        return [
          if (const FileAssociationService().isSupported) ...[
            _buildFileAssociations(tokens),
            const SizedBox(height: AppTokens.space5),
          ],
          _buildGeneral(tokens),
        ];
      case _SettingsSection.appearance:
        return [
          _group(
            tokens,
            _copy('显示', 'Display'),
            _buildAppearanceDisplay(tokens),
          ),
          const SizedBox(height: AppTokens.space5),
          _group(
            tokens,
            _copy('界面', 'Interface'),
            _buildAppearanceInterface(tokens),
          ),
          const SizedBox(height: AppTokens.space5),
          _buildDirectoryNavigation(tokens),
        ];
      case _SettingsSection.browsing:
        return [_buildBrowsing(tokens)];
      case _SettingsSection.reading:
        return [_buildReading(tokens)];
      case _SettingsSection.playback:
        return _buildPlayback(tokens);
      case _SettingsSection.archives:
        return _buildArchives(tokens);
      case _SettingsSection.image:
        return _buildImage(tokens);
      case _SettingsSection.shortcuts:
        return [_buildShortcuts(tokens)];
      case _SettingsSection.about:
        return _buildAbout(tokens);
    }
  }

  Widget _group(
    ViewerThemeTokens tokens,
    String title,
    Widget child, {
    String? trailing,
    String? description,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
          child: Row(
            children: [
              Expanded(
                child: AppSearchText(
                  title,
                  style: AppTextStyles.label.copyWith(
                    color: tokens.textTertiary,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (trailing != null)
                AppSearchText(
                  trailing,
                  style: AppTextStyles.finePrint.copyWith(
                    color: tokens.textTertiary,
                  ),
                ),
            ],
          ),
        ),
        if (description != null) _note(tokens, description),
        child,
      ],
    );
  }

  Widget _note(ViewerThemeTokens tokens, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
    child: AppSearchText(
      text,
      style: AppTextStyles.label.copyWith(
        color: tokens.textTertiary,
        height: 1.5,
      ),
    ),
  );

  Widget _card(ViewerThemeTokens tokens, List<Widget> rows) {
    final searchGroup = _searchGroupSerial++;
    final children = <Widget>[];
    for (var index = 0; index < rows.length; index++) {
      if (index > 0) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Container(
              height: 1,
              color: tokens.border.withValues(alpha: 0.65),
            ),
          ),
        );
      }
      children.add(rows[index]);
    }
    return DecoratedBox(
      key: ValueKey('settings.searchGroup.$searchGroup'),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AppTokens.containerRadius),
        border: Border.all(
          color: _relatedSearchGroup == searchGroup
              ? tokens.accentStrong
              : tokens.border.withValues(alpha: 0.65),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.containerRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  List<Widget> _buildInteraction(ViewerThemeTokens tokens) {
    final value = _settings.interaction;
    return [
      _group(
        tokens,
        _copy('滚轮与滚动', 'Wheel & scrolling'),
        _card(tokens, [
          _selectRow<WheelAction>(
            key: const ValueKey('settings.wheelAction'),
            title: _copy('滚轮操作', 'Wheel action'),
            description: _copy(
              '单页、双页模式使用此操作；长图和连续阅读模式始终滚动。Ctrl + 滚轮始终缩放。',
              'Applies to Single page and Double page modes. Long image and Continuous reading modes always scroll. Ctrl + wheel always zooms.',
            ),
            value: value.wheelAction,
            items: {
              WheelAction.navigate: _copy('翻页', 'Turn pages'),
              WheelAction.zoom: _copy('缩放', 'Zoom'),
            },
            onChanged: (next) => _update(
              _settings.copyWith(
                interaction: value.copyWith(wheelAction: next),
              ),
            ),
          ),
          _selectRow<int>(
            key: const ValueKey('settings.wheelIntervalMs'),
            title: _copy('滚轮翻页最短间隔', 'Minimum wheel page interval'),
            description: _copy(
              '持续滚动可连续翻页；间隔越大，翻页越慢。主画布与缩略图栏共用。',
              'Keep scrolling to turn pages repeatedly. Longer intervals turn pages more slowly. The canvas and thumbnail strip share this setting.',
            ),
            value: value.wheelIntervalMs,
            items: {
              80: _copy('80 毫秒', '80 ms'),
              120: _copy('120 毫秒', '120 ms'),
              180: _copy('180 毫秒', '180 ms'),
              250: _copy('250 毫秒', '250 ms'),
              350: _copy('350 毫秒', '350 ms'),
              500: _copy('500 毫秒', '500 ms'),
              600: _copy('600 毫秒', '600 ms'),
              if (!{
                80,
                120,
                180,
                250,
                350,
                500,
                600,
              }.contains(value.wheelIntervalMs))
                value.wheelIntervalMs: value.wheelIntervalMs.toString(),
            },
            onChanged: (next) => _update(
              _settings.copyWith(
                interaction: value.copyWith(wheelIntervalMs: next),
              ),
            ),
          ),
          _switchRow(
            title: _copy('反转滚轮翻页方向', 'Reverse wheel page direction'),
            description: _copy(
              '反转普通滚轮的上一张 / 下一张方向。',
              'Reverse previous / next for wheel navigation.',
            ),
            value: value.reverseWheel,
            onChanged: (next) => _update(
              _settings.copyWith(
                interaction: value.copyWith(reverseWheel: next),
              ),
            ),
          ),
          _selectRow<double>(
            key: const ValueKey('settings.scrollSpeed'),
            title: _copy('手动滚动速度', 'Manual scroll speed'),
            description: _copy(
              '调整长图、连续阅读及缩略图横向滚动的距离。',
              'Adjust scroll distance in Long image and Continuous reading modes, and when scrolling the thumbnail strip horizontally.',
            ),
            value: value.scrollSpeed,
            items: {
              0.25: _copy('0.25×', '0.25×'),
              0.5: _copy('0.5×', '0.5×'),
              1.0: _copy('1×', '1×'),
              1.5: _copy('1.5×', '1.5×'),
              2.0: _copy('2×', '2×'),
              3.0: _copy('3×', '3×'),
              if (!{0.25, 0.5, 1.0, 1.5, 2.0, 3.0}.contains(value.scrollSpeed))
                value.scrollSpeed: value.scrollSpeed.toString(),
            },
            onChanged: (next) => _update(
              _settings.copyWith(
                interaction: value.copyWith(scrollSpeed: next),
              ),
            ),
          ),
          _selectRow<double>(
            key: const ValueKey('settings.zoomSpeed'),
            title: _copy('滚轮缩放速度', 'Wheel zoom speed'),
            description: _copy(
              '调整普通缩放操作及 Ctrl + 滚轮的灵敏度。',
              'Sensitivity of wheel zoom and Ctrl + wheel.',
            ),
            value: value.zoomSpeed,
            items: {
              0.25: _copy('0.25×', '0.25×'),
              0.5: _copy('0.5×', '0.5×'),
              1.0: _copy('1×', '1×'),
              1.5: _copy('1.5×', '1.5×'),
              2.0: _copy('2×', '2×'),
              3.0: _copy('3×', '3×'),
              if (!{0.25, 0.5, 1.0, 1.5, 2.0, 3.0}.contains(value.zoomSpeed))
                value.zoomSpeed: value.zoomSpeed.toString(),
            },
            onChanged: (next) => _update(
              _settings.copyWith(interaction: value.copyWith(zoomSpeed: next)),
            ),
          ),
        ]),
      ),
      const SizedBox(height: AppTokens.space5),
      _group(
        tokens,
        _copy('缩放与换图', 'Zoom & image changes'),
        _card(tokens, [
          _switchRow(
            title: AppLocalizations.of(context)!.focusZoom,
            description: _copy(
              '换图时保留实际像素缩放比例，不随图片尺寸重新适配。连续阅读始终保持整条画布的缩放。',
              'Keep the actual pixel scale when changing images. Continuous reading always retains its canvas zoom.',
            ),
            value: value.keepZoom,
            onChanged: (next) => _update(
              _settings.copyWith(interaction: value.copyWith(keepZoom: next)),
            ),
          ),
          if (value.keepZoom)
            _switchRow(
              title: AppLocalizations.of(context)!.keepZoomPosition,
              description: _copy(
                '保持视口中心对应的图片相对位置；关闭后按适配方式从顶部、左侧或中心开始。',
                'Keep the relative image point at the viewport center. Otherwise start at the top, left or center for the sizing mode.',
              ),
              value: value.keepZoomPosition,
              onChanged: (next) => _update(
                _settings.copyWith(
                  interaction: value.copyWith(keepZoomPosition: next),
                ),
              ),
            ),
          _selectRow<ZoomCenter>(
            key: const ValueKey('settings.zoomCenter'),
            title: AppLocalizations.of(context)!.zoomCenter,
            description: _copy(
              '适用于所有查看方式的滚轮和捏合缩放。',
              'Applies to wheel and pinch zoom in every viewing mode.',
            ),
            value: value.zoomCenter,
            items: {
              ZoomCenter.pointer: AppLocalizations.of(context)!
                  .zoomCenterPointer,
              ZoomCenter.viewport: AppLocalizations.of(context)!
                  .zoomCenterViewport,
            },
            onChanged: (next) => _update(
              _settings.copyWith(interaction: value.copyWith(zoomCenter: next)),
            ),
          ),
        ]),
      ),
      const SizedBox(height: AppTokens.space5),
      _group(
        tokens,
        _copy('长按切图', 'Hold to navigate'),
        _card(tokens, [
          _switchRow(
            title: _copy('长按连续切图', 'Repeat while held'),
            description: _copy(
              '适用于键盘 ← / → 和画面两侧翻页按钮。首尾越界时保持当前图片。',
              'Applies to the left and right arrow keys and the buttons at the sides of the image. Stops at the first and last image.',
            ),
            value: value.holdNavigation,
            onChanged: (next) => _update(
              _settings.copyWith(
                interaction: value.copyWith(holdNavigation: next),
              ),
            ),
          ),
          if (value.holdNavigation) ...[
            _selectRow<int>(
              key: const ValueKey('settings.holdDelayMs'),
              title: _copy('长按等待时间', 'Hold delay'),
              description: _copy(
                '按下后先切一张，持续按住达到此时间后开始连续切图。',
                'Change the image once on press, then repeat after holding for this long.',
              ),
              value: value.holdDelayMs,
              items: {
                200: _copy('200 毫秒', '200 ms'),
                300: _copy('300 毫秒', '300 ms'),
                400: _copy('400 毫秒', '400 ms'),
                600: _copy('600 毫秒', '600 ms'),
                800: _copy('800 毫秒', '800 ms'),
                1000: _copy('1000 毫秒', '1000 ms'),
                if (!{
                  200,
                  300,
                  400,
                  600,
                  800,
                  1000,
                }.contains(value.holdDelayMs))
                  value.holdDelayMs: value.holdDelayMs.toString(),
              },
              onChanged: (next) => _update(
                _settings.copyWith(
                  interaction: value.copyWith(holdDelayMs: next),
                ),
              ),
            ),
            _selectRow<int>(
              key: const ValueKey('settings.holdIntervalMs'),
              title: _copy('连续切图间隔', 'Repeat interval'),
              description: _copy(
                '控制长按时的切图频率。松开或窗口失焦后立即停止。',
                'Set how often images change while a key or button is held. Stops when released or when the window loses focus.',
              ),
              value: value.holdIntervalMs,
              items: {
                80: _copy('80 毫秒', '80 ms'),
                120: _copy('120 毫秒', '120 ms'),
                180: _copy('180 毫秒', '180 ms'),
                250: _copy('250 毫秒', '250 ms'),
                350: _copy('350 毫秒', '350 ms'),
                500: _copy('500 毫秒', '500 ms'),
                600: _copy('600 毫秒', '600 ms'),
                if (!{
                  80,
                  120,
                  180,
                  250,
                  350,
                  500,
                  600,
                }.contains(value.holdIntervalMs))
                  value.holdIntervalMs: value.holdIntervalMs.toString(),
              },
              onChanged: (next) => _update(
                _settings.copyWith(
                  interaction: value.copyWith(holdIntervalMs: next),
                ),
              ),
            ),
          ],
        ]),
      ),
      const SizedBox(height: AppTokens.space5),
      _group(
        tokens,
        _copy('切换动画', 'Image transitions'),
        _card(tokens, [
          _selectRow<ImageTransition>(
            key: const ValueKey('settings.transition'),
            title: _copy('切换效果', 'Transition effect'),
            description: _copy(
              '用于单页和双页切图；长图、连续阅读及原生 HDR 显示直接切换。遵循系统减少动态效果设置。',
              'Apply transitions in Single page and Double page modes. Long image, Continuous reading and native HDR switch directly. Follow the system setting to reduce motion.',
            ),
            value: value.transition,
            items: {
              ImageTransition.none: _copy('无动画', 'None'),
              ImageTransition.fade: _copy('淡入淡出', 'Fade'),
              ImageTransition.slide: _copy('横向滑动', 'Slide'),
              ImageTransition.zoom: _copy('轻微缩放', 'Gentle zoom'),
            },
            onChanged: (next) => _update(
              _settings.copyWith(interaction: value.copyWith(transition: next)),
            ),
          ),
          if (value.transition != ImageTransition.none)
            _selectRow<int>(
              key: const ValueKey('settings.transitionDurationMs'),
              title: _copy('动画时长', 'Transition duration'),
              description: _copy(
                '时长越短，切换越利落。连续切图会打断上一段动画。',
                'Shorter durations feel quicker. Repeated navigation interrupts the previous transition.',
              ),
              value: value.transitionDurationMs,
              items: {
                50: _copy('50 毫秒', '50 ms'),
                80: _copy('80 毫秒', '80 ms'),
                140: _copy('140 毫秒', '140 ms'),
                220: _copy('220 毫秒', '220 ms'),
                300: _copy('300 毫秒', '300 ms'),
                500: _copy('500 毫秒', '500 ms'),
                if (!{
                  50,
                  80,
                  140,
                  220,
                  300,
                  500,
                }.contains(value.transitionDurationMs))
                  value.transitionDurationMs: value.transitionDurationMs
                      .toString(),
              },
              onChanged: (next) => _update(
                _settings.copyWith(
                  interaction: value.copyWith(transitionDurationMs: next),
                ),
              ),
            ),
        ]),
      ),
    ];
  }

  Widget _buildFileAssociations(ViewerThemeTokens tokens) => _group(
    tokens,
    _copy('系统集成', 'System integration'),
    _card(tokens, [
      LayoutBuilder(
        builder: (context, constraints) => _rowFrame(
          stacked: constraints.maxWidth < 460,
          texts: _rowText(
            _copy('文件关联', 'File associations'),
            _copy(
              '管理图片、压缩包和漫画的打开方式及默认应用。',
              'Manage Open With choices and defaults for images, archives and comics.',
            ),
          ),
          control: AppButton(
            key: const ValueKey('settings.fileAssociations'),
            label: _copy('管理关联', 'Manage associations'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const FileAssociationsDialog(),
            ),
          ),
        ),
      ),
    ]),
  );

  Widget _buildGeneral(ViewerThemeTokens tokens) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _group(
          tokens,
          _copy('语言与窗口', 'Language & windows'),
          _card(tokens, [
            _selectRow<String>(
              key: const ValueKey('settings.language'),
              title: l10n.language,
              description: _copy(
                '界面文案使用的语言。',
                'Language used for interface text.',
              ),
              value: _settings.localeCode,
              items: {
                'system': l10n.systemLanguage,
                'zh': l10n.simplifiedChinese,
                'en': l10n.english,
              },
              onChanged: (value) =>
                  _update(_settings.copyWith(localeCode: value)),
            ),
            _selectRow<InstanceMode>(
              key: const ValueKey('settings.instanceMode'),
              title: _copy('实例模式', 'Instance mode'),
              description: _copy(
                '单进程复用已有窗口；多进程每次启动独立窗口。保存后对后续启动生效，已打开的窗口保留。',
                'Single process reuses an existing window; multiple processes open independent windows. Applies to subsequent launches; existing windows stay open.',
              ),
              value: _settings.instanceMode,
              items: {
                InstanceMode.singleProcess: _copy('单进程', 'Single process'),
                InstanceMode.multiProcess: _copy('多进程', 'Multiple processes'),
              },
              onChanged: (value) =>
                  _update(_settings.copyWith(instanceMode: value)),
            ),
            _switchRow(
              title: _copy('窗口保持置顶', 'Keep window on top'),
              description: _copy(
                '让查看器窗口保持在其他窗口上方。',
                'Keep the viewer above other windows.',
              ),
              value: _settings.alwaysOnTop,
              onChanged: (value) =>
                  _update(_settings.copyWith(alwaysOnTop: value)),
            ),
          ]),
        ),
        const SizedBox(height: AppTokens.space5),
        _group(
          tokens,
          _copy('最近打开', 'Recent items'),
          _card(tokens, [
            _switchRow(
              title: _copy('记录最近打开', 'Record recent items'),
              description: _copy(
                '记录主动打开的图片、文件夹和未加密的压缩包。关闭后停止添加记录，也不再在启动时恢复上次内容；已有记录保留，可单独清空。',
                'Remember images, folders and unencrypted archives you open. When off, stop adding records and restoring the last item at startup. Existing records are kept and can be cleared separately.',
              ),
              value: _settings.recentOpenEnabled,
              onChanged: (value) =>
                  _update(_settings.copyWith(recentOpenEnabled: value)),
            ),
            _selectRow<int>(
              key: const ValueKey('settings.recentOpenLimit'),
              title: _copy('最多保留', 'Maximum items'),
              description: _copy(
                '达到上限时移除最早的记录；重复打开移到最前。',
                'Oldest items are removed at the limit. Reopening moves an item to the top.',
              ),
              value: _settings.recentOpenLimit,
              items: {
                for (final count in {
                  10,
                  20,
                  50,
                  100,
                  _settings.recentOpenLimit,
                })
                  count: '$count',
              },
              onChanged: (value) =>
                  _update(_settings.copyWith(recentOpenLimit: value)),
            ),
            _switchRow(
              title: _copy('新窗口显示最近打开', 'Show recent items in new windows'),
              description: _copy(
                '不自动打开上次内容。通过文件关联、命令行或拖放指定的内容仍直接打开。',
                'Show the list instead of restoring the last item. An explicitly supplied file or folder still opens directly.',
              ),
              value: _settings.openRecentOnNewWindow,
              onChanged: (value) =>
                  _update(_settings.copyWith(openRecentOnNewWindow: value)),
            ),
            LayoutBuilder(
              builder: (context, constraints) => _rowFrame(
                stacked: constraints.maxWidth < 460,
                texts: _rowText(
                  _copy('清空记录', 'Clear records'),
                  _recentOpenMessage ??
                      _copy(
                        '清除最近打开及上次打开位置，保留阅读设置与进度。',
                        'Clear recent items and the last-opened location, keeping reading preferences and progress.',
                      ),
                ),
                control: AppButton(
                  key: const ValueKey('settings.clearRecentOpen'),
                  label: _copy('清空', 'Clear'),
                  variant: AppButtonVariant.neutral,
                  onPressed: widget.onClearRecentOpen == null
                      ? null
                      : _clearRecentOpen,
                ),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  Future<void> _clearRecentOpen() async {
    if (!await confirmClearRecentOpen(context)) return;
    try {
      await widget.onClearRecentOpen!();
      if (mounted) {
        setState(
          () =>
              _recentOpenMessage = _copy('已清空最近打开记录。', 'Recent items cleared.'),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _recentOpenMessage = _copy(
            '清空失败，请重试。',
            'Unable to clear items. Try again.',
          ),
        );
      }
    }
  }

  Widget _buildAppearanceDisplay(ViewerThemeTokens tokens) {
    final l10n = AppLocalizations.of(context)!;
    return _card(tokens, [
      _selectRow<ViewerThemeMode>(
        key: const ValueKey('settings.theme'),
        title: l10n.theme,
        description: _copy(
          '跟随系统时随操作系统的浅色或深色模式切换。',
          'Follow the system light or dark appearance.',
        ),
        value: _settings.themeMode,
        items: {
          ViewerThemeMode.system: l10n.themeSystem,
          ViewerThemeMode.light: l10n.themeLight,
          ViewerThemeMode.dark: l10n.themeDark,
        },
        onChanged: (value) => _update(_settings.copyWith(themeMode: value)),
      ),
    ]);
  }

  Widget _buildAppearanceInterface(ViewerThemeTokens tokens) {
    final l10n = AppLocalizations.of(context)!;
    return _card(tokens, [
      _tabRow<ToolbarMode>(
        key: const ValueKey('settings.toolbarMode'),
        title: l10n.toolbarMode,
        description: l10n.toolbarModeDescription,
        value: _settings.toolbarMode,
        options: [
          (ToolbarMode.normal, l10n.normalMode, FluentIcons.window_20_regular),
          (
            ToolbarMode.floating,
            l10n.floatingMode,
            FluentIcons.layer_20_regular,
          ),
        ],
        onChanged: (value) => _update(_settings.copyWith(toolbarMode: value)),
      ),
      _switchRow(
        title: l10n.showBottomBar,
        description: l10n.showBottomBarDescription,
        value: _settings.showBottomBar,
        onChanged: (value) => _update(_settings.copyWith(showBottomBar: value)),
      ),
      _switchRow(
        title: l10n.showThumbnailFileNames,
        description: l10n.showThumbnailFileNamesDescription,
        value: _settings.showThumbnailFileNames,
        onChanged: (value) =>
            _update(_settings.copyWith(showThumbnailFileNames: value)),
      ),
    ]);
  }

  Widget _buildDirectoryNavigation(ViewerThemeTokens tokens) {
    final l10n = AppLocalizations.of(context)!;
    return _group(
      tokens,
      _copy('目录导航', 'Directory navigation'),
      _card(tokens, [
        _switchRow(
          title: l10n.directoryNavigationVisible,
          description: l10n.directoryNavigationVisibleDescription,
          value: _settings.showDirectoryPanel,
          onChanged: (value) =>
              _update(_settings.copyWith(showDirectoryPanel: value)),
        ),
        _switchRow(
          title: l10n.pinDirectory,
          description: l10n.pinDirectoryDescription,
          value: _settings.pinDirectoryPanel,
          onChanged: (value) =>
              _update(_settings.copyWith(pinDirectoryPanel: value)),
        ),
      ]),
    );
  }

  Widget _buildBrowsing(ViewerThemeTokens tokens) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDirectoryNavigation(tokens),
        const SizedBox(height: AppTokens.space5),
        _group(
          tokens,
          _copy('子文件夹浏览', 'Subfolder browsing'),
          _card(tokens, [
            _switchRow(
              title: l10n.recursiveFolderBrowsing,
              description: l10n.recursiveFolderBrowsingDescription,
              value: _settings.browseMode.isRecursive,
              onChanged: (enabled) => _update(
                _settings.copyWith(
                  browseMode: !enabled
                      ? FolderBrowseMode.currentFolder
                      : _settings.folderContinuousReading
                      ? FolderBrowseMode.recursiveFlat
                      : FolderBrowseMode.recursiveFolders,
                ),
              ),
            ),
            _switchRow(
              title: l10n.folderContinuousReading,
              description: l10n.folderContinuousReadingDescription,
              value: _settings.folderContinuousReading,
              enabled: _settings.browseMode.isRecursive,
              onChanged: (enabled) => _update(
                _settings.copyWith(
                  browseMode: enabled
                      ? FolderBrowseMode.recursiveFlat
                      : FolderBrowseMode.recursiveFolders,
                  folderContinuousReading: enabled,
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: AppTokens.space5),
        _group(
          tokens,
          _copy('扫描与刷新', 'Scanning & refresh'),
          _card(tokens, [
            _switchRow(
              title: l10n.scanUnknownExtensions,
              description: l10n.scanUnknownExtensionsDescription,
              value: _settings.scanUnknownExtensions,
              onChanged: (value) =>
                  _update(_settings.copyWith(scanUnknownExtensions: value)),
            ),
            _switchRow(
              title: l10n.watchFolderChanges,
              description: l10n.watchFolderChangesDescription,
              value: _settings.watchFolderChanges,
              onChanged: (value) =>
                  _update(_settings.copyWith(watchFolderChanges: value)),
            ),
          ]),
        ),
        const SizedBox(height: AppTokens.space5),
        _group(
          tokens,
          _copy('排序', 'Sorting'),
          _card(tokens, [
            _selectRow<SortOrder>(
              key: const ValueKey('settings.sortOrder'),
              title: l10n.sortOrder,
              description: l10n.sortOrderDescription,
              descriptionContent: AppDescriptionLink(
                linkKey: const ValueKey('settings.openArchiveSort'),
                text: l10n.sortOrderDescription,
                linkText: l10n.archiveSortLink,
                linkLabel: l10n.archiveSortSettings,
                onPressed: _openArchiveSortSettings,
              ),
              value: _settings.sortOrder,
              items: {
                for (final item in sortOrderOptions)
                  item: localizedSortOrderLabel(l10n, item),
              },
              onChanged: (value) =>
                  _update(_settings.copyWith(sortOrder: value)),
            ),
            _selectRow<FileNameSortMode>(
              key: const ValueKey('settings.fileNameSortMode'),
              title: l10n.fileNameSortMode,
              description: l10n.fileNameSortModeDescription,
              value: _settings.fileNameSortMode,
              items: {
                FileNameSortMode.natural: l10n.fileNameSortNatural,
                FileNameSortMode.lexicographic: l10n.fileNameSortLexicographic,
              },
              tooltips: {
                FileNameSortMode.natural: l10n.fileNameSortNaturalTooltip,
                FileNameSortMode.lexicographic:
                    l10n.fileNameSortLexicographicTooltip,
              },
              onChanged: (value) =>
                  _update(_settings.copyWith(fileNameSortMode: value)),
            ),
          ]),
        ),
        const SizedBox(height: AppTokens.space5),
      ],
    );
  }

  List<Widget> _buildArchives(ViewerThemeTokens tokens) {
    final l10n = AppLocalizations.of(context)!;
    final custom =
        _archiveMemoryCustom || _settings.archiveMemoryBudgetMiB != 0;
    if (custom && _archiveMemoryController.text.isEmpty) {
      _archiveMemoryController.text =
          (_settings.archiveMemoryBudgetMiB == 0
                  ? 256
                  : _settings.archiveMemoryBudgetMiB)
              .toString();
    }
    return [
      _group(
        tokens,
        _copy('章节与换包', 'Chapters & archive navigation'),
        _card(tokens, [
          _switchRow(
            title: l10n.archiveContinuousReading,
            description: l10n.archiveContinuousReadingDescription,
            value: _settings.archiveContinuousReading,
            onChanged: (value) =>
                _update(_settings.copyWith(archiveContinuousReading: value)),
          ),
          KeyedSubtree(
            key: _archiveSortTargetKey,
            child: _selectRow<SortOrder>(
              key: const ValueKey('settings.archiveSortOrder'),
              focusNode: _archiveSortFocus,
              title: l10n.archiveSortOrder,
              description: l10n.archiveSortDescription,
              value: _settings.archiveSortOrder,
              items: {
                for (final order in archiveSortOrderOptions)
                  order: localizedSortOrderLabel(l10n, order),
              },
              onChanged: (value) =>
                  _update(_settings.copyWith(archiveSortOrder: value)),
            ),
          ),
          _switchRow(
            title: l10n.archiveAutoAdvance,
            description: l10n.archiveAutoAdvanceDescription,
            value: _settings.archiveAutoAdvance,
            onChanged: (value) =>
                _update(_settings.copyWith(archiveAutoAdvance: value)),
          ),
        ]),
      ),
      const SizedBox(height: AppTokens.space5),
      _group(
        tokens,
        _copy('预加载与内存', 'Preloading & memory'),
        _card(tokens, [
          _selectRow<ArchivePrefetchMode>(
            key: const ValueKey('settings.archivePrefetchMode'),
            title: l10n.archivePrefetchMode,
            description: [
              l10n.archivePrefetchDescription,
              if (widget.archivePerformanceStatus != null)
                widget.archivePerformanceStatus!,
            ].join(' '),
            value: _settings.archivePrefetchMode,
            items: {
              ArchivePrefetchMode.automatic: l10n.archivePrefetchAutomatic,
              ArchivePrefetchMode.conservative:
                  l10n.archivePrefetchConservative,
              ArchivePrefetchMode.off: l10n.archivePrefetchOff,
            },
            onChanged: (value) =>
                _update(_settings.copyWith(archivePrefetchMode: value)),
          ),
          _selectRow<bool>(
            key: const ValueKey('settings.archiveMemoryMode'),
            title: l10n.archiveMemoryBudget,
            description: l10n.archiveMemoryDescription,
            value: custom,
            items: {
              false: l10n.archiveBudgetAutomatic,
              true: l10n.archiveBudgetCustom,
            },
            onChanged: (value) {
              setState(() {
                _archiveMemoryCustom = value;
                _archiveMemoryError = null;
                _archiveMemoryController.text = '256';
              });
              _update(
                _settings.copyWith(archiveMemoryBudgetMiB: value ? 256 : 0),
              );
            },
          ),
          if (custom)
            Padding(
              padding: const EdgeInsets.all(16),
              child: AppInput(
                key: const ValueKey('settings.archiveMemoryCustom'),
                controller: _archiveMemoryController,
                label: l10n.archiveMemoryBudget,
                suffixText: 'MiB',
                helperText: '32–1024 MiB',
                errorText: _archiveMemoryError,
                keyboardType: TextInputType.number,
                inputFormatters: [_archiveMemoryFormatter],
                onChanged: (text) {
                  final value = int.tryParse(text.trim());
                  if (value == null || value < 32 || value > 1024) {
                    setState(
                      () => _archiveMemoryError = l10n.archiveMemoryInvalid,
                    );
                    return;
                  }
                  setState(() => _archiveMemoryError = null);
                  _update(_settings.copyWith(archiveMemoryBudgetMiB: value));
                },
              ),
            ),
        ]),
      ),
      const SizedBox(height: AppTokens.space5),
      _group(
        tokens,
        l10n.archiveCache,
        _card(tokens, [
          _switchRow(
            title: l10n.archivePersistCache,
            description: l10n.archivePersistDescription,
            value: _settings.archivePersistCache,
            onChanged: (value) =>
                _update(_settings.copyWith(archivePersistCache: value)),
          ),
          _selectRow<int>(
            key: const ValueKey('settings.archiveDiskBudget'),
            title: l10n.archiveDiskBudget,
            description: l10n.archiveDiskDescription,
            value: _settings.archiveDiskBudgetMiB,
            items: {
              for (final value in {
                256,
                512,
                1024,
                2048,
                4096,
                8192,
                _settings.archiveDiskBudgetMiB,
              })
                value: '$value MiB',
            },
            onChanged: (value) =>
                _update(_settings.copyWith(archiveDiskBudgetMiB: value)),
          ),
          _selectRow<int>(
            key: const ValueKey('settings.archiveRetention'),
            title: l10n.archiveRetention,
            description: l10n.archiveRetentionDescription,
            value: _settings.archiveCacheRetentionDays,
            items: {
              for (final days in {
                1,
                3,
                7,
                14,
                30,
                _settings.archiveCacheRetentionDays,
              })
                days: '$days ${l10n.archiveRetentionDay}',
            },
            onChanged: (value) =>
                _update(_settings.copyWith(archiveCacheRetentionDays: value)),
          ),
          LayoutBuilder(
            builder: (context, constraints) => _rowFrame(
              stacked: constraints.maxWidth < 460,
              texts: _rowText(
                l10n.archiveCacheUsage,
                _archiveCacheMessage ??
                    (widget.archiveCacheUsageBytes == null
                        ? l10n.archiveCacheUnknown
                        : '${(widget.archiveCacheUsageBytes! / (1024 * 1024)).toStringAsFixed(1)} MiB'),
              ),
              control: AppButton(
                key: const ValueKey('settings.archiveClearCache'),
                label: l10n.archiveClearCache,
                variant: AppButtonVariant.neutral,
                onPressed:
                    widget.onClearArchiveCache == null || _clearingArchiveCache
                    ? null
                    : _clearArchiveCache,
              ),
            ),
          ),
        ]),
      ),
    ];
  }

  Future<void> _clearArchiveCache() async {
    final clear = widget.onClearArchiveCache;
    if (clear == null || _clearingArchiveCache) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _clearingArchiveCache = true);
    try {
      await clear();
      if (mounted) {
        setState(() => _archiveCacheMessage = l10n.archiveCacheCleared);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _archiveCacheMessage = l10n.archiveCacheClearFailed);
      }
    } finally {
      if (mounted) setState(() => _clearingArchiveCache = false);
    }
  }

  Widget _buildReading(ViewerThemeTokens tokens) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _group(
          tokens,
          _copy('默认查看设置', 'Viewing defaults'),
          _card(tokens, [
            _selectRow<ViewerMode>(
              key: const ValueKey('settings.defaultViewerMode'),
              title: _copy('默认查看方式', 'Default viewing mode'),
              description: '',
              value: _settings.defaultViewerMode,
              items: {
                for (final mode in ViewerMode.values)
                  mode: localizedViewerModeLabel(l10n, mode),
              },
              onChanged: (value) =>
                  _update(_settings.copyWith(defaultViewerMode: value)),
            ),
            for (final mode in ViewerMode.values)
              _selectRow<ViewScaleMode>(
                key: ValueKey('settings.defaultScale.${mode.name}'),
                title: _copy(
                  '${localizedViewerModeLabel(l10n, mode)}尺寸适配',
                  '${localizedViewerModeLabel(l10n, mode)} sizing',
                ),
                description: '',
                value: _settings.defaultScaleModeFor(mode),
                items: {
                  for (final scale in ViewScaleMode.values)
                    scale: localizedScaleModeLabel(l10n, scale),
                },
                onChanged: (value) => _update(
                  _settings.copyWith(
                    defaultScaleModes: {
                      ..._settings.defaultScaleModes,
                      mode: value,
                    },
                  ),
                ),
              ),
          ]),
          description: _copy(
            '用于尚无阅读记录的文件夹和压缩包；已有记录优先恢复该位置的查看方式、尺寸适配、方向和进度。手动缩放比例不随位置保存。',
            'Used for folders and archives without reading records. Existing records restore the viewing mode, sizing, direction and progress. Manual zoom is not saved per location.',
          ),
        ),
        const SizedBox(height: AppTokens.space5),
        _group(
          tokens,
          _copy('双页', 'Double page'),
          _card(tokens, [
            _selectRow<ReadingDirection>(
              key: const ValueKey('settings.readingDirection'),
              title: _copy('默认双页阅读方向', 'Default spread reading direction'),
              description: _copy(
                '决定双页跨页中两张图片的左右位置；从右到左时后一张显示在左侧。不改变文件顺序和翻页键。',
                'Sets the left/right placement of the two pages in a spread; right to left puts the later page on the left. File order and paging keys stay unchanged.',
              ),
              value: _settings.readingDirection,
              items: {
                ReadingDirection.leftToRight: l10n.leftToRight,
                ReadingDirection.rightToLeft: l10n.rightToLeftManga,
              },
              onChanged: (value) =>
                  _update(_settings.copyWith(readingDirection: value)),
            ),
            _switchRow(
              title: l10n.doublePageCoverAlone,
              description: _copy(
                '双页模式把第一页作为封面单独显示。',
                'Shows the first page alone as a cover in double-page mode.',
              ),
              value: _settings.doublePageFirstAlone,
              onChanged: (value) =>
                  _update(_settings.copyWith(doublePageFirstAlone: value)),
            ),
            _switchRow(
              title: _copy('宽图独占一页', 'Show wide images alone'),
              description: _copy(
                '宽大于高的图片单独显示，不与相邻图片配对。',
                'Images wider than they are tall occupy a spread without a neighboring image.',
              ),
              value: _settings.doublePageWideAlone,
              onChanged: (value) =>
                  _update(_settings.copyWith(doublePageWideAlone: value)),
            ),
            _switchRow(
              title: _copy('自动拆分宽图', 'Split wide images automatically'),
              description: _copy(
                '将双页扫描图沿中线分成两页显示，原文件保持不变。封面或不支持拆分的图片仍整张显示。',
                'Display two-page scans as separate halves without changing the source file. Covers and images that cannot be split stay whole.',
              ),
              value: _settings.doublePageSplitWide,
              onChanged: (value) =>
                  _update(_settings.copyWith(doublePageSplitWide: value)),
            ),
          ]),
        ),
        const SizedBox(height: AppTokens.space5),
        _group(
          tokens,
          l10n.comic,
          _card(tokens, [
            _selectRow<ComicLayoutDirection>(
              key: const ValueKey('settings.comicLayout'),
              title: _copy('默认连续阅读方向', 'Default continuous reading direction'),
              description: _copy(
                '纵向连续上下滚动；横向左右排列，并按所选方向从一侧开始阅读。仅影响连续阅读模式。',
                'Stack pages vertically and scroll up or down, or place them side by side and read in the chosen direction. Applies only to Continuous reading mode.',
              ),
              value: _settings.comicLayoutDirection,
              items: {
                for (final item in ComicLayoutDirection.values)
                  item: localizedComicLayoutLabel(l10n, item),
              },
              onChanged: (value) =>
                  _update(_settings.copyWith(comicLayoutDirection: value)),
            ),
            _comicGapRow(tokens),
            _switchRow(
              title: l10n.comicUniformSize,
              description: _copy(
                '纵向统一页宽，横向统一页高。开启时，100% 以第一张图的原始宽度或高度为基准；关闭后实际大小按每张图的原始尺寸显示。',
                'Use a uniform width vertically or height horizontally. At 100%, page 1 supplies the reference size. Turn off to show each page at its own native size.',
              ),
              value: _settings.comicUniformSize,
              onChanged: (next) =>
                  _update(_settings.copyWith(comicUniformSize: next)),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _comicGapRow(ViewerThemeTokens tokens) {
    final l10n = AppLocalizations.of(context)!;
    final selected = _comicGapSelectedPreset(_settings.comicPageGap);
    final custom = _comicGapCustom || selected == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 460;
            final control = Semantics(
              label: l10n.comicPageGap,
              container: true,
              child: SizedBox(
                width: stacked ? double.infinity : _selectControlWidth,
                child: AppSelect<_ComicGapPreset>(
                  key: const ValueKey('settings.comicPageGap'),
                  value: custom ? _ComicGapPreset.custom : selected,
                  options: [
                    for (final item in _ComicGapPreset.values)
                      AppSelectOption(
                        value: item,
                        label: _comicGapPresetLabel(l10n, item),
                      ),
                  ],
                  onChanged: _selectComicGapPreset,
                ),
              ),
            );
            return _rowFrame(
              stacked: stacked,
              texts: _rowText(
                l10n.comicPageGap,
                _copy(
                  '调整相邻页面之间的间距。选择自定义后，可用滑块在 0 到 48 像素之间调整。',
                  'Space between pages. Choose Custom to adjust the slider from 0 to 48 px.',
                ),
              ),
              control: control,
            );
          },
        ),
        if (custom) _comicGapSlider(tokens),
      ],
    );
  }

  String _comicGapPresetLabel(AppLocalizations l10n, _ComicGapPreset preset) =>
      switch (preset) {
        _ComicGapPreset.none => l10n.comicGapNone,
        _ComicGapPreset.tight => l10n.comicGapTight,
        _ComicGapPreset.standard => l10n.comicGapStandard,
        _ComicGapPreset.loose => l10n.comicGapLoose,
        _ComicGapPreset.custom => l10n.comicGapCustom,
      };

  _ComicGapPreset? _comicGapSelectedPreset(double gap) {
    for (final preset in _ComicGapPreset.values) {
      final value = preset.value;
      if (value != null && (value - gap).abs() < 0.01) return preset;
    }
    return null;
  }

  void _selectComicGapPreset(_ComicGapPreset preset) {
    final custom = preset == _ComicGapPreset.custom;
    if (_comicGapCustom != custom) {
      setState(() => _comicGapCustom = custom);
    }
    final value = preset.value;
    if (value != null) _update(_settings.copyWith(comicPageGap: value));
  }

  Widget _comicGapSlider(ViewerThemeTokens tokens) {
    final value = (_comicGapDrag ?? _settings.comicPageGap)
        .clamp(ViewerSettings.minComicPageGap, ViewerSettings.maxComicPageGap)
        .toDouble();
    final label = _copy('${value.round()} 像素', '${value.round()} px');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: AppSlider(
              variant: AppSliderVariant.setting,
              key: const ValueKey('settings.comicPageGapSlider'),
              min: ViewerSettings.minComicPageGap,
              max: ViewerSettings.maxComicPageGap,
              divisions:
                  (ViewerSettings.maxComicPageGap -
                          ViewerSettings.minComicPageGap)
                      .round(),
              value: value,
              label: label,
              onChanged: (next) => setState(() => _comicGapDrag = next),
              onChangeEnd: (next) {
                setState(() => _comicGapDrag = null);
                _update(_settings.copyWith(comicPageGap: next));
              },
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 64,
            child: AppSearchText(
              label,
              textAlign: TextAlign.end,
              style: AppTextStyles.caption.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPlayback(ViewerThemeTokens tokens) {
    final l10n = AppLocalizations.of(context)!;
    final value = _settings.autoPlay;
    return [
      _group(
        tokens,
        l10n.autoPlayTitle,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _note(
              tokens,
              _copy(
                '从当前位置自动播放当前列表。各查看方式的参数分别保存，与画布中的快捷设置同步；修改参数不会开始播放。',
                'Play the current list from your current position. Each viewing mode saves its own settings, shared with the canvas controls. Changing settings does not start playback.',
              ),
            ),
            _card(tokens, [
              for (final mode in ViewerMode.values)
                _autoPlayNumberRow(mode: mode),
              _autoPlayNumberRow(mode: ViewerMode.longImage, dwell: true),
              _switchRow(
                title: l10n.autoPlayLoop,
                description: _copy(
                  '到达当前列表末尾后回到开头；不会自动打开其他目录或压缩包。',
                  'Return to the start at the end of this list, without opening another folder or archive.',
                ),
                value: value.loop,
                onChanged: (loop) => _update(
                  _settings.copyWith(autoPlay: value.copyWith(loop: loop)),
                ),
              ),
              _selectRow<AutoPlayAnimationPolicy>(
                key: const ValueKey('settings.autoPlay.animationPolicy'),
                title: l10n.autoPlayAnimation,
                description: _copy(
                  '用于单页和双页自动换图。',
                  'Used for automatic image changes in single and double-page modes.',
                ),
                value: value.animationPolicy,
                items: {
                  AutoPlayAnimationPolicy.completeOnce:
                      l10n.autoPlayCompleteOnce,
                  AutoPlayAnimationPolicy.fixedInterval:
                      l10n.autoPlayFixedInterval,
                  AutoPlayAnimationPolicy.stop: l10n.autoPlayStay,
                },
                onChanged: (policy) => _update(
                  _settings.copyWith(
                    autoPlay: value.copyWith(animationPolicy: policy),
                  ),
                ),
              ),
              _selectRow<AutoPlayStatusDisplay>(
                key: const ValueKey('settings.autoPlay.statusDisplay'),
                title: _copy('右上角状态显示', 'Top-right playback status'),
                description: _copy(
                  '选择自动隐藏后，播放中 2 秒无操作会淡出状态面板，鼠标移到画面右上角即可显示；暂停时保持可见。',
                  'With Auto-hide, the status panel fades out after 2 seconds without interaction during playback. Move the pointer to the upper-right of the image area to show it. Stays visible while paused.',
                ),
                value: value.statusDisplay,
                items: {
                  AutoPlayStatusDisplay.autoHide:
                      l10n.animationControlsAutoHide,
                  AutoPlayStatusDisplay.always: l10n.animationControlsAlways,
                },
                onChanged: (display) => _update(
                  _settings.copyWith(
                    autoPlay: value.copyWith(statusDisplay: display),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
      const SizedBox(height: AppTokens.space5),
      ..._buildAnimationSettings(tokens),
    ];
  }

  Widget _autoPlayNumberRow({required ViewerMode mode, bool dwell = false}) {
    final l10n = AppLocalizations.of(context)!;
    final scrolling =
        !dwell && (mode == ViewerMode.longImage || mode == ViewerMode.comic);
    final label = localizedViewerModeLabel(l10n, mode);
    final title = dwell
        ? _copy('长图无需滚动时停留', 'Long image dwell time when it fits')
        : scrolling
        ? _copy('$label滚动速度', '$label scroll speed')
        : _copy('$label换图间隔', '$label image interval');
    return LayoutBuilder(
      builder: (context, constraints) => _rowFrame(
        stacked: constraints.maxWidth < 460,
        texts: _rowText(title, ''),
        control: SizedBox(
          width: constraints.maxWidth < 460
              ? double.infinity
              : _selectControlWidth,
          child: _PlaybackNumberInput(
            key: ValueKey(
              'settings.autoPlay.${scrolling ? "speed" : "interval"}.${mode.name}',
            ),
            title: title,
            scrolling: scrolling,
            resetGeneration: _playbackResetGeneration,
            value: scrolling
                ? _settings.autoPlay.speedFor(mode)
                : _settings.autoPlay.intervalFor(mode),
            onChanged: (number) {
              final value = _settings.autoPlay;
              _update(
                _settings.copyWith(
                  autoPlay: scrolling
                      ? value.copyWith(
                          scrollSpeeds: {...value.scrollSpeeds, mode: number},
                        )
                      : value.copyWith(
                          intervals: {...value.intervals, mode: number},
                        ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildAnimationSettings(ViewerThemeTokens tokens) {
    final l10n = AppLocalizations.of(context)!;
    return [
      _group(
        tokens,
        _copy('动图播放', 'Animation playback'),
        _card(tokens, [
          _switchRow(
            title: l10n.animationAutoPlay,
            description: l10n.animationAutoPlayDescription,
            value: _settings.animationAutoPlay,
            onChanged: (value) =>
                _update(_settings.copyWith(animationAutoPlay: value)),
          ),
          _selectRow<AnimationLoopMode>(
            key: const ValueKey('settings.animationLoopMode'),
            title: l10n.animationLoopMode,
            description: l10n.animationDefaultLoopDescription,
            value: _settings.animationLoopMode,
            items: {
              for (final mode in AnimationLoopMode.values)
                mode: animationLoopLabel(l10n, mode),
            },
            onChanged: (value) =>
                _update(_settings.copyWith(animationLoopMode: value)),
          ),
          _selectRow<double>(
            key: const ValueKey('settings.animationSpeed'),
            title: l10n.animationDefaultSpeed,
            description: l10n.animationDefaultSpeedDescription,
            value: _settings.animationSpeed,
            items: {
              for (final speed in animationPlaybackSpeeds)
                speed:
                    '${speed == speed.roundToDouble() ? speed.toInt() : speed}×',
            },
            onChanged: (value) =>
                _update(_settings.copyWith(animationSpeed: value)),
          ),
          _selectRow<AnimationControlsMode>(
            key: const ValueKey('settings.animationControlsMode'),
            title: l10n.animationControlsDisplay,
            description: l10n.animationControlsDisplayDescription,
            value: _settings.animationControlsMode,
            items: {
              AnimationControlsMode.autoHide: l10n.animationControlsAutoHide,
              AnimationControlsMode.always: l10n.animationControlsAlways,
              AnimationControlsMode.hidden: l10n.animationControlsHidden,
            },
            onChanged: (value) =>
                _update(_settings.copyWith(animationControlsMode: value)),
          ),
        ]),
      ),
      const SizedBox(height: AppTokens.space5),
    ];
  }

  List<Widget> _buildImage(ViewerThemeTokens tokens) {
    final l10n = AppLocalizations.of(context)!;
    final capabilities = widget.decoderRegistry
        .capabilities()
        .where((item) => item.available)
        .toList();
    final count = capabilities.length;
    final sources = <DecoderSource, List<DecoderCapability>>{};
    for (final capability in capabilities) {
      sources.putIfAbsent(capability.sourceKind, () => []).add(capability);
    }
    final expanded = _formatsExpanded || _query.trim().isNotEmpty;
    return [
      _group(
        tokens,
        _copy('预加载与缓存', 'Preloading & cache'),
        _card(tokens, [
          _selectRow<ThumbnailPrefetchMode>(
            key: const ValueKey('settings.thumbnailPrefetchMode'),
            title: _copy('缩略图预加载', 'Thumbnail preloading'),
            description: _copy(
              '自动：提前加载两侧各两屏，最多各 32 张。保守：两侧各半屏，最多各 8 张。隐藏缩略图栏后，已有任务继续；切换文件夹后优先加载新内容。关闭预加载时只加载可见缩略图。',
              'Automatic preloads two screens on each side, up to 32 thumbnails per side. Conservative preloads half a screen per side, up to 8 each. Tasks continue when the strip is hidden; new folders take priority. Off loads only visible thumbnails.',
            ),
            value: _settings.thumbnailPrefetchMode,
            items: {
              ThumbnailPrefetchMode.automatic: _copy('自动', 'Automatic'),
              ThumbnailPrefetchMode.conservative: _copy('保守', 'Conservative'),
              ThumbnailPrefetchMode.off: _copy('关闭', 'Off'),
            },
            onChanged: (value) =>
                _update(_settings.copyWith(thumbnailPrefetchMode: value)),
          ),
        ]),
      ),
      const SizedBox(height: AppTokens.space5),
      _group(
        tokens,
        _copy('HDR', 'HDR'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _card(tokens, [
              _switchRow(
                title: _copy('自动 HDR 显示', 'Automatic HDR display'),
                description: _copy(
                  '在当前屏幕和图片支持时使用 HDR，否则使用 SDR。系统 HDR 需在系统设置中开启。',
                  'Use HDR when supported by the display and image; otherwise use SDR. Enable system HDR in your system settings.',
                ),
                value: _settings.autoHdr,
                onChanged: (value) =>
                    _update(_settings.copyWith(autoHdr: value)),
              ),
            ]),
            const SizedBox(height: AppTokens.space5),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSearchText(
                    _copy('按图片类型使用 HDR', 'Use HDR by image type'),
                    style: AppTextStyles.body.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AppSearchText(
                    _settings.autoHdr
                        ? _copy(
                            '分别选择使用 HDR 的图片类型。',
                            'Choose which image types use HDR.',
                          )
                        : _copy(
                            '自动 HDR 已关闭，以下选择会保留。',
                            'Automatic HDR is off. Your choices below are kept.',
                          ),
                    style: AppTextStyles.label.copyWith(
                      color: tokens.textTertiary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            _card(tokens, [
              _switchRow(
                title: _copy(
                  '线性 HDR（HDR / EXR）',
                  'Scene-linear HDR (HDR / EXR)',
                ),
                enabled: _settings.autoHdr,
                description: _copy(
                  '关闭后，HDR / EXR 图片使用 SDR 映射。',
                  'When off, HDR / EXR images use SDR tone mapping.',
                ),
                value: _settings.hdrLinear,
                onChanged: (value) =>
                    _update(_settings.copyWith(hdrLinear: value)),
              ),
              _switchRow(
                title: _copy('PQ / HLG', 'PQ / HLG'),
                enabled: _settings.autoHdr,
                description: _copy(
                  '识别 PNG、AVIF 和 HEIF 中的 PQ / HLG 标记；关闭后使用 SDR 映射。',
                  'Read PQ / HLG tags in PNG, AVIF and HEIF. When off, use SDR tone mapping.',
                ),
                value: _settings.hdrPqHlg,
                onChanged: (value) =>
                    _update(_settings.copyWith(hdrPqHlg: value)),
              ),
              _switchRow(
                title: _copy('Gain Map', 'Gain Map'),
                enabled: _settings.autoHdr,
                description: _copy(
                  '重建 JPEG、AVIF 和 HEIF 增益图；关闭后使用自带 SDR 基础图。',
                  'Reconstruct Gain Maps in JPEG, AVIF and HEIF. When off, use the embedded SDR base image.',
                ),
                value: _settings.hdrGainMap,
                onChanged: (value) =>
                    _update(_settings.copyWith(hdrGainMap: value)),
              ),
              _switchRow(
                title: _copy('RAW', 'RAW'),
                enabled: _settings.autoHdr,
                description: _copy(
                  '关闭后使用普通显影结果，曝光和白平衡不受影响。',
                  'When off, use standard RAW development. Exposure and white balance stay unchanged.',
                ),
                value: _settings.hdrRaw,
                onChanged: (value) =>
                    _update(_settings.copyWith(hdrRaw: value)),
              ),
              _switchRow(
                title: _copy('Dolby Vision', 'Dolby Vision'),
                enabled: _settings.autoHdr,
                description: _copy(
                  '关闭后，Dolby Vision 静帧使用 SDR 映射。',
                  'When off, Dolby Vision stills use SDR tone mapping.',
                ),
                value: _settings.hdrDolbyVision,
                onChanged: (value) =>
                    _update(_settings.copyWith(hdrDolbyVision: value)),
              ),
            ]),
          ],
        ),
      ),
      const SizedBox(height: AppTokens.space5),
      _group(
        tokens,
        _copy('格式支持', 'Format support'),
        _card(tokens, [
          LayoutBuilder(
            builder: (context, constraints) => _rowFrame(
              stacked: constraints.maxWidth < 460,
              texts: _rowText(
                l10n.parsingCapabilities,
                count == 0
                    ? _copy(
                        '未检测到当前平台支持的格式。',
                        'No supported formats detected on this platform.',
                      )
                    : _copy(
                        '当前平台支持 $count 种格式，按解码来源分组。',
                        '$count formats supported on this platform, grouped by decoder.',
                      ),
              ),
              control: AppButton(
                key: const ValueKey('settings.toggleFormats'),
                label: expanded
                    ? _copy('收起格式列表', 'Hide formats')
                    : _copy('查看格式支持', 'View formats'),
                variant: AppButtonVariant.neutral,
                onPressed: count == 0
                    ? null
                    : () {
                        if (_query.trim().isNotEmpty) _clearSearch();
                        setState(() => _formatsExpanded = !expanded);
                      },
              ),
            ),
          ),
          if (expanded)
            for (final source in sources.entries)
              _formatGroup(source.key, source.value, l10n, tokens),
        ]),
      ),
    ];
  }

  Widget _formatGroup(
    DecoderSource source,
    List<DecoderCapability> capabilities,
    AppLocalizations l10n,
    ViewerThemeTokens tokens,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSearchText(
          localizedDecoderSource(l10n, source),
          style: AppTextStyles.label.copyWith(
            color: tokens.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, constraints) {
            final minimumWidth = MediaQuery.textScalerOf(context).scale(260);
            final columns = constraints.maxWidth >= minimumWidth * 2 + 24
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 24) / columns;
            return Wrap(
              spacing: 24,
              children: [
                for (final capability in capabilities)
                  SizedBox(
                    width: width,
                    child: _capabilityRow(capability, l10n, tokens),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );

  List<Widget> _buildAbout(ViewerThemeTokens tokens) {
    final l10n = AppLocalizations.of(context)!;
    return [
      _card(tokens, [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(
                    'assets/ui/app-icon.png',
                    width: 52,
                    height: 52,
                    semanticLabel: l10n.appTitle,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppSearchText(
                          l10n.appTitle,
                          style: AppTextStyles.sectionTitle.copyWith(
                            color: tokens.textPrimary,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        AppSearchText(
                          _copy(
                            '版本 ${AppInfo.version}（构建 ${AppInfo.buildNumber}）',
                            'Version ${AppInfo.version} (build ${AppInfo.buildNumber})',
                          ),
                          style: AppTextStyles.caption.copyWith(
                            color: tokens.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _badge(tokens, AppInfo.platformLabel),
                            _badge(tokens, 'Flutter'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: AppSearchText(
                l10n.appDescription,
                style: AppTextStyles.bodySmall.copyWith(
                  color: tokens.textSecondary,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      ]),
      const SizedBox(height: AppTokens.space5),
      _group(
        tokens,
        _copy('第三方组件', 'Third-party components'),
        _card(tokens, [
          _aboutComponent(
            tokens,
            'resvg',
            _copy(
              'MIT / Apache-2.0 · SVG 渲染',
              'MIT / Apache-2.0 · SVG rendering',
            ),
          ),
          _aboutComponent(
            tokens,
            'ImageMagick',
            _copy(
              'ImageMagick License · 扩展格式兼容解码',
              'ImageMagick License · extended format fallback',
            ),
          ),
          _aboutComponent(
            tokens,
            '7-Zip',
            _copy(
              'LGPL-2.1+（含 unRAR 限制）· 压缩包按需读取',
              'LGPL-2.1+ (unRAR restriction) · on-demand archive reading',
            ),
          ),
          _aboutComponent(
            tokens,
            'libultrahdr',
            _copy(
              'Apache-2.0 · Ultra HDR / Gain Map',
              'Apache-2.0 · Ultra HDR / Gain Map',
            ),
          ),
          _aboutComponent(
            tokens,
            'libjpeg-turbo',
            _copy('IJG / BSD · JPEG 编解码', 'IJG / BSD · JPEG codec'),
          ),
          _aboutComponent(
            tokens,
            'libavif',
            _copy('BSD-2-Clause · AVIF 解码', 'BSD-2-Clause · AVIF decoding'),
          ),
          _aboutComponent(
            tokens,
            'libheif',
            _copy(
              'LGPL-3.0 · HEIF / HEIC 解码',
              'LGPL-3.0 · HEIF / HEIC decoding',
            ),
          ),
          _aboutComponent(
            tokens,
            'LibRaw',
            _copy(
              'LGPL-2.1 / CDDL-1.0 · RAW 显影',
              'LGPL-2.1 / CDDL-1.0 · RAW development',
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 0),
        child: AppSearchText(
          _copy(
            '用于 Dolby Vision 的 FFmpeg / libplacebo 为可选外部组件，遵循其各自的许可证。',
            'FFmpeg / libplacebo for Dolby Vision are optional external components under their own licenses.',
          ),
          style: AppTextStyles.label.copyWith(
            color: tokens.textTertiary,
            height: 1.5,
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: AppTextAction(
          key: const ValueKey('settings.openLicenses'),
          label: _copy('开源许可', 'Open-source licenses'),
          onPressed: _openLicenses,
        ),
      ),
    ];
  }

  void _openLicenses() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (context) => const LicensesPage()),
    );
  }

  Widget _aboutComponent(
    ViewerThemeTokens tokens,
    String name,
    String detail,
  ) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSearchText(
          name,
          style: AppTextStyles.body.copyWith(
            color: tokens.textPrimary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 3),
        AppSearchText(
          detail,
          style: AppTextStyles.label.copyWith(
            color: tokens.textTertiary,
            height: 1.5,
          ),
        ),
      ],
    ),
  );

  ViewerShortcutBindings get _shortcutBindings =>
      widget.shortcuts.withOverrides(_settings.shortcutOverrides);

  void _onShortcutSearchChanged() {
    final value = _shortcutSearchController.value;
    if (value.composing.isValid && !value.composing.isCollapsed) return;
    if (_shortcutQuery == value.text) return;
    setState(() => _shortcutQuery = value.text);
    final scroll = _scrollControllers[_SettingsSection.shortcuts]!;
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  Future<void> _editShortcut(ViewerCommand command, String action) async {
    final platform = Theme.of(context).platform;
    final defaults = widget.shortcuts.withOverrides(const {});
    String commandLabel(ViewerCommand command) {
      for (final group in _shortcutGroups().values) {
        for (final row in group) {
          if (row.commands.contains(command)) return row.action;
        }
      }
      return command.name;
    }

    final binding = await showDialog<ViewerShortcutBinding>(
      context: context,
      builder: (_) => ShortcutEditorDialog(
        command: command,
        action: action,
        bindings: _shortcutBindings,
        defaults: defaults,
        commandLabel: commandLabel,
      ),
    );
    if (binding == null || !mounted) return;
    final key = ViewerShortcutBindings.overrideKey(platform, command);
    final overrides = Map<String, ViewerShortcutBinding>.of(
      _settings.shortcutOverrides,
    );
    if (binding == defaults.binding(command, platform: platform)) {
      overrides.remove(key);
    } else {
      overrides[key] = binding;
    }
    _update(_settings.copyWith(shortcutOverrides: Map.unmodifiable(overrides)));
  }

  Map<String, List<_Shortcut>> _shortcutGroups() {
    final platform = Theme.of(context).platform;
    final bindings = _shortcutBindings;
    _Shortcut command(String zh, String en, ViewerCommand action) => _Shortcut(
      _copy(zh, en),
      [bindings.label(action, platform: platform)],
      null,
      '${action.name} ${switch (action) {
        ViewerCommand.deleteFile => '删除 废纸篓 trash',
        ViewerCommand.saveOriginal => '另存为 save as',
        ViewerCommand.actualSize => '实际大小 原始大小 100%',
        ViewerCommand.toggleThumbnails => '胶片栏 filmstrip',
        ViewerCommand.reveal => '打开图片路径 定位文件 open file location',
        ViewerCommand.copyPath => '复制路径 copy path',
        _ => '',
      }}',
      [action],
    );
    return <String, List<_Shortcut>>{
      _copy('文件', 'Files'): [
        command('打开图片或压缩包', 'Open image or archive', ViewerCommand.openFile),
        command('打开文件夹', 'Open folder', ViewerCommand.openFolder),
        command('复制文件', 'Copy file', ViewerCommand.copyFile),
        command('复制图片路径', 'Copy image path', ViewerCommand.copyPath),
        command('在文件管理器中显示', 'Reveal in file manager', ViewerCommand.reveal),
        command('重命名', 'Rename', ViewerCommand.rename),
        command('移到回收站', 'Move to trash', ViewerCommand.deleteFile),
        command('保存原图副本', 'Save original copy', ViewerCommand.saveOriginal),
        command('打印', 'Print', ViewerCommand.print),
      ],
      _copy('浏览', 'Browsing'): [
        _Shortcut(
          _copy('上一张 / 下一张；双页翻一整屏', 'Previous / next image or spread'),
          [
            bindings.label(ViewerCommand.previousImage, platform: platform),
            bindings.label(ViewerCommand.nextImage, platform: platform),
          ],
          '/',
          '',
          const [ViewerCommand.previousImage, ViewerCommand.nextImage],
        ),
        _Shortcut(
          _copy('双页按单图步进', 'Step one image in a spread'),
          [
            bindings.label(
              ViewerCommand.previousSingleImage,
              platform: platform,
            ),
            bindings.label(ViewerCommand.nextSingleImage, platform: platform),
          ],
          '/',
          '',
          const [
            ViewerCommand.previousSingleImage,
            ViewerCommand.nextSingleImage,
          ],
        ),
        _Shortcut(
          _copy(
            '滚动长图或连续页面；长按连续滚动',
            'Scroll long image or continuous pages; hold to scroll',
          ),
          const ['↑', '↓'],
          '/',
        ),
        _Shortcut(
          _copy(
            '翻页；长图与连续阅读滚动一屏',
            'Turn page; scroll a screen in long or continuous reading',
          ),
          [
            bindings.label(ViewerCommand.pageUp, platform: platform),
            bindings.label(ViewerCommand.pageDown, platform: platform),
          ],
          '/',
          '',
          const [ViewerCommand.pageUp, ViewerCommand.pageDown],
        ),
        _Shortcut(
          _copy('第一张 / 最后一张', 'First / last image'),
          [
            bindings.label(ViewerCommand.firstImage, platform: platform),
            bindings.label(ViewerCommand.lastImage, platform: platform),
          ],
          '/',
          '',
          const [ViewerCommand.firstImage, ViewerCommand.lastImage],
        ),
        _Shortcut(
          _copy('当前内容起点 / 终点', 'Start / end of content'),
          [
            bindings.label(ViewerCommand.home, platform: platform),
            bindings.label(ViewerCommand.end, platform: platform),
          ],
          '/',
          '',
          const [ViewerCommand.home, ViewerCommand.end],
        ),
        _Shortcut(
          _copy(
            '上一章或同级包 / 下一章或同级包',
            'Previous / next chapter or sibling archive',
          ),
          [
            bindings.label(ViewerCommand.previousChapter, platform: platform),
            bindings.label(ViewerCommand.nextChapter, platform: platform),
          ],
          '/',
          '',
          const [ViewerCommand.previousChapter, ViewerCommand.nextChapter],
        ),
        command(
          '上级目录（限当前导航根内）',
          'Parent directory within reading root',
          ViewerCommand.parentFolder,
        ),
        command(
          '搜索当前网格或目录',
          'Search current grid or directory',
          ViewerCommand.search,
        ),
        command('重新载入', 'Reload', ViewerCommand.reload),
      ],
      _copy('缩放与查看方式', 'Zoom & viewing modes'): [
        _Shortcut(
          _copy('放大 / 缩小（支持数字键盘）', 'Zoom in / out (including numpad)'),
          [
            bindings.label(ViewerCommand.zoomIn, platform: platform),
            bindings.label(ViewerCommand.zoomOut, platform: platform),
          ],
          '/',
          '',
          const [ViewerCommand.zoomIn, ViewerCommand.zoomOut],
        ),
        command(
          '原始尺寸；连续阅读使用阅读基准尺寸',
          'Actual size; reading base size in uniform continuous reading',
          ViewerCommand.actualSize,
        ),
        command('自动适应', 'Auto fit', ViewerCommand.autoFit),
        command('适应宽度', 'Fit width', ViewerCommand.fitWidth),
        command('适应高度', 'Fit height', ViewerCommand.fitHeight),
        command('锁定或解锁缩放比例', 'Lock or unlock zoom', ViewerCommand.lockZoom),
        command('单页', 'Single page', ViewerCommand.singlePage),
        command('双页', 'Double page', ViewerCommand.doublePage),
        command('长图', 'Long image', ViewerCommand.longImage),
        command('连续阅读', 'Continuous reading', ViewerCommand.comic),
        command('顺时针旋转', 'Rotate clockwise', ViewerCommand.rotate),
        command('水平翻转', 'Flip horizontally', ViewerCommand.flip),
      ],
      _copy('面板与网格', 'Panels & grid'): [
        command(
          '显示或隐藏目录面板',
          'Show or hide directory',
          ViewerCommand.toggleDirectory,
        ),
        command(
          '显示或隐藏缩略图',
          'Show or hide thumbnails',
          ViewerCommand.toggleThumbnails,
        ),
        command(
          '显示或隐藏图片信息',
          'Show or hide image information',
          ViewerCommand.toggleInfo,
        ),
        command(
          '网格总览 / 返回阅读',
          'Grid overview / return to reading',
          ViewerCommand.toggleGrid,
        ),
        _Shortcut(_copy('网格中选择图片', 'Select image in grid'), const [
          '←',
          '→',
          '↑',
          '↓',
        ], '/'),
        _Shortcut(
          _copy('网格中翻屏、选择首尾', 'Move a screen or to first / last in grid'),
          const ['PageUp', 'PageDown', 'Home', 'End'],
          '/',
        ),
        _Shortcut(_copy('网格中打开选中图片', 'Open selected image in grid'), const [
          'Enter',
        ]),
      ],
      _copy('工具与播放', 'Tools & playback'): [
        command('颜色拾取', 'Color picker', ViewerCommand.colorPicker),
        _Shortcut(_copy('取色时微调像素', 'Nudge sampled pixel'), const [
          '←',
          '→',
          '↑',
          '↓',
        ], '/'),
        command('取色时复制颜色', 'Copy sampled color', ViewerCommand.copyFile),
        command(
          '播放或暂停动图',
          'Play or pause animation',
          ViewerCommand.toggleAnimation,
        ),
        _Shortcut(
          _copy(
            '动图上一帧 / 下一帧（自动暂停）',
            'Previous / next animation frame (pauses animation)',
          ),
          [
            bindings.label(ViewerCommand.previousFrame, platform: platform),
            bindings.label(ViewerCommand.nextFrame, platform: platform),
          ],
          '/',
          '',
          const [ViewerCommand.previousFrame, ViewerCommand.nextFrame],
        ),
        command(
          '开始或暂停自动播放',
          'Start or pause auto play',
          ViewerCommand.autoPlay,
        ),
        command('停止自动播放', 'Stop auto play', ViewerCommand.stopAutoPlay),
      ],
      _copy('窗口', 'Windows'): [
        command('设置', 'Settings', ViewerCommand.settings),
        if (_settings.instanceMode == InstanceMode.multiProcess)
          command('新建窗口', 'New window', ViewerCommand.newWindow),
        command('窗口置顶', 'Always on top', ViewerCommand.alwaysOnTop),
        command('切换全屏', 'Toggle fullscreen', ViewerCommand.fullscreen),
        if (platform == TargetPlatform.macOS &&
            !bindings.isCustomized(ViewerCommand.fullscreen, platform))
          _Shortcut(_copy('切换全屏（兼容键）', 'Toggle fullscreen (alternate)'), [
            bindings.fullscreen.displayLabel(platform: platform),
          ]),
        command('无边框模式', 'Borderless mode', ViewerCommand.borderless),
        _Shortcut(
          _copy(
            '逐层退出取色、目录、网格、自动播放、浮层或全屏／无边框',
            'Exit color picker, directory, grid, auto play, overlays or fullscreen / borderless one layer at a time',
          ),
          const ['Esc'],
        ),
      ],
      _copy('目录宽度（分隔条聚焦时）', 'Directory width (divider focused)'): [
        _Shortcut(_copy('按 10 像素调整宽度', 'Adjust width by 10 pixels'), const [
          '←',
          '→',
        ], '/'),
        _Shortcut(_copy('恢复默认宽度', 'Reset width'), const ['Home']),
        _Shortcut(_copy('撤销最近一次宽度调整', 'Undo last width change'), [
          platform == TargetPlatform.macOS ? '⌘+Z' : 'Ctrl+Z',
        ]),
        _Shortcut(_copy('取消当前拖动', 'Cancel current drag'), const ['Esc']),
      ],
    };
  }

  String _normalizeShortcutSearch(String text) => text
      .toLowerCase()
      .replaceAll('⌘', 'cmd')
      .replaceAll('command', 'cmd')
      .replaceAll('meta', 'cmd')
      .replaceAll('⌃', 'ctrl')
      .replaceAll('control', 'ctrl')
      .replaceAll('⌥', 'alt')
      .replaceAll('option', 'alt')
      .replaceAll('⇧', 'shift')
      .replaceAll('⌫', 'backspace')
      .replaceAll('escape', 'esc')
      .replaceAll(RegExp(r'\s*\+\s*'), '+');

  bool get _shortcutCategoryMatches {
    final terms = AppSearchScope.terms(_query);
    const category = '快捷键 shortcuts 键盘 keyboard 按键 key';
    return terms.every(category.contains);
  }

  bool _shortcutMatches(String group, _Shortcut shortcut, {String? query}) {
    final labels = {group, shortcut.action};
    final text = _normalizeShortcutSearch(
      [
        ...labels,
        ...shortcut.keys,
        shortcut.aliases,
        if (shortcut.keys.contains('Space')) '空格',
        '快捷键 shortcuts 键盘 keyboard 按键 key',
        for (final entry in _searchTranslations.entries)
          if (labels.contains(entry.value)) entry.key,
      ].join(' '),
    );
    return AppSearchScope.terms(_normalizeShortcutSearch(query ?? _query))
        .every(text.contains);
  }

  Widget _buildShortcuts(ViewerThemeTokens tokens) {
    final groups = _shortcutGroups();
    final filtering =
        (_query.trim().isNotEmpty && !_shortcutCategoryMatches) ||
        _shortcutQuery.isNotEmpty;
    final visibleGroups = {
      for (final group in groups.entries)
        group.key: [
          for (final shortcut in group.value)
            if ((!filtering || _shortcutMatches(group.key, shortcut)) &&
                _shortcutMatches(group.key, shortcut, query: _shortcutQuery))
              shortcut,
        ],
    };
    return AppSearchScope(
      query: '$_query $_shortcutQuery',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (visibleGroups.values.every((rows) => rows.isEmpty)) ...[
            _note(
              tokens,
              _copy(
                '没有匹配的快捷键，试试功能名或按键。',
                'No matching shortcuts. Try an action or key.',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                key: const ValueKey('shortcuts.clearSearch'),
                label: _copy('清除快捷键搜索', 'Clear shortcut search'),
                variant: AppButtonVariant.subtle,
                onPressed: _shortcutSearchController.clear,
              ),
            ),
          ],
          for (final entry in visibleGroups.entries)
            if (entry.value.isNotEmpty) ...[
              _group(tokens, entry.key, _shortcutCard(tokens, entry.value)),
              const SizedBox(height: AppTokens.space5),
            ],
          if (!filtering)
            _note(
              tokens,
              _copy(
                '双页方向键不随阅读方向反转；触屏横滑按阅读方向翻页，放大后改为平移。单指拖动平移，双指捏合缩放。',
                'In Double page mode, arrow keys keep their direction. Touch swipes follow the reading direction; when zoomed in, swiping pans instead. Drag with one finger to pan or pinch with two fingers to zoom.',
              ),
            ),
        ],
      ),
    );
  }

  Widget _shortcutCard(ViewerThemeTokens tokens, List<_Shortcut> shortcuts) =>
      _card(tokens, [
        for (final shortcut in shortcuts)
          LayoutBuilder(
            builder: (context, constraints) => _rowFrame(
              stacked: constraints.maxWidth < 460,
              texts: _rowText(shortcut.action, ''),
              control: Wrap(
                spacing: 4,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (
                    var index = 0;
                    index < shortcut.keys.length;
                    index++
                  ) ...[
                    if (index > 0 && shortcut.separator != null)
                      AppSearchText(
                        shortcut.separator!,
                        style: AppTextStyles.finePrint.copyWith(
                          color: tokens.textTertiary,
                        ),
                      ),
                    if (index < shortcut.commands.length)
                      AppShortcutKeycap(
                        key: ValueKey(
                          'shortcuts.edit.${shortcut.commands[index].name}',
                        ),
                        label: shortcut.keys[index] == '—'
                            ? _copy('未设置', 'Unassigned')
                            : shortcut.keys[index],
                        tooltip: _copy('修改快捷键', 'Edit shortcut'),
                        onPressed: () => _editShortcut(
                          shortcut.commands[index],
                          shortcut.action,
                        ),
                      )
                    else
                      AppShortcutKeycap(
                        label: shortcut.keys[index],
                        tooltip: _copy('固定快捷键', 'Fixed shortcut'),
                      ),
                  ],
                ],
              ),
            ),
          ),
      ]);
  Widget _selectRow<T>({
    required Key key,
    required String title,
    required String description,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
    Map<T, String>? tooltips,
    Widget? descriptionContent,
    FocusNode? focusNode,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 460;
        final control = Semantics(
          label: title,
          container: true,
          child: SizedBox(
            width: stacked ? double.infinity : _selectControlWidth,
            child: AppSelect<T>(
              key: key,
              focusNode: focusNode,
              value: value,
              options: [
                for (final entry in items.entries)
                  AppSelectOption<T>(
                    value: entry.key,
                    label: entry.value,
                    tooltip: tooltips?[entry.key],
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
        );
        return _rowFrame(
          stacked: stacked,
          texts: _rowText(
            title,
            description,
            descriptionContent: descriptionContent,
          ),
          control: control,
        );
      },
    );
  }

  Widget _tabRow<T>({
    required Key key,
    required String title,
    required String description,
    required T value,
    required List<(T, String, IconData)> options,
    required ValueChanged<T> onChanged,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 460;
        final control = Semantics(
          label: title,
          container: true,
          child: SizedBox(
            width: stacked ? double.infinity : 220,
            child: AppTabSwitch<T>(
              key: key,
              value: value,
              expand: stacked,
              showSelectedIcon: false,
              options: [
                for (final option in options)
                  AppTabOption<T>(
                    value: option.$1,
                    label: option.$2,
                    icon: option.$3,
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
        );
        return _rowFrame(
          stacked: stacked,
          texts: _rowText(title, description),
          control: control,
        );
      },
    );
  }

  Widget _rowFrame({
    required bool stacked,
    required Widget texts,
    required Widget control,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [texts, const SizedBox(height: 10), control],
            )
          : Row(
              children: [
                Expanded(child: texts),
                const SizedBox(width: 24),
                control,
              ],
            ),
    );
  }

  Widget _switchRow({
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return AppInteractiveSurface(
      onTap: enabled ? () => onChanged(!value) : null,
      radius: 0,
      canRequestFocus: false,
      excludeFromSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: AppSwitch(
          label: title,
          description: description,
          value: value,
          enabled: enabled,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _rowText(
    String title,
    String description, {
    Widget? descriptionContent,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppSearchText(
        title,
        style: AppTextStyles.body.copyWith(
          color: ViewerThemeTokens.of(context).textPrimary,
          height: 1.4,
        ),
      ),
      if (descriptionContent != null || description.isNotEmpty) ...[
        const SizedBox(height: 3),
        descriptionContent ??
            AppSearchText(
              description,
              style: AppTextStyles.label.copyWith(
                color: ViewerThemeTokens.of(context).textTertiary,
                height: 1.5,
              ),
            ),
      ],
    ],
  );

  Widget _capabilityRow(
    DecoderCapability capability,
    AppLocalizations l10n,
    ViewerThemeTokens tokens,
  ) => Padding(
    key: ValueKey('settings.format.${capability.format.name}'),
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppSearchText(
          localizedFormatLabel(l10n, capability.format),
          style: AppTextStyles.body.copyWith(
            color: tokens.textPrimary,
            height: 1.4,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (capability.animated) _badge(tokens, _copy('动画', 'Animation')),
        if (capability.metadata) _badge(tokens, _copy('元数据', 'Metadata')),
      ],
    ),
  );

  Widget _badge(ViewerThemeTokens tokens, String label) => DecoratedBox(
    decoration: BoxDecoration(
      color: tokens.surfaceSubtle,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: tokens.border.withValues(alpha: 0.8)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: AppSearchText(
        label,
        style: AppTextStyles.caption.copyWith(
          color: tokens.textSecondary,
          height: 1.3,
        ),
      ),
    ),
  );
}

/// Owns editing state so rebuilding settings never replaces an active input.
class _PlaybackNumberInput extends StatefulWidget {
  const _PlaybackNumberInput({
    required this.title,
    required this.value,
    required this.scrolling,
    required this.resetGeneration,
    required this.onChanged,
    super.key,
  });

  final String title;
  final double value;
  final bool scrolling;
  final int resetGeneration;
  final ValueChanged<double> onChanged;

  @override
  State<_PlaybackNumberInput> createState() => _PlaybackNumberInputState();
}

class _PlaybackNumberInputState extends State<_PlaybackNumberInput> {
  late final _controller = TextEditingController(text: _format(widget.value));
  late final _formatter = AppNumberInputFormatter(
    integerDigits: 4,
    decimalPlaces: widget.scrolling ? 2 : 1,
  );
  bool _valid = true;

  String _format(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  @override
  void didUpdateWidget(covariant _PlaybackNumberInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetGeneration != widget.resetGeneration ||
        (oldWidget.value != widget.value &&
            double.tryParse(_controller.text) != widget.value)) {
      _controller.text = _format(widget.value);
      _valid = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      label: widget.title,
      child: AppInput(
        controller: _controller,
        suffixText: widget.scrolling ? 'px/s' : 's',
        helperText: widget.scrolling
            ? '5–1000 px/s'
            : l10n.autoPlayIntervalHint,
        errorText: _valid
            ? null
            : widget.scrolling
            ? l10n.autoPlayInvalidSpeed
            : l10n.autoPlayInvalidInterval,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [_formatter],
        onChanged: (text) {
          final number = double.tryParse(text);
          final valid =
              number != null &&
              number.isFinite &&
              number >= (widget.scrolling ? 5 : 0.5) &&
              number <= (widget.scrolling ? 1000 : 3600);
          setState(() => _valid = valid);
          if (valid) widget.onChanged(number);
        },
      ),
    );
  }
}

class _Shortcut {
  const _Shortcut(
    this.action,
    this.keys, [
    this.separator,
    this.aliases = '',
    this.commands = const [],
  ]);

  final String action;
  final List<String> keys;
  final String? separator;
  final String aliases;
  final List<ViewerCommand> commands;
}
