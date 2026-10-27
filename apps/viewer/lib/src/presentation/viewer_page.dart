import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart' as intl;
import 'package:path/path.dart' as paths;
import 'package:window_manager/window_manager.dart';
import 'package:windows_file_picker/windows_file_picker.dart';

import '../../l10n/app_localizations.dart';
import '../application/app_config_store.dart';
import '../application/app_instance_coordinator.dart';
import '../application/desktop_instance_platform.dart';
import '../application/animation_playback_controller.dart';
import '../application/auto_play_controller.dart';
import '../application/color_picker_controller.dart';
import '../domain/picked_color.dart';
import '../domain/auto_play_settings.dart';
import 'auto_play_status.dart';
import '../application/archive_service.dart';
import '../application/decode_request.dart';
import '../application/decode_fallback.dart';
import '../application/decode_scheduler.dart';
import '../application/decoder_registry.dart';
import '../application/file_operation_service.dart';
import '../application/external_open_service.dart';
import '../application/format_detector.dart';
import '../application/hdr_input_metadata.dart';
import '../application/hdr_display_policy.dart';
import '../application/image_resource_service.dart';
import 'raw_resource_image.dart';
import '../application/image_source.dart';
import '../application/locale_controller.dart';
import '../application/metadata_service.dart';
import '../application/photo_metadata_reader.dart';
import '../application/prefetch_planner.dart' as prefetch;
import '../application/reading_spreads.dart';
import '../application/reading_state_store.dart';
import '../application/recent_open_store.dart';
import '../application/recent_color_store.dart';
import '../application/system_resource_service.dart';
import '../application/svg_resources.dart' show svgVersion;
import '../application/svg_webview_session.dart';
import '../application/viewer_controller.dart';
import '../application/viewer_session.dart';
import '../application/window_placement_controller.dart';
import '../domain/archive_failure.dart';
import '../domain/comic_layout_direction.dart';
import '../domain/image_entry.dart';
import '../domain/image_format.dart';
import '../domain/image_resource_key.dart';
import '../domain/view_scale_mode.dart';
import '../domain/viewer_mode.dart';
import '../domain/viewer_settings.dart';
import 'animated_image_view.dart';
import 'animation_playback_bar.dart';
import 'comic_strip_viewport.dart';
import 'keyboard_scroll_controller.dart';
import 'long_image_viewport.dart';
import 'print_preview_dialog.dart';
import 'settings_page.dart';
import 'viewer_shortcuts.dart';
import 'zoomable_viewport.dart';
import 'view_scale_layout.dart';
import 'archive_password_dialog.dart';
import 'chapter_directory_tree.dart';
import 'directory_panel_region.dart';
import 'bar_layout_metrics.dart';
import 'command_bar_layout.dart';
import 'color_picker_overlay.dart';
import 'color_picker_target.dart';
import 'components/app_action_button.dart';
import 'components/app_backdrop_surface.dart';
import 'components/app_button.dart';
import 'components/app_dialog.dart';
import 'components/app_file_name_editor.dart';
import 'components/app_icon_button.dart';
import 'components/app_image_error.dart';
import 'components/app_info_field.dart';
import 'components/app_notification.dart';
import 'components/app_repeat_icon_button.dart';
import 'components/app_slider.dart';
import 'components/app_text_action.dart';
import 'components/app_text_input_scope.dart';
import 'hdr_image_view.dart';
import 'image_histogram_section.dart';
import 'ico_variant_field.dart';
import 'image_navigation_transition.dart';
import 'localized_error.dart';
import 'localized_labels.dart';
import 'photo_metadata_format.dart';
import 'navigation_hold_controller.dart';
import 'resource_image.dart';
import 'scroll_navigation_controller.dart';
import 'source_image_view.dart';
import 'split_wide_image.dart';
import 'status_bar_layout.dart';
import 'svg_image.dart';
import 'theme/app_control_styles.dart';
import 'theme/app_styles.dart';
import 'theme/app_theme.dart';
import 'theme/app_tokens.dart';
import 'viewer_bottom_bar.dart';
import 'grid_overview.dart';
import 'recent_open_page.dart';

class ViewerPage extends StatefulWidget {
  const ViewerPage({
    this.initialPath,
    this.instanceCoordinator,
    this.windowPlacement,
    this.pendingNativeRequests = const [],
    this.additionalPaths = const [],
    this.initialSettings,
    this.localeController,
    this.onThemeModeChanged,
    this.archiveService,
    this.configStore,
    this.shortcuts = ViewerShortcutBindings.defaults,
    super.key,
  });

  final String? initialPath;
  final AppInstanceCoordinator? instanceCoordinator;
  final WindowPlacementController? windowPlacement;
  final List<List<String>> pendingNativeRequests;
  final List<String> additionalPaths;
  final ArchiveService? archiveService;
  final AppConfigStore? configStore;

  /// Seeds the session without reading the persisted settings; used by tests
  /// and by callers that already resolved a startup configuration.
  final ViewerSettings? initialSettings;
  final AppLocaleController? localeController;
  final ValueChanged<ViewerThemeMode>? onThemeModeChanged;
  final ViewerShortcutBindings shortcuts;
  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

/// One top bar command, shared by its icon button and its overflow menu item.
typedef _TopBarCommand = ({
  String label,
  IconData icon,
  VoidCallback? onPressed,
  ViewerShortcutBinding? shortcut,
});

/// Which anchored menu the top bar currently shows.
enum _TopBarMenuKind { sortOrder, commandOverflow, viewMode }

/// Ordinary panels and temporary borderless panels never overwrite each other.
class _ViewerPanelLayout {
  _ViewerPanelLayout({this.thumbnailsVisible = true, this.directoryPinned});
  bool infoVisible = false;
  bool thumbnailsVisible;
  bool directoryVisible = false;
  bool directoryDismissed = false;
  bool? directoryPinned;
  double? directoryWidth;
  final expandedPaths = <String>{};
}

class _SafeSubmenuButton extends StatefulWidget {
  const _SafeSubmenuButton({
    required this.child,
    required this.menuChildren,
    required this.style,
    required this.menuStyle,
    required this.alignmentOffset,
    required this.leadingIcon,
    required this.submenuIcon,
    this.hoverOpenDelay = const Duration(milliseconds: 180),
    this.enabled = true,
    this.crossAxisUnconstrained = true,
  });

  final Widget child;
  final List<Widget> menuChildren;
  final ButtonStyle style;
  final MenuStyle menuStyle;
  final Offset alignmentOffset;
  final Widget? leadingIcon;
  final WidgetStateProperty<Widget?> submenuIcon;
  final Duration hoverOpenDelay;
  final bool enabled;
  final bool crossAxisUnconstrained;

  @override
  State<_SafeSubmenuButton> createState() => _SafeSubmenuButtonState();
}

class _SafeSubmenuButtonState extends State<_SafeSubmenuButton> {
  static const _submenuCloseDelay = Duration(milliseconds: 420);
  static const _submenuReturnDelay = Duration(milliseconds: 560);
  final _controller = MenuController();
  final _buttonKey = GlobalKey();
  Timer? _openTimer;
  Timer? _closeTimer;
  bool _buttonHovered = false;
  bool _submenuHovered = false;
  bool _closing = false;
  late Offset _resolvedAlignmentOffset = widget.alignmentOffset;

  bool get _isHovered => _buttonHovered || _submenuHovered;

  void _openOnHover() {
    if (!widget.enabled) return;
    _closeTimer?.cancel();
    _openTimer?.cancel();
    _openTimer = Timer(widget.hoverOpenDelay, () {
      if (mounted && _buttonHovered) _openMenu();
    });
  }

  void _openMenu({bool force = false}) {
    if (!widget.enabled) return;
    _openTimer?.cancel();
    _closeTimer?.cancel();
    _closing = false;
    final renderObject = _buttonKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      final top = renderObject.localToGlobal(Offset.zero).dy;
      final viewportHeight = MediaQuery.sizeOf(context).height;
      final menuHeight =
          widget.menuChildren.length * AppTokens.menuItemHeight +
          AppTokens.space2;
      final roomBelow =
          viewportHeight - top - renderObject.size.height - AppTokens.space1;
      final opensAbove = roomBelow < menuHeight && top > menuHeight;
      _resolvedAlignmentOffset = Offset(
        widget.alignmentOffset.dx,
        opensAbove
            ? renderObject.size.height + AppTokens.space1 - menuHeight
            : -AppTokens.space1,
      );
    }
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (force || _buttonHovered || _submenuHovered)) {
        _controller.open();
      }
    });
  }

  void _scheduleClose([Duration delay = _submenuCloseDelay]) {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    _closeTimer = Timer(delay, () {
      if (mounted && !_isHovered) {
        _closing = true;
        _controller.close();
      }
    });
  }

  void _enterButton(PointerEnterEvent event) {
    _buttonHovered = true;
    _closeTimer?.cancel();
    final wasClosing = _closing;
    _closing = false;
    // MenuController.isOpen remains true during the close animation. Reopen
    // immediately only when a close was actually requested; a normal return
    // to the parent should keep the existing submenu intact.
    if (wasClosing) {
      _openMenu();
    } else if (!_controller.isOpen) {
      _openOnHover();
    }
  }

  void _exitButton(PointerExitEvent event) {
    _buttonHovered = false;
    _scheduleClose(_submenuReturnDelay);
  }

  void _enterSubmenu(PointerEnterEvent event) {
    _submenuHovered = true;
    _closeTimer?.cancel();
    final wasClosing = _closing;
    _closing = false;
    if (wasClosing) _openMenu();
  }

  bool _isReturningToButton(PointerExitEvent event) {
    final renderObject = _buttonKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final buttonRect = topLeft & renderObject.size;
    const safePadding = AppTokens.space1;
    return event.position.dx <= buttonRect.right + safePadding &&
        event.position.dy >= buttonRect.top - safePadding &&
        event.position.dy <= buttonRect.bottom + safePadding;
  }

  void _exitSubmenu(PointerExitEvent event) {
    _submenuHovered = false;
    // Keep the submenu open while the pointer is crossing the small safe
    // overlap back toward its parent item. This uses global coordinates so it
    // remains reliable even when the overlay changes hit-test order.
    if (_isReturningToButton(event)) {
      _closeTimer?.cancel();
      _closing = false;
      return;
    }
    _scheduleClose();
  }

  @override
  void dispose() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final submenuChildren = [
      for (final child in widget.menuChildren)
        MouseRegion(onEnter: _enterSubmenu, onExit: _exitSubmenu, child: child),
    ];
    return MenuAnchor(
      controller: _controller,
      crossAxisUnconstrained: widget.crossAxisUnconstrained,
      style: widget.menuStyle,
      alignmentOffset: _resolvedAlignmentOffset,
      menuChildren: submenuChildren,
      builder: (context, controller, child) => MouseRegion(
        onEnter: _enterButton,
        onExit: _exitButton,
        child: MenuItemButton(
          key: _buttonKey,
          closeOnActivate: false,
          onPressed: !widget.enabled
              ? null
              : () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    _openMenu(force: true);
                  }
                },
          leadingIcon: widget.leadingIcon,
          trailingIcon: widget.submenuIcon.resolve(const {}),
          style: widget.style,
          child: widget.child,
        ),
      ),
    );
  }
}

class _ViewerPageState extends State<ViewerPage>
    with TickerProviderStateMixin, WidgetsBindingObserver, WindowListener {
  static const _infoPanelWidth = 360.0;
  static const _infoPanelMinWidth = 260.0;
  static const _topBarHeight = 44.0;
  static const _topBarControlSize = 36.0;
  static const _topBarFlushControlSize = 44.0;
  static const _topBarIconSize = 18.0;
  // Top bar geometry. The bar collapses by measured content width (see
  // [CommandBarLayout]) instead of fixed window-width breakpoints.
  static const _sortLabelMaxWidth = 96.0;
  // Text padding (8 + 8) plus the chevron and its gap (4 + 14) inside the
  // labelled sort button, plus the 2 px padding on both sides.
  static const _sortLabelChrome = 38.0;
  static const _topBarLeadingInset = 10.0;
  static const _sortMenuWidth = 252.0;
  static const _overflowMenuWidth = 224.0;
  static const _contextMenuWidth = 280.0;
  static const _contextMenuActionWidth = 64.0;
  static const _bottomStatusBarHeight = 40.0;
  static const _bottomBarButtonSize = 32.0;
  static const _bottomBarIconSize = 18.0;
  static const _scaleButtonIconSize = 16.0;
  static const _statusZoomPanelWidth = 300.0;
  static const _minZoomScale = 0.05;
  static const _maxZoomScale = 8.0;
  static const _zoomSliderWidth = 120.0;
  static const _zoomSliderThumbRadius = AppTokens.zoomSliderThumbRadius;
  static const _zoomSliderHoverRadius = 12.0;
  late final _configStore = widget.configStore ?? AppConfigStore();
  late final _readingStates = ReadingStateStore(_configStore);
  late final _controller = ViewerController(
    configStore: _configStore,
    archiveService: widget.archiveService,
    readingStates: _readingStates,
  );
  final _session = ViewerSession();
  final _autoPlay = AutoPlayController();
  late final _colorPicker = ColorPickerController(
    history: RecentColorStore(_configStore),
  );

  String get _colorPickerLabel =>
      colorPickerCopy(context, '颜色拾取', 'Color picker');

  void _toggleColorPicker() {
    if (!_colorPicker.active &&
        (_controller.currentEntry == null ||
            _gridVisible ||
            _controller.currentEntry!.format == ImageFormat.archive)) {
      return;
    }
    _closeTopBarMenu();
    _closeContextMenu();
    _closeStatusZoomPanel();
    _navigationHold.stop();
    _stopVerticalScroll();
    _colorPicker.format = _session.settings.colorPickerFormat;
    setState(() {
      _colorPicker.setActive(!_colorPicker.active);
      _showLeftNavigation = _showRightNavigation = false;
    });
    _focusNode.requestFocus();
  }

  void _saveColorPickerFormat(ColorCopyFormat format) {
    final settings = _session.settings.copyWith(colorPickerFormat: format);
    _session.applySettings(settings);
    unawaited(_persistSettings(settings));
  }

  late final Ticker _autoPlayTicker;
  Duration _autoPlayLastTick = Duration.zero;
  Object? _autoPlayPresentation;
  ImageEntry? _autoPlaySpreadEntry;
  ImageEntry? _autoPlaySpreadPeer;
  final _displayedEntries = <String>{};
  final _autoPlayAnimations = <String, AnimationPlaybackController>{};
  bool _autoPlayAdvancing = false;
  bool _autoPlayOptionsOpen = false;
  AutoPlayStatus _autoPlayLastStatus = AutoPlayStatus.stopped;
  String? _readingScope;
  String? _readingContext;
  String? _readingEntry;
  Map<String, String> _readingEntryPaths = {};
  List<ImageEntry>? _readingEntriesSource;
  Timer? _readingSaveTimer;
  bool _restoringReading = false;
  bool _closingWindow = false;
  bool _showingRecentOpen = false;
  int _recentOpenGeneration = 0;
  List<RecentOpenEntry> _recentMenuEntries = const [];
  bool _recentMenuLoading = false;
  Offset? _readingRestoreAnchor;
  ViewerShortcutBindings get _shortcuts =>
      widget.shortcuts.withOverrides(_session.settings.shortcutOverrides);
  LogicalKeyboardKey? _navigationShortcutKey;
  final _formatDetector = FormatDetector();
  final _focusNode = FocusNode();
  final _directorySearchFocus = FocusNode();
  final _borderlessDirectorySearchFocus = FocusNode();
  final _gridSearchFocus = FocusNode();
  final _fileNameEditorKey = GlobalKey<AppFileNameEditorState>();
  final _gridKey = GlobalKey<GridOverviewState>();
  bool _gridVisible = false;
  ImageEntry? _gridSelected;
  Future<ImageMetadata>? _gridMetadata;
  ImageFileVersion? _gridMetadataVersion;
  double _gridItemWidth = 180;
  String? _gridReadingId;
  String get _gridLabel => Localizations.localeOf(context).languageCode == 'zh'
      ? '网格总览'
      : 'Grid overview';
  bool get _canEnterGrid =>
      !_showingRecentOpen && _controller.entries.isNotEmpty;

  void _toggleGrid() {
    if (!_gridVisible && !_canEnterGrid) return;
    if (_colorPicker.active) _toggleColorPicker();
    _closeTopBarMenu();
    _closeContextMenu();
    _closeStatusZoomPanel();
    _navigationHold.stop();
    _stopVerticalScroll();
    _cancelSelection();
    _autoPlay.pause();
    if (!_gridVisible) {
      _showingRecentOpen = false;
      _comicPositionController.flushCurrentPage();
      _neighborPrecacheTimer?.cancel();
      _gridSelected = _controller.currentEntry;
      _gridReadingId = _controller.currentEntry?.id;
      _gridMetadata = _metadataFuture;
      _gridMetadataVersion = _metadataVersion;
    }
    setState(() => _gridVisible = !_gridVisible);
    _animationPlayback.value?.setSuspended(_gridVisible || _animationSuspended);
    if (!_gridVisible) _scheduleNeighborPrecache();
    _focusNode.requestFocus();
  }

  void _selectGridEntry(ImageEntry entry) {
    if (_gridSelected?.id != entry.id) {
      setState(() {
        _gridSelected = entry;
        _gridMetadata = null;
      });
      if (_infoVisible) _loadGridMetadata();
    }
    _focusNode.requestFocus();
  }

  void _loadGridMetadata() {
    final entry = _gridSelected;
    if (entry == null) return;
    final version = _resources.version(entry);
    if (_gridMetadata != null && _gridMetadataVersion == version) return;
    _gridMetadataVersion = version;
    _gridMetadata = _resources.metadata(
      entry,
      priority: DecodePriority.metadata,
    );
    _gridMetadata!.ignore();
  }

  Future<void> _openGridEntry(ImageEntry entry) async {
    final index = _controller.entries.indexWhere((item) => item.id == entry.id);
    if (index < 0) return;
    await _select(index);
    if (mounted && _gridVisible && _controller.currentEntry?.id == entry.id) {
      _toggleGrid();
    }
  }

  Widget _buildGridOverview() => Padding(
    padding: EdgeInsets.only(top: _floatingToolbar ? _topBarHeight : 0),
    child: GridOverview(
      key: _gridKey,
      searchFocusNode: _gridSearchFocus,
      entries: _controller.entries,
      resources: _resources,
      selectedId: _gridSelected?.id,
      readingId: _controller.currentEntry?.id,
      scopeLabel:
          _controller.archiveContext?.displayPath(
            _controller.folderPath ?? '',
          ) ??
          (_controller.folderPath == null
              ? ''
              : paths.basename(_controller.folderPath!)),
      emptyMessage: _emptyCanvasMessage(),
      onSelect: _selectGridEntry,
      onOpen: _openGridEntry,
      onClose: _toggleGrid,
      onOpenDirectory: !_session.settings.showBottomBar
          ? _toggleDirectoryPanel
          : null,
      onOpenFolder: _openFolder,
      itemWidth: _gridItemWidth,
      onSizeChanged: (value) => setState(() => _gridItemWidth = value),
    ),
  );

  Future<void> _gridAction(VoidCallback action) async {
    final entry = _gridSelected;
    if (entry == null) return;
    await _openGridEntry(entry);
    if (mounted && !_gridVisible && _controller.currentEntry?.id == entry.id) {
      action();
    }
  }

  Widget _buildGridStatusBar() {
    final tokens = ViewerThemeTokens.of(context);
    return ColoredBox(
      color: tokens.navigationSurface,
      child: Center(
        child: SizedBox(
          height: _bottomBarButtonSize,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _buildDirectoryToggle(),
                _buildThumbnailToggle(),
                Expanded(
                  child: Text(
                    _gridSelected?.relativePath ?? _gridLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
                AppIconButton(
                  icon: FluentIcons.info_20_regular,
                  tooltip: _tooltipLabel(
                    _l10n.information,
                    _binding(ViewerCommand.toggleInfo),
                  ),
                  onPressed: () {
                    setState(() => _infoVisible = !_infoVisible);
                    if (_infoVisible) _loadGridMetadata();
                  },
                ),
                AppIconButton(
                  icon: FluentIcons.full_screen_maximize_20_regular,
                  tooltip: _l10n.fullscreen,
                  onPressed: _toggleFullscreen,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  final _transformController = TransformationController();
  final _svgWebView = SvgWebViewSession();
  final _comicPositionController = ComicPositionController();
  final _modeProgress =
      <
        ViewerMode,
        ({
          String entryId,
          ViewScaleMode scaleMode,
          Matrix4 transform,
          double referenceScale,
          ComicReadingPosition? comicPosition,
        })
      >{};
  Matrix4? _modeRestoreTransform;
  ComicReadingPosition? _comicRestorePosition;
  final _viewportCommands = ZoomableViewportCommands();
  final _scrollNavigation = ScrollNavigationController();
  int _transitionDirection = 1;
  bool _holdSingleImage = false;
  String? _pairingAnchorId;
  late final NavigationHoldController _navigationHold =
      NavigationHoldController((direction) {
        if (!_windowFocused ||
            !_focusNode.hasFocus ||
            _contextMenuOpen ||
            _topBarMenuEntry != null) {
          _navigationHold.stop();
          return;
        }
        _move(direction, singleImage: _holdSingleImage);
      });
  final _zoomSliderLayerLink = LayerLink();
  final _zoomSliderTooltipController = OverlayPortalController();
  double _zoomReferenceScale = 1.0;
  final _zoomReferenceChanges = ValueNotifier<double>(1);
  Size? _lastContentSize;
  Size? _lastViewportSize;
  ({double scale, Offset? anchor})? _pendingEntryView;
  int _comicReferenceResetRequest = -1;
  Future<ImageMetadata>? _spreadMetadataSource;
  String? _spreadMetadataPeerId;
  Future<List<ImageMetadata?>>? _spreadMetadataFuture;
  bool _resettingScale = false;
  bool _zoomReferenceAdjustmentScheduled = false;
  double? _pendingZoomReferenceActualScale;
  final _registry = DecoderRegistry();
  final _fileOperations = FileOperationService();
  final _resources = ImageResourceService();
  bool _showToolbar = true;
  bool _toolbarPointerInside = false;
  bool _toolbarFocused = false;
  bool _toolbarKeyboardFocus = true;
  final _ordinaryLayout = _ViewerPanelLayout();
  _ViewerPanelLayout? _borderlessLayout;
  bool get _isBorderless => _borderlessLayout != null;
  _ViewerPanelLayout get _panelLayout => _borderlessLayout ?? _ordinaryLayout;
  bool get _floatingToolbar =>
      _isBorderless || _session.settings.toolbarMode == ToolbarMode.floating;
  bool get _infoVisible => _panelLayout.infoVisible;
  set _infoVisible(bool value) => _panelLayout.infoVisible = value;
  bool get _thumbnailsVisible => _panelLayout.thumbnailsVisible;
  set _thumbnailsVisible(bool value) => _panelLayout.thumbnailsVisible = value;
  bool get _directoryVisible => _panelLayout.directoryVisible;
  set _directoryVisible(bool value) => _panelLayout.directoryVisible = value;
  bool get _directoryDismissed => _panelLayout.directoryDismissed;
  set _directoryDismissed(bool value) =>
      _panelLayout.directoryDismissed = value;
  String? _directoryRootPath;
  Set<String> get _directoryExpandedPaths => _panelLayout.expandedPaths;
  bool _isFullscreen = false;
  bool _windowFocused = true;
  final _activePointerDowns = <int, PointerDownEvent>{};
  bool _zoomSliderPointerMoved = false;
  bool _zoomSliderStartedOnThumb = false;
  bool _zoomSliderHovered = false;
  double? _zoomSliderPointerDownX;
  bool _showLeftNavigation = false;
  bool _showRightNavigation = false;
  bool _dropActive = false;
  bool _disposing = false;
  bool _pageActive = true;
  double _physicalViewportExtent = 2048;
  final _hdrHoveredControls = <String>{};
  final _hdrControlsHovered = ValueNotifier(false);
  bool _isMaximized = false;
  Timer? _toolbarTimer;
  // The OS move loop takes the cursor away from the Flutter view, so a drag
  // reports a pointer exit even though the pointer keeps holding the bar.
  bool _windowDragActive = false;
  bool _pendingToolbarHoverCheck = false;
  final _topBarRegionKey = GlobalKey();
  final _animationPlayback = ValueNotifier<AnimationPlaybackController?>(null);
  String? _animationSelectedId;
  bool _animationSuspended = false;
  final _frameInfo = ValueNotifier<(int, int)>((0, 1));
  final _infoScrollController = ScrollController();
  double _ordinaryInfoOffset = 0;
  ImageFileVersion? _metadataVersion;
  Future<ImageMetadata>? _metadataFuture;
  Timer? _neighborPrecacheTimer;
  Timer? _resourceTimer;
  final _systemResources = const SystemResourceService();
  final _prefetchPlanner = const prefetch.PrefetchPlanner();
  int _lastReadingIndex = -1;
  prefetch.ReadingDirection _readingDirection =
      prefetch.ReadingDirection.stationary;
  Set<int> _visibleComicPages = {};
  List<prefetch.PageGeometry>? _comicGeometry;
  double? _comicViewportStart;
  double? _comicViewportEnd;
  DateTime? _lastMemoryPressure;
  Duration _frameBudget = const Duration(microseconds: 16667);
  Set<String> _admittedComicPages = {};
  List<ImageEntry>? _plannedEntries;
  final Set<String> _landscapeIds = {};
  DecodeRequest? _selectionRequest;
  int _selectionGeneration = 0;
  int? _pendingSelectionIndex;
  SourceFileLease? _clipboardLease;
  final _contextMenuController = MenuController();
  final _contextMenuCoordinateKey = GlobalKey();
  final _contextMenuVisible = ValueNotifier(false);
  final _contextMenuRevision = ValueNotifier(0);
  Offset _contextMenuAnchorPosition = Offset.zero;
  Object? _contextMenuToken;
  bool get _contextMenuOpen => _contextMenuVisible.value;
  Offset? _contextMenuPosition;
  Timer? _contextMenuDismissTimer;
  final _externalOpen = const ExternalOpenService();
  List<ExternalApplication> _externalApplications = const [];
  ImageEntry? _externalMenuEntry;
  bool _externalApplicationsLoading = false;
  bool _externalApplicationsFailed = false;
  bool _externalOpenBusy = false;
  OverlayEntry? _topBarMenuEntry;
  _TopBarMenuKind? _topBarMenuKind;
  OverlayEntry? _statusZoomEntry;
  bool _statusZoomHasControls = false;
  // Last decision of each bar, kept so a width that hovers around a collapse
  // threshold does not flip the same group on and off every frame.
  CommandBarLayout? _commandBarLayout;
  StatusBarLayout? _statusBarLayout;
  int _viewResetRequest = 0;
  late final KeyboardScrollController _keyboardScroll;

  String? get _initialPath => widget.initialPath;
  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    _physicalViewportExtent =
        math.max(size.width, size.height) *
        MediaQuery.devicePixelRatioOf(context);
    final refreshRate = View.of(context).display.refreshRate;
    _frameBudget = Duration(
      microseconds: (1000000 / (refreshRate > 0 ? refreshRate : 60)).round(),
    );
  }

  @override
  void deactivate() {
    _saveReadingState();
    _pageActive = false;
    _neighborPrecacheTimer?.cancel();
    _neighborPrecacheTimer = null;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _pageActive = true;
    _scheduleNeighborPrecache();
  }

  @override
  void initState() {
    super.initState();
    _autoPlayTicker = createTicker(_tickAutoPlay);
    _autoPlay.addListener(_onAutoPlayChanged);
    _keyboardScroll = KeyboardScrollController(
      vsync: this,
      onScroll: (delta) {
        if (_session.mode == ViewerMode.comic && _isHorizontalComic) {
          _viewportCommands.moveHorizontally(delta);
        } else {
          _viewportCommands.moveVertically(delta);
        }
      },
    );
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    _controller.addListener(_onControllerChanged);
    _session.addListener(_onSessionChanged);
    _transformController.addListener(_scheduleReadingSave);
    _controller.prepareArchiveEntry = _prepareArchiveEntry;
    WidgetsBinding.instance.addTimingsCallback(_recordFrameTimings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _clearTextInput();
      _initialize();
    });
  }

  @override
  void dispose() {
    widget.instanceCoordinator?.detach();
    widget.windowPlacement?.dispose();
    _configStore.cancelPendingReads();
    _readingSaveTimer?.cancel();
    _disposing = true;
    _autoPlayTicker.dispose();
    _autoPlay.removeListener(_onAutoPlayChanged);
    _autoPlay.dispose();
    _colorPicker.dispose();
    _notifications.dispose();
    _keyboardScroll.dispose();
    _navigationHold.dispose();
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    _controller.removeListener(_onControllerChanged);
    _session.removeListener(_onSessionChanged);
    _transformController.removeListener(_scheduleReadingSave);
    _controller.dispose();
    _session.dispose();
    _focusNode.dispose();
    _directorySearchFocus.dispose();
    _borderlessDirectorySearchFocus.dispose();
    _gridSearchFocus.dispose();
    _transformController.dispose();
    _zoomReferenceChanges.dispose();
    _viewportCommands.dispose();
    _hdrControlsHovered.dispose();
    _toolbarTimer?.cancel();
    _neighborPrecacheTimer?.cancel();
    _resourceTimer?.cancel();
    WidgetsBinding.instance.removeTimingsCallback(_recordFrameTimings);
    _contextMenuDismissTimer?.cancel();
    _contextMenuController.close();
    _contextMenuVisible.dispose();
    _contextMenuRevision.dispose();
    _contextMenuToken = null;
    _topBarMenuEntry?.remove();
    _topBarMenuEntry?.dispose();
    _topBarMenuEntry = null;
    _topBarMenuKind = null;
    _statusZoomEntry?.remove();
    _statusZoomEntry?.dispose();
    _statusZoomEntry = null;
    _resources.dispose();
    _svgWebView.dispose();
    _frameInfo.dispose();
    _animationPlayback.dispose();
    _infoScrollController.dispose();
    _selectionRequest?.cancel();
    unawaited(_clipboardLease?.release() ?? Future<void>.value());
    super.dispose();
  }

  void _onSessionChanged() {
    _autoPlay.configure(_session.settings.autoPlay, _session.mode);
    if (!_restoringReading) _saveReadingState();
    if (_contextMenuOpen) _scheduleContextMenuClose();
    _scheduleNeighborPrecache();
    if (mounted) setState(() {});
  }

  void _scheduleReadingSave() {
    if (_restoringReading ||
        _disposing ||
        _closingWindow ||
        _readingScope == null) {
      return;
    }
    _readingSaveTimer?.cancel();
    _readingSaveTimer = Timer(
      const Duration(milliseconds: 350),
      _saveReadingState,
    );
  }

  Future<void> _saveReadingState() async {
    final scope = _readingScope;
    if (scope == null || _restoringReading) return;
    _readingSaveTimer?.cancel();
    String? entryPath = _readingEntry;
    double? pageFraction;
    double? crossFraction;
    if (_session.mode == ViewerMode.comic) {
      final position = _comicPositionController.capture();
      if (position != null && _readingEntryPaths.containsKey(position.path)) {
        entryPath = _readingEntryPaths[position.path];
        pageFraction = position.pageFraction;
        crossFraction = position.crossFraction;
      }
    } else if (_session.mode == ViewerMode.longImage &&
        _lastContentSize != null) {
      final content = _lastContentSize!;
      final viewport = _lastViewportSize;
      final matrix = _transformController.value;
      final scale = matrix.getMaxScaleOnAxis();
      if (viewport != null && !content.isEmpty && scale > 0) {
        final translation = matrix.getTranslation();
        pageFraction =
            ((viewport.height / 2 - translation.y) / scale / content.height)
                .clamp(0, 1);
        crossFraction =
            ((viewport.width / 2 - translation.x) / scale / content.width)
                .clamp(0, 1);
      }
    }
    await _readingStates
        .save(
          scope,
          _session.readingState(
            entryPath: entryPath,
            pageFraction: pageFraction,
            crossFraction: crossFraction,
          ),
        )
        .catchError((Object _) {});
  }

  void _syncReadingContext() {
    if (_controller.isIndexing || _controller.isOpeningArchive) return;
    final scope = _controller.readingScopeKey;
    final token = scope ?? _controller.archiveContext?.extractionRoot;
    if (token != _readingContext) {
      _saveReadingState();
      _restoringReading = true;
      _readingScope = scope;
      _readingContext = token;
      _modeProgress.clear();
      _modeRestoreTransform = null;
      _pendingEntryView = null;
      _pendingZoomReferenceActualScale = null;
      _lastContentSize = null;
      _lastViewportSize = null;
      _comicRestorePosition = null;
      _readingRestoreAnchor = null;
      _resettingScale = true;
      _transformController.value = Matrix4.identity();
      _zoomReferenceScale = 1;
      _viewResetRequest++;
      final saved = scope == null ? null : _readingStates[scope];
      _session.restoreReadingState(saved);
      final current = _controller.currentEntry;
      if (saved?.entryPath != null &&
          current != null &&
          _controller.readingEntryPath(current) == saved!.entryPath &&
          saved.pageFraction != null) {
        if (_session.mode == ViewerMode.comic) {
          _comicRestorePosition = ComicReadingPosition(
            path: current.id,
            pageFraction: saved.pageFraction!,
            crossFraction: saved.crossFraction ?? 0.5,
          );
        } else if (_session.mode == ViewerMode.longImage) {
          _readingRestoreAnchor = Offset(
            saved.crossFraction ?? 0.5,
            saved.pageFraction!,
          );
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _restoringReading = false;
        _scheduleReadingSave();
      });
    }
    if (!identical(_readingEntriesSource, _controller.entries)) {
      _readingEntriesSource = _controller.entries;
      _readingEntryPaths = {
        for (final entry in _controller.entries)
          entry.id: ?_controller.readingEntryPath(entry),
      };
    }
    final current = _controller.currentEntry;
    _readingEntry = current == null
        ? null
        : _controller.readingEntryPath(current);
    if (!_restoringReading) _scheduleReadingSave();
  }

  @override
  void onWindowClose() async {
    if (_closingWindow) return;
    _closingWindow = true;
    await widget.instanceCoordinator?.close();
    _readingSaveTimer?.cancel();
    _resourceTimer?.cancel();
    _navigationHold.stop();
    _stopVerticalScroll();
    _autoPlay.stop();
    try {
      await Future.wait([
        _saveReadingState(),
        _controller.flushPersistence(),
        _colorPicker.flushHistory(),
        if (widget.windowPlacement case final placement?) placement.flush(),
      ]).timeout(const Duration(seconds: 2));
    } catch (error) {
      debugPrint('Unable to finish saving before window close: $error');
    } finally {
      // Re-enter the native close path so the HWND is destroyed before the
      // message loop quits. Never leave preventClose enabled after a save error.
      try {
        await windowManager.setPreventClose(false);
        await windowManager.close();
      } catch (error) {
        _closingWindow = false;
        if (mounted) {
          _showErrorNotification(
            recentCopy(
              context,
              '无法关闭窗口，请重试。',
              'Unable to close the window. Try again.',
            ),
          );
        }
      }
    }
  }

  void _toggleThumbnails() {
    if (!mounted) return;
    setState(() {
      _thumbnailsVisible = !_thumbnailsVisible;
    });
  }

  void _toggleInfoPanel() {
    _closeContextMenu();
    if (_gridVisible) _loadGridMetadata();
    setState(() => _infoVisible = !_infoVisible);
  }

  void _toggleDirectoryPanel() {
    _closeContextMenu();
    _navigationHold.stop();
    _stopVerticalScroll();
    if (_directoryIsShown) {
      _closeDirectory();
    } else {
      _setDirectoryVisible(true);
    }
  }

  @override
  void onWindowEnterFullScreen() {
    _closeTopBarMenu();
    _closeStatusZoomPanel();
    _enterFullscreen();
  }

  @override
  void onWindowLeaveFullScreen() {
    _closeTopBarMenu();
    _closeStatusZoomPanel();
    _leaveFullscreen();
  }

  @override
  void onWindowBlur() {
    _navigationHold.stop();
    _cancelActivePointers();
    _setWindowFocused(false);
    if (_contextMenuOpen) _scheduleContextMenuClose();
    _closeTopBarMenu();
    _closeStatusZoomPanel();
  }

  @override
  void onWindowFocus() {
    unawaited(widget.instanceCoordinator?.markActive() ?? Future<void>.value());
    if (_colorPicker.active) unawaited(_colorPicker.refreshHistory());
    _setWindowFocused(true);
    _contextMenuDismissTimer?.cancel();
  }

  void _setWindowFocused(bool value) {
    _controller.setWindowFocused(value);
    _resources.setActive(value);
    _scheduleNeighborPrecache();
    if (!mounted || _windowFocused == value) return;
    setState(() => _windowFocused = value);
  }

  void _cancelActivePointers() {
    // The mouse-up can go to the external application after focus changes.
    // End the old gesture so it cannot capture clicks when this window returns.
    for (final pointer in List<int>.of(_activePointerDowns.keys)) {
      GestureBinding.instance.cancelPointer(pointer);
    }
    _activePointerDowns.clear();
  }

  void _recoverMousePointers(PointerEvent event) {
    if (event.kind != PointerDeviceKind.mouse || _activePointerDowns.isEmpty) {
      return;
    }
    // Flutter keeps button chords in one pointer sequence. A fresh mouse-down
    // or button-free hover means an older sequence from that mouse was lost.
    final stale = _activePointerDowns.values
        .where(
          (previous) =>
              previous.kind == PointerDeviceKind.mouse &&
              previous.device == event.device &&
              previous.pointer != event.pointer,
        )
        .map((previous) => previous.pointer)
        .toList();
    for (final pointer in stale) {
      _activePointerDowns.remove(pointer);
      GestureBinding.instance.cancelPointer(pointer);
    }
  }

  @override
  void onWindowMinimize() {
    if (mounted) setState(() => _animationSuspended = true);
    _animationPlayback.value?.setSuspended(true);
  }

  @override
  void onWindowRestore() {
    if (mounted) setState(() => _animationSuspended = false);
    _animationPlayback.value?.setSuspended(_gridVisible);
  }

  @override
  void onWindowMaximize() {
    _closeTopBarMenu();
    _closeStatusZoomPanel();
    _setMaximizedState(true);
  }

  @override
  void onWindowUnmaximize() {
    _closeTopBarMenu();
    _closeStatusZoomPanel();
    _setMaximizedState(false);
  }

  @override
  void onWindowResize() {
    _closeTopBarMenu();
    _closeStatusZoomPanel();
  }

  @override
  void onWindowResized() {
    _closeTopBarMenu();
    _closeStatusZoomPanel();
    unawaited(_syncMaximizedState());
  }

  @override
  void onWindowMove() {
    _closeTopBarMenu();
    _closeStatusZoomPanel();
  }

  @override
  void onWindowMoved() {
    _closeTopBarMenu();
    _closeStatusZoomPanel();
  }

  void _setMaximizedState(bool value) {
    if (!mounted || _isMaximized == value) return;
    setState(() => _isMaximized = value);
  }

  Future<void> _syncMaximizedState() async {
    final value = await windowManager.isMaximized();
    _setMaximizedState(value);
  }

  void _enterFullscreen() {
    if (!mounted) return;
    setState(() => _isFullscreen = true);
  }

  void _leaveFullscreen() {
    if (!mounted) return;
    setState(() => _isFullscreen = false);
    unawaited(_syncWindowFrame());
  }

  Future<void> _syncFullscreenState() async {
    final value = await windowManager.isFullScreen();
    if (value) {
      _enterFullscreen();
    } else {
      _leaveFullscreen();
    }
  }

  Future<void> _syncWindowFrame() async {
    if (_isFullscreen) return;
    if (_isBorderless) {
      await windowManager.setAsFrameless();
    } else {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    }
  }

  Future<void> _toggleBorderless() async {
    _closeTopBarMenu();
    _closeContextMenu();
    _closeStatusZoomPanel();
    _toolbarTimer?.cancel();
    final restoreInfoOffset = _isBorderless ? _ordinaryInfoOffset : null;
    if (!_isBorderless && _infoScrollController.hasClients) {
      _ordinaryInfoOffset = _infoScrollController.offset;
    }
    setState(() {
      _borderlessLayout = _isBorderless
          ? null
          : _ViewerPanelLayout(
              thumbnailsVisible: false,
              directoryPinned: false,
            );
      _showToolbar = !_floatingToolbar;
    });
    _focusNode.requestFocus();
    if (restoreInfoOffset != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _infoScrollController.hasClients) {
          _infoScrollController.jumpTo(
            restoreInfoOffset.clamp(
              0,
              _infoScrollController.position.maxScrollExtent,
            ),
          );
        }
      });
    }
    await _syncWindowFrame();
  }

  void _configureArchive(ViewerSettings settings) {
    _resources.configureThumbnails(settings.thumbnailPrefetchMode);
    _controller.configureArchive(settings);
    _configureImagePrefetch(settings);
    if (_controller.entries.isEmpty) {
      _resources.applyWorkingSet(
        protectedIds: {},
        retainedIds: {},
        memoryBudgetBytes: _archiveMemoryBudgetBytes,
      );
    }
    _scheduleNeighborPrecache();
  }

  int? get _archiveMemoryBudgetBytes =>
      !_controller.isArchiveView ||
          _session.settings.archiveMemoryBudgetMiB == 0
      ? null
      : _session.settings.archiveMemoryBudgetMiB * 1024 * 1024;

  void _configureImagePrefetch(ViewerSettings settings) {
    _resources.configurePrefetch(
      !_controller.isArchiveView
          ? prefetch.PrefetchLevel.normal
          : switch (settings.archivePrefetchMode) {
              ArchivePrefetchMode.automatic => prefetch.PrefetchLevel.normal,
              ArchivePrefetchMode.conservative =>
                prefetch.PrefetchLevel.conservative,
              ArchivePrefetchMode.off => prefetch.PrefetchLevel.onDemand,
            },
    );
  }

  Future<void> _readSystemResources() async {
    final snapshot = await _systemResources.read(
      diskPath: Directory.systemTemp.path,
    );
    if (!mounted) return;
    final previousLevel = _resources.policy.level;
    _resources.policy.updateMemory(
      physicalMemoryBytes: snapshot?.physicalMemoryBytes,
      availableMemoryBytes: snapshot?.availableMemoryBytes,
    );
    final capacity = snapshot?.diskCapacityBytes;
    final diskMargin = math.max(
      1024 * 1024 * 1024,
      math.min(8 * 1024 * 1024 * 1024, (capacity ?? 0) ~/ 20),
    );
    final lowDisk =
        snapshot?.availableDiskBytes != null &&
        snapshot!.availableDiskBytes! < diskMargin;
    final lowMemory =
        snapshot?.availableMemoryBytes != null &&
        snapshot!.availableMemoryBytes! < 32 * 1024 * 1024;
    if (lowDisk || lowMemory) {
      if (lowDisk && _resources.policy.reason != 'diskSpace') {
        unawaited(_controller.clearArchiveCache().catchError((_) {}));
      }
      _lastMemoryPressure = DateTime.now();
      _resources.policy.pressure(
        reason: lowDisk ? 'diskSpace' : 'availableMemory',
      );
    }
    if (_lastMemoryPressure != null &&
        DateTime.now().difference(_lastMemoryPressure!) >
            const Duration(seconds: 10) &&
        (snapshot?.availableMemoryBytes ?? 0) > 128 * 1024 * 1024 &&
        !lowDisk) {
      _resources.policy.clearPressure();
      _lastMemoryPressure = null;
    }
    _resources.policy.tick();
    _resources.refreshPolicy();
    if (_resources.policy.level != previousLevel) setState(() {});
    _scheduleNeighborPrecache();
  }

  void _recordFrameTimings(List<FrameTiming> timings) {
    final previousLevel = _resources.policy.level;
    for (final timing in timings) {
      _resources.recordFrame(
        elapsed: timing.totalSpan,
        frameBudget: _frameBudget,
      );
    }
    if (mounted && previousLevel != _resources.policy.level) {
      setState(() {});
      _scheduleNeighborPrecache();
    }
  }

  @override
  void didHaveMemoryPressure() {
    _lastMemoryPressure = DateTime.now();
    _resources.memoryPressure();
    _scheduleNeighborPrecache();
  }

  Future<void> _prepareArchiveEntry(
    ImageEntry entry,
    DecodeRequest request,
  ) async {
    if (!mounted) throw DecodeCancelled();
    await _resources.metadata(entry, priority: DecodePriority.foreground);
    request.throwIfCancelled();
    if (!mounted) throw DecodeCancelled();
    if (entry.format == ImageFormat.svg ||
        _resources.isAnimated(entry) ||
        _resources.inflightBytes > _resources.memoryBudgetBytes ~/ 2) {
      return;
    }
    final width = _imageCacheWidth();
    final stream = _resources
        .provider(entry, targetWidth: width, targetHeight: width)
        .resolve(ImageConfiguration.empty);
    final ready = Completer<void>();
    final listener = ImageStreamListener(
      (_, _) {
        if (!ready.isCompleted) ready.complete();
      },
      onError: (Object error, StackTrace? stack) {
        if (!ready.isCompleted) ready.completeError(error, stack);
      },
    );
    void cancel() {
      if (!ready.isCompleted) ready.completeError(DecodeCancelled());
    }

    stream.addListener(listener);
    request.addCancelListener(cancel);
    try {
      await ready.future;
      request.throwIfCancelled();
    } finally {
      request.removeCancelListener(cancel);
      stream.removeListener(listener);
    }
  }

  ViewerSettings _persistedSettings = const ViewerSettings();
  Future<void> _externalOpenQueue = Future<void>.value();

  Future<void> _persistSettings(ViewerSettings settings) async {
    final previous = _persistedSettings;
    _persistedSettings = settings;
    try {
      await settings.save(store: _configStore, previous: previous);
    } catch (_) {
      if (identical(_persistedSettings, settings)) {
        _persistedSettings = previous;
      }
      rethrow;
    }
  }

  void _receiveLaunch(AppLaunchRequest request) {
    _externalOpenQueue = _externalOpenQueue
        .then((_) async {
          if (!mounted || _closingWindow) return;
          Navigator.of(context).popUntil((route) => route.isFirst);
          if (await windowManager.isMinimized()) await windowManager.restore();
          await windowManager.show();
          await windowManager.focus();
          _focusNode.requestFocus();
          for (final path in request.paths) {
            if (!mounted || _closingWindow) return;
            await _saveReadingState();
            await _openPath(path);
          }
        })
        .catchError((Object error) {
          if (mounted) {
            _showErrorNotification(
              recentCopy(
                context,
                '无法打开外部请求，请重试。',
                'Unable to open the external request. Please retry.',
              ),
            );
          }
        });
  }

  Future<void> _newWindow({String? path}) async {
    _closeContextMenu();
    if (_session.settings.instanceMode != InstanceMode.multiProcess) return;
    try {
      await DesktopInstancePlatform.launchNew(path: path);
    } catch (_) {
      if (mounted) {
        _showErrorNotification(
          recentCopy(
            context,
            '无法创建新窗口，请重试。',
            'Unable to create a new window. Please retry.',
          ),
        );
      }
    }
  }

  Future<void> _initialize() async {
    final settings =
        widget.initialSettings ??
        await ViewerSettings.load(store: _configStore);
    if (!mounted) return;
    _persistedSettings = settings;
    await windowManager.setPreventClose(true);
    unawaited(_controller.sweepStaleArchives());
    _isFullscreen = await windowManager.isFullScreen();
    _isMaximized = await windowManager.isMaximized();
    _controller.configureOptions(
      sortOrder: settings.sortOrder,
      fileNameSortMode: settings.fileNameSortMode,
      browseMode: settings.browseMode,
      scanUnknownExtensions: settings.scanUnknownExtensions,
      watchFolderChanges: settings.watchFolderChanges,
      recentOpenEnabled: settings.recentOpenEnabled,
      recentOpenLimit: settings.recentOpenLimit,
    );
    _configureArchive(settings);
    unawaited(_readSystemResources());
    _resourceTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_readSystemResources()),
    );
    await windowManager.setAlwaysOnTop(settings.alwaysOnTop);
    final actualAlwaysOnTop = await windowManager.isAlwaysOnTop();
    final appliedSettings = actualAlwaysOnTop == settings.alwaysOnTop
        ? settings
        : settings.copyWith(alwaysOnTop: actualAlwaysOnTop);
    widget.localeController?.setPreference(appliedSettings.localeCode);
    widget.onThemeModeChanged?.call(appliedSettings.themeMode);
    _ordinaryLayout.directoryVisible = appliedSettings.showDirectoryPanel;
    _ordinaryLayout.directoryDismissed = !appliedSettings.showDirectoryPanel;
    _session.applySettings(appliedSettings);
    setState(() {
      _showToolbar = !_floatingToolbar;
    });
    await _readingStates.load();
    if (!mounted) return;
    if (_initialPath != null) {
      await _openPath(_initialPath!);
    } else if (settings.openRecentOnNewWindow || !settings.recentOpenEnabled) {
      _showRecentOpen();
    } else {
      final restored = await _controller.restoreRecentFolder();
      if (!restored && mounted) _showRecentOpen();
    }
    if (!mounted) return;
    widget.instanceCoordinator?.attach(_receiveLaunch);
    DesktopInstancePlatform.listen(
      (files) => unawaited(_receiveNativeFiles(files)),
    );
    for (final files in widget.pendingNativeRequests.toList()) {
      await _receiveNativeFiles(files);
    }
    for (final path in widget.additionalPaths) {
      if (settings.instanceMode == InstanceMode.multiProcess) {
        await _newWindow(path: path);
      } else {
        _receiveLaunch(AppLaunchRequest(paths: [path]));
      }
    }
  }

  Future<void> _receiveNativeFiles(List<String> files) async {
    try {
      // Finder can deliver to any running app instance, including a window
      // whose settings predate a mode change made in another window.
      final config = await _configStore.readOrEmpty();
      final settings = config['settings'];
      if (!mounted || _closingWindow) return;
      if (files.isNotEmpty &&
          settings is Map &&
          settings['instanceMode'] == 'multiProcess') {
        for (final path in files) {
          await DesktopInstancePlatform.launchNew(path: path);
        }
      } else {
        _receiveLaunch(AppLaunchRequest(paths: files));
      }
    } catch (_) {
      if (mounted) {
        _showErrorNotification(
          recentCopy(
            context,
            '无法处理文件打开请求，请重试。',
            'Unable to handle the file-open request. Please retry.',
          ),
        );
      }
    }
  }

  Future<void> _applySettings(
    ViewerSettings settings, {
    bool preserveRecentOpen = false,
  }) async {
    if (settings.showDirectoryPanel != _session.settings.showDirectoryPanel) {
      _ordinaryLayout.directoryVisible = settings.showDirectoryPanel;
      _ordinaryLayout.directoryDismissed = !settings.showDirectoryPanel;
    }
    if (settings == _session.settings) return;
    final recentLimitChanged =
        settings.recentOpenLimit != _session.settings.recentOpenLimit;
    _controller.recentOpenEnabled = settings.recentOpenEnabled;
    _controller.recentOpenLimit = settings.recentOpenLimit;
    if (_readingContext == null &&
        settings.defaultScaleModeFor(_session.mode) !=
            _session.settings.defaultScaleModeFor(_session.mode)) {
      _resettingScale = true;
      _pendingEntryView = null;
      _pendingZoomReferenceActualScale = null;
      _modeRestoreTransform = null;
      _viewResetRequest++;
      if (_session.mode != ViewerMode.comic) {
        _transformController.value = Matrix4.identity();
      }
    }
    _navigationHold.stop();
    _stopVerticalScroll();
    if (!settings.showBottomBar) _closeStatusZoomPanel();
    final currentAlwaysOnTop = await windowManager.isAlwaysOnTop();
    if (currentAlwaysOnTop != settings.alwaysOnTop) {
      await windowManager.setAlwaysOnTop(settings.alwaysOnTop);
    }
    widget.localeController?.setPreference(settings.localeCode);
    widget.onThemeModeChanged?.call(settings.themeMode);
    _session.applySettings(settings);
    _autoPlay.configure(settings.autoPlay, _session.mode);
    setState(() {
      _showToolbar = !_floatingToolbar;
    });
    await _persistSettings(settings);
    if (recentLimitChanged && !preserveRecentOpen) {
      await _controller.recentOpen.trim(settings.recentOpenLimit);
    }
    await _controller.setOptions(
      sortOrder: settings.sortOrder,
      fileNameSortMode: settings.fileNameSortMode,
      browseMode: settings.browseMode,
      scanUnknownExtensions: settings.scanUnknownExtensions,
      watchFolderChanges: settings.watchFolderChanges,
    );
    _configureArchive(settings);
  }

  bool _settingsOpening = false;

  Future<void> _showSettings() async {
    if (_settingsOpening) return;
    _settingsOpening = true;
    try {
      _navigationHold.stop();
      final cache = await _controller.archiveCacheStats();
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => SettingsPage(
            shortcuts: _shortcuts,
            settings: _session.settings,
            onChanged: _applySettings,
            onResetAll: (settings) =>
                _applySettings(settings, preserveRecentOpen: true),
            decoderRegistry: _registry,
            archiveCacheUsageBytes: cache.bytes,
            onClearArchiveCache: _controller.clearArchiveCache,
            onClearRecentOpen: _controller.clearRecentOpen,
            archivePerformanceStatus: switch (_resources.policy.level) {
              prefetch.PrefetchLevel.normal => _l10n.archivePerformanceNormal,
              prefetch.PrefetchLevel.conservative =>
                _l10n.archivePerformanceConservative,
              prefetch.PrefetchLevel.onDemand =>
                _l10n.archivePerformanceOnDemand,
            },
          ),
        ),
      );
      if (mounted && _showingRecentOpen) {
        setState(() => _recentOpenGeneration++);
      }
    } finally {
      _settingsOpening = false;
    }
  }

  Future<void> _toggleMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (maximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    await _syncMaximizedState();
  }

  Future<void> _toggleAlwaysOnTop() async {
    final current = await windowManager.isAlwaysOnTop();
    await windowManager.setAlwaysOnTop(!current);
    final actual = await windowManager.isAlwaysOnTop();
    final settings = _session.settings.copyWith(alwaysOnTop: actual);
    _session.applySettings(settings);
    await _persistSettings(settings);
  }

  void _clearTextInput() {
    // Pointer events bubble through the viewer shell even when they start in
    // the rename field. Never tear down the active editable client while the
    // text field owns focus, otherwise the next click inside the field cannot
    // continue typing.
    if (focusedTextEditor != null) return;
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    SystemChannels.textInput.invokeMethod<void>('TextInput.clearClient');
  }

  void _showToolbarOnEnter() {
    if (!mounted || !_floatingToolbar) {
      return;
    }
    _toolbarTimer?.cancel();
    if (!_showToolbar) setState(() => _showToolbar = true);
  }

  void _hideToolbarOnExit() {
    if (!mounted ||
        _disposing ||
        _windowDragActive ||
        !_floatingToolbar ||
        _toolbarPointerInside ||
        (_toolbarFocused && _toolbarKeyboardFocus) ||
        _topBarMenuEntry != null ||
        _statusZoomEntry != null ||
        _autoPlayOptionsOpen) {
      return;
    }
    _toolbarTimer?.cancel();
    _toolbarTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted &&
          !_windowDragActive &&
          _floatingToolbar &&
          !_toolbarPointerInside &&
          !(_toolbarFocused && _toolbarKeyboardFocus) &&
          _topBarMenuEntry == null &&
          _statusZoomEntry == null &&
          !_autoPlayOptionsOpen) {
        setState(() => _showToolbar = false);
      }
    });
  }

  /// Moves the window through the OS drag loop without losing the floating bar.
  ///
  /// The move loop owns the pointer until the button is released, so the bar
  /// stops receiving hover reports and a stale pointer exit would hide it in
  /// the middle of the drag. Keep it on screen for the whole move and re-read
  /// the pointer once the loop hands the cursor back.
  Future<void> _beginWindowDrag() async {
    if (_windowDragActive) return;
    _closeTopBarMenu();
    _toolbarTimer?.cancel();
    _pendingToolbarHoverCheck = false;
    _windowDragActive = true;
    if (!_showToolbar && _floatingToolbar) {
      setState(() => _showToolbar = true);
    }
    try {
      await windowManager.startDragging();
    } on PlatformException {
      // The window can already be gone when the move is requested.
    } finally {
      _windowDragActive = false;
    }
    if (!mounted) return;
    _pendingToolbarHoverCheck = true;
  }

  bool _isPointerOverTopBar(Offset globalPosition) {
    final box = _topBarRegionKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    return (box.localToGlobal(Offset.zero) & box.size).contains(globalPosition);
  }

  /// Applies the first pointer report after a window move, because the hover
  /// state kept by the framework is stale after the OS owned the cursor.
  void _trackToolbarPointer(PointerEvent event) {
    if (!_pendingToolbarHoverCheck) return;
    _pendingToolbarHoverCheck = false;
    if (!_floatingToolbar) {
      return;
    }
    if (_isPointerOverTopBar(event.position)) {
      _toolbarPointerInside = true;
      _showToolbarOnEnter();
    } else if (_showToolbar) {
      _toolbarPointerInside = false;
      _hideToolbarOnExit();
    }
  }

  Future<void> _openPath(String path) async {
    path = paths.normalize(paths.absolute(path));
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await _openFolderPath(path, establishRoot: true);
      return;
    }
    if (type != FileSystemEntityType.file) return;
    final file = File(path);
    final format = await _formatDetector.detect(file);
    if (format == ImageFormat.archive) {
      await _openArchive(file);
      return;
    }
    final insideArchive =
        _controller.archiveContext?.contains(file.path) == true;
    await _controller.openFolder(
      file.parent.path,
      preferredFilePath: file.path,
      keepArchiveContext: insideArchive,
      persistRecent: !insideArchive,
      recordRecentOpen: false,
    );
    if (!mounted) return;
    final index = _controller.entries.indexWhere(
      (entry) => entry.id == file.path,
    );
    if (index >= 0) {
      setState(() => _showingRecentOpen = false);
      _controller.select(index);
      if (!insideArchive) unawaited(_controller.recordRecentImage(file.path));
    }
    _resetView();
  }

  void _showRecentOpen() {
    if (_gridVisible) _toggleGrid();
    _closeContextMenu();
    _closeTopBarMenu();
    _navigationHold.stop();
    _autoPlay.pause();
    if (!mounted) return;
    setState(() {
      _showingRecentOpen = true;
      _recentOpenGeneration++;
    });
  }

  Future<void> _openFile() async {
    final selection = await FilePicker.pickFile(
      dialogTitle: _l10n.selectImageOrComic,
      windowsOptions: await _windowsPickerOptions(),
    );
    final path = selection?.path;
    if (path != null) await _openPath(path);
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    if (details.files.isEmpty) return;
    setState(() => _dropActive = false);
    await _openPath(details.files.first.path);
  }

  void _onControllerChanged() {
    if (_gridVisible) {
      final reading = _controller.currentEntry;
      final selected = _controller.entries
          .where((entry) => entry.id == _gridSelected?.id)
          .firstOrNull;
      if (_gridReadingId != reading?.id) {
        _gridSelected = reading;
        _gridMetadata = null;
      } else if (selected == null) {
        final previous =
            _plannedEntries?.indexWhere(
              (entry) => entry.id == _gridSelected?.id,
            ) ??
            0;
        _gridSelected = _controller.entries.isEmpty
            ? null
            : _controller.entries[previous.clamp(
                0,
                _controller.entries.length - 1,
              )];
        _gridMetadata = null;
      } else {
        _gridSelected = selected;
      }
      _gridReadingId = reading?.id;
      if (_infoVisible) _loadGridMetadata();
    }
    _syncReadingContext();
    final root = _controller.directoryRoot?.path;
    if (_directoryRootPath != root) {
      _directoryRootPath = root;
      _directoryExpandedPaths.clear();
    }
    _configureImagePrefetch(_session.settings);
    _resources.setThumbnailCollection((
      _controller.folderPath,
      _controller.archiveContext?.session?.identity,
    ), _controller.entries);
    if (!identical(_plannedEntries, _controller.entries)) {
      _pairingAnchorId = null;
      _plannedEntries = _controller.entries;
      _visibleComicPages = {};
      _admittedComicPages = {};
      _comicGeometry = null;
      _comicViewportStart = null;
      _comicViewportEnd = null;
      _landscapeIds.retainAll(_controller.entries.map((entry) => entry.id));
    }
    if (_lastReadingIndex >= 0 &&
        _lastReadingIndex != _controller.currentIndex) {
      _readingDirection = _controller.currentIndex > _lastReadingIndex
          ? prefetch.ReadingDirection.forward
          : prefetch.ReadingDirection.backward;
    }
    _lastReadingIndex = _controller.currentIndex;
    final entry = _controller.currentEntry;
    final version = entry == null ? null : _resources.version(entry);
    if (version != _metadataVersion) {
      if (_colorPicker.active) _colorPicker.resetImage();
      _metadataVersion = version;
      _displayedEntries.remove(entry?.id);
      _autoPlayAnimations.remove(entry?.id);
      _animationSelectedId = entry?.id;
      _animationPlayback.value = null;
      _frameInfo.value = (0, 1);
      if (entry == null) {
        _metadataFuture = null;
      } else {
        _metadataFuture = _resources.metadata(
          entry,
          priority: DecodePriority.foreground,
        );
        // Repeated input can replace this future before the next build attaches
        // FutureBuilder. Its snapshot still receives errors when it is shown.
        _metadataFuture!.ignore();
      }
    }
    if (!_controller.isIndexing) {
      _resources.retainPaths(
        _controller.entries.map((entry) => entry.id).toSet(),
      );
    }
    if (mounted) setState(() {});
    _scheduleNeighborPrecache();
  }

  Future<Size?> _loadImageSize(String path) async {
    final entry = _controller.entries
        .where((entry) => entry.id == path)
        .firstOrNull;
    if (entry == null) return null;
    final visible =
        _session.mode != ViewerMode.comic ||
        _visibleComicPages.contains(_controller.entries.indexOf(entry)) ||
        entry.id == _controller.currentEntry?.id;
    final metadata = await _resources.metadata(
      entry,
      priority: visible ? DecodePriority.foreground : DecodePriority.metadata,
    );
    if (metadata.width <= 0 || metadata.height <= 0) return null;
    return Size(metadata.width.toDouble(), metadata.height.toDouble());
  }

  void _scheduleNeighborPrecache() {
    if (!mounted ||
        _gridVisible ||
        !_pageActive ||
        _disposing ||
        _controller.isOpeningArchive ||
        _selectionRequest != null ||
        _controller.currentEntry == null) {
      _neighborPrecacheTimer?.cancel();
      _neighborPrecacheTimer = null;
      return;
    }
    if (_neighborPrecacheTimer?.isActive ?? false) return;
    _neighborPrecacheTimer = Timer(const Duration(milliseconds: 80), () {
      _neighborPrecacheTimer = null;
      _precacheNeighbors();
    });
  }

  void _precacheNeighbors() {
    if (!mounted ||
        _gridVisible ||
        !_pageActive ||
        _disposing ||
        _controller.isOpeningArchive ||
        _selectionRequest != null) {
      return;
    }
    final entries = _controller.entries;
    if (entries.isEmpty) return;
    final comic = _session.mode == ViewerMode.comic;
    final visible = <int>{
      _controller.currentIndex,
      if (comic) ..._visibleComicPages,
      if (_session.mode == ViewerMode.doublePage &&
          _doublePagePeerIndex() != null)
        _doublePagePeerIndex()!,
    };
    final cached = _resources.cachedIds;
    final width = _imageCacheWidth() ?? 2048;
    final estimated = <int, int>{};
    for (var index = 0; index < entries.length; index++) {
      final metadata = _resources.cachedMetadata(entries[index]);
      final w = metadata?.width ?? entries[index].width;
      final h = metadata?.height ?? entries[index].height;
      final scale = w != null && h != null && w > 0 && h > 0
          ? math.min(1.0, width / math.max(w, h))
          : 1.0;
      estimated[index] = w != null && h != null && w > 0 && h > 0
          ? math.max(1, (w * h * scale * scale * 4).round())
          : width * width * 4;
    }
    final plan = _prefetchPlanner.plan(
      totalPages: entries.length,
      visiblePages: visible,
      pageGroups: _session.mode == ViewerMode.doublePage
          ? _doublePageGroups()
          : null,
      direction: _readingDirection,
      level: _resources.policy.level,
      geometry: comic ? _comicGeometry : null,
      viewportStart: comic ? _comicViewportStart : null,
      viewportEnd: comic ? _comicViewportEnd : null,
      cachedPages: {
        for (var i = 0; i < entries.length; i++)
          if (cached.contains(entries[i].id)) i,
      },
      estimatedBytes: estimated,
      estimatedPageBytes: width * width * 4,
      budgetBytes:
          math.min(
            _resources.memoryBudgetBytes,
            _archiveMemoryBudgetBytes ?? _resources.memoryBudgetBytes,
          ) ~/
          2,
    );
    String id(int index) => entries[index].id;
    _resources.applyWorkingSet(
      protectedIds: plan.protectedPages.map(id).toSet(),
      retainedIds: plan.retainedPages.map(id).toSet(),
      tasks: {for (final task in plan.tasks) id(task.index): task},
      memoryBudgetBytes: _archiveMemoryBudgetBytes,
    );
    final admitted = {
      ...plan.protectedPages.map(id),
      for (final page in plan.nearPages)
        if (cached.contains(id(page))) id(page),
    };
    if (comic && !setEquals(admitted, _admittedComicPages)) {
      setState(() => _admittedComicPages = admitted);
    }
    for (final task in plan.tasks) {
      if (plan.protectedPages.contains(task.index)) continue;
      final entry = entries[task.index];
      if (!_resources.canPrefetch(entry)) continue;
      unawaited(
        _resources
            .prefetch(
              entry,
              targetWidth: width,
              targetHeight: width,
              priority: task.priority,
              distance: task.distance,
            )
            .then((_) {
              if (mounted &&
                  !cached.contains(entry.id) &&
                  _resources.cachedIds.contains(entry.id)) {
                _scheduleNeighborPrecache();
              }
            })
            .catchError((_) {}),
      );
    }
  }

  int? _imageCacheWidth() {
    if (!_session.fitMode) return null;
    // Async preparation and prefetch may finish while the element is inactive.
    // Read inherited metrics only in didChangeDependencies, where it is safe.
    return math.max(256, (_physicalViewportExtent * 1.25).round());
  }

  Future<void> _openFolder() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: _l10n.selectImageFolder,
      windowsOptions: await _windowsPickerOptions(),
    );
    if (path == null) return;
    await _openFolderPath(path, establishRoot: true);
  }

  Future<WindowsOptions> _windowsPickerOptions() async {
    if (!Platform.isWindows) return const WindowsOptions();
    try {
      final windowHandle = await windowManager.getId();
      return FilePickerWindowsOptions(
        parentWindowHandle: windowHandle,
        lockParentWindow: true,
      );
    } catch (_) {
      // The foreground-window fallback keeps file_picker usable on older
      // window_manager implementations or during early startup.
      return const WindowsOptions(lockParentWindow: true);
    }
  }

  Future<void> _openFolderPath(
    String path, {
    bool establishRoot = false,
  }) async {
    _cancelSelection();
    if (establishRoot) {
      await _controller.openFolder(path);
    } else {
      await _controller.navigateToFolder(path);
    }
    if (!mounted) return;
    setState(() => _showingRecentOpen = false);
    _resetView();
  }

  Future<void> _openChapterPath(String path) async {
    _cancelSelection();
    try {
      final archive = _controller.navigationContainers
          .where((entry) => entry.id == path)
          .firstOrNull;
      if (archive != null) {
        await _openArchiveEntry(archive);
      } else {
        await _controller.openChapter(path);
      }
      if (mounted) _resetView();
    } on DecodeCancelled {
      return;
    } catch (_) {
      if (mounted) _showErrorNotification(_l10n.directoryReadFailed);
    }
  }

  void _setDirectoryVisible(bool visible) {
    setState(() {
      _directoryVisible = visible;
      _directoryDismissed = !visible;
    });
    if (_isBorderless) return;
    final settings = _session.settings.copyWith(showDirectoryPanel: visible);
    _session.applySettings(settings);
    unawaited(_persistSettings(settings));
  }

  void _closeDirectory() {
    _setDirectoryVisible(false);
    _focusNode.requestFocus();
  }

  Future<void> _toggleDirectoryPinned() async {
    if (_isBorderless) {
      setState(() {
        _panelLayout.directoryPinned = !(_panelLayout.directoryPinned ?? false);
        _directoryDismissed = false;
        _directoryVisible = true;
      });
      return;
    }
    final settings = _session.settings.copyWith(
      showDirectoryPanel: true,
      pinDirectoryPanel: !_session.settings.pinDirectoryPanel,
    );
    // Unpinning keeps the tree open as an overlay, including in narrow windows.
    setState(() {
      _directoryDismissed = false;
      _directoryVisible = true;
    });
    _session.applySettings(settings);
    await _persistSettings(settings);
  }

  Future<void> _saveDirectoryPanelWidth(double width) async {
    if (_isBorderless) {
      setState(
        () => _panelLayout.directoryWidth =
            ViewerSettings.normalizeDirectoryPanelWidth(width),
      );
      return;
    }
    final settings = _session.settings.copyWith(
      directoryPanelWidth: ViewerSettings.normalizeDirectoryPanelWidth(width),
    );
    if (settings == _session.settings) return;
    _session.applySettings(settings);
    await _persistSettings(settings);
  }

  bool get _directoryPinnedOpen =>
      _directoryVisible &&
      (_panelLayout.directoryPinned ?? _session.settings.pinDirectoryPanel) &&
      !_directoryDismissed;

  bool get _directoryIsDocked => _directoryPinnedOpen;

  bool get _directoryIsShown => _directoryVisible || _directoryPinnedOpen;

  Widget _buildDirectoryRegion(Widget child) => LayoutBuilder(
    builder: (context, constraints) {
      final docked = _directoryIsDocked;
      final visible = _directoryIsShown;
      Widget treeForLayout(_ViewerPanelLayout layout) => ChapterDirectoryTree(
        key: ValueKey((
          _controller.directoryRoot?.path,
          identical(layout, _ordinaryLayout),
        )),
        controller: _controller,
        searchFocusNode: identical(layout, _ordinaryLayout)
            ? _directorySearchFocus
            : _borderlessDirectorySearchFocus,
        expandedPaths: layout.expandedPaths,
        pinned: layout.directoryPinned ?? _session.settings.pinDirectoryPanel,
        onTogglePinned: () => unawaited(_toggleDirectoryPinned()),
        onClose: _closeDirectory,
        onChooseFolder: () => unawaited(_openFolder()),
        onOpenFolder: (path) async {
          await _openChapterPath(path);
          if (mounted && !docked) _closeDirectory();
        },
        onOpenParent: (path) async {
          await _openFolderPath(path);
          if (mounted && !docked) _closeDirectory();
        },
        onOpenArchive: (entry) async {
          final previous = _controller.archiveContext;
          await _openArchiveEntry(entry);
          if (mounted &&
              !docked &&
              !identical(previous, _controller.archiveContext)) {
            _closeDirectory();
          }
        },
      );
      return DirectoryPanelRegion(
        availableWidth: constraints.maxWidth,
        minimumContentWidth: 200,
        preferredWidth:
            _panelLayout.directoryWidth ??
            _session.settings.directoryPanelWidth,
        docked: docked,
        visible: visible,
        maintainState: true,
        overlayTopInset: _floatingToolbar ? _topBarHeight : 0,
        panel: Padding(
          // Floating commands may cover the image, but never directory tools.
          padding: EdgeInsets.only(
            top: _floatingToolbar && docked ? _topBarHeight : 0,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: _isBorderless,
                child: treeForLayout(_ordinaryLayout),
              ),
              if (_isBorderless && visible) treeForLayout(_panelLayout),
            ],
          ),
        ),
        onClose: _closeDirectory,
        onWidthChanged: (width) => unawaited(_saveDirectoryPanelWidth(width)),
        child: child,
      );
    },
  );

  Future<void> _select(int index) async {
    if (!_autoPlayAdvancing && _autoPlay.scrolling) {
      _autoPlay.pause();
    }
    if (!_autoPlayAdvancing && _session.mode != ViewerMode.comic) {
      _autoPlay.resetInterval();
    }
    if (index < 0 || index >= _controller.entries.length) return;
    if (index != _controller.currentIndex) {
      _transitionDirection = (index - _controller.currentIndex).sign;
    }
    if (index >= 0 &&
        index < _controller.entries.length &&
        _controller.entries[index].format == ImageFormat.archive) {
      await _openArchiveEntry(_controller.entries[index]);
      return;
    }
    // Repeated clicks must not reset the displayed image or restart extraction
    // of the same pending archive page. Clicking the visible page can still
    // cancel navigation to a different page that has not finished preparing.
    if (index == _pendingSelectionIndex) return;
    if (index == _controller.currentIndex) {
      if (_pendingSelectionIndex != null) {
        _cancelSelection();
        _scheduleNeighborPrecache();
      }
      return;
    }

    if (_session.mode == ViewerMode.comic) {
      _session.moveComicSelection();
      _controller.select(index);
      return;
    }
    if (_controller.isArchiveView) {
      _selectionRequest?.cancel();
      _neighborPrecacheTimer?.cancel();
      _pendingSelectionIndex = index;
      final generation = ++_selectionGeneration;
      final request = _selectionRequest = DecodeRequest();
      final targets = _session.mode == ViewerMode.doublePage
          ? _doublePageGroups().firstWhere((group) => group.contains(index))
          : [index];
      AppNotificationHandle? preparingNotice;
      final notice = Timer(const Duration(milliseconds: 120), () {
        if (mounted && identical(request, _selectionRequest)) {
          preparingNotice = _notifications.show(_l10n.archivePreparingPage);
        }
      });
      try {
        await Future.wait<void>([
          for (final target in targets)
            () async {
              try {
                await _prepareArchiveEntry(
                  _controller.entries[target],
                  request,
                );
              } on DecodeCancelled {
                rethrow;
              } catch (_) {
                // A broken page gets its own tile; its partner remains usable.
              }
            }(),
        ]);
        request.throwIfCancelled();
        if (!mounted || generation != _selectionGeneration) return;
        _resetView();
        _controller.select(index);
      } on DecodeCancelled {
        // Keep the previous page while a newer navigation request is prepared.
      } finally {
        notice.cancel();
        preparingNotice?.close();
        if (identical(request, _selectionRequest)) {
          _selectionRequest = null;
          _pendingSelectionIndex = null;
          _scheduleNeighborPrecache();
        }
      }
      return;
    }
    _resetView();
    _controller.select(index);
  }

  Future<void> _openArchive(File file) async {
    await _openArchiveWithPassword(file);
  }

  Future<void> _openArchiveEntry(ImageEntry entry) =>
      _openArchiveWithPassword(null, entry: entry);

  Future<void> _openArchiveWithPassword(File? file, {ImageEntry? entry}) async {
    _cancelSelection();
    String? password;
    ArchiveOpenOutcome outcome;
    while (true) {
      outcome = entry == null
          ? await _controller.openArchive(file!, password: password)
          : await _controller.openArchiveEntry(entry, password: password);
      if (!mounted) return;
      final kind = _controller.lastArchiveFailure;
      if (outcome != ArchiveOpenOutcome.failed ||
          (kind != ArchiveFailureKind.encrypted &&
              kind != ArchiveFailureKind.wrongPassword &&
              kind != ArchiveFailureKind.passwordUnverifiable)) {
        break;
      }
      password = await showArchivePasswordDialog(
        context,
        archiveName: entry?.name ?? file!.uri.pathSegments.last,
        error: kind == ArchiveFailureKind.wrongPassword
            ? ArchivePasswordError.wrongPassword
            : kind == ArchiveFailureKind.passwordUnverifiable
            ? ArchivePasswordError.cannotVerify
            : null,
      );
      if (password == null || !mounted) return;
    }
    password = null;
    if (!mounted) return;
    switch (outcome) {
      case ArchiveOpenOutcome.opened:
        setState(() => _showingRecentOpen = false);
        _resetView();
        break;
      case ArchiveOpenOutcome.empty:
        final archiveFile =
            file ??
            (entry?.isMaterialized == true
                ? entry!.file
                : _controller.archiveContext?.archiveFile);
        _showErrorNotification(
          _l10n.archiveEmpty,
          actionLabel: archiveFile == null ? null : _l10n.showInExplorer,
          onAction: archiveFile == null
              ? null
              : () => unawaited(_revealArchive(archiveFile)),
        );
        break;
      case ArchiveOpenOutcome.failed:
        final kind =
            _controller.lastArchiveFailure ?? ArchiveFailureKind.corrupt;
        final message = localizedArchiveFailure(_l10n, kind);
        _showErrorNotification(
          message,
          actionLabel: _l10n.archiveRetry,
          onAction: () =>
              unawaited(_openArchiveWithPassword(file, entry: entry)),
        );
        break;
      case ArchiveOpenOutcome.cancelled:
        break;
    }
  }

  final _notifications = AppNotificationController();

  void _showErrorNotification(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    _notifications.show(
      message,
      type: AppNotificationType.error,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  Future<void> _revealArchive(File file) async {
    try {
      await _fileOperations.reveal(file);
    } catch (error) {
      if (!mounted) return;
      _showErrorNotification(localizedErrorMessage(_l10n, error));
    }
  }

  Future<void> _reloadCurrentImage() async {
    final entry = _controller.currentEntry;
    final folder = _controller.folderPath;
    if (folder == null) return;
    final path = entry?.id;
    if (path != null) _resources.invalidate(path);
    _metadataVersion = null;
    await _controller.openFolder(
      folder,
      preferredFilePath: path,
      keepArchiveContext: _controller.isArchiveView,
      persistRecent: false,
      establishRoot: false,
    );
    if (!mounted) return;
    _session.markReloaded();
    _resetView();
  }

  void _move(int offset, {bool singleImage = false}) {
    if (_autoPlay.scrolling) _autoPlay.pause();
    _autoPlay.resetInterval();
    if (_controller.entries.isEmpty) return;
    final step = _session.mode == ViewerMode.doublePage && !singleImage
        ? _doublePageStep(offset)
        : offset;
    final currentIndex = _pendingSelectionIndex ?? _controller.currentIndex;
    final nextIndex = currentIndex + step;
    if (_session.settings.archiveAutoAdvance &&
        _controller.isArchiveView &&
        (nextIndex < 0 || nextIndex >= _controller.entries.length)) {
      if (_controller.isOpeningArchive) return;
      final next = _controller.adjacentArchive(offset.sign);
      if (next != null) {
        _stopVerticalScroll();
        unawaited(_openArchiveEntry(next));
      }
      return;
    }
    // A boundary press must not reset the current transform or restart an
    // archive selection that is still being prepared.
    if (nextIndex < 0 ||
        nextIndex >= _controller.entries.length ||
        nextIndex == currentIndex) {
      _navigationHold.stop();
      return;
    }
    _transitionDirection = offset.sign;
    if (_session.mode == ViewerMode.doublePage && singleImage) {
      _pairingAnchorId = _controller.entries[nextIndex].id;
    }
    _stopVerticalScroll();
    if (_session.mode == ViewerMode.comic) {
      _session.moveComicSelection();
      _controller.move(step);
      return;
    }
    if (_controller.isArchiveView) {
      unawaited(_select(nextIndex));
      return;
    }
    _resetView();
    _controller.move(step);
  }

  void _cancelSelection() {
    _selectionRequest?.cancel();
    _selectionRequest = null;
    _pendingSelectionIndex = null;
    ++_selectionGeneration;
  }

  int _doublePageStep(int direction) {
    final groups = _doublePageGroups();
    final anchor = _pendingSelectionIndex ?? _controller.currentIndex;
    final group = groups.indexWhere((pages) => pages.contains(anchor));
    final next = group + direction.sign;
    if (group < 0 || next < 0 || next >= groups.length) {
      return direction > 0 ? _controller.entries.length - anchor : -anchor - 1;
    }
    return groups[next].first - anchor;
  }

  void _resetView() {
    if (_restoringReading) return;
    _readingRestoreAnchor = null;
    _modeRestoreTransform = null;
    _comicRestorePosition = null;
    _stopVerticalScroll();
    _pendingZoomReferenceActualScale = null;
    if (_session.mode != ViewerMode.comic &&
        _session.settings.interaction.keepZoom &&
        _lastContentSize != null &&
        _lastViewportSize != null) {
      final matrix = _transformController.value;
      final content = _lastContentSize;
      final viewport = _lastViewportSize;
      final scale = matrix.getMaxScaleOnAxis();
      final translation = matrix.getTranslation();
      _pendingEntryView = (
        scale: scale * _zoomReferenceScale,
        anchor:
            _session.settings.interaction.keepZoomPosition &&
                content != null &&
                viewport != null &&
                !content.isEmpty
            ? Offset(
                (viewport.width / 2 - translation.x) / scale / content.width,
                (viewport.height / 2 - translation.y) / scale / content.height,
              )
            : null,
      );
      _viewResetRequest++;
    } else {
      _pendingEntryView = null;
      _resettingScale = true;
      _transformController.value = Matrix4.identity();
      _viewResetRequest++;
    }
    _session.resetForEntry();
  }

  void _rotateDisplay() {
    _pendingEntryView = null;
    _resettingScale = true;
    _pendingZoomReferenceActualScale = null;
    _transformController.value = Matrix4.identity();
    _viewResetRequest++;
    _session.rotateDisplay();
  }

  void _toggleHorizontalFlip() {
    _pendingZoomReferenceActualScale = null;
    _viewportCommands.resetView();
    _session.toggleHorizontalFlip();
  }

  void _setScaleMode(ViewScaleMode mode) {
    _autoPlay.pause();
    _resettingScale = true;
    _pendingEntryView = null;
    _modeRestoreTransform = null;
    _comicRestorePosition = null;
    if (_session.mode == ViewerMode.comic) {
      _pendingZoomReferenceActualScale = null;
      setState(() {
        _viewResetRequest++;
        _session.setScaleMode(mode);
      });
      return;
    }
    final modeChanged = _session.scaleMode != mode;
    _pendingZoomReferenceActualScale = null;
    if (modeChanged) {
      _transformController.value = Matrix4.identity();
      _viewResetRequest++;
      _session.setScaleMode(mode);
    } else {
      _viewportCommands.resetView();
      _session.setZoomed(false);
    }
  }

  Widget _buildDisplayTransform(Widget child) {
    return RotatedBox(
      quarterTurns: _session.rotationQuarterTurns,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..scaleByDouble(_session.flipHorizontal ? -1.0 : 1.0, 1.0, 1.0, 1.0),
        child: child,
      ),
    );
  }

  Future<void> _toggleFullscreen() async {
    _closeStatusZoomPanel();
    final fullscreen = await windowManager.isFullScreen();
    await windowManager.setFullScreen(!fullscreen);
    await _syncFullscreenState();
  }

  Future<void> _showContextMenu(Offset position) async {
    _navigationHold.stop();
    _closeTopBarMenu();
    _closeStatusZoomPanel();
    final previous = _contextMenuPosition;
    if (_contextMenuOpen &&
        previous != null &&
        (previous - position).distance < 2) {
      _closeContextMenu();
      return;
    }
    _contextMenuDismissTimer?.cancel();
    _closeContextMenu();
    final token = Object();
    _contextMenuToken = token;
    // MenuAnchor hides its overlay asynchronously, even without animations.
    // Let that close finish before reusing the anchor for a new menu.
    if (_contextMenuController.isOpen) {
      await Future<void>.delayed(Duration.zero);
      if (!identical(_contextMenuToken, token)) return;
    }
    if (!mounted) return;
    final anchor = _contextMenuCoordinateKey.currentContext?.findRenderObject();
    if (anchor is! RenderBox || !anchor.hasSize) return;
    _recentMenuLoading = _session.settings.recentOpenEnabled;
    _externalMenuEntry = _actionEntry;
    _externalApplications = const [];
    _externalApplicationsLoading = _externalMenuEntry != null;
    _externalApplicationsFailed = false;
    final viewport = MediaQuery.sizeOf(context);
    final left = position.dx
        .clamp(8.0, math.max(8.0, viewport.width - _contextMenuWidth))
        .toDouble();
    final top = position.dy
        .clamp(8.0, math.max(8.0, viewport.height - 520))
        .toDouble();
    _contextMenuPosition = position;
    _contextMenuAnchorPosition = anchor.globalToLocal(Offset(left, top));
    _contextMenuVisible.value = true;
    _contextMenuRevision.value++;
    _contextMenuController.open();
    unawaited(_loadRecentMenu(token));
    unawaited(_loadExternalApplications(token, _externalMenuEntry));
  }

  Future<void> _loadExternalApplications(
    Object token,
    ImageEntry? entry,
  ) async {
    if (entry == null) return;
    List<ExternalApplication> applications = const [];
    var failed = false;
    try {
      applications = await _externalOpen.applications(entry);
    } catch (_) {
      failed = true;
    }
    if (!mounted || !identical(_contextMenuToken, token)) return;
    _externalApplications = applications;
    _externalApplicationsLoading = false;
    _externalApplicationsFailed = failed;
    _contextMenuRevision.value++;
  }

  Widget _externalOpenMenu() {
    final entry = _externalMenuEntry;
    return _SafeSubmenuButton(
      enabled: entry != null && !_externalOpenBusy,
      crossAxisUnconstrained: false,
      menuStyle: _submenuMenuStyle().copyWith(
        maximumSize: const WidgetStatePropertyAll(Size(280, double.infinity)),
      ),
      alignmentOffset: const Offset(-4, -4),
      submenuIcon: const WidgetStatePropertyAll(
        Icon(FluentIcons.chevron_right_16_regular, size: 16),
      ),
      style: _submenuButtonStyle(),
      leadingIcon: const Icon(
        FluentIcons.open_20_regular,
        size: AppTokens.menuIconSize,
      ),
      menuChildren: [
        if (_externalApplicationsLoading)
          _menuItem(_l10n.externalOpenLoading, () {}, enabled: false)
        else if (_externalApplicationsFailed)
          _menuItem(_l10n.externalOpenListFailed, () {}, enabled: false)
        else if (_externalApplications.isEmpty)
          _menuItem(_l10n.externalOpenNoApplications, () {}, enabled: false),
        for (final application in _externalApplications)
          Tooltip(
            message: application.name,
            child: _menuItem(
              application.name,
              () => unawaited(_openInExternalApplication(entry!, application)),
              leading: application.icon == null
                  ? const Icon(FluentIcons.app_generic_20_regular)
                  : Image.memory(
                      application.icon!,
                      width: AppTokens.menuIconSize,
                      height: AppTokens.menuIconSize,
                      errorBuilder: (context, error, stack) =>
                          const Icon(FluentIcons.app_generic_20_regular),
                    ),
            ),
          ),
        _menuDivider(),
        _menuItem(
          _l10n.externalOpenChoose,
          () => unawaited(_openInExternalApplication(entry!, null)),
          enabled: entry != null,
          leading: const Icon(FluentIcons.folder_open_20_regular),
        ),
      ],
      child: Text(_l10n.externalOpen),
    );
  }

  Future<void> _openInExternalApplication(
    ImageEntry entry,
    ExternalApplication? application,
  ) async {
    if (_externalOpenBusy) return;
    _externalOpenBusy = true;
    _closeContextMenu();
    _closeTopBarMenu();
    try {
      await _externalOpen.open(
        entry,
        application: application,
        saveCopy: (source) async {
          if (!mounted) return null;
          if (await source.length() > _resources.memoryBudgetBytes ~/ 2) {
            throw StateError(_l10n.archiveResourceInsufficient);
          }
          final bytes = await source.readAsBytes();
          if (!mounted) return null;
          final uri = await FilePicker.saveFile(
            dialogTitle: _l10n.externalOpenSaveCopy,
            fileName: entry.name,
            bytes: bytes,
            windowsOptions: await _windowsPickerOptions(),
          );
          return uri == null ? null : File.fromUri(uri);
        },
      );
    } catch (error) {
      if (mounted) {
        _showErrorNotification(
          _l10n.externalOpenFailed(localizedErrorMessage(_l10n, error)),
        );
      }
    } finally {
      _externalOpenBusy = false;
      if (mounted && _contextMenuOpen) _contextMenuRevision.value++;
    }
  }

  Widget _buildContextMenuAnchor() => ValueListenableBuilder(
    valueListenable: _contextMenuRevision,
    builder: (context, revision, child) => Positioned(
      left: _contextMenuAnchorPosition.dx,
      top: _contextMenuAnchorPosition.dy,
      child: ExcludeSemantics(
        child: MenuAnchor(
          controller: _contextMenuController,
          onClose: _closeContextMenu,
          useRootOverlay: true,
          animated: false,
          style: AppControlStyles.menu(ViewerThemeTokens.of(context)).copyWith(
            minimumSize: const WidgetStatePropertyAll(
              Size(_contextMenuWidth, 0),
            ),
          ),
          menuChildren: _contextMenuOpen ? _contextMenuChildren() : const [],
          builder: (context, controller, child) =>
              const SizedBox(width: 1, height: 1),
        ),
      ),
    ),
  );

  Future<void> _loadRecentMenu(Object token) async {
    List<RecentOpenEntry> entries;
    try {
      entries = _session.settings.recentOpenEnabled
          ? await _controller.loadRecentOpen()
          : const [];
    } catch (_) {
      entries = const [];
    }
    if (!mounted || !identical(_contextMenuToken, token)) return;
    _recentMenuEntries = entries;
    _recentMenuLoading = false;
    _contextMenuRevision.value++;
  }

  void _closeContextMenu() {
    if (_disposing) return;
    _contextMenuDismissTimer?.cancel();
    if (!_contextMenuOpen) return;
    _contextMenuToken = null;
    _contextMenuPosition = null;
    _contextMenuVisible.value = false;
    _contextMenuController.close();
  }

  void _scheduleContextMenuClose() {
    _contextMenuDismissTimer?.cancel();
    _contextMenuDismissTimer = Timer(
      const Duration(milliseconds: 180),
      _closeContextMenu,
    );
  }

  Widget _menuItem(
    String label,
    VoidCallback action, {
    Widget? leading,
    String? shortcut,
    Widget? trailing,
    bool selected = false,
    bool showSelectionIndicator = false,
    bool enabled = true,
  }) {
    final tokens = ViewerThemeTokens.of(context);
    final trailingWidget =
        trailing ??
        (shortcut != null || showSelectionIndicator
            ? SizedBox(
                width: shortcut != null
                    ? math.max(
                        58,
                        measureBarLabelWidth(
                              context,
                              shortcut,
                              AppTextStyles.label,
                            ) +
                            (showSelectionIndicator
                                ? AppTokens.menuIconSize + AppTokens.space2
                                : 0),
                      )
                    : AppTokens.menuIconSize,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (shortcut != null)
                      Flexible(
                        child: Text(
                          shortcut,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: AppTextStyles.label.copyWith(
                            color: enabled
                                ? tokens.textTertiary
                                : tokens.textDisabled,
                          ),
                        ),
                      ),
                    if (shortcut != null && selected && showSelectionIndicator)
                      const SizedBox(width: AppTokens.space2),
                    if (selected && showSelectionIndicator)
                      Icon(
                        FluentIcons.checkmark_16_regular,
                        size: AppTokens.menuIconSize,
                        color: enabled
                            ? tokens.accentStrong
                            : tokens.textDisabled,
                      ),
                  ],
                ),
              )
            : null);
    final leadingWidget = leading == null
        ? (showSelectionIndicator && !selected
              ? const SizedBox(width: AppTokens.menuIconSize)
              : null)
        : IconTheme.merge(
            data: IconThemeData(
              color: !enabled
                  ? tokens.textDisabled
                  : selected
                  ? tokens.accentStrong
                  : tokens.textSecondary,
              size: AppTokens.menuIconSize,
            ),
            child: leading,
          );
    return MenuItemButton(
      overflowAxis: Axis.vertical,
      leadingIcon: leadingWidget,
      onPressed: enabled ? action : null,
      trailingIcon: trailingWidget,
      style: AppControlStyles.menuItem(context, selected: selected),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _menuDivider() => SizedBox(
    height: AppTokens.space2,
    child: Center(
      child: SizedBox(
        width: double.infinity,
        height: 1,
        child: ColoredBox(color: ViewerThemeTokens.of(context).border),
      ),
    ),
  );

  ButtonStyle _submenuButtonStyle() {
    return AppControlStyles.submenu(context);
  }

  MenuStyle _submenuMenuStyle() {
    final tokens = ViewerThemeTokens.of(context);
    return AppControlStyles.menu(tokens);
  }

  Widget _menuActionBar(
    List<(String, IconData, VoidCallback?, String?, bool)> actions,
  ) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppTokens.space2,
      vertical: 1,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (label, icon, action, shortcut, selected) in actions)
          SizedBox(
            width: _contextMenuActionWidth,
            child: MenuItemButton(
              onPressed: action,
              style: AppControlStyles.menuAction(
                ViewerThemeTokens.of(context),
                selected: selected,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: AppTokens.menuIconSize),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.finePrint,
                  ),
                  if (shortcut != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      shortcut,
                      style: AppTextStyles.shortcut.copyWith(
                        color: ViewerThemeTokens.of(context).textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    ),
  );

  List<Widget> _viewModeMenuChildren() => [
    _menuItem(
      _gridLabel,
      _toggleGrid,
      shortcut: _binding(ViewerCommand.toggleGrid)
          .displayLabel(platform: Theme.of(context).platform),
      leading: const Icon(FluentIcons.grid_20_regular),
      selected: _gridVisible,
      enabled: _gridVisible || _canEnterGrid,
      showSelectionIndicator: true,
    ),
    _menuItem(
      _l10n.singlePage,
      () => _setViewerMode(ViewerMode.single),
      shortcut: _keyLabel(ViewerCommand.singlePage),
      leading: const Icon(FluentIcons.document_one_page_20_regular),
      selected: !_gridVisible && _session.mode == ViewerMode.single,
      showSelectionIndicator: true,
    ),
    _menuItem(
      _l10n.doublePage,
      () => _setViewerMode(ViewerMode.doublePage),
      shortcut: _keyLabel(ViewerCommand.doublePage),
      leading: const Icon(FluentIcons.copy_20_regular),
      selected: !_gridVisible && _session.mode == ViewerMode.doublePage,
      showSelectionIndicator: true,
    ),
    _menuItem(
      _l10n.longImage,
      () => _setViewerMode(ViewerMode.longImage),
      shortcut: _keyLabel(ViewerCommand.longImage),
      leading: const Icon(FluentIcons.arrow_autofit_height_20_regular),
      selected: !_gridVisible && _session.mode == ViewerMode.longImage,
      showSelectionIndicator: true,
    ),
    _menuItem(
      _l10n.comic,
      () => _setViewerMode(ViewerMode.comic),
      shortcut: _keyLabel(ViewerCommand.comic),
      leading: const Icon(FluentIcons.book_open_20_regular),
      selected: !_gridVisible && _session.mode == ViewerMode.comic,
      showSelectionIndicator: true,
    ),
    if (_session.mode == ViewerMode.doublePage) ...[
      _menuDivider(),
      for (final direction in ReadingDirection.values)
        _menuItem(
          direction == ReadingDirection.leftToRight
              ? _l10n.leftToRight
              : _l10n.rightToLeftManga,
          () {
            _closeTopBarMenu();
            _session.setReadingDirection(direction);
          },
          leading: Icon(
            direction == ReadingDirection.leftToRight
                ? FluentIcons.arrow_right_20_regular
                : FluentIcons.arrow_left_20_regular,
          ),
          selected: _session.readingDirection == direction,
          showSelectionIndicator: true,
        ),
    ],
    if (_session.mode == ViewerMode.comic) ...[
      _menuDivider(),
      for (final direction in ComicLayoutDirection.values)
        _menuItem(
          localizedComicLayoutLabel(_l10n, direction),
          () {
            _closeTopBarMenu();
            _session.setLayoutDirection(direction);
          },
          leading: Icon(switch (direction) {
            ComicLayoutDirection.vertical => FluentIcons.arrow_down_20_regular,
            ComicLayoutDirection.horizontalLeftToRight =>
              FluentIcons.arrow_right_20_regular,
            ComicLayoutDirection.horizontalRightToLeft =>
              FluentIcons.arrow_left_20_regular,
          }),
          selected: _session.layoutDirection == direction,
          showSelectionIndicator: true,
        ),
    ],
  ];

  String get _actualSizeLabel =>
      _session.mode == ViewerMode.comic && _session.settings.comicUniformSize
      ? _l10n.readingBaseSize
      : _l10n.actualSize;

  String get _viewModeLabel => _gridVisible
      ? _gridLabel
      : switch (_session.mode) {
          ViewerMode.single => _l10n.singlePage,
          ViewerMode.doublePage => _l10n.doublePage,
          ViewerMode.longImage => _l10n.longImage,
          ViewerMode.comic => _l10n.comic,
        };

  String get _viewModeTooltip => '${_l10n.viewMode} · $_viewModeLabel';

  IconData get _viewModeIcon => _gridVisible
      ? FluentIcons.grid_20_regular
      : switch (_session.mode) {
          ViewerMode.single => FluentIcons.document_one_page_20_regular,
          ViewerMode.doublePage => FluentIcons.copy_20_regular,
          ViewerMode.longImage => FluentIcons.arrow_autofit_height_20_regular,
          ViewerMode.comic => FluentIcons.book_open_20_regular,
        };

  List<Widget> _scaleModeMenuChildren() => [
    for (final mode in ViewScaleMode.values)
      _menuItem(
        mode == ViewScaleMode.originalSize
            ? _actualSizeLabel
            : localizedScaleModeLabel(_l10n, mode),
        () {
          _closeStatusZoomPanel();
          _setScaleMode(mode);
        },
        shortcut: _keyLabel(switch (mode) {
          ViewScaleMode.autoFit => ViewerCommand.autoFit,
          ViewScaleMode.fitWidth => ViewerCommand.fitWidth,
          ViewScaleMode.fitHeight => ViewerCommand.fitHeight,
          ViewScaleMode.originalSize => ViewerCommand.actualSize,
        }),
        leading: Icon(switch (mode) {
          ViewScaleMode.autoFit => FluentIcons.arrow_fit_20_regular,
          ViewScaleMode.fitWidth => FluentIcons.arrow_autofit_width_20_regular,
          ViewScaleMode.fitHeight =>
            FluentIcons.arrow_autofit_height_20_regular,
          ViewScaleMode.originalSize =>
            FluentIcons.full_screen_maximize_20_regular,
        }, size: AppTokens.menuIconSize),
        selected:
            mode == _session.scaleMode &&
            (_transformController.value.getMaxScaleOnAxis() - 1).abs() < 0.0001,
        showSelectionIndicator: true,
      ),
    _menuDivider(),
    _menuItem(
      _l10n.focusZoom,
      () {
        _closeStatusZoomPanel();
        unawaited(
          _applySettings(
            _session.settings.copyWith(
              interaction: _session.settings.interaction.copyWith(
                keepZoom: !_session.settings.interaction.keepZoom,
              ),
            ),
          ),
        );
      },
      leading: const Icon(FluentIcons.lock_closed_20_regular),
      shortcut: _keyLabel(ViewerCommand.lockZoom),
      selected: _session.settings.interaction.keepZoom,
      showSelectionIndicator: true,
    ),
  ];

  IconData _sortOrderIcon(SortOrder order) => switch (order) {
    SortOrder.fileSystem => FluentIcons.arrow_sort_20_regular,
    SortOrder.nameAscending => FluentIcons.text_sort_ascending_20_regular,
    SortOrder.nameDescending => FluentIcons.text_sort_descending_20_regular,
    SortOrder.sizeAscending => FluentIcons.arrow_sort_up_lines_20_regular,
    SortOrder.sizeDescending => FluentIcons.arrow_sort_down_lines_20_regular,
    SortOrder.modifiedNewest => FluentIcons.arrow_sort_down_20_regular,
    SortOrder.modifiedOldest => FluentIcons.arrow_sort_up_20_regular,
  };

  List<SortOrder> get _availableSortOrders =>
      _controller.isArchiveView ? archiveSortOrderOptions : sortOrderOptions;

  List<Widget> _sortMenuChildren() => [
    for (final order in _availableSortOrders)
      _menuItem(
        localizedSortOrderLabel(_l10n, order),
        () => _selectSortOrder(order),
        leading: Icon(_sortOrderIcon(order), size: AppTokens.menuIconSize),
        selected:
            order ==
            (_controller.isArchiveView
                ? _session.settings.archiveSortOrder
                : _session.settings.sortOrder),
        showSelectionIndicator: true,
      ),
  ];

  List<Widget> _recentOpenMenuChildren() {
    final tokens = ViewerThemeTokens.of(context);
    return [
      if (!_session.settings.recentOpenEnabled)
        _menuItem(
          recentCopy(context, '最近打开记录已关闭', 'Recording is off'),
          () {},
          enabled: false,
        )
      else if (_recentMenuLoading)
        _menuItem(
          recentCopy(context, '正在读取最近打开…', 'Loading recent items…'),
          () {},
          enabled: false,
        )
      else if (_recentMenuEntries.isEmpty)
        _menuItem(
          recentCopy(context, '还没有最近打开的项目', 'No recent items'),
          () {},
          enabled: false,
        )
      else
        for (final recent in _recentMenuEntries.take(10))
          Tooltip(
            message: recent.path,
            child: MenuItemButton(
              key: ValueKey(('recent.menu', recent.path)),
              style: AppControlStyles.menuItem(context),
              leadingIcon: Icon(
                switch (recent.kind) {
                  RecentOpenKind.image => FluentIcons.image_20_regular,
                  RecentOpenKind.folder => FluentIcons.folder_open_20_regular,
                  RecentOpenKind.archive => FluentIcons.archive_20_regular,
                },
                size: AppTokens.menuIconSize,
                color: tokens.textSecondary,
              ),
              onPressed: () => unawaited(_openRecentMenuEntry(recent)),
              child: SizedBox(
                width: 260,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recent.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall,
                    ),
                    Text(
                      paths.dirname(recent.path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.finePrint.copyWith(
                        color: tokens.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      _menuDivider(),
      _menuItem(
        recentCopy(context, '查看全部最近打开', 'View all recent items'),
        _showRecentOpen,
        leading: const Icon(FluentIcons.home_20_regular),
      ),
      _menuItem(
        recentCopy(context, '清空最近打开', 'Clear recent items'),
        () async {
          _closeContextMenu();
          if (!await confirmClearRecentOpen(context)) return;
          try {
            await _controller.clearRecentOpen();
            if (mounted) setState(() => _recentOpenGeneration++);
          } catch (_) {
            if (mounted) {
              _showErrorNotification(
                recentCopy(
                  context,
                  '清空失败，请重试。',
                  'Unable to clear items. Try again.',
                ),
              );
            }
          }
        },
        leading: const Icon(FluentIcons.delete_20_regular),
        enabled: _recentMenuEntries.isNotEmpty,
      ),
    ];
  }

  Future<void> _openRecentMenuEntry(RecentOpenEntry entry) async {
    _closeContextMenu();
    try {
      final type = await FileSystemEntity.type(entry.path);
      final exists = entry.kind == RecentOpenKind.folder
          ? type == FileSystemEntityType.directory
          : type == FileSystemEntityType.file;
      if (!mounted) return;
      if (!exists) {
        _showErrorNotification(
          recentCopy(
            context,
            '找不到此项目，请检查磁盘或网络连接，或从最近列表移除。',
            'Item not found. Check the drive or network connection, or remove it from recent items.',
          ),
        );
        return;
      }
      await _openPath(entry.path);
    } catch (_) {
      if (mounted) {
        _showErrorNotification(
          recentCopy(
            context,
            '无法打开此项目，请检查权限后重试。',
            'Unable to open this item. Check permissions and try again.',
          ),
        );
      }
    }
  }

  List<Widget> _contextMenuChildren() {
    final entry = _actionEntry;
    final readOnlyArchive = _controller.isReadOnlyArchive;
    return [
      _menuActionBar([
        (
          recentCopy(context, '复制文件', 'Copy file'),
          FluentIcons.copy_20_regular,
          entry == null
              ? null
              : () => _runFileOperation(
                  _fileOperations.copyFile,
                  retainForClipboard: true,
                ),
          _keyLabel(ViewerCommand.copyFile),
          false,
        ),
        (
          _l10n.delete,
          FluentIcons.delete_20_regular,
          entry == null || readOnlyArchive ? null : _deleteCurrent,
          _keyLabel(ViewerCommand.deleteFile),
          false,
        ),
        (
          _l10n.print,
          FluentIcons.print_20_regular,
          entry == null ? null : _printCurrent,
          _keyLabel(ViewerCommand.print),
          false,
        ),
        (
          _l10n.saveOriginalImage,
          FluentIcons.save_20_regular,
          entry == null ? null : _saveOriginalImage,
          _keyLabel(ViewerCommand.saveOriginal),
          false,
        ),
      ]),
      _menuDivider(),
      _menuItem(
        _l10n.openImage,
        _openFile,
        shortcut: _keyLabel(ViewerCommand.openFile),
        leading: const Icon(FluentIcons.image_20_regular),
      ),
      _menuItem(
        _l10n.openFolder,
        _openFolder,
        shortcut: _keyLabel(ViewerCommand.openFolder),
        leading: const Icon(FluentIcons.folder_open_20_regular),
      ),
      if (_session.settings.instanceMode == InstanceMode.multiProcess) ...[
        _menuItem(
          recentCopy(context, '新建窗口', 'New window'),
          () => unawaited(_newWindow()),
          leading: const Icon(FluentIcons.window_new_20_regular),
          shortcut: _binding(ViewerCommand.newWindow)
              .displayLabel(platform: Theme.of(context).platform),
        ),
        if (entry != null && !readOnlyArchive)
          _menuItem(
            recentCopy(context, '在新窗口打开', 'Open in new window'),
            () => unawaited(_newWindow(path: entry.file.path)),
            leading: const Icon(FluentIcons.open_20_regular),
          ),
      ],
      _SafeSubmenuButton(
        menuStyle: _submenuMenuStyle(),
        alignmentOffset: const Offset(-4, -4),
        submenuIcon: const WidgetStatePropertyAll(
          Icon(FluentIcons.chevron_right_16_regular, size: 16),
        ),
        style: _submenuButtonStyle(),
        menuChildren: _recentOpenMenuChildren(),
        leadingIcon: const Icon(
          FluentIcons.history_20_regular,
          size: AppTokens.menuIconSize,
        ),
        child: Text(recentCopy(context, '最近打开', 'Recent items')),
      ),
      if (entry != null) ...[
        if (!readOnlyArchive) ...[
          _menuItem(
            _l10n.copyImagePath,
            () => Clipboard.setData(ClipboardData(text: entry.id)),
            shortcut: _keyLabel(ViewerCommand.copyPath),
            leading: const Icon(FluentIcons.link_20_regular),
          ),
        ],
        _menuItem(
          _l10n.openImagePath,
          _revealCurrentFile,
          shortcut: _keyLabel(ViewerCommand.reveal),
          leading: const Icon(FluentIcons.folder_open_20_regular),
        ),
      ],
      _externalOpenMenu(),
      _menuDivider(),
      _SafeSubmenuButton(
        hoverOpenDelay: const Duration(milliseconds: 180),
        menuStyle: _submenuMenuStyle(),
        alignmentOffset: const Offset(-4, -4),
        submenuIcon: const WidgetStatePropertyAll(
          Icon(FluentIcons.chevron_right_16_regular, size: 16),
        ),
        style: _submenuButtonStyle(),
        menuChildren: _viewModeMenuChildren(),
        leadingIcon: const Icon(
          FluentIcons.grid_20_regular,
          size: AppTokens.menuIconSize,
        ),
        child: Text(_l10n.viewMode),
      ),
      _SafeSubmenuButton(
        hoverOpenDelay: const Duration(milliseconds: 180),
        menuStyle: _submenuMenuStyle(),
        alignmentOffset: const Offset(-4, -4),
        submenuIcon: const WidgetStatePropertyAll(
          Icon(FluentIcons.chevron_right_16_regular, size: 16),
        ),
        style: _submenuButtonStyle(),
        menuChildren: _sortMenuChildren(),
        leadingIcon: const Icon(
          FluentIcons.arrow_sort_down_lines_20_regular,
          size: AppTokens.menuIconSize,
        ),
        child: Text(_l10n.viewOrder),
      ),
      _SafeSubmenuButton(
        hoverOpenDelay: const Duration(milliseconds: 180),
        menuStyle: _submenuMenuStyle(),
        alignmentOffset: const Offset(-4, -4),
        submenuIcon: const WidgetStatePropertyAll(
          Icon(FluentIcons.chevron_right_16_regular, size: 16),
        ),
        style: _submenuButtonStyle(),
        menuChildren: _scaleModeMenuChildren(),
        leadingIcon: const Icon(
          FluentIcons.zoom_in_20_regular,
          size: AppTokens.menuIconSize,
        ),
        child: Text(_l10n.zoomMode),
      ),
      _menuDivider(),
      _menuItem(
        _isFullscreen ? _l10n.exitFullscreen : _l10n.fullscreen,
        () {
          _closeContextMenu();
          unawaited(_toggleFullscreen());
        },
        leading: const Icon(FluentIcons.full_screen_maximize_20_regular),
        shortcut: _keyLabel(ViewerCommand.fullscreen),
      ),
      if (_isBorderless) ...[
        _menuItem(
          _infoVisible ? _l10n.hideInfo : _l10n.showInfo,
          _toggleInfoPanel,
          shortcut: _keyLabel(ViewerCommand.toggleInfo),
          leading: const Icon(FluentIcons.info_20_regular),
        ),
      ],
      if (_isBorderless || !_session.settings.showBottomBar)
        _menuItem(
          _directoryIsShown
              ? _l10n.hideDirectoryPanel
              : _l10n.showDirectoryPanel,
          _toggleDirectoryPanel,
          shortcut: _keyLabel(ViewerCommand.toggleDirectory),
          leading: const Icon(FluentIcons.panel_left_20_regular),
        ),
      _menuItem(
        _l10n.settings,
        _showSettings,
        shortcut: _keyLabel(ViewerCommand.settings),
        leading: const Icon(FluentIcons.settings_20_regular),
      ),
    ];
  }

  Future<void> _printCurrent() async {
    final entry = _controller.currentEntry;
    if (entry == null) return;
    try {
      final bytes = await _resources.printBytes(entry);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            PrintPreviewDialog(entry: entry, imageBytes: bytes),
      );
    } catch (error) {
      if (!mounted) return;
      _showErrorNotification(
        _l10n.printPreviewFailed(localizedErrorMessage(_l10n, error)),
      );
    }
  }

  Future<void> _runFileOperation(
    Future<void> Function(File file) operation, {
    bool retainForClipboard = false,
  }) async {
    final entry = _actionEntry;
    if (entry == null) return;
    // Close auxiliary overlays before handing focus to an external shell
    // window.
    _closeContextMenu();
    _closeTopBarMenu();
    try {
      final lease = await entry.acquireFile();
      var retained = false;
      try {
        await operation(lease.file);
        if (retainForClipboard && !_disposing) {
          await _clipboardLease?.release();
          _clipboardLease = entry.source == null ? null : lease;
          retained = entry.source != null;
        }
      } finally {
        if (!retained) await lease.release();
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      _showErrorNotification(localizedErrorMessage(_l10n, error));
    }
  }

  Future<void> _saveOriginalImage() async {
    final entry = _actionEntry;
    if (entry == null) return;
    _closeContextMenu();
    _closeTopBarMenu();
    try {
      final lease = await entry.acquireFile();
      try {
        if (await lease.file.length() > _resources.memoryBudgetBytes ~/ 2) {
          throw StateError(_l10n.archiveResourceInsufficient);
        }
        final bytes = await lease.file.readAsBytes();
        if (!mounted) return;
        await FilePicker.saveFile(
          dialogTitle: _l10n.saveOriginalImage,
          fileName: entry.name,
          bytes: bytes,
          windowsOptions: await _windowsPickerOptions(),
        );
      } finally {
        await lease.release();
      }
    } catch (error) {
      if (mounted) _showErrorNotification(localizedErrorMessage(_l10n, error));
    }
  }

  Future<void> _revealCurrentFile() async {
    final context = _controller.archiveContext;
    if (context != null) {
      await _revealArchive(context.archiveFile);
      return;
    }
    await _runFileOperation(_fileOperations.reveal);
  }

  void _setViewerMode(ViewerMode mode) {
    _closeTopBarMenu();
    if (_gridVisible) _toggleGrid();
    if (_session.mode == mode) return;
    _resettingScale = true;
    _navigationHold.stop();
    _stopVerticalScroll();
    _toolbarTimer?.cancel();
    if (_session.mode == ViewerMode.comic) {
      _comicPositionController.flushCurrentPage();
    }
    _cancelSelection();
    final entryId = _controller.currentEntry?.id;
    if (entryId != null) {
      _modeProgress[_session.mode] = (
        entryId: entryId,
        scaleMode: _session.scaleMode,
        transform: Matrix4.copy(_transformController.value),
        referenceScale: _zoomReferenceScale,
        comicPosition: _session.mode == ViewerMode.comic
            ? _comicPositionController.capture()
            : null,
      );
    }
    final saved = _modeProgress[mode];
    final restore =
        saved != null &&
        saved.entryId == entryId &&
        saved.scaleMode == _session.scaleModeFor(mode);
    _modeRestoreTransform = restore ? Matrix4.copy(saved.transform) : null;
    _comicRestorePosition = restore ? saved.comicPosition : null;
    _zoomReferenceScale = restore ? saved.referenceScale : 1;
    _pendingZoomReferenceActualScale = null;
    _pendingEntryView = null;
    _comicReferenceResetRequest = -1;
    _transformController.value = _modeRestoreTransform ?? Matrix4.identity();
    _session.setMode(mode);
    _autoPlay.configure(_session.settings.autoPlay, mode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _deleteCurrent() async {
    if (_controller.isReadOnlyArchive) return;
    final entry = _actionEntry;
    final folder = _controller.folderPath;
    if (entry == null || folder == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      requestFocus: true,
      builder: (context) {
        final description = _l10n.deleteCurrentImageDescription(entry.name);
        final nameStart = description.indexOf(entry.name);
        return AppConfirmDialog(
          title: _l10n.deleteCurrentImageQuestion,
          content: nameStart < 0
              ? Text(description)
              : Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: description.substring(0, nameStart)),
                      TextSpan(
                        text: entry.name,
                        style: AppTextStyles.control.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: description.substring(
                          nameStart + entry.name.length,
                        ),
                      ),
                    ],
                  ),
                ),
          cancelLabel: _l10n.cancel,
          confirmLabel: _l10n.moveToRecycleBin,
          danger: true,
        );
      },
    );
    if (confirmed != true || !mounted) return;
    try {
      await _fileOperations.moveToTrash(entry.file);
      await _controller.openFolder(folder, establishRoot: false);
    } catch (error) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AppDialog(
          title: _l10n.deleteFailed,
          content: Text(localizedErrorMessage(_l10n, error)),
          actions: [
            AppButton(
              label: _l10n.acknowledge,
              variant: AppButtonVariant.neutral,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _handleEscape() async {
    if (_gridVisible && _topBarMenuEntry == null && _statusZoomEntry == null) {
      _toggleGrid();
      return;
    }
    if (_autoPlay.active &&
        _statusZoomEntry == null &&
        _topBarMenuEntry == null) {
      _autoPlay.stop();
      return;
    }
    if (_statusZoomEntry != null) {
      _closeStatusZoomPanel();
      return;
    }
    if (_topBarMenuEntry != null) {
      _closeTopBarMenu();
      return;
    }
    if (_infoVisible) {
      if (mounted) setState(() => _infoVisible = false);
      return;
    }
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
      await _syncFullscreenState();
      return;
    }
    if (_isBorderless) {
      await _toggleBorderless();
      return;
    }
    if (_floatingToolbar && mounted) {
      setState(() => _showToolbar = false);
    }
  }

  void _stopVerticalScroll() {
    _keyboardScroll.cancel();
  }

  void _startVerticalScroll(double direction) {
    _autoPlay.pause();
    final distance = _viewportCommands.remainingVerticalDistance(direction);
    if (distance == null) return;
    if (_session.mode == ViewerMode.longImage &&
        direction < 0 &&
        distance <= 0.01) {
      if (_controller.currentIndex + 1 < _controller.entries.length) {
        _move(1);
      }
      return;
    }
    _keyboardScroll.press(direction);
  }

  bool get _isHorizontalComic =>
      _session.mode == ViewerMode.comic &&
      _session.layoutDirection != ComicLayoutDirection.vertical;

  void _startHorizontalScroll(double direction) {
    _autoPlay.pause();
    final distance = _viewportCommands.remainingHorizontalDistance(direction);
    if (distance == null) return;
    _keyboardScroll.press(direction);
  }

  void _onVerticalBoundary(VerticalScrollBoundary boundary) {
    if (boundary != VerticalScrollBoundary.none) {
      _keyboardScroll.stopAtBoundary();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (!resumed) _cancelActivePointers();
    if (!resumed) _navigationHold.stop();
    if (!resumed) _stopVerticalScroll();
    _resources.setActive(resumed);
    _controller.setWindowFocused(resumed);
    _animationSuspended = !resumed;
    _animationPlayback.value?.setSuspended(_animationSuspended || _gridVisible);
    if (mounted) setState(() {});
    _scheduleNeighborPrecache();
  }

  void _startNavigationHold(int direction, {bool singleImage = false}) {
    _holdSingleImage = singleImage;
    final settings = _session.settings.interaction;
    _navigationHold.press(
      direction,
      enabled: settings.holdNavigation,
      delay: Duration(milliseconds: settings.holdDelayMs),
      interval: Duration(milliseconds: settings.holdIntervalMs),
    );
  }

  TargetPlatform get _shortcutPlatform => Theme.of(context).platform;

  ViewerShortcutBinding _binding(ViewerCommand command) =>
      _shortcuts.binding(command, platform: _shortcutPlatform);

  String _keyLabel(ViewerCommand command) =>
      _shortcuts.label(command, platform: _shortcutPlatform);

  ImageEntry? get _actionEntry => _showingRecentOpen
      ? null
      : _gridVisible
      ? _gridSelected
      : _controller.currentEntry;

  void _toggleZoomLock() {
    final settings = _session.settings;
    unawaited(
      _applySettings(
        settings.copyWith(
          interaction: settings.interaction.copyWith(
            keepZoom: !settings.interaction.keepZoom,
          ),
        ),
      ),
    );
  }

  void _jumpToImage(bool last) {
    if (_controller.entries.isEmpty) return;
    _autoPlay.pause();
    _navigationHold.stop();
    _stopVerticalScroll();
    unawaited(_select(last ? _controller.entries.length - 1 : 0));
  }

  void _scrollReading(double direction, {bool boundary = false}) {
    if (_session.mode != ViewerMode.longImage &&
        _session.mode != ViewerMode.comic) {
      if (boundary) {
        _jumpToImage(direction < 0);
      } else {
        _move(direction < 0 ? 1 : -1);
      }
      return;
    }
    _autoPlay.pause();
    _navigationHold.stop();
    _stopVerticalScroll();
    final horizontal = _isHorizontalComic;
    if (horizontal &&
        _session.layoutDirection ==
            ComicLayoutDirection.horizontalRightToLeft) {
      direction = -direction;
    }
    final remaining = horizontal
        ? _viewportCommands.remainingHorizontalDistance(direction)
        : _viewportCommands.remainingVerticalDistance(direction);
    if (remaining == null) return;
    final viewport = _lastViewportSize;
    final extent = horizontal ? viewport?.width : viewport?.height;
    final distance = boundary
        ? remaining
        : math.min(remaining, (extent ?? 400) * 0.9);
    if (horizontal) {
      _viewportCommands.moveHorizontally(direction * distance);
    } else {
      _viewportCommands.moveVertically(direction * distance);
    }
  }

  void _switchChapter(int offset) {
    if (!_controller.hasFolderNavigation || _controller.isOpeningArchive) {
      return;
    }
    final chapters = _controller.chapterChoices;
    final current = chapters.indexWhere(
      (chapter) => chapter.path == _controller.selectedChapterPath,
    );
    final next = current + offset;
    if (current >= 0 && next >= 0 && next < chapters.length) {
      _autoPlay.pause();
      unawaited(_openChapterPath(chapters[next].path));
    }
  }

  void _focusSearch() {
    final inDirectory =
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<ChapterDirectoryTree>() !=
        null;
    if (_directoryIsShown &&
        (!_directoryIsDocked || inDirectory || !_gridVisible)) {
      (_isBorderless ? _borderlessDirectorySearchFocus : _directorySearchFocus)
          .requestFocus();
    } else if (_gridVisible) {
      _gridSearchFocus.requestFocus();
    } else {
      _toggleGrid();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _gridVisible) _gridSearchFocus.requestFocus();
      });
    }
  }

  void _beginRename() {
    final entry = _actionEntry;
    if (entry == null ||
        _controller.isReadOnlyArchive ||
        !entry.isMaterialized) {
      return;
    }
    if (_gridVisible) _loadGridMetadata();
    setState(() => _infoVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _actionEntry?.id != entry.id) return;
      _fileNameEditorKey.currentState?.beginEditing();
    });
  }

  void _executeCommand(ViewerCommand command) {
    switch (command) {
      case ViewerCommand.previousImage:
      case ViewerCommand.nextImage:
      case ViewerCommand.previousSingleImage:
      case ViewerCommand.nextSingleImage:
        break; // Handled with press/release tracking in _onKey.
      case ViewerCommand.toggleAnimation:
        if (!_gridVisible && (_animationPlayback.value?.frameCount ?? 0) > 1) {
          _animationPlayback.value?.toggle();
        }
      case ViewerCommand.openFile:
        unawaited(_openFile());
      case ViewerCommand.openFolder:
        unawaited(_openFolder());
      case ViewerCommand.settings:
        unawaited(_showSettings());
      case ViewerCommand.newWindow:
        unawaited(_newWindow());
      case ViewerCommand.fullscreen:
        unawaited(_toggleFullscreen());
      case ViewerCommand.borderless:
        unawaited(_toggleBorderless());
      case ViewerCommand.toggleDirectory:
        _toggleDirectoryPanel();
      case ViewerCommand.toggleInfo:
        _toggleInfoPanel();
      case ViewerCommand.toggleThumbnails:
        _toggleThumbnails();
      case ViewerCommand.toggleGrid:
        _toggleGrid();
      case ViewerCommand.alwaysOnTop:
        unawaited(_toggleAlwaysOnTop());
      case ViewerCommand.search:
        _focusSearch();
      case ViewerCommand.colorPicker:
        _toggleColorPicker();
      case ViewerCommand.autoPlay:
        _toggleAutoPlay();
      case ViewerCommand.stopAutoPlay:
        _autoPlay.stop();
      case ViewerCommand.copyFile:
        unawaited(
          _runFileOperation(_fileOperations.copyFile, retainForClipboard: true),
        );
      case ViewerCommand.deleteFile:
        unawaited(_deleteCurrent());
      case ViewerCommand.rename:
        _beginRename();
      case ViewerCommand.saveOriginal:
        unawaited(_saveOriginalImage());
      case ViewerCommand.copyPath:
        final entry = _actionEntry;
        if (entry != null && !_controller.isReadOnlyArchive) {
          unawaited(Clipboard.setData(ClipboardData(text: entry.id)));
        }
      case ViewerCommand.reveal:
        unawaited(_revealCurrentFile());
      case ViewerCommand.print:
        if (_gridVisible) {
          unawaited(_gridAction(_printCurrent));
        } else {
          unawaited(_printCurrent());
        }
      case ViewerCommand.reload:
        unawaited(_reloadCurrentImage());
      case ViewerCommand.rotate:
        if (_actionEntry == null) return;
        if (_gridVisible) {
          unawaited(_gridAction(_rotateDisplay));
        } else {
          _rotateDisplay();
        }
      case ViewerCommand.flip:
        if (_actionEntry == null) return;
        if (_gridVisible) {
          unawaited(_gridAction(_toggleHorizontalFlip));
        } else {
          _toggleHorizontalFlip();
        }
      case ViewerCommand.zoomIn:
        if (_gridVisible) {
          setState(() => _gridItemWidth = (_gridItemWidth + 24).clamp(96, 320));
        } else if (_actionEntry != null) {
          _zoomIn();
        }
      case ViewerCommand.zoomOut:
        if (_gridVisible) {
          setState(() => _gridItemWidth = (_gridItemWidth - 24).clamp(96, 320));
        } else if (_actionEntry != null) {
          _zoomOut();
        }
      case ViewerCommand.actualSize:
        _setScaleMode(ViewScaleMode.originalSize);
      case ViewerCommand.autoFit:
        _setScaleMode(ViewScaleMode.autoFit);
      case ViewerCommand.fitWidth:
        _setScaleMode(ViewScaleMode.fitWidth);
      case ViewerCommand.fitHeight:
        _setScaleMode(ViewScaleMode.fitHeight);
      case ViewerCommand.lockZoom:
        _toggleZoomLock();
      case ViewerCommand.singlePage:
        _setViewerMode(ViewerMode.single);
      case ViewerCommand.doublePage:
        _setViewerMode(ViewerMode.doublePage);
      case ViewerCommand.longImage:
        _setViewerMode(ViewerMode.longImage);
      case ViewerCommand.comic:
        _setViewerMode(ViewerMode.comic);
      case ViewerCommand.firstImage:
        _jumpToImage(false);
      case ViewerCommand.lastImage:
        _jumpToImage(true);
      case ViewerCommand.pageUp:
        _scrollReading(1);
      case ViewerCommand.pageDown:
        _scrollReading(-1);
      case ViewerCommand.home:
        _scrollReading(1, boundary: true);
      case ViewerCommand.end:
        _scrollReading(-1, boundary: true);
      case ViewerCommand.previousChapter:
        _switchChapter(-1);
      case ViewerCommand.nextChapter:
        _switchChapter(1);
      case ViewerCommand.parentFolder:
        final parent = _controller.parentFolderPath;
        if (parent != null) {
          _autoPlay.pause();
          unawaited(_openFolderPath(parent));
        }
      case ViewerCommand.previousFrame:
      case ViewerCommand.nextFrame:
        if (!_gridVisible) {
          _autoPlay.pause();
          _animationPlayback.value?.step(
            command == ViewerCommand.previousFrame ? -1 : 1,
          );
        }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyUpEvent) {
      if (key == _navigationShortcutKey) {
        _navigationShortcutKey = null;
        _navigationHold.stop();
        if (_isHorizontalComic) _stopVerticalScroll();
      }
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        _keyboardScroll.release(key == LogicalKeyboardKey.arrowUp ? 1 : -1);
      }
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        _navigationHold.release(key == LogicalKeyboardKey.arrowLeft ? -1 : 1);
        if (_isHorizontalComic) {
          _keyboardScroll.release(key == LogicalKeyboardKey.arrowLeft ? 1 : -1);
        }
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_contextMenuOpen &&
        key == LogicalKeyboardKey.escape &&
        event is KeyDownEvent) {
      _closeContextMenu();
      return KeyEventResult.handled;
    }
    final command = _shortcuts.commandFor(event, platform: _shortcutPlatform);
    const applicationCommands = {
      ViewerCommand.openFile,
      ViewerCommand.openFolder,
      ViewerCommand.settings,
      ViewerCommand.newWindow,
      ViewerCommand.fullscreen,
      ViewerCommand.borderless,
      ViewerCommand.stopAutoPlay,
      ViewerCommand.search,
    };
    if (applicationCommands.contains(command)) {
      if (event is KeyDownEvent) _executeCommand(command!);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && event is KeyDownEvent) {
      if (_colorPicker.active) {
        _toggleColorPicker();
        return KeyEventResult.handled;
      }
      if (_directoryIsShown) {
        _closeDirectory();
        return KeyEventResult.handled;
      }
    }
    if (focusedTextEditor != null) {
      _navigationHold.stop();
      _stopVerticalScroll();
      if (key == LogicalKeyboardKey.escape && event is KeyDownEvent) {
        _focusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape && event is KeyDownEvent) {
      unawaited(_handleEscape());
      return KeyEventResult.handled;
    }
    const panelCommands = {
      ViewerCommand.toggleDirectory,
      ViewerCommand.toggleInfo,
      ViewerCommand.toggleThumbnails,
      ViewerCommand.toggleGrid,
      ViewerCommand.alwaysOnTop,
    };
    if (panelCommands.contains(command)) {
      if (event is KeyDownEvent) _executeCommand(command!);
      return KeyEventResult.handled;
    }
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final gridHasFocus =
        _gridVisible &&
        focusContext?.findAncestorStateOfType<GridOverviewState>() != null;
    if (_directoryIsShown &&
        (!_directoryIsDocked ||
            (FocusManager.instance.primaryFocus != _focusNode &&
                !gridHasFocus))) {
      return KeyEventResult.ignored;
    }
    if (command == ViewerCommand.colorPicker) {
      if (event is KeyDownEvent) _toggleColorPicker();
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    final bare =
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed;
    if (_colorPicker.active) {
      if (command == ViewerCommand.copyFile) {
        if (event is KeyDownEvent) unawaited(_colorPicker.copy());
        return KeyEventResult.handled;
      }
      final direction = {
        LogicalKeyboardKey.arrowLeft: (-1, 0),
        LogicalKeyboardKey.arrowRight: (1, 0),
        LogicalKeyboardKey.arrowUp: (0, -1),
        LogicalKeyboardKey.arrowDown: (0, 1),
      }[key];
      if (bare &&
          direction != null &&
          FocusManager.instance.primaryFocus == _focusNode) {
        _colorPicker.nudge(direction.$1, direction.$2);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_gridVisible) {
      final result = _gridKey.currentState?.handleKey(event);
      if (result == KeyEventResult.handled) return result!;
      if (key == LogicalKeyboardKey.space) return KeyEventResult.handled;
    }
    if (focusContext?.findAncestorWidgetOfExactType<AnimationPlaybackBar>() !=
            null &&
        const [
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.home,
          LogicalKeyboardKey.end,
          LogicalKeyboardKey.pageUp,
          LogicalKeyboardKey.pageDown,
        ].contains(key)) {
      return KeyEventResult.ignored;
    }
    if (command != null) {
      if (const {
        ViewerCommand.previousImage,
        ViewerCommand.nextImage,
        ViewerCommand.previousSingleImage,
        ViewerCommand.nextSingleImage,
      }.contains(command)) {
        final single =
            command == ViewerCommand.previousSingleImage ||
            command == ViewerCommand.nextSingleImage;
        if (_gridVisible ||
            (single && _session.mode != ViewerMode.doublePage)) {
          return KeyEventResult.ignored;
        }
        if (event is KeyDownEvent) {
          final direction =
              command == ViewerCommand.previousImage ||
                  command == ViewerCommand.previousSingleImage
              ? -1
              : 1;
          _navigationShortcutKey = key;
          if (_isHorizontalComic) {
            _startHorizontalScroll(-direction.toDouble());
          } else {
            _startNavigationHold(direction, singleImage: single);
          }
        }
        return KeyEventResult.handled;
      }
      const repeatable = {
        ViewerCommand.zoomIn,
        ViewerCommand.zoomOut,
        ViewerCommand.pageUp,
        ViewerCommand.pageDown,
        ViewerCommand.previousFrame,
        ViewerCommand.nextFrame,
      };
      if (event is KeyDownEvent || repeatable.contains(command)) {
        _executeCommand(command);
      }
      return KeyEventResult.handled;
    }
    if (bare &&
        (_session.mode == ViewerMode.longImage ||
            _session.mode == ViewerMode.comic) &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      if (event is KeyDownEvent) {
        _startVerticalScroll(key == LogicalKeyboardKey.arrowUp ? 1 : -1);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    final entry = _controller.currentEntry;
    final hasBottomNavigation = _controller.hasFolderNavigation;
    final normalMode = !_floatingToolbar;
    final showBottomBar = !_isBorderless && _session.settings.showBottomBar;
    final thumbnailHeight = hasBottomNavigation ? 128.0 : 88.0;
    final navigation = <Widget>[
      _buildNavigationHotspot(left: true),
      _buildNavigationHotspot(left: false),
    ];
    return AnimatedBuilder(
      animation: Listenable.merge([
        _hdrControlsHovered,
        _notifications,
        _contextMenuVisible,
      ]),
      builder: (context, child) => ColorPickerScope(
        controller: _colorPicker,
        active: _colorPicker.active,
        child: HdrOverlayScope(
          suspended:
              _colorPicker.active ||
              _gridVisible ||
              _notifications.isNotEmpty ||
              _contextMenuOpen ||
              _topBarMenuKind != null ||
              _statusZoomEntry != null ||
              _dropActive ||
              (_directoryIsShown && !_directoryIsDocked) ||
              _showLeftNavigation ||
              _showRightNavigation ||
              !_windowFocused ||
              _hdrControlsHovered.value,
          child: child!,
        ),
      ),
      child: AppNotificationHost(
        controller: _notifications,
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dropActive = true),
          onDragExited: (_) => setState(() => _dropActive = false),
          onDragDone: _handleDrop,
          child: Scaffold(
            body: DragToResizeArea(
              resizeEdgeSize: 5,
              enableResizeEdges:
                  _isBorderless && !_isFullscreen && !_isMaximized
                  ? null
                  : const [],
              child: Listener(
                onPointerHover: (event) {
                  _recoverMousePointers(event);
                  _trackToolbarPointer(event);
                },
                onPointerDown: (event) {
                  _recoverMousePointers(event);
                  _activePointerDowns[event.pointer] = event;
                  _trackToolbarPointer(event);
                  _navigationHold.stop();
                  _stopVerticalScroll();
                  // Keep the editor's input connection alive when a click lands
                  // inside the rename field. The shell owns this listener, so it
                  // also receives pointer events that belong to the TextField.
                  if (FocusManager.instance.primaryFocus == _focusNode) {
                    _clearTextInput();
                  }
                },
                onPointerUp: (event) =>
                    _activePointerDowns.remove(event.pointer),
                onPointerCancel: (event) =>
                    _activePointerDowns.remove(event.pointer),
                onPointerMove: (event) {
                  _trackToolbarPointer(event);
                  if (!_floatingToolbar) return;
                  if (event.localPosition.dy <= 64) {
                    _showToolbarOnEnter();
                  } else if (_showToolbar) {
                    _hideToolbarOnExit();
                  }
                },
                child: Focus(
                  autofocus: true,
                  focusNode: _focusNode,
                  onFocusChange: (hasFocus) {
                    if (hasFocus) {
                      _clearTextInput();
                    } else {
                      _navigationHold.stop();
                      _stopVerticalScroll();
                    }
                  },
                  onKeyEvent: _onKey,
                  child: Stack(
                    key: _contextMenuCoordinateKey,
                    children: [
                      _buildContextMenuAnchor(),
                      Positioned.fill(
                        top: normalMode ? _topBarHeight : 0,
                        bottom: showBottomBar ? _bottomStatusBarHeight : 0,
                        child: _buildDirectoryRegion(
                          _buildImageRegion(
                            entry,
                            navigation: navigation,
                            thumbnailHeight: thumbnailHeight,
                            showThumbnails: _thumbnailsVisible,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _buildMenuBar(),
                      ),
                      if (showBottomBar)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: _bottomStatusBarHeight,
                          child: _buildBottomStatusBar(),
                        ),
                      if (_controller.isIndexing)
                        const Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      if (_dropActive)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ColoredBox(
                              color: tokens.accent.withValues(alpha: 0.40),
                              child: Center(
                                child: Text(
                                  _l10n.dropToOpen,
                                  style: AppTextStyles.pageTitle.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationHotspot({required bool left}) {
    final visible = left ? _showLeftNavigation : _showRightNavigation;
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 48,
      bottom: 0,
      width: 84,
      child: MouseRegion(
        onEnter: (_) => setState(() {
          if (left) {
            _showLeftNavigation = true;
          } else {
            _showRightNavigation = true;
          }
        }),
        onExit: (_) => setState(() {
          if (left) {
            _showLeftNavigation = false;
          } else {
            _showRightNavigation = false;
          }
        }),
        child: Align(
          alignment: left ? Alignment.centerLeft : Alignment.centerRight,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: IgnorePointer(
              ignoring: !visible,
              child: _edgeButton(
                left
                    ? FluentIcons.chevron_left_20_regular
                    : FluentIcons.chevron_right_20_regular,
                left ? -1 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onAutoPlayChanged() {
    if (_disposing) return;
    if (_autoPlay.playing && !_autoPlayTicker.isActive) {
      _autoPlayLastTick = Duration.zero;
      _autoPlayTicker.start();
    } else if (!_autoPlay.playing && _autoPlayTicker.isActive) {
      _autoPlayTicker.stop();
    }
    if (_autoPlayLastStatus != _autoPlay.status) {
      _autoPlayLastStatus = _autoPlay.status;
      if (mounted) setState(() {});
    }
  }

  Set<String> get _autoPlayVisibleIds {
    final entry = _controller.currentEntry;
    if (entry == null) return {};
    final peer =
        _session.mode == ViewerMode.doublePage &&
            _autoPlaySpreadEntry?.id == entry.id
        ? _autoPlaySpreadPeer
        : null;
    return {entry.id, if (peer != null) peer.id};
  }

  void _markAutoPlayDisplayed(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_disposing) _displayedEntries.add(id);
    });
  }

  void _toggleAutoPlay() {
    if (_colorPicker.active) _toggleColorPicker();
    if (_gridVisible) _toggleGrid();
    _autoPlay.configure(_session.settings.autoPlay, _session.mode);
    if (_autoPlay.playing) {
      _autoPlay.pause();
    } else if (_controller.currentEntry != null &&
        _controller.currentEntry!.format != ImageFormat.archive) {
      for (final id in _autoPlayVisibleIds) {
        _autoPlayAnimations[id]?.setPlaying(true);
      }
      _autoPlay.start();
    }
  }

  Future<void> _saveAutoPlay(AutoPlaySettings settings) async {
    final updated = _session.settings.copyWith(autoPlay: settings);
    _session.applySettings(updated);
    _autoPlay.configure(settings, _session.mode);
    await _persistSettings(updated);
  }

  Future<void> _showAutoPlayOptions() async {
    _autoPlayOptionsOpen = true;
    try {
      final value = await showAutoPlayOptions(
        context,
        settings: _autoPlay.settings,
        mode: _session.mode,
        onStop: _autoPlay.stop,
      );
      if (value != null && mounted) await _saveAutoPlay(value);
    } finally {
      _autoPlayOptionsOpen = false;
    }
  }

  void _tickAutoPlay(Duration elapsed) {
    final delta = elapsed - _autoPlayLastTick;
    _autoPlayLastTick = elapsed;
    if (!_autoPlay.playing || _disposing || !mounted) return;
    final entry = _controller.currentEntry;
    if (entry == null || entry.format == ImageFormat.archive) {
      _autoPlay.stop();
      return;
    }
    final ids = _autoPlayVisibleIds;
    final presentation = (
      _session.mode,
      entry.id,
      _metadataVersion,
      ids.join('|'),
    );
    if (_autoPlayPresentation != presentation) {
      _autoPlayPresentation = presentation;
      if (!_autoPlay.scrolling) _autoPlay.resetInterval();
      _autoPlayAnimations.removeWhere((id, _) => !ids.contains(id));
    }
    final suspended =
        _colorPicker.active ||
        !_pageActive ||
        _animationSuspended ||
        _autoPlayAdvancing ||
        _autoPlayOptionsOpen ||
        _contextMenuOpen ||
        _topBarMenuEntry != null ||
        _statusZoomEntry != null ||
        !(ModalRoute.of(context)?.isCurrent ?? true);
    if (suspended) return;
    final states = <AutoPlayAnimationState>[];
    var ready = true;
    final peer =
        _session.mode == ViewerMode.doublePage &&
            _autoPlaySpreadEntry?.id == entry.id
        ? _autoPlaySpreadPeer
        : null;
    for (final page in [entry, ?peer]) {
      final id = page.id;
      final animation = _autoPlayAnimations[id];
      if (_resources.isAnimated(page)) {
        if (animation == null) {
          ready = false;
          continue;
        }
        if (animation.error != null) {
          _autoPlay.pause();
          return;
        }
        final snapshot = animation.snapshot;
        if (animation.frameCount > 1) {
          states.add((
            ready: animation.ready,
            playedOnce: snapshot.completedPlays > 0 || snapshot.ended,
            paused: !snapshot.playing && !snapshot.ended,
          ));
        }
        ready = ready && animation.ready;
      } else {
        ready = ready && _displayedEntries.contains(id);
      }
    }
    // A resumed ticker can include time spent outside the visible route.
    final step = delta > const Duration(milliseconds: 100)
        ? const Duration(milliseconds: 100)
        : delta;
    if (_autoPlay.scrolling) {
      if (!ready) return;
      // Placeholder aspect ratios must not be mistaken for the end of a strip.
      if (_session.mode == ViewerMode.comic &&
          !_comicPositionController.layoutReady) {
        return;
      }
      final direction =
          _isHorizontalComic &&
              _session.layoutDirection ==
                  ComicLayoutDirection.horizontalRightToLeft
          ? 1.0
          : -1.0;
      final distance = _isHorizontalComic
          ? _viewportCommands.remainingHorizontalDistance(direction)
          : _viewportCommands.remainingVerticalDistance(direction);
      if (distance == null) return;
      if (distance <= 0.01) {
        final reverseDistance = _isHorizontalComic
            ? _viewportCommands.remainingHorizontalDistance(-direction)
            : _viewportCommands.remainingVerticalDistance(-direction);
        if ((reverseDistance ?? 0) <= 0.01) {
          if (_session.mode == ViewerMode.comic) {
            // The complete strip already fits; repeated resets have no visible effect.
            _autoPlay.stop();
          } else if (_autoPlay.tick(
            step,
            ready: ready,
            timedScrollHold: true,
          )) {
            unawaited(_advanceAutoPlay());
          }
        } else {
          unawaited(_advanceAutoPlay());
        }
      } else {
        final amount = math.min(
          distance,
          _autoPlay.settings.speedFor(_session.mode) *
              step.inMicroseconds /
              1000000,
        );
        if (_isHorizontalComic) {
          _viewportCommands.moveHorizontally(direction * amount);
        } else {
          _viewportCommands.moveVertically(direction * amount);
        }
      }
    } else if (_autoPlay.tick(step, ready: ready, animations: states)) {
      unawaited(_advanceAutoPlay());
    }
  }

  Future<void> _advanceAutoPlay() async {
    if (_autoPlayAdvancing) return;
    _autoPlayAdvancing = true;
    try {
      final current = _controller.currentIndex;
      var next =
          current +
          (_session.mode == ViewerMode.doublePage ? _doublePageStep(1) : 1);
      if (_session.mode == ViewerMode.comic) next = _controller.entries.length;
      if (next >= _controller.entries.length) {
        if (!_autoPlay.settings.loop) {
          _autoPlay.stop();
          return;
        }
        next = 0;
      }
      // Containers are explicit navigation destinations, not slideshow items.
      if (_controller.entries[next].format == ImageFormat.archive) {
        _autoPlay.stop();
        return;
      }
      _autoPlay.resetInterval();
      if (next == current) {
        if (_autoPlay.scrolling) {
          if (_session.mode == ViewerMode.comic) {
            _session.moveComicSelection();
          } else {
            _resetView();
          }
        }
        return;
      }
      await _select(next);
    } finally {
      _autoPlayAdvancing = false;
    }
  }

  Widget _buildCanvas(ImageEntry? entry) {
    if (entry == null) {
      final tokens = ViewerThemeTokens.of(context);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.image_24_regular,
              size: 56,
              color: tokens.textDisabled,
            ),
            const SizedBox(height: 10),
            Text(
              _emptyCanvasMessage(),
              style: AppTextStyles.body.copyWith(color: tokens.textTertiary),
            ),
          ],
        ),
      );
    }
    if (entry.format == ImageFormat.archive) {
      return Center(child: Text(_l10n.selectContainer));
    }
    return HdrViewportBoundary(
      insets: _floatingToolbar && _showToolbar
          ? const EdgeInsets.only(top: _topBarHeight)
          : EdgeInsets.zero,
      child: Listener(
        onPointerDown: (_) => _focusNode.requestFocus(),
        onPointerMove: (event) {
          if (event.down) _autoPlay.pause();
        },
        onPointerPanZoomStart: (_) => _autoPlay.pause(),
        onPointerSignal: (event) {
          if (event is PointerScrollInertiaCancelEvent) {
            _scrollNavigation.reset();
            return;
          }
          if (event is! PointerScrollEvent) return;
          if (_autoPlay.scrolling ||
              HardwareKeyboard.instance.isControlPressed ||
              _session.settings.interaction.wheelAction == WheelAction.zoom) {
            _autoPlay.pause();
          }
          final pressed = HardwareKeyboard.instance.logicalKeysPressed;
          final direction = _scrollNavigation.handle(
            event,
            interval: Duration(
              milliseconds: _session.settings.interaction.wheelIntervalMs,
            ),
            enabled:
                _session.settings.interaction.wheelAction ==
                    WheelAction.navigate &&
                _session.mode != ViewerMode.longImage &&
                _session.mode != ViewerMode.comic &&
                !pressed.contains(LogicalKeyboardKey.controlLeft) &&
                !pressed.contains(LogicalKeyboardKey.controlRight),
          );
          if (direction != null) {
            _move(
              _session.settings.interaction.reverseWheel
                  ? -direction
                  : direction,
            );
          }
        },
        child: GestureDetector(
          onDoubleTap: _colorPicker.active
              ? null
              : () => _setScaleMode(
                  _session.fitMode
                      ? ViewScaleMode.originalSize
                      : _session.defaultScaleModeFor(_session.mode),
                ),
          child: _session.mode == ViewerMode.single
              ? _buildSingleImageViewport(entry)
              : _buildModeViewport(entry),
        ),
      ),
    );
  }

  String _emptyCanvasMessage() {
    if (_controller.isOpeningArchive) return _l10n.archiveOpening;
    if (_controller.isIndexing && _controller.scanProgress != null) {
      return _l10n.scanProgress(
        _controller.scanProgress!.scannedDirectories,
        _controller.scanProgress!.foundImages,
      );
    }
    if (_controller.folderPath == null) return _l10n.folderNotOpened;
    final recursive =
        _controller.activeBrowseMode.isRecursive ||
        _controller.archiveContext != null;
    return recursive ? _l10n.emptyRecursiveFolder : _l10n.emptyFolder;
  }

  Widget _buildSingleImageViewport(ImageEntry entry) {
    return FutureBuilder<ImageMetadata>(
      future: _metadataFuture,
      initialData: _resources.cachedMetadata(entry),
      builder: (context, snapshot) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final viewport = Size(constraints.maxWidth, constraints.maxHeight);
            // FutureBuilder retains the previous image's data while waiting.
            // Keep the viewport and transition mounted, but never use that
            // stale size to finish restoring the newly selected image.
            final metadata = snapshot.connectionState == ConnectionState.waiting
                ? _resources.cachedMetadata(entry)
                : snapshot.data;
            final sourceSize =
                metadata != null && metadata.width > 0 && metadata.height > 0
                ? Size(metadata.width.toDouble(), metadata.height.toDouble())
                : viewport;
            final imageSize = _session.fitMode
                ? _fitImageSize(sourceSize, viewport)
                : sourceSize;
            final referenceScale = imageSize.width / sourceSize.width;
            final restoredEntry = _entryTransformForLayout(
              viewport,
              rotatedContent(imageSize),
              referenceScale,
              startAtTop: _session.scaleMode == ViewScaleMode.fitWidth,
              startAtLeft: _session.scaleMode == ViewScaleMode.fitHeight,
              metadataReady: metadata != null,
            );
            _setZoomReferenceScale(
              _session.fitMode && sourceSize.width > 0
                  ? imageSize.width / sourceSize.width
                  : 1,
            );
            final rotated = _session.rotationQuarterTurns.isOdd;
            final contentSize = rotated
                ? Size(imageSize.height, imageSize.width)
                : imageSize;
            return ZoomableViewport(
              key: const ValueKey('single-viewport'),
              initialTransform: restoredEntry ?? _modeRestoreTransform,
              resetTransform: restoredEntry,
              zoomOnWheel:
                  _session.settings.interaction.wheelAction == WheelAction.zoom,
              wheelZoomSpeed: _session.settings.interaction.zoomSpeed,
              contentSize: contentSize,
              minScale: _matrixMinZoomScale(),
              maxScale: _matrixMaxZoomScale(),
              controller: _transformController,
              commands: _viewportCommands,
              resetRequest: _viewResetRequest,
              startAtTop:
                  _session.scaleMode == ViewScaleMode.fitWidth ||
                  _session.mode == ViewerMode.longImage ||
                  _session.mode == ViewerMode.comic,
              startAtLeft: _session.scaleMode == ViewScaleMode.fitHeight,
              zoomAroundCenter:
                  _session.settings.interaction.zoomCenter ==
                  ZoomCenter.viewport,
              onInteractionUpdate: (scale) {
                final zoomed = scale > 1.01;
                if (_session.isZoomed != zoomed && mounted) {
                  _session.setZoomed(zoomed);
                }
              },
              child: SizedBox(
                width: contentSize.width,
                height: contentSize.height,
                child: _buildImageTransition(
                  transitionKey: '${entry.id}:${_session.reloadToken}',
                  child: Center(
                    child: _buildDisplayTransform(
                      SizedBox(
                        width: imageSize.width,
                        height: imageSize.height,
                        child: _buildImageWidget(entry, BoxFit.contain),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Size _fitImageSize(Size source, Size viewport) {
    if (source.width <= 0 || source.height <= 0) return viewport;
    final rotated = _session.rotationQuarterTurns.isOdd;
    final sourceWidth = rotated ? source.height : source.width;
    final sourceHeight = rotated ? source.width : source.height;
    final scale = viewScaleFor(
      Size(sourceWidth, sourceHeight),
      viewport,
      _session.scaleMode,
    );
    return Size(source.width * scale, source.height * scale);
  }

  Widget _buildModeViewport(ImageEntry entry) {
    if (_session.mode == ViewerMode.comic) {
      return _buildComicViewport();
    }
    final nextIndex = _session.mode == ViewerMode.doublePage
        ? _doublePagePeerIndex()
        : null;
    final metadataPeer = nextIndex == null
        ? null
        : _controller.entries[nextIndex];
    if (_spreadMetadataSource != _metadataFuture ||
        _spreadMetadataPeerId != metadataPeer?.id ||
        _spreadMetadataFuture == null) {
      _spreadMetadataSource = _metadataFuture;
      _spreadMetadataPeerId = metadataPeer?.id;
      _spreadMetadataFuture = Future.wait<ImageMetadata?>([
        _metadataFuture ?? _resources.metadata(entry),
        if (metadataPeer != null)
          _resources
              .metadata(metadataPeer)
              .then<ImageMetadata?>(
                (value) => value,
                onError: (Object error, StackTrace stack) => null,
              ),
      ]);
    }
    return FutureBuilder<List<ImageMetadata?>>(
      future: _spreadMetadataFuture,
      initialData: [
        _resources.cachedMetadata(entry),
        if (metadataPeer != null) _resources.cachedMetadata(metadataPeer),
      ],
      builder: (context, snapshot) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final viewport = Size(constraints.maxWidth, constraints.maxHeight);
            final waiting = snapshot.connectionState == ConnectionState.waiting;
            final metadata = waiting
                ? _resources.cachedMetadata(entry)
                : snapshot.data?.firstOrNull;
            final source =
                metadata != null && metadata.width > 0 && metadata.height > 0
                ? Size(metadata.width.toDouble(), metadata.height.toDouble())
                : viewport;
            // Newly loaded dimensions can make a wide image stand alone.
            // Re-evaluate the grouping in this metadata-driven build.
            final peerIndex = _session.mode == ViewerMode.doublePage
                ? _doublePagePeerIndex()
                : null;
            final next = peerIndex == null
                ? null
                : _controller.entries[peerIndex];
            _autoPlaySpreadEntry = entry;
            _autoPlaySpreadPeer = next;
            final peerMetadata = next == null
                ? null
                : _resources.cachedMetadata(next) ??
                      (!waiting && next.id == metadataPeer?.id
                          ? snapshot.data?.elementAtOrNull(1)
                          : null);
            final nextSize = next == null
                ? null
                : peerMetadata == null ||
                      peerMetadata.width <= 0 ||
                      peerMetadata.height <= 0
                ? source
                : Size(
                    peerMetadata.width.toDouble(),
                    peerMetadata.height.toDouble(),
                  );
            final splitWide =
                _session.mode == ViewerMode.doublePage &&
                _session.settings.doublePageSplitWide &&
                !(_session.settings.doublePageFirstAlone &&
                    _controller.currentIndex == 0) &&
                next == null &&
                !_resources.isAnimated(entry) &&
                entry.format != ImageFormat.apng &&
                metadata != null &&
                !metadata.isHdr &&
                metadata.width >= 2 &&
                metadata.height > 0 &&
                metadata.width > metadata.height;
            final gap = next != null || splitWide ? 12.0 : 0.0;
            final natural = Size(
              source.width + (nextSize?.width ?? 0) + gap,
              math.max(source.height, nextSize?.height ?? source.height),
            );
            final referenceScale = viewScaleFor(
              rotatedContent(natural),
              viewport,
              _session.scaleMode,
            );
            final contentSize = Size(
              natural.width * referenceScale,
              natural.height * referenceScale,
            );
            final longWidth = contentSize.width;
            final restoredEntry = _entryTransformForLayout(
              viewport,
              rotatedContent(contentSize),
              referenceScale,
              startAtTop:
                  _session.mode == ViewerMode.longImage ||
                  _session.scaleMode == ViewScaleMode.fitWidth,
              startAtLeft: _session.scaleMode == ViewScaleMode.fitHeight,
              metadataReady:
                  metadata != null && (next == null || peerMetadata != null),
            );
            _setZoomReferenceScale(referenceScale);
            final child =
                _session.mode == ViewerMode.longImage &&
                    _shouldTileLongImage(entry, source)
                ? LongImageViewport(
                    entry: entry,
                    sampleKind: _colorSampleKind(entry),
                    resources: _resources,
                    sourceSize: source,
                    onDisplayed: () => _markAutoPlayDisplayed(entry.id),
                    viewport: viewport,
                    baseWidth: longWidth,
                    controller: _transformController,
                    targetWidth:
                        _imageCacheWidth() ??
                        math.max(256, viewport.width.round()),
                  )
                : _session.mode == ViewerMode.longImage
                ? SizedBox(
                    width: contentSize.width,
                    height: contentSize.height,
                    child: _buildImageWidget(entry, BoxFit.contain),
                  )
                : splitWide
                ? SizedBox(
                    width: contentSize.width,
                    height: contentSize.height,
                    child: SplitWideImage(
                      sourceSize: source,
                      gap: gap * referenceScale,
                      buildImage: () =>
                          _buildImageWidget(entry, BoxFit.contain),
                    ),
                  )
                : _buildDoublePageContent(
                    entry,
                    next,
                    source,
                    nextSize,
                    referenceScale,
                    contentSize,
                  );
            return ZoomableViewport(
              key: ValueKey('mode-viewport:${_session.mode}'),
              initialTransform: restoredEntry ?? _modeRestoreTransform,
              resetTransform: restoredEntry,
              onHorizontalSwipe: _session.mode == ViewerMode.doublePage
                  ? (direction) => _move(
                      _session.readingDirection == ReadingDirection.rightToLeft
                          ? -direction
                          : direction,
                    )
                  : null,
              resetRequest: _viewResetRequest,
              zoomOnWheel:
                  _session.mode == ViewerMode.doublePage &&
                  _session.settings.interaction.wheelAction == WheelAction.zoom,
              wheelScrollSpeed: _session.settings.interaction.scrollSpeed,
              wheelZoomSpeed: _session.settings.interaction.zoomSpeed,
              zoomAroundCenter:
                  _session.settings.interaction.zoomCenter ==
                  ZoomCenter.viewport,
              contentSize: rotatedContent(contentSize),
              minScale: _matrixMinZoomScale(),
              maxScale: _matrixMaxZoomScale(),
              controller: _transformController,
              commands: _viewportCommands,
              onVerticalBoundary: _session.mode == ViewerMode.longImage
                  ? _onVerticalBoundary
                  : null,
              startAtTop:
                  _session.mode == ViewerMode.longImage ||
                  _session.scaleMode == ViewScaleMode.fitWidth,
              startAtLeft: _session.scaleMode == ViewScaleMode.fitHeight,
              onWheel: _session.mode == ViewerMode.longImage ? (_) {} : null,
              onInteractionUpdate: (scale) {
                final rotatedSize = rotatedContent(contentSize);
                final canPan =
                    rotatedSize.width * scale > viewport.width + 0.5 ||
                    rotatedSize.height * scale > viewport.height + 0.5;
                if (_session.isZoomed != canPan && mounted) {
                  _session.setZoomed(canPan);
                }
              },
              child: _buildImageTransition(
                transitionKey: [
                  _session.mode,
                  entry.id,
                  next?.id,
                  splitWide,
                ].join(':'),
                child: _buildDisplayTransform(child),
              ),
            );
          },
        );
      },
    );
  }

  List<List<int>> _doublePageGroups() {
    for (final entry in _controller.entries) {
      final metadata = _resources.cachedMetadata(entry);
      if (metadata != null && metadata.width > metadata.height) {
        _landscapeIds.add(entry.id);
      }
    }
    return readingSpreads(
      _controller.entries,
      firstAlone: _session.settings.doublePageFirstAlone,
      wideAlone: _session.settings.doublePageWideAlone,
      splitWide: _session.settings.doublePageSplitWide,
      pairingAnchor: _controller.entries.indexWhere(
        (entry) => entry.id == _pairingAnchorId,
      ),
      landscapeIds: _landscapeIds,
    );
  }

  int? _doublePagePeerIndex() {
    final group = _doublePageGroups()
        .where((group) => group.contains(_controller.currentIndex))
        .firstOrNull;
    return group
        ?.where((index) => index != _controller.currentIndex)
        .firstOrNull;
  }

  bool _shouldTileLongImage(ImageEntry entry, Size source) =>
      !_resources.isAnimated(entry) &&
      entry.format != ImageFormat.svg &&
      source.height >= 12000;

  Widget _buildDoublePageContent(
    ImageEntry entry,
    ImageEntry? peer,
    Size source,
    Size? peerSize,
    double scale,
    Size contentSize,
  ) {
    final pages = <ImageEntry>[entry, ?peer]
      ..sort(
        (a, b) => _controller.entries
            .indexWhere((entry) => entry.id == a.id)
            .compareTo(
              _controller.entries.indexWhere((entry) => entry.id == b.id),
            ),
      );
    final ordered = _session.readingDirection == ReadingDirection.rightToLeft
        ? pages.reversed
        : pages;
    // During a transition the outgoing spread receives the new spread's
    // constraints. Keep its own aspect ratio instead of overflowing its row.
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: contentSize.width,
        height: contentSize.height,
        child: Row(
          children: [
            for (final (position, page) in ordered.indexed) ...[
              if (position > 0) SizedBox(width: 12 * scale),
              SizedBox(
                width:
                    (page.id == entry.id ? source.width : peerSize!.width) *
                    scale,
                height:
                    (page.id == entry.id ? source.height : peerSize!.height) *
                    scale,
                child: GestureDetector(
                  onTap: () {
                    if (_animationSelectedId == page.id) return;
                    setState(() {
                      _animationSelectedId = page.id;
                      _animationPlayback.value = null;
                    });
                  },
                  child: _buildImageWidget(page, BoxFit.contain),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildComicViewport() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        // The strip reports a stable pixel reference; scrolling never changes it.
        _lastViewportSize = viewport;
        return ComicStripViewport(
          key: ValueKey(
            'comic-strip-viewport:$_readingContext:${_session.reloadToken}',
          ),
          positionController: _comicPositionController,
          initialPosition: _comicRestorePosition,
          entries: _controller.entries,
          currentIndex: _controller.currentIndex,
          jumpToken: _session.comicJumpToken,
          viewport: viewport,
          baseWidth: viewport.width,
          wheelScrollSpeed: _session.settings.interaction.scrollSpeed,
          wheelZoomSpeed: _session.settings.interaction.zoomSpeed,
          scaleMode: _session.scaleMode,
          resetRequest: _viewResetRequest,
          uniformPageSize: _session.settings.comicUniformSize,
          onReferenceScaleChanged: (scale) {
            if (_comicReferenceResetRequest != _viewResetRequest) {
              _comicReferenceResetRequest = _viewResetRequest;
              _setZoomReferenceScale(scale, preserveScale: false);
            } else {
              _setZoomReferenceScale(scale);
            }
          },
          minScale: _matrixMinZoomScale(),
          maxScale: _matrixMaxZoomScale(),
          zoomAroundCenter:
              _session.settings.interaction.zoomCenter == ZoomCenter.viewport,
          controller: _transformController,
          commands: _viewportCommands,
          onVerticalBoundary: _onVerticalBoundary,
          pageGap: _session.settings.comicPageGap,
          layoutDirection: _session.layoutDirection,
          metadataPreloadPages: switch (_resources.policy.level) {
            prefetch.PrefetchLevel.normal => 3,
            prefetch.PrefetchLevel.conservative => 2,
            prefetch.PrefetchLevel.onDemand => 0,
          },
          admittedPageIds: _admittedComicPages,
          onVisiblePagesChanged: (visible, geometry, start, end) {
            if (!mounted) return;
            _visibleComicPages = visible;
            _comicGeometry = geometry;
            _comicViewportStart = start;
            _comicViewportEnd = end;
            _scheduleNeighborPrecache();
          },
          loadSize: _loadImageSize,
          onCurrentPageChanged: (index) {
            if (!mounted || index == _controller.currentIndex) return;
            _controller.select(index);
          },
          buildPage: (page, isCurrent) =>
              _buildImageWidget(page, BoxFit.contain, isCurrent),
        );
      },
    );
  }

  ColorSampleKind _colorSampleKind(ImageEntry entry) {
    if (entry.format == ImageFormat.svg) return ColorSampleKind.svg;
    final metadata = _resources.cachedMetadata(entry);
    if (metadata?.isHdr != true) return ColorSampleKind.srgb;
    return metadata!.hdrEncoding == HdrEncoding.gainMap
        ? ColorSampleKind.sdrBase
        : ColorSampleKind.sdrMapped;
  }

  Widget _buildImageWidget(
    ImageEntry entry, [
    BoxFit? overrideFit,
    // Comic mode pauses animations on pages that are not the current one so a
    // long strip does not keep several decoders running at once.
    bool playAnimation = true,
  ]) {
    if (!entry.isMaterialized) {
      return SourceImageView(
        key: ValueKey('source:${entry.id}'),
        entry: entry,
        builder: (resolved) =>
            _buildImageWidget(resolved, overrideFit, playAnimation),
        errorBuilder: (error) => _errorView(entry, error),
      );
    }
    final fit =
        overrideFit ?? (_session.fitMode ? BoxFit.contain : BoxFit.none);
    final metadata = _resources.cachedMetadata(entry);
    final width = metadata?.width ?? entry.width;
    final height = metadata?.height ?? entry.height;
    return ColorPickerTarget(
      id: entry.id,
      name: entry.name,
      sourceSize: width != null && height != null && width > 0 && height > 0
          ? Size(width.toDouble(), height.toDouble())
          : null,
      kind: _colorSampleKind(entry),
      child: _resources.isAnimated(entry)
          ? AnimatedImageView(
              key: ValueKey((_resources.version(entry), _session.reloadToken)),
              resources: _resources,
              entry: entry,
              targetSize: _imageCacheWidth(),
              file: entry.file,
              autoPlay: _session.settings.animationAutoPlay,
              initialPlayback: entry.id == _animationSelectedId
                  ? _animationPlayback.value?.snapshot
                  : null,
              loopMode: _session.settings.animationLoopMode,
              defaultSpeed: _session.settings.animationSpeed,
              onError: (_) => _markAutoPlayFailed(entry.id),
              playing:
                  playAnimation &&
                  !_gridVisible &&
                  !_colorPicker.active &&
                  !_animationSuspended &&
                  _pageActive,
              onController: (controller) {
                if (!mounted ||
                    _disposing ||
                    !_autoPlayVisibleIds.contains(entry.id)) {
                  return;
                }
                _autoPlayAnimations[entry.id] = controller;
                if (entry.id ==
                    (_animationSelectedId ?? _controller.currentEntry?.id)) {
                  if (!identical(_animationPlayback.value, controller)) {
                    _animationPlayback.value = controller;
                    if (_autoPlay.active) setState(() {});
                  }
                }
              },
              fit: fit,
              onFrameInfo: (frame, frameCount) =>
                  _updateFrameInfo(entry, frame, frameCount),
            )
          : _buildStaticImage(entry, fit, playAnimation),
    );
  }

  Widget _buildStaticImage(
    ImageEntry entry, [
    BoxFit? overrideFit,
    bool playAnimation = true,
  ]) {
    final fit =
        overrideFit ?? (_session.fitMode ? BoxFit.contain : BoxFit.none);
    if (entry.format == ImageFormat.svg) {
      return SvgImage(
        key: ValueKey((entry.id, _session.reloadToken)),
        file: entry.file,
        version: svgVersion(entry),
        session: _svgWebView,
        allowWebView:
            playAnimation &&
            entry.id == (_animationSelectedId ?? _controller.currentEntry?.id),
        transform: _transformController,
        onDisplayed: () => _markAutoPlayDisplayed(entry.id),
        onFallback: () {
          if (!mounted || _disposing) return;
          _notifications.show(
            _l10n.svgStaticPreview,
            type: AppNotificationType.warning,
          );
        },
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _errorView(entry, error),
      );
    }
    final target = _colorPicker.active ? null : _imageCacheWidth();
    final metadata = _resources.cachedMetadata(entry);
    Widget onFrame(
      BuildContext context,
      Widget child,
      int? frame,
      bool synchronous,
    ) {
      if (frame != null || synchronous) {
        _markAutoPlayDisplayed(entry.id);
      }
      return child;
    }

    final image = entry.format == ImageFormat.raw
        ? RawResourceImage(
            key: ValueKey(_resources.version(entry)),
            resources: _resources,
            entry: entry,
            transform: _transformController,
            sourceSize:
                metadata != null && metadata.width > 0 && metadata.height > 0
                ? Size(metadata.width.toDouble(), metadata.height.toDouble())
                : null,
            fit: fit,
            fullResolution: _colorPicker.active,
            frameBuilder: onFrame,
            errorBuilder: (context, error, stack) => _errorView(entry, error),
          )
        : ResourceImage(
            resources: _resources,
            entry: entry,
            targetWidth: target,
            targetHeight: target,
            fit: fit,
            frameBuilder: (context, child, frame, synchronous) {
              if (frame != null || synchronous) {
                _markAutoPlayDisplayed(entry.id);
              }
              return child;
            },
            errorBuilder: (context, error, stack) => _errorView(entry, error),
          );
    if (metadata != null &&
        shouldUseHdrDisplay(
          _session.settings,
          entry.format,
          metadata.hdrEncoding,
        ) &&
        _session.mode != ViewerMode.comic &&
        metadata.isHdr) {
      if (metadata.width > 0 && metadata.height > 0) {
        return HdrImageView(
          key: ValueKey('hdr:${entry.id}'),
          path: entry.file.path,
          decodeFrame: (request) => _resources.hdrFrame(entry, request),
          runDecode: (request, operation) =>
              _resources.runHdrTask(entry, request, operation),
          revision: _resources.version(entry),
          sourceSize: Size(
            metadata.width.toDouble(),
            metadata.height.toDouble(),
          ),
          fit: fit,
          child: image,
        );
      }
    }
    return image;
  }

  void _updateFrameInfo(ImageEntry entry, int frame, int frameCount) {
    if (!mounted || _controller.currentEntry?.id != entry.id) {
      return;
    }
    if (_frameInfo.value != (frame, frameCount)) {
      _frameInfo.value = (frame, frameCount);
      if (_colorPicker.active) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _colorPicker.refreshFrame(entry.id);
        });
      }
    }
  }

  Widget _buildImageTransition({
    required String transitionKey,
    required Widget child,
  }) {
    final entry = _controller.currentEntry;
    final format = entry?.format;
    final metadata = entry == null ? null : _resources.cachedMetadata(entry);
    if (format == ImageFormat.hdr ||
        format == ImageFormat.exr ||
        entry != null &&
            metadata != null &&
            shouldUseHdrDisplay(
              _session.settings,
              entry.format,
              metadata.hdrEncoding,
            )) {
      return child;
    }
    final interaction = _session.settings.interaction;
    return ImageNavigationTransition(
      imageKey: transitionKey,
      effect: interaction.transition,
      duration: Duration(milliseconds: interaction.transitionDurationMs),
      direction: _transitionDirection,
      enabled:
          _session.mode == ViewerMode.single ||
          _session.mode == ViewerMode.doublePage,
      child: child,
    );
  }

  Widget _errorView(ImageEntry entry, Object error) {
    _markAutoPlayFailed(entry.id);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTokens.space5),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppImageError(
                title: _l10n.imageParseFailed(entry.name),
                details: error is ImageDecodeFailure
                    ? recentCopy(
                        context,
                        '图片可能已损坏，或格式暂不受支持。可以重试或切换到其他图片。',
                        'The image may be damaged or unsupported. Retry or open another image.',
                      )
                    : localizedErrorMessage(_l10n, error),
              ),
              const SizedBox(height: AppTokens.space4),
              AppButton(
                key: ValueKey('image.retry.${entry.id}'),
                label: _l10n.archiveRetryPage,
                variant: AppButtonVariant.neutral,
                onPressed: () {
                  _resources.invalidate(entry.id);
                  setState(() => _session.markReloaded());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _markAutoPlayFailed(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_disposing && _autoPlayVisibleIds.contains(id)) {
        _autoPlay.pause();
      }
    });
  }

  void _setHdrControlHovered(String name, bool hovered) {
    if (_disposing || !mounted) return;
    if (hovered) {
      _hdrHoveredControls.add(name);
    } else {
      _hdrHoveredControls.remove(name);
    }
    _hdrControlsHovered.value = _hdrHoveredControls.isNotEmpty;
  }

  Widget _hdrControlRegion(String name, Widget child) => MouseRegion(
    onEnter: (_) => _setHdrControlHovered(name, true),
    onExit: (_) => _setHdrControlHovered(name, false),
    child: child,
  );

  Widget _buildMenuBar() =>
      _hdrControlRegion('toolbar', _buildMenuBarContent());

  Widget _buildMenuBarContent() {
    final tokens = ViewerThemeTokens.of(context);
    final entry = _controller.currentEntry;
    final filename = entry?.name ?? _l10n.appTitle;
    final normalMode = !_floatingToolbar;
    final showMenu = normalMode || _showToolbar;
    return MouseRegion(
      key: _topBarRegionKey,
      onEnter: (_) {
        _toolbarPointerInside = true;
        _showToolbarOnEnter();
      },
      onExit: (_) {
        _toolbarPointerInside = false;
        _hideToolbarOnExit();
      },
      child: Focus(
        onKeyEvent: (_, _) {
          _toolbarKeyboardFocus = true;
          _showToolbarOnEnter();
          return KeyEventResult.ignored;
        },
        onFocusChange: (focused) {
          _toolbarFocused = focused;
          if (focused && _toolbarKeyboardFocus) {
            _showToolbarOnEnter();
          } else {
            _hideToolbarOnExit();
          }
        },
        child: Listener(
          onPointerDown: (_) => _toolbarKeyboardFocus = false,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => unawaited(_beginWindowDrag()),
            child: IgnorePointer(
              ignoring: !showMenu,
              child: AnimatedOpacity(
                key: const ValueKey('viewer-top-bar'),
                opacity: showMenu ? 1 : 0,
                duration: AppTokens.panelAnimation,
                child: AppBackdropSurface(
                  // Opacity zero skips painting, while fade-out keeps its
                  // material instead of abruptly switching to an opaque fill.
                  active: !normalMode,
                  child: Container(
                    height: _topBarHeight,
                    foregroundDecoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: tokens.navigationBorder),
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // The bar collapses by measured content width, so new
                        // commands, longer labels or a larger text scale move the
                        // collapse point on their own.
                        final layout = _commandBarLayout =
                            CommandBarLayout.resolve(
                              width: constraints.maxWidth,
                              extents: _commandBarExtents(),
                              commandCount: _topBarCommands().length,
                              previous: _commandBarLayout,
                            );
                        final windowButtons = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildWindowButton(
                              icon: FluentIcons.subtract_16_regular,
                              tooltip: _l10n.minimize,
                              onPressed: windowManager.minimize,
                              flushSquare: true,
                            ),
                            _buildWindowButton(
                              icon: _isMaximized
                                  ? FluentIcons.square_multiple_16_regular
                                  : FluentIcons.square_16_regular,
                              tooltip: _isMaximized
                                  ? _l10n.restore
                                  : _l10n.maximize,
                              onPressed: _toggleMaximized,
                              flushSquare: true,
                            ),
                            _buildWindowButton(
                              icon: FluentIcons.dismiss_16_regular,
                              tooltip: _l10n.close,
                              onPressed: windowManager.close,
                              closeButton: true,
                              flushSquare: true,
                            ),
                          ],
                        );
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            Row(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: _topBarLeadingInset,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    // Keeps a measurement mismatch from clipping a
                                    // command button instead of scrolling.
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: _buildToolbarActions(layout),
                                    ),
                                  ),
                                ),
                                Expanded(child: _buildMaximizeRegion()),
                                Expanded(child: _buildMaximizeRegion()),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildSortControl(
                                      compact: layout.compactSort,
                                    ),
                                    // The pin stays reachable from the context menu
                                    // once the bar hides it.
                                    if (layout.showPin)
                                      _buildWindowButton(
                                        icon: _session.settings.alwaysOnTop
                                            ? FluentIcons.pin_20_filled
                                            : FluentIcons.pin_20_regular,
                                        iconSize: _topBarIconSize,
                                        tooltip: _tooltipLabel(
                                          _session.settings.alwaysOnTop
                                              ? _l10n.cancelAlwaysOnTop
                                              : _l10n.windowAlwaysOnTop,
                                          _binding(ViewerCommand.alwaysOnTop),
                                        ),
                                        onPressed: _toggleAlwaysOnTop,
                                        selected: _session.settings.alwaysOnTop,
                                      ),
                                    windowButtons,
                                  ],
                                ),
                              ],
                            ),
                            // The file name keeps the middle of the bar, so the
                            // command groups grow symmetrically around it.
                            if (layout.showFileName)
                              Align(
                                alignment: Alignment.center,
                                child: _buildMaximizeRegion(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: math.max(
                                        0,
                                        layout.fileNameWidth,
                                      ),
                                    ),
                                    child: Text(
                                      filename,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: _windowChromeColor(tokens),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMaximizeRegion({Widget? child}) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onDoubleTap: _toggleMaximized,
    child: child ?? const SizedBox.expand(),
  );

  void _showTopBarMenu(
    BuildContext triggerContext,
    _TopBarMenuKind kind, {
    List<_TopBarCommand> commands = const [],
  }) {
    if (_topBarMenuEntry != null) {
      final sameMenu = _topBarMenuKind == kind;
      _closeTopBarMenu();
      if (sameMenu) return;
    }
    _closeStatusZoomPanel();
    final button = triggerContext.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(triggerContext, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final topLeft = button.localToGlobal(Offset.zero, ancestor: overlayBox);
    final menuWidth = kind == _TopBarMenuKind.sortOrder
        ? _sortMenuWidth
        : _overflowMenuWidth;
    final itemCount = kind == _TopBarMenuKind.viewMode
        ? ViewerMode.values.length + 1
        : kind == _TopBarMenuKind.sortOrder
        ? _availableSortOrders.length
        : commands.length;
    final menuHeight = itemCount * AppTokens.menuItemHeight + 8.0;
    // The sort panel keeps its right edge on the trigger; the overflow panel
    // grows to the right because it sits at the start of the command bar.
    final anchorLeft = kind == _TopBarMenuKind.sortOrder
        ? topLeft.dx + button.size.width - menuWidth
        : topLeft.dx;
    final left = anchorLeft
        .clamp(8.0, math.max(8.0, overlayBox.size.width - menuWidth - 8.0))
        .toDouble();
    final top =
        (kind == _TopBarMenuKind.viewMode
                ? _topBarHeight + 6.0
                : topLeft.dy + button.size.height + 6.0)
            .clamp(
              8.0,
              math.max(8.0, overlayBox.size.height - menuHeight - 8.0),
            )
            .toDouble();
    final children = kind == _TopBarMenuKind.viewMode
        ? _viewModeMenuChildren()
        : kind == _TopBarMenuKind.sortOrder
        ? _sortMenuChildren()
        : _commandMenuChildren(commands);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                if ((event.buttons & kSecondaryMouseButton) != 0) {
                  unawaited(_showContextMenu(event.position));
                } else {
                  _closeTopBarMenu();
                }
              },
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: menuWidth,
            child: GestureDetector(
              onTap: () {},
              child: Material(
                color: ViewerThemeTokens.of(context).surfaceElevated,
                elevation: 8,
                shadowColor: AppControlStyles.menuShadow(
                  ViewerThemeTokens.of(context),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.menuRadius),
                  side: BorderSide(color: ViewerThemeTokens.of(context).border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.space1),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    _topBarMenuEntry = entry;
    _topBarMenuKind = kind;
    overlay.insert(entry);
    if (mounted) setState(() {});
  }

  List<Widget> _commandMenuChildren(List<_TopBarCommand> commands) => [
    for (final command in commands)
      _menuItem(
        command.label == _viewModeTooltip ? _l10n.viewMode : command.label,
        command.onPressed ?? () {},
        leading: Icon(
          command.icon,
          color: command.onPressed == null
              ? ViewerThemeTokens.of(context).textDisabled
              : null,
        ),
        shortcut: command.shortcut?.displayLabel(
          platform: Theme.of(context).platform,
        ),
        enabled: command.onPressed != null,
      ),
  ];

  void _selectSortOrder(SortOrder order) {
    _closeTopBarMenu();
    if (_controller.isArchiveView) {
      if (order == _session.settings.archiveSortOrder) return;
      unawaited(
        _applySettings(_session.settings.copyWith(archiveSortOrder: order)),
      );
      return;
    }
    if (order == _session.settings.sortOrder) return;
    unawaited(_applySettings(_session.settings.copyWith(sortOrder: order)));
  }

  void _closeTopBarMenu() {
    final entry = _topBarMenuEntry;
    final wasOpen = entry != null;
    _topBarMenuEntry = null;
    _topBarMenuKind = null;
    entry?.remove();
    entry?.dispose();
    if (wasOpen && mounted) setState(() {});
    if (wasOpen) _hideToolbarOnExit();
  }

  Widget _buildSortControl({required bool compact}) {
    if (compact) {
      return Builder(
        builder: (buttonContext) => _buildWindowButton(
          // A dedicated sort icon keeps the compact trigger distinguishable from
          // the command overflow trigger when both are visible.
          icon: FluentIcons.arrow_sort_20_regular,
          iconSize: _topBarIconSize,
          tooltip: _l10n.viewOrder,
          onPressed: () =>
              _showTopBarMenu(buttonContext, _TopBarMenuKind.sortOrder),
        ),
      );
    }
    return Flexible(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 96),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Builder(
            builder: (buttonContext) => AppActionButton(
              onPressed: () =>
                  _showTopBarMenu(buttonContext, _TopBarMenuKind.sortOrder),
              style: AppControlStyles.sortTrigger(
                ViewerThemeTokens.of(context),
                size: _topBarControlSize,
                foregroundColor: _windowChromeColor(
                  ViewerThemeTokens.of(context),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _l10n.viewOrder,
                        maxLines: 1,
                        style: AppTextStyles.bodySmall,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _topBarMenuKind == _TopBarMenuKind.sortOrder
                        ? 0.5
                        : 0,
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    child: const Icon(
                      FluentIcons.chevron_down_16_regular,
                      size: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWindowButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool closeButton = false,
    bool flushSquare = false,
    bool selected = false,
    double iconSize = 15,
  }) {
    final tokens = ViewerThemeTokens.of(context);
    final chromeColor = _windowChromeColor(tokens);
    return SizedBox(
      width: flushSquare ? _topBarFlushControlSize : _topBarControlSize,
      height: flushSquare ? _topBarFlushControlSize : _topBarControlSize,
      child: AppIconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        iconWidget: Icon(icon, size: iconSize),
        style: AppControlStyles.windowIcon(
          tokens,
          size: flushSquare ? _topBarFlushControlSize : _topBarControlSize,
          chromeColor: chromeColor,
          flushSquare: flushSquare,
          closeButton: closeButton,
          selected: selected,
        ),
      ),
    );
  }

  Color _windowChromeColor(ViewerThemeTokens tokens) =>
      tokens.textPrimary.withValues(alpha: _windowFocused ? 1 : 0.68);

  ButtonStyle _toolbarButtonStyle({bool selected = false}) {
    final tokens = ViewerThemeTokens.of(context);
    return AppControlStyles.toolbarIcon(
      tokens,
      size: _topBarControlSize,
      selected: selected,
    );
  }

  Widget _buildToolbarIconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    bool selected = false,
  }) {
    return AppIconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconWidget: Icon(icon, size: _topBarIconSize),
      style: _toolbarButtonStyle(selected: selected),
    );
  }

  String _tooltipLabel(String label, ViewerShortcutBinding? shortcut) {
    if (shortcut == null) return label;
    return '$label · ${shortcut.displayLabel(platform: Theme.of(context).platform)}';
  }

  /// Command slots that keep their own icon before the rest collapse into the
  /// overflow menu. The last visible slot is always given to the overflow
  /// trigger, so the bar never scrolls or clips at small window widths.
  /// Natural widths of the command bar groups for the current content.
  ///
  /// The labelled sort control is measured with the live label and text scale;
  /// icon buttons reuse the tap-target aware metrics of the real widgets.
  CommandBarExtents _commandBarExtents() {
    final labelWidth = measureBarLabelWidth(
      context,
      _l10n.viewOrder,
      AppTextStyles.bodySmall,
    );
    final sortLabel =
        math.min(
          _sortLabelMaxWidth,
          math.max(_topBarControlSize, labelWidth + _sortLabelChrome - 4),
        ) +
        4;
    return CommandBarExtents(
      leadingInset: _topBarLeadingInset,
      commandButton: barIconButtonExtent(context, size: _topBarControlSize),
      sortLabel: sortLabel,
      sortCompact: _topBarControlSize,
      pin: _topBarControlSize,
      windowControls: _topBarFlushControlSize * 3,
    );
  }

  List<_TopBarCommand> _topBarCommands() {
    final hasEntry = _controller.currentEntry != null;
    return [
      (
        label: _l10n.rotateClockwise,
        icon: FluentIcons.arrow_rotate_clockwise_20_regular,
        onPressed: hasEntry
            ? (_gridVisible
                  ? () => unawaited(_gridAction(_rotateDisplay))
                  : _rotateDisplay)
            : null,
        shortcut: _binding(ViewerCommand.rotate),
      ),
      (
        label: _l10n.flipHorizontally,
        icon: FluentIcons.flip_horizontal_20_regular,
        onPressed: hasEntry
            ? (_gridVisible
                  ? () => unawaited(_gridAction(_toggleHorizontalFlip))
                  : _toggleHorizontalFlip)
            : null,
        shortcut: _binding(ViewerCommand.flip),
      ),
      (
        label: _l10n.print,
        icon: FluentIcons.print_20_regular,
        onPressed: hasEntry
            ? (_gridVisible
                  ? () => unawaited(_gridAction(_printCurrent))
                  : _printCurrent)
            : null,
        shortcut: _binding(ViewerCommand.print),
      ),
      (
        label: _autoPlay.playing ? _l10n.autoPlayPause : _l10n.autoPlayStart,
        icon: _autoPlay.playing
            ? FluentIcons.pause_20_regular
            : FluentIcons.play_20_regular,
        onPressed: hasEntry
            ? () {
                _closeTopBarMenu();
                _toggleAutoPlay();
              }
            : null,
        shortcut: _binding(ViewerCommand.autoPlay),
      ),
      if (_autoPlay.active)
        (
          label: _l10n.autoPlayStop,
          icon: FluentIcons.stop_20_regular,
          onPressed: () {
            _closeTopBarMenu();
            _autoPlay.stop();
          },
          shortcut: _binding(ViewerCommand.stopAutoPlay),
        ),
      (
        label: _colorPickerLabel,
        icon: FluentIcons.eyedropper_20_regular,
        onPressed: hasEntry && !_gridVisible ? _toggleColorPicker : null,
        shortcut: _binding(ViewerCommand.colorPicker),
      ),
      (
        label: _viewModeTooltip,
        icon: _viewModeIcon,
        onPressed: () => _showTopBarMenu(context, _TopBarMenuKind.viewMode),
        shortcut: null,
      ),
      (
        label: _isBorderless ? _l10n.exitBorderless : _l10n.enterBorderless,
        icon: FluentIcons.window_20_regular,
        onPressed: _toggleBorderless,
        shortcut: _binding(ViewerCommand.borderless),
      ),
    ];
  }

  Widget _buildToolbarActions(CommandBarLayout layout) {
    final commands = _topBarCommands();
    final slots = layout.commandSlots;
    final overflow = commands.length > slots;
    var visibleCount = overflow ? slots - 1 : commands.length;
    // Keep playback and stop together when the bar folds into its menu.
    if (_autoPlay.active &&
        overflow &&
        visibleCount > 0 &&
        commands[visibleCount - 1].label ==
            (_autoPlay.playing ? _l10n.autoPlayPause : _l10n.autoPlayStart)) {
      visibleCount--;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final command in commands.take(visibleCount))
          Builder(
            builder: (buttonContext) => _buildToolbarIconButton(
              tooltip: _tooltipLabel(command.label, command.shortcut),
              icon: command.icon,
              onPressed: command.label == _viewModeTooltip
                  ? () =>
                        _showTopBarMenu(buttonContext, _TopBarMenuKind.viewMode)
                  : command.onPressed,
            ),
          ),
        if (overflow)
          Builder(
            builder: (buttonContext) => _buildToolbarIconButton(
              tooltip: _l10n.moreActions,
              icon: FluentIcons.more_horizontal_20_regular,
              selected: _topBarMenuKind == _TopBarMenuKind.commandOverflow,
              onPressed: () => _showTopBarMenu(
                buttonContext,
                _TopBarMenuKind.commandOverflow,
                commands: commands.skip(visibleCount).toList(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBottomStatusBar() {
    final tokens = ViewerThemeTokens.of(context);
    return _hdrControlRegion(
      'status',
      Container(
        key: const ValueKey('viewer.statusSurface'),
        color: tokens.navigationSurface,
        foregroundDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: tokens.navigationBorder)),
        ),
        child: _buildBottomStatusBarContent(),
      ),
    );
  }

  Widget _buildBottomStatusBarContent() {
    if (_gridVisible) return _buildGridStatusBar();
    final entry = _controller.currentEntry;
    final tokens = ViewerThemeTokens.of(context);
    return Container(
      height: _bottomStatusBarHeight,
      decoration: BoxDecoration(color: tokens.navigationSurface),
      child: FutureBuilder<ImageMetadata>(
        future: _metadataFuture,
        initialData: entry == null ? null : _resources.cachedMetadata(entry),
        builder: (context, snapshot) {
          final metadata = snapshot.data;
          final dimensions =
              metadata == null || metadata.width <= 0 || metadata.height <= 0
              ? ''
              : '${metadata.width} × ${metadata.height}';
          return LayoutBuilder(
            builder: (context, constraints) {
              final statusBarWidth = constraints.maxWidth;
              final layout = _statusBarLayout = StatusBarLayout.resolve(
                width: statusBarWidth,
                extents: _statusBarExtents(
                  context: context,
                  entry: entry,
                  dimensions: dimensions,
                  tokens: tokens,
                ),
                previous: _statusBarLayout,
              );
              final showMetadata = layout.showMetadata && entry != null;
              final showZoomControls = layout.showZoomControls;
              final showScaleModes = layout.showScaleModes;
              if (showZoomControls &&
                  _statusZoomEntry != null &&
                  _statusZoomHasControls) {
                // The popover trigger disappeared because the bar grew wide
                // enough to show the inline cluster again.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _closeStatusZoomPanel();
                });
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  height: _bottomStatusBarHeight,
                  child: Center(
                    child: SizedBox(
                      height: _bottomBarButtonSize,
                      width: double.infinity,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                if (!showMetadata) ...[
                                  Flexible(child: _buildDirectoryToggle()),
                                  Flexible(child: _buildThumbnailToggle()),
                                ] else ...[
                                  _buildDirectoryToggle(),
                                  _buildThumbnailToggle(),
                                  Flexible(
                                    child: _buildStatusMetadata(
                                      entry: entry,
                                      dimensions: dimensions,
                                      tokens: tokens,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // Both sides share whatever the middle leaves over, so
                          // the info toggle stays exactly in the bar's center.
                          _buildBottomIconButton(
                            tooltip: _tooltipLabel(
                              _infoVisible ? _l10n.hideInfo : _l10n.showInfo,
                              _binding(ViewerCommand.toggleInfo),
                            ),
                            onPressed: _toggleInfoPanel,
                            iconWidget: _buildBottomInfoIcon(
                              size: _bottomBarIconSize,
                            ),
                          ),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (showScaleModes) ...[
                                  _buildScaleButton(
                                    tooltip: _tooltipLabel(
                                      _l10n.zoomToWindow,
                                      _binding(ViewerCommand.autoFit),
                                    ),
                                    icon: _buildBottomVectorIcon(
                                      _BottomVectorIconKind.fitToWindow,
                                      size: _scaleButtonIconSize,
                                    ),
                                    onPressed: () =>
                                        _setScaleMode(ViewScaleMode.autoFit),
                                  ),
                                  _buildScaleButton(
                                    tooltip: _tooltipLabel(
                                      _actualSizeLabel,
                                      _binding(ViewerCommand.actualSize),
                                    ),
                                    icon: _buildBottomVectorIcon(
                                      _BottomVectorIconKind.actualSize,
                                      size: _scaleButtonIconSize,
                                    ),
                                    onPressed: () => _setScaleMode(
                                      ViewScaleMode.originalSize,
                                    ),
                                  ),
                                  _buildStatusDivider(tokens),
                                ],
                                if (showZoomControls)
                                  _buildZoomControls()
                                else
                                  Builder(
                                    builder: (buttonContext) =>
                                        _buildStatusMoreButton(buttonContext),
                                  ),
                                ...[
                                  _buildStatusDivider(tokens),
                                  if (layout.showFullscreen)
                                    _buildBottomIconButton(
                                      tooltip: _tooltipLabel(
                                        _isFullscreen
                                            ? _l10n.exitFullscreen
                                            : _l10n.fullscreen,
                                        _binding(ViewerCommand.fullscreen),
                                      ),
                                      onPressed: _toggleFullscreen,
                                      icon: _isFullscreen
                                          ? FluentIcons
                                                .full_screen_minimize_20_regular
                                          : FluentIcons
                                                .full_screen_maximize_20_regular,
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Natural widths of the status bar groups for the current content.
  ///
  /// Buttons reuse the tap-target aware metrics of the real widgets and the
  /// three file facts are measured with the live text style and text scale, so
  /// the bar collapses because the content no longer fits, not because the
  /// window crossed a hand-tuned width.
  StatusBarExtents _statusBarExtents({
    required BuildContext context,
    required ImageEntry? entry,
    required String dimensions,
    required ViewerThemeTokens tokens,
  }) {
    final button = barIconButtonExtent(
      context,
      size: _bottomBarButtonSize,
      horizontalPadding: 2,
    );
    final divider = AppTokens.space2 * 2 + 1;
    return StatusBarExtents(
      // Matches the padding of the status bar container.
      horizontalInset: AppTokens.space2 * 2,
      directoryToggle: button,
      thumbnailToggle: button,
      metadata: entry == null
          ? 0
          : _statusMetadataWidth(
              context,
              entry: entry,
              dimensions: dimensions,
              style: _statusTextStyle(tokens),
              divider: divider,
            ),
      infoToggle: button,
      divider: divider,
      scaleModes: button * 2 + divider,
      zoomCluster: _zoomSliderWidth + button * 2 + 72,
      zoomTrigger: button,
      fullscreen: button,
    );
  }

  /// Format, dimensions and byte size as one left section, including the gaps
  /// and separators the metadata row renders.
  double _statusMetadataWidth(
    BuildContext context, {
    required ImageEntry entry,
    required String dimensions,
    required TextStyle style,
    required double divider,
  }) {
    final l10n = AppLocalizations.of(context)!;
    var width =
        6 +
        measureBarLabelWidth(
          context,
          localizedFormatLabel(l10n, entry.format),
          style,
        );
    if (dimensions.isNotEmpty) {
      width += divider + measureBarLabelWidth(context, dimensions, style);
    }
    return width +
        divider +
        measureBarLabelWidth(context, _formatBytes(entry.byteLength), style);
  }

  TextStyle _statusTextStyle(ViewerThemeTokens tokens) =>
      AppTextStyles.label.copyWith(color: tokens.textSecondary);

  /// Format, dimensions and byte size of the current image. Every text is
  /// flexible so an unusually long value is ellipsized instead of overflowing
  /// the left section.
  Widget _buildStatusMetadata({
    required ImageEntry entry,
    required String dimensions,
    required ViewerThemeTokens tokens,
  }) {
    final style = _statusTextStyle(tokens);
    Widget label(String text) =>
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 6),
        label(localizedFormatLabel(_l10n, entry.format)),
        if (dimensions.isNotEmpty) ...[
          _buildStatusDivider(tokens),
          // Only the dimensions shrink, and only when they are the last field
          // that no longer fits; the format and the byte size stay readable.
          Flexible(child: label(dimensions)),
        ],
        _buildStatusDivider(tokens),
        label(_formatBytes(entry.byteLength)),
      ],
    );
  }

  Widget _buildStatusMoreButton(BuildContext buttonContext) =>
      _buildBottomIconButton(
        tooltip: _l10n.moreZoomOptions,
        onPressed: () => _showStatusZoomPanel(buttonContext),
        icon: FluentIcons.more_horizontal_20_regular,
        selected: _statusZoomEntry != null,
      );

  /// Popover that replaces the zoom cluster on narrow windows. It opens above
  /// its trigger and shares the sizing commands with the percentage menu.
  void _showStatusZoomPanel(
    BuildContext triggerContext, {
    bool showZoomControls = true,
  }) {
    if (_statusZoomEntry != null) {
      _closeStatusZoomPanel();
      return;
    }
    _closeTopBarMenu();
    final button = triggerContext.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(triggerContext, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final topLeft = button.localToGlobal(Offset.zero, ancestor: overlayBox);
    final left = (topLeft.dx + button.size.width - _statusZoomPanelWidth)
        .clamp(
          8.0,
          math.max(8.0, overlayBox.size.width - _statusZoomPanelWidth - 8.0),
        )
        .toDouble();
    final bottom = overlayBox.size.height - topLeft.dy + 6.0;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                if ((event.buttons & kSecondaryMouseButton) != 0) {
                  unawaited(_showContextMenu(event.position));
                } else {
                  _closeStatusZoomPanel();
                }
              },
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: left,
            bottom: bottom,
            width: _statusZoomPanelWidth,
            child: GestureDetector(
              onTap: () {},
              child: Material(
                color: ViewerThemeTokens.of(context).surfaceElevated,
                elevation: 8,
                shadowColor: AppColors.shadow.withValues(alpha: 0.28),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.menuRadius),
                  side: BorderSide(color: ViewerThemeTokens.of(context).border),
                ),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: math.max(
                      80,
                      overlayBox.size.height - bottom - 8,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: _buildStatusZoomPanel(
                      showZoomControls: showZoomControls,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    _statusZoomEntry = entry;
    _statusZoomHasControls = showZoomControls;
    overlay.insert(entry);
    if (mounted) setState(() {});
  }

  Widget _buildStatusZoomPanel({required bool showZoomControls}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppTokens.space1),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ..._scaleModeMenuChildren(),
        if (showZoomControls) _menuDivider(),
        if (showZoomControls)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.space3,
              vertical: 5,
            ),
            child: _buildZoomControls(showSizingTrigger: false),
          ),
      ],
    ),
  );

  void _closeStatusZoomPanel() {
    final entry = _statusZoomEntry;
    if (entry == null) return;
    _statusZoomEntry = null;
    _statusZoomHasControls = false;
    // The slider moves back into the status bar, so its hover tooltip must not
    // outlive the panel that hosted it.
    _setZoomSliderHovered(false);
    entry.remove();
    entry.dispose();
    if (mounted) setState(() {});
  }

  Widget _buildDirectoryToggle() => Semantics(
    key: const ValueKey('navigation.directory'),
    toggled: _directoryIsShown,
    child: _buildBottomIconButton(
      tooltip: _tooltipLabel(
        _directoryIsShown ? _l10n.hideDirectoryPanel : _l10n.showDirectoryPanel,
        _binding(ViewerCommand.toggleDirectory),
      ),
      icon: _directoryIsShown
          ? FluentIcons.panel_left_20_filled
          : FluentIcons.panel_left_20_regular,
      selected: _directoryIsShown,
      onPressed: _toggleDirectoryPanel,
    ),
  );

  Widget _buildThumbnailToggle() => _buildBottomIconButton(
    key: const ValueKey('navigation.thumbnails'),
    tooltip: _tooltipLabel(
      _thumbnailsVisible ? _l10n.hideThumbnails : _l10n.showThumbnails,
      _binding(ViewerCommand.toggleThumbnails),
    ),
    onPressed: _toggleThumbnails,
    iconWidget: _buildBottomVectorIcon(
      _thumbnailsVisible
          ? _BottomVectorIconKind.thumbnailBarVisible
          : _BottomVectorIconKind.thumbnailBarHidden,
      size: _scaleButtonIconSize,
    ),
  );

  Widget _buildBottomIconButton({
    Key? key,
    required String tooltip,
    IconData? icon,
    Widget? iconWidget,
    required VoidCallback? onPressed,
    double iconSize = _bottomBarIconSize,
    bool selected = false,
    bool repeatOnHold = false,
  }) {
    final button = repeatOnHold
        ? AppRepeatIconButton(
            tooltip: tooltip,
            icon: icon!,
            iconSize: iconSize,
            onPressed: onPressed,
            style: _bottomBarButtonStyle(selected: selected),
          )
        : AppIconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            iconWidget: iconWidget ?? Icon(icon!, size: iconSize),
            style: _bottomBarButtonStyle(selected: selected),
          );
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: button,
    );
  }

  Widget _buildBottomInfoIcon({required double size}) => Builder(
    builder: (context) {
      final color =
          IconTheme.of(context).color ??
          ViewerThemeTokens.of(context).textPrimary;
      return Image.asset(
        'assets/ui/info.png',
        width: size,
        height: size,
        color: color,
        colorBlendMode: BlendMode.srcIn,
        excludeFromSemantics: true,
      );
    },
  );

  Widget _buildBottomVectorIcon(
    _BottomVectorIconKind kind, {
    required double size,
  }) => Builder(
    builder: (context) {
      final color =
          IconTheme.of(context).color ??
          ViewerThemeTokens.of(context).textPrimary;
      return CustomPaint(
        size: Size.square(size),
        painter: _BottomVectorIconPainter(kind: kind, color: color),
      );
    },
  );

  ButtonStyle _bottomBarButtonStyle({bool selected = false}) {
    final tokens = ViewerThemeTokens.of(context);
    return AppControlStyles.bottomIcon(
      tokens,
      size: _bottomBarButtonSize,
      selected: selected,
    );
  }

  Widget _buildScaleButton({
    required String tooltip,
    required Widget icon,
    required VoidCallback onPressed,
  }) => _buildBottomIconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    iconWidget: icon,
  );

  Widget _buildStatusDivider(ViewerThemeTokens tokens) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: SizedBox(
      height: 14,
      width: 1,
      child: ColoredBox(color: tokens.border),
    ),
  );

  Widget _buildZoomControls({bool showSizingTrigger = true}) => AnimatedBuilder(
    animation: Listenable.merge([_transformController, _zoomReferenceChanges]),
    builder: (context, child) {
      final scale = _currentZoomScale();
      final canZoomOut = scale > _minZoomScale + 0.0001;
      final canZoomIn = scale < _maxZoomScale - 0.0001;
      final tokens = ViewerThemeTokens.of(context);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSizingTrigger)
            Builder(
              builder: (buttonContext) => Tooltip(
                message: _l10n.zoomMode,
                child: AppActionButton(
                  key: const ValueKey('viewer.zoomMenu'),
                  onPressed: () => _showStatusZoomPanel(
                    buttonContext,
                    showZoomControls: false,
                  ),
                  style: AppControlStyles.statusZoom(tokens),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _zoomPercentLabel(scale),
                        style: AppTextStyles.label,
                      ),
                      const Icon(FluentIcons.chevron_down_16_regular, size: 12),
                    ],
                  ),
                ),
              ),
            ),
          _buildBottomIconButton(
            tooltip: _tooltipLabel(
              _l10n.zoomOut,
              _binding(ViewerCommand.zoomOut),
            ),
            onPressed: canZoomOut ? _zoomOut : null,
            icon: FluentIcons.zoom_out_20_regular,
            repeatOnHold: true,
          ),
          _buildZoomSlider(scale: scale, tokens: tokens),
          _buildBottomIconButton(
            tooltip: _tooltipLabel(
              _l10n.zoomIn,
              _binding(ViewerCommand.zoomIn),
            ),
            onPressed: canZoomIn ? _zoomIn : null,
            icon: FluentIcons.zoom_in_20_regular,
            repeatOnHold: true,
          ),
        ],
      );
    },
  );

  Widget _buildZoomSlider({
    required double scale,
    required ViewerThemeTokens tokens,
  }) {
    final sliderValue = _scaleToSlider(scale);
    final thumbPosition = _zoomSliderThumbPosition(scale);
    return SizedBox(
      width: _zoomSliderWidth,
      child: OverlayPortal(
        controller: _zoomSliderTooltipController,
        overlayChildBuilder: (context) => UnconstrainedBox(
          alignment: Alignment.topLeft,
          child: CompositedTransformFollower(
            link: _zoomSliderLayerLink,
            targetAnchor: Alignment.center,
            followerAnchor: Alignment.bottomCenter,
            offset: const Offset(0, -14),
            showWhenUnlinked: false,
            child: SizedBox(
              width: 44,
              height: 22,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadow.withValues(alpha: 0.20),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _zoomPercentLabel(scale),
                      style: AppTextStyles.finePrint.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (event) =>
              _updateZoomSliderHover(event.localPosition.dx, scale),
          onHover: (event) =>
              _updateZoomSliderHover(event.localPosition.dx, scale),
          onExit: (_) => _setZoomSliderHovered(false),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerHover: (event) =>
                _updateZoomSliderHover(event.localPosition.dx, scale),
            onPointerDown: (event) => _onZoomSliderPointerDown(event, scale),
            onPointerMove: _onZoomSliderPointerMove,
            onPointerUp: _onZoomSliderPointerUp,
            onPointerCancel: (_) => _resetZoomSliderPointer(),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AppSlider(
                  variant: AppSliderVariant.zoom,
                  value: sliderValue,
                  min: 0,
                  max: 1,
                  label: _zoomPercentLabel(scale),
                  semanticFormatterCallback: (value) =>
                      _zoomPercentLabel(_sliderToScale(value)),
                  onChanged: _setZoomSlider,
                ),
                Positioned(
                  left: thumbPosition - 0.5,
                  top: 16,
                  child: CompositedTransformTarget(
                    link: _zoomSliderLayerLink,
                    child: const SizedBox(width: 1, height: 1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setZoomSlider(double value) {
    if (_zoomSliderStartedOnThumb && !_zoomSliderPointerMoved) return;
    final targetScale = _sliderToScale(value);
    if ((targetScale - _currentZoomScale()).abs() < 0.0001) return;
    _requestScale(targetScale);
  }

  void _requestScale(double scale) {
    _autoPlay.pause();
    final matrixScale = scale / _zoomReferenceScale;
    _viewportCommands.setScale(
      matrixScale
          .clamp(_matrixMinZoomScale(), _matrixMaxZoomScale())
          .toDouble(),
    );
  }

  double _scaleToSlider(double scale) =>
      (math.log(scale.clamp(_minZoomScale, _maxZoomScale) / _minZoomScale) /
              math.log(_maxZoomScale / _minZoomScale))
          .clamp(0, 1);

  double _sliderToScale(double value) => math.exp(
    math.log(_minZoomScale) +
        value.clamp(0, 1) * math.log(_maxZoomScale / _minZoomScale),
  );

  double _currentZoomScale() =>
      (_transformController.value.getMaxScaleOnAxis() * _zoomReferenceScale)
          .clamp(_minZoomScale, _maxZoomScale)
          .toDouble();

  Size rotatedContent(Size size) => _session.rotationQuarterTurns.isOdd
      ? Size(size.height, size.width)
      : size;

  Matrix4? _entryTransformForLayout(
    Size viewport,
    Size content,
    double referenceScale, {
    required bool startAtTop,
    required bool startAtLeft,
    required bool metadataReady,
  }) {
    _lastContentSize = content;
    _lastViewportSize = viewport;
    final readingAnchor = _readingRestoreAnchor;
    if (readingAnchor != null) {
      if (metadataReady) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_readingRestoreAnchor == readingAnchor) {
            _readingRestoreAnchor = null;
          }
        });
      }
      return Matrix4.identity()..setTranslationRaw(
        viewport.width / 2 - readingAnchor.dx * content.width,
        viewport.height / 2 - readingAnchor.dy * content.height,
        0,
      );
    }
    final pending = _pendingEntryView;
    if (pending == null) return null;
    final scale = pending.scale / referenceScale;
    final anchor = pending.anchor;
    final offset = anchor == null
        ? Offset(
            startAtLeft ? 0 : (viewport.width - content.width * scale) / 2,
            startAtTop ? 0 : (viewport.height - content.height * scale) / 2,
          )
        : Offset(
            viewport.width / 2 - anchor.dx * content.width * scale,
            viewport.height / 2 - anchor.dy * content.height * scale,
          );
    if (metadataReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pendingEntryView == pending) _pendingEntryView = null;
      });
    }
    return Matrix4.identity()
      ..scaleByDouble(scale, scale, scale, 1)
      ..setTranslationRaw(offset.dx, offset.dy, 0);
  }

  void _setZoomReferenceScale(double scale, {bool preserveScale = true}) {
    final next = scale.isFinite && scale > 0 ? scale : 1.0;
    final previous = _zoomReferenceScale;
    _zoomReferenceScale = next;
    if (_zoomReferenceChanges.value != next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _zoomReferenceChanges.value = _zoomReferenceScale;
      });
    }
    if (_resettingScale) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resettingScale = false;
      });
      return;
    }
    if (!preserveScale) return;
    if (_pendingEntryView != null) return;
    if (!mounted || (next - previous).abs() < 0.000001) return;

    // Fit-to-window changes the content's reference scale when the viewport
    // is resized. Once the user has manually zoomed, preserve the actual
    // scale relative to the source image instead of changing the zoom value
    // as a side effect of the window resize.
    final matrixScale = _transformController.value.getMaxScaleOnAxis();
    if ((matrixScale - 1).abs() < 0.0001 &&
        !_session.settings.interaction.keepZoom) {
      return;
    }
    _pendingZoomReferenceActualScale ??= matrixScale * previous;
    if (_zoomReferenceAdjustmentScheduled) return;
    _zoomReferenceAdjustmentScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _zoomReferenceAdjustmentScheduled = false;
      if (!mounted) return;
      final actualScale = _pendingZoomReferenceActualScale;
      _pendingZoomReferenceActualScale = null;
      if (actualScale == null) return;
      _viewportCommands.setScale(actualScale / _zoomReferenceScale);
    });
  }

  // Fit is the baseline of every mode: a tiny image can be displayed far above
  // its native size, and a huge image far below it. Keep matrix scale 1 inside
  // the limits so the first pan does not clamp a fitted image to the
  // source-pixel zoom range.
  double _matrixMinZoomScale() =>
      math.min(1.0, _minZoomScale / _zoomReferenceScale);

  double _matrixMaxZoomScale() =>
      math.max(1.0, _maxZoomScale / _zoomReferenceScale);

  String _zoomPercentLabel(double scale) => '${(scale * 100).round()}%';

  void _zoomOut() {
    final scale = _currentZoomScale();
    if (scale <= _minZoomScale + 0.0001) return;
    _requestScale(scale / 1.15);
  }

  void _zoomIn() {
    final scale = _currentZoomScale();
    if (scale >= _maxZoomScale - 0.0001) return;
    _requestScale(scale * 1.15);
  }

  void _setZoomSliderHovered(bool hovered) {
    if (_zoomSliderHovered == hovered || !mounted) return;
    setState(() => _zoomSliderHovered = hovered);
    if (hovered) {
      _zoomSliderTooltipController.show();
    } else {
      _zoomSliderTooltipController.hide();
    }
  }

  void _updateZoomSliderHover(double pointerX, double scale) {
    final thumbX = _zoomSliderThumbPosition(scale);
    _setZoomSliderHovered((pointerX - thumbX).abs() <= _zoomSliderHoverRadius);
  }

  void _onZoomSliderPointerDown(PointerDownEvent event, double scale) {
    _zoomSliderPointerDownX = event.localPosition.dx;
    _zoomSliderPointerMoved = false;
    final thumbX = _zoomSliderThumbPosition(scale);
    _zoomSliderStartedOnThumb =
        (event.localPosition.dx - thumbX).abs() <= _zoomSliderHoverRadius;
    _setZoomSliderHovered(_zoomSliderStartedOnThumb);
    if (!_zoomSliderStartedOnThumb) {
      _setZoomSlider(_zoomSliderValueAt(event.localPosition.dx));
    }
  }

  void _onZoomSliderPointerMove(PointerMoveEvent event) {
    final downX = _zoomSliderPointerDownX;
    if (downX == null) return;
    if ((event.localPosition.dx - downX).abs() <= 1) return;
    _zoomSliderPointerMoved = true;
    _setZoomSliderHovered(true);
    _setZoomSlider(_zoomSliderValueAt(event.localPosition.dx));
  }

  void _onZoomSliderPointerUp(PointerUpEvent event) {
    _updateZoomSliderHover(event.localPosition.dx, _currentZoomScale());
    _resetZoomSliderPointer();
  }

  void _resetZoomSliderPointer() {
    _zoomSliderPointerDownX = null;
    _zoomSliderPointerMoved = false;
    _zoomSliderStartedOnThumb = false;
  }

  double _zoomSliderThumbPosition(double scale) =>
      _zoomSliderThumbRadius +
      _scaleToSlider(scale) * (_zoomSliderWidth - _zoomSliderThumbRadius * 2);

  double _zoomSliderValueAt(double pointerX) =>
      ((pointerX - _zoomSliderThumbRadius) /
              (_zoomSliderWidth - _zoomSliderThumbRadius * 2))
          .clamp(0, 1);

  Widget _buildBottomBar() => _hdrControlRegion(
    'thumbnails',
    ViewerBottomBar(
      shortcuts: _shortcuts,
      controller: _controller,
      resources: _resources,
      mode: _session.mode,
      parentFolderPath: _controller.parentFolderPath,
      onOpenFolder: _openFolderPath,
      onOpenChapter: (path) => unawaited(_openChapterPath(path)),
      onOpenArchive: _openArchiveEntry,
      onCancelArchiveOpening: _controller.cancelArchiveOpen,
      onSelect: _select,
      showFileNames: _session.settings.showThumbnailFileNames,
      viewportVisible: _thumbnailsVisible && _session.settings.showBottomBar,
      interaction: _session.settings.interaction,
      onNavigate: _move,
    ),
  );

  Widget _edgeButton(IconData icon, int offset) {
    final anchor = _pendingSelectionIndex ?? _controller.currentIndex;
    final target =
        anchor +
        (_session.mode == ViewerMode.doublePage
            ? _doublePageStep(offset)
            : offset);
    final canMove =
        anchor >= 0 &&
        ((target >= 0 &&
                target < _controller.entries.length &&
                target != anchor) ||
            (_session.settings.archiveAutoAdvance &&
                _controller.isArchiveView &&
                _controller.adjacentArchive(offset) != null));
    final tokens = ViewerThemeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: AppRepeatIconButton(
        tooltip: offset < 0 ? _l10n.previousImage : _l10n.nextImage,
        icon: icon,
        iconSize: 20,
        activateOnPress: true,
        canRepeat: () =>
            _windowFocused &&
            _focusNode.hasFocus &&
            (ModalRoute.of(context)?.isCurrent ?? true) &&
            !_contextMenuOpen &&
            _topBarMenuEntry == null,
        repeatEnabled: _session.settings.interaction.holdNavigation,
        repeatDelay: Duration(
          milliseconds: _session.settings.interaction.holdDelayMs,
        ),
        repeatInterval: Duration(
          milliseconds: _session.settings.interaction.holdIntervalMs,
        ),
        onPressed: canMove && _windowFocused ? () => _move(offset) : null,
        style: AppControlStyles.edgeNavigation(tokens, isDark: isDark),
      ),
    );
  }

  Widget _buildImageRegion(
    ImageEntry? entry, {
    required List<Widget> navigation,
    required double thumbnailHeight,
    required bool showThumbnails,
  }) => GestureDetector(
    key: const ValueKey('viewer.content'),
    behavior: HitTestBehavior.opaque,
    onSecondaryTapUp: (details) {
      if (!_gridVisible) _showContextMenu(details.globalPosition);
    },
    child: _showingRecentOpen
        ? Padding(
            padding: EdgeInsets.only(top: _floatingToolbar ? _topBarHeight : 0),
            child: RecentOpenPage(
              key: ValueKey(('recent.welcome', _recentOpenGeneration)),
              store: _controller.recentOpen,
              enabled: _session.settings.recentOpenEnabled,
              limit: _session.settings.recentOpenLimit,
              beforeLoad: _controller.flushPersistence,
              onOpenPath: _openPath,
              onOpenFile: _openFile,
              onOpenFolder: _openFolder,
              onBack: _controller.folderPath == null
                  ? null
                  : () => setState(() => _showingRecentOpen = false),
            ),
          )
        : _buildReadingRegion(
            entry,
            navigation: navigation,
            thumbnailHeight: thumbnailHeight,
            showThumbnails: showThumbnails,
          ),
  );

  Widget _buildReadingRegion(
    ImageEntry? entry, {
    required List<Widget> navigation,
    required double thumbnailHeight,
    required bool showThumbnails,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final infoWidth = math.min(
        _infoPanelWidth,
        math.max(_infoPanelMinWidth, constraints.maxWidth * 0.6),
      );
      // With a pinned directory, the remaining area can be narrower than the
      // information panel. Let information cover this area rather than pushing
      // the pinned directory out or overflowing the image/chapter controls.
      final infoOverlays =
          _infoVisible &&
          (_isBorderless || constraints.maxWidth - infoWidth < 160);
      return Stack(
        fit: StackFit.expand,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Offstage(
                              offstage: _gridVisible,
                              child: TickerMode(
                                enabled: !_gridVisible,
                                child: _buildCanvas(entry),
                              ),
                            ),
                          ),
                          if (_gridVisible)
                            Positioned.fill(child: _buildGridOverview()),
                          if (!_gridVisible && !_colorPicker.active)
                            ...navigation,
                          if (!_gridVisible &&
                              !_colorPicker.active &&
                              _autoPlay.active)
                            Positioned(
                              left: 8,
                              right: 8,
                              top: _floatingToolbar && _showToolbar
                                  ? _topBarHeight + 8
                                  : 8,
                              child: Align(
                                alignment: Alignment.topRight,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 280,
                                  ),
                                  child: _hdrControlRegion(
                                    'autoPlay',
                                    AutoPlayStatusIndicator(
                                      controller: _autoPlay,
                                      position:
                                          '${_controller.currentIndex + 1} / ${_controller.entries.length}',
                                      onOptions: _showAutoPlayOptions,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (!_gridVisible)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 720,
                                  ),
                                  child:
                                      ValueListenableBuilder<
                                        AnimationPlaybackController?
                                      >(
                                        valueListenable: _animationPlayback,
                                        builder: (context, controller, _) =>
                                            controller == null ||
                                                controller.frameCount <= 1 ||
                                                _session
                                                        .settings
                                                        .animationControlsMode ==
                                                    AnimationControlsMode.hidden
                                            ? const SizedBox.shrink()
                                            : _hdrControlRegion(
                                                'animation',
                                                AnimationPlaybackBar(
                                                  controller: controller,
                                                  shortcuts: _shortcuts,
                                                  autoHide:
                                                      _session
                                                          .settings
                                                          .animationControlsMode ==
                                                      AnimationControlsMode
                                                          .autoHide,
                                                ),
                                              ),
                                      ),
                                ),
                              ),
                            ),
                          if (_colorPicker.active && !_gridVisible)
                            Positioned.fill(
                              child: ColorPickerOverlay(
                                controller: _colorPicker,
                                onClose: _toggleColorPicker,
                                onFormatChanged: _saveColorPickerFormat,
                                bottomInset:
                                    (_animationPlayback.value?.frameCount ??
                                            0) >
                                        1
                                    ? 72
                                    : 0,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Visibility(
                      visible: showThumbnails,
                      maintainState: true,
                      child: SizedBox(
                        height: thumbnailHeight,
                        child: _buildBottomBar(),
                      ),
                    ),
                  ],
                ),
              ),
              if (_infoVisible && !infoOverlays)
                _buildInfoPanel(
                  _gridVisible ? _gridSelected : entry,
                  width: infoWidth,
                ),
            ],
          ),
          if (infoOverlays)
            Positioned(
              key: const ValueKey('viewer.infoOverlay'),
              right: 0,
              top: 0,
              bottom: 0,
              width: math.min(infoWidth, constraints.maxWidth),
              child: _buildInfoPanel(
                _gridVisible ? _gridSelected : entry,
                width: math.min(infoWidth, constraints.maxWidth),
              ),
            ),
        ],
      );
    },
  );

  Widget _buildInfoPanel(ImageEntry? entry, {required double width}) {
    final tokens = ViewerThemeTokens.of(context);
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
        child: Card(
          margin: EdgeInsets.zero,
          color: tokens.surfaceElevated,
          surfaceTintColor: AppColors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.containerRadius),
            side: BorderSide(color: tokens.border.withValues(alpha: 0.65)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 56,
                child: Row(
                  children: [
                    const SizedBox(width: AppTokens.space4),
                    Expanded(
                      child: Text(
                        _l10n.information,
                        style: AppTextStyles.compactTitle.copyWith(
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                    if (!_floatingToolbar || _isBorderless) ...[
                      AppIconButton(
                        tooltip: _l10n.closeInfoPanel,
                        onPressed: () => setState(() => _infoVisible = false),
                        iconWidget: const Icon(FluentIcons.dismiss_20_regular),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _buildInfo(entry)),
            ],
          ),
        ),
      ),
    );
  }

  void _selectIcoVariant(ImageEntry entry, int index) {
    if (_resources.selectedIcoIndex(entry) == index) return;
    _comicRestorePosition = _comicPositionController.capture();
    _resources.selectIcoVariant(entry, index);
    _colorPicker.resetImage();
    _displayedEntries.remove(entry.id);
    final future = _resources.metadata(
      entry,
      priority: DecodePriority.foreground,
    );
    if (_controller.currentEntry?.id == entry.id) _metadataFuture = future;
    if (_gridSelected?.id == entry.id) _gridMetadata = future;
    _spreadMetadataSource = null;
    _comicGeometry = null;
    _pendingEntryView = null;
    _viewResetRequest++;
    _session.markReloaded();
    setState(() {});
  }

  Widget _buildInfo(ImageEntry? entry) => entry == null
      ? Padding(
          padding: const EdgeInsets.all(AppTokens.space5),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    FluentIcons.image_24_regular,
                    size: AppTokens.space6,
                    color: ViewerThemeTokens.of(context).textSecondary,
                  ),
                ),
                const SizedBox(height: AppTokens.space3),
                Text(
                  _l10n.noImage,
                  style: AppTextStyles.control.copyWith(
                    color: ViewerThemeTokens.of(context).textSecondary,
                  ),
                ),
              ],
            ),
          ),
        )
      : FutureBuilder<ImageMetadata>(
          key: ValueKey(entry.id),
          future: _gridVisible ? _gridMetadata : _metadataFuture,
          initialData: _resources.cachedMetadata(entry),
          builder: (context, snapshot) {
            final metadata = entry.format == ImageFormat.ico
                ? _resources.cachedMetadata(entry) ?? snapshot.data
                : snapshot.data;
            return Scrollbar(
              controller: _infoScrollController,
              thickness: 4,
              radius: const Radius.circular(2),
              interactive: true,
              child: SingleChildScrollView(
                controller: _infoScrollController,
                padding: const EdgeInsets.all(AppTokens.space4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppFileNameEditor(
                      key: _fileNameEditorKey,
                      label: _l10n.fileName,
                      fileName: entry.name,
                      canEdit:
                          !_controller.isReadOnlyArchive &&
                          entry.isMaterialized &&
                          entry.file.existsSync(),
                      unavailableMessage: _l10n.renameUnavailable,
                      invalidMessage: _l10n.invalidFileName,
                      renameTooltip: _tooltipLabel(
                        _l10n.renameFile,
                        _binding(ViewerCommand.rename),
                      ),
                      onRename: (name) => _renameFile(entry, name),
                    ),
                    _infoDivider(),
                    _infoGroup(_l10n.basicInformation, const []),
                    _infoField(
                      _l10n.format,
                      localizedFormatLabel(_l10n, entry.format),
                    ),
                    if (metadata != null && metadata.readable)
                      _infoField(
                        _l10n.dimensions,
                        '${metadata.width} × ${metadata.height}',
                      ),
                    if (metadata == null)
                      _infoHint(
                        snapshot.hasError
                            ? _l10n.readingDimensionsFailed
                            : _l10n.readingDimensions,
                      )
                    else if (!metadata.readable)
                      _unreadableMetadata(),
                    _infoField(_l10n.size, _formatBytes(entry.byteLength)),
                    _infoField(
                      _l10n.modifiedTime,
                      _formatModifiedTime(entry.modifiedAt),
                    ),
                    if (metadata != null &&
                        metadata.icoVariants.isNotEmpty) ...[
                      const SizedBox(height: AppTokens.space2),
                      IcoVariantField(
                        variants: metadata.icoVariants,
                        selectedIndex: metadata.icoIndex!,
                        onChanged: (index) => _selectIcoVariant(entry, index),
                      ),
                    ],
                    const SizedBox(height: AppTokens.space3),
                    _pathField(entry),
                    if (metadata != null &&
                        metadata.readable &&
                        _basicMetadataFields(metadata).isNotEmpty) ...[
                      _infoDivider(),
                      _infoGroup(_l10n.imageProperties, const []),
                      ..._basicMetadataFields(metadata),
                    ],
                    _infoDivider(),
                    ImageHistogramSection(
                      key: ValueKey((entry.id, metadata?.icoIndex)),
                      entry: entry,
                      resources: _resources,
                    ),
                    if (metadata != null && metadata.readable)
                      _buildMoreMetadata(entry, metadata),
                    if (metadata == null && snapshot.hasError)
                      _infoHint(_l10n.readingMetadataFailed),
                  ],
                ),
              ),
            );
          },
        );

  List<Widget> _basicMetadataFields(ImageMetadata metadata) {
    final fields = <Widget>[
      if (metadata.orientation != 1)
        _infoField(_l10n.orientation, _orientationLabel(metadata.orientation)),
    ];
    if (metadata.bitDepth != null) {
      fields.add(_infoField(_l10n.colorDepth, '${metadata.bitDepth} bit'));
    }
    if (metadata.hasAlpha != null) {
      fields.add(
        _infoField(
          _l10n.alphaChannel,
          metadata.hasAlpha! ? _l10n.hasAlpha : _l10n.opaque,
        ),
      );
    }
    if (metadata.colorSpace != null) {
      fields.add(_infoField(_l10n.colorSpace, metadata.colorSpace!));
    }
    if (metadata.codec != null) {
      fields.add(_infoField(_l10n.codec, metadata.codec!));
    }
    return fields;
  }

  Widget _buildMoreMetadata(ImageEntry entry, ImageMetadata metadata) {
    final animation = metadata.animation;
    final camera = _cameraMetadata(metadata.values);
    final specialized = _specializedMetadata(entry, metadata.values);
    final other = _otherMetadata(metadata.values);
    final hasMore =
        animation != null ||
        _resources.isAnimated(entry) ||
        camera.isNotEmpty ||
        specialized.isNotEmpty ||
        other.isNotEmpty;
    if (!hasMore) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoDivider(),
        if (animation != null || _resources.isAnimated(entry))
          _animationSection(animation),
        if (camera.isNotEmpty) ...[
          if (animation != null || _resources.isAnimated(entry)) _infoDivider(),
          _infoGroup(_l10n.cameraInformation, camera),
        ],
        if (specialized.isNotEmpty) ...[
          if (animation != null ||
              _resources.isAnimated(entry) ||
              camera.isNotEmpty)
            _infoDivider(),
          _infoGroup(specialized.first.value, specialized.skip(1).toList()),
        ],
        if (other.isNotEmpty) ...[
          if (animation != null ||
              _resources.isAnimated(entry) ||
              camera.isNotEmpty ||
              specialized.isNotEmpty)
            _infoDivider(),
          _infoGroup(_l10n.additionalMetadata, other),
        ],
      ],
    );
  }

  Widget _animationSection(ImageAnimationMetadata? animation) {
    return ValueListenableBuilder<(int, int)>(
      valueListenable: _frameInfo,
      builder: (context, frameInfo, _) {
        final frameCount = math.max(animation?.frameCount ?? 0, frameInfo.$2);
        final count = frameCount > 1 ? '$frameCount' : '—';
        final fps = animation?.fps;
        final details = <_InfoValueLine>[
          _InfoValueLine(label: _l10n.frames, value: count),
        ];
        if (fps != null) {
          details.add(
            _InfoValueLine(
              label: _l10n.frameRate,
              value: '${fps.toStringAsFixed(fps >= 10 ? 0 : 1)} FPS',
            ),
          );
        }
        if (animation?.durationMs != null) {
          details.add(
            _InfoValueLine(
              label: _l10n.duration,
              value: _formatDuration(animation!.durationMs!),
            ),
          );
        }
        if (animation?.loopCount != null) {
          details.add(
            _InfoValueLine(
              label: _l10n.loopCount,
              value: animation!.loopCount == 0
                  ? _l10n.infiniteLoop
                  : _l10n.playCount(animation.loopCount!),
            ),
          );
        }
        return _infoGroup(_l10n.animationInformation, details);
      },
    );
  }

  List<_InfoValueLine> _cameraMetadata(Map<String, String> values) {
    return [
      for (final (label, value) in cameraMetadataRows(values, _l10n))
        _InfoValueLine(label: label, value: value),
    ];
  }

  List<_InfoValueLine> _specializedMetadata(
    ImageEntry entry,
    Map<String, String> values,
  ) {
    if (entry.format == ImageFormat.svg) {
      final rows = <_InfoValueLine>[];
      for (final (label, key) in <(String, String)>[
        (_l10n.physicalSize, 'svgPhysicalSize'),
        (_l10n.viewBox, 'svgViewBox'),
        (_l10n.nodeCount, 'svgNodeCount'),
      ]) {
        final value = _metadataValue(values, key);
        if (value != null) rows.add(_InfoValueLine(label: label, value: value));
      }
      return rows.isEmpty
          ? const []
          : [_InfoValueLine(value: _l10n.vectorInformation), ...rows];
    }
    return const [];
  }

  List<_InfoValueLine> _otherMetadata(Map<String, String> values) {
    const excluded = {
      'exif',
      'xmp',
      'format',
      'width',
      'height',
      'orientation',
      'make',
      'model',
      'datetimeoriginal',
      'lensmodel',
      'fnumber',
      'exposuretime',
      'iso',
      'focallength',
      'exposurebias',
      'whitebalance',
      'flash',
      'gpslatitude',
      'gpslongitude',
      'gpslatituderef',
      'gpslongituderef',
      'offsettimeoriginal',
      'subsectimeoriginal',
      'exifcolorspace',
      'interopindex',
      'cicpcolorspace',
      'unprofiledadobergb',
      ...PhotoMetadataReader.descriptiveKeys,
      'svgphysicalsize',
      'svgviewbox',
      'svgnodecount',
      'codec',
      'colorspace',
      'bitdepth',
      'hasalpha',
    };
    return [
      for (final (label, value) in descriptiveMetadataRows(values, _l10n))
        _InfoValueLine(label: label, value: value),
      ...values.entries
          .where(
            (entry) =>
                !excluded.contains(entry.key.toLowerCase()) &&
                entry.value.trim().isNotEmpty,
          )
          .map(
            (entry) =>
                _InfoValueLine(label: entry.key, value: entry.value.trim()),
          ),
    ];
  }

  String? _metadataValue(Map<String, String> values, String key) {
    for (final entry in values.entries) {
      if (entry.key.toLowerCase() == key.toLowerCase()) {
        return entry.value.trim();
      }
    }
    return null;
  }

  Widget _infoGroup(String title, List<_InfoValueLine> lines) {
    final tokens = ViewerThemeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.caption.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppTokens.space3),
        for (final line in lines) _infoField(line.label ?? '', line.value),
      ],
    );
  }

  Widget _infoDivider() => Divider(
    height: AppTokens.space6,
    thickness: 1,
    color: ViewerThemeTokens.of(context).border,
  );

  Widget _unreadableMetadata() => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          FluentIcons.warning_24_regular,
          size: 17,
          color: ViewerThemeTokens.of(context).warning,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            _l10n.unreadableImageMetadata,
            style: AppTextStyles.body.copyWith(
              color: ViewerThemeTokens.of(context).warning,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _infoHint(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: AppTextStyles.body.copyWith(
        color: ViewerThemeTokens.of(context).textTertiary,
      ),
    ),
  );

  Widget _pathField(ImageEntry entry) {
    final path = _controller.displayPathFor(entry);
    final wrappedPath = path.replaceAllMapped(
      RegExp(r'[/\\]'),
      (match) => '${match[0]}\u200b',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _l10n.path,
          style: AppTextStyles.caption.copyWith(
            color: ViewerThemeTokens.of(context).textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Tooltip(
                message: path,
                child: AppTextAction(
                  key: const ValueKey('info.path'),
                  label: wrappedPath,
                  maxLines: 2,
                  semanticsLabel: path,
                  onPressed: _revealCurrentFile,
                ),
              ),
            ),
            const SizedBox(width: AppTokens.space2),
            AppIconButton(
              key: const ValueKey('info.copyPath'),
              icon: FluentIcons.copy_16_regular,
              iconSize: 16,
              tooltip: _l10n.copyImagePath,
              onPressed: () => Clipboard.setData(ClipboardData(text: path)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _infoField(String label, String value) =>
      AppInfoField(label: label, value: value);

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatModifiedTime(DateTime time) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return intl.DateFormat('yyyy-MM-dd HH:mm', locale).format(time.toLocal());
  }

  String _formatDuration(int milliseconds) {
    final seconds = milliseconds / 1000;
    return seconds >= 60
        ? '${(seconds / 60).floor()}:${(seconds % 60).toStringAsFixed(1).padLeft(4, '0')}'
        : '${seconds.toStringAsFixed(seconds >= 10 ? 1 : 2)} s';
  }

  Future<String?> _renameFile(ImageEntry entry, String name) async {
    if (_controller.isReadOnlyArchive) return _l10n.archiveReadOnly;
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == entry.name) return null;
    if (trimmed.contains('\\') ||
        trimmed.contains('/') ||
        trimmed == '.' ||
        trimmed == '..' ||
        trimmed.length > 255) {
      return _l10n.invalidFileName;
    }
    try {
      if (!await entry.file.exists()) return _l10n.renameUnavailable;
      final target = File(
        '${entry.file.parent.path}${Platform.pathSeparator}$trimmed',
      );
      if (await target.exists()) return _l10n.renameTargetExists;
      await entry.file.rename(target.path);
      await _openPath(target.path);
      return null;
    } catch (error) {
      return localizedErrorMessage(_l10n, error);
    }
  }

  String _orientationLabel(int orientation) => switch (orientation) {
    1 => _l10n.orientationNormal,
    2 => _l10n.orientationHorizontalMirror,
    3 => _l10n.orientationRotate180,
    4 => _l10n.orientationVerticalMirror,
    5 => _l10n.orientationMirrorRotate270,
    6 => _l10n.orientationRotate90,
    7 => _l10n.orientationMirrorRotate90,
    8 => _l10n.orientationRotate270,
    _ => _l10n.orientationUnknown(orientation),
  };
}

class _InfoValueLine {
  const _InfoValueLine({this.label, required this.value});

  final String? label;
  final String value;
}

enum _BottomVectorIconKind {
  fitToWindow,
  actualSize,
  thumbnailBarHidden,
  thumbnailBarVisible,
}

class _BottomVectorIconPainter extends CustomPainter {
  const _BottomVectorIconPainter({required this.kind, required this.color});

  final _BottomVectorIconKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // The glyphs use a native 16x16 grid, matching the toolbar's display
    // size. This avoids scaling a 24x24 SVG viewBox down to the final icon.
    final scale = math.min(size.width, size.height) / 16;
    canvas.save();
    canvas.translate(
      (size.width - 16 * scale) / 2,
      (size.height - 16 * scale) / 2,
    );
    canvas.scale(scale);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    switch (kind) {
      case _BottomVectorIconKind.fitToWindow:
        _paintFitToWindow(canvas, paint);
      case _BottomVectorIconKind.actualSize:
        _paintActualSize(canvas, paint);
      case _BottomVectorIconKind.thumbnailBarHidden:
        _paintThumbnailBar(canvas, paint, filled: false);
      case _BottomVectorIconKind.thumbnailBarVisible:
        _paintThumbnailBar(canvas, paint, filled: true);
    }
    canvas.restore();
  }

  void _paintFitToWindow(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(5.5, 1.5)
      ..lineTo(3.5, 1.5)
      ..quadraticBezierTo(1.5, 1.5, 1.5, 3.5)
      ..lineTo(1.5, 5.5)
      ..moveTo(6.5, 6.5)
      ..lineTo(1.5, 1.5)
      ..moveTo(10.5, 1.5)
      ..lineTo(12.5, 1.5)
      ..quadraticBezierTo(14.5, 1.5, 14.5, 3.5)
      ..lineTo(14.5, 5.5)
      ..moveTo(9.5, 6.5)
      ..lineTo(14.5, 1.5)
      ..moveTo(5.5, 14.5)
      ..lineTo(3.5, 14.5)
      ..quadraticBezierTo(1.5, 14.5, 1.5, 12.5)
      ..lineTo(1.5, 10.5)
      ..moveTo(6.5, 9.5)
      ..lineTo(1.5, 14.5)
      ..moveTo(10.5, 14.5)
      ..lineTo(12.5, 14.5)
      ..quadraticBezierTo(14.5, 14.5, 14.5, 12.5)
      ..lineTo(14.5, 10.5)
      ..moveTo(9.5, 9.5)
      ..lineTo(14.5, 14.5);
    canvas.drawPath(path, paint);
  }

  void _paintActualSize(Canvas canvas, Paint paint) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(2.5, 2.5, 9.5, 9.5),
        const Radius.circular(1.25),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(6.5, 6.5, 13.5, 13.5),
        const Radius.circular(1.25),
      ),
      paint,
    );
  }

  void _paintThumbnailBar(Canvas canvas, Paint paint, {required bool filled}) {
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(2, 2, 14, 14),
          const Radius.circular(1.5),
        ),
      );
    if (filled) {
      final fill = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      final upper = Path()
        ..moveTo(2, 9.5)
        ..lineTo(2, 3.5)
        ..cubicTo(2, 2.6716, 2.6716, 2, 3.5, 2)
        ..lineTo(12.5, 2)
        ..cubicTo(13.3284, 2, 14, 2.6716, 14, 3.5)
        ..lineTo(14, 9.5)
        ..close();
      canvas.drawPath(upper, fill);
    }
    paint
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(outline, paint);
    final separators = Path()
      ..moveTo(2, 9.5)
      ..lineTo(14, 9.5)
      ..moveTo(6, 9.5)
      ..lineTo(6, 14)
      ..moveTo(10, 9.5)
      ..lineTo(10, 14);
    canvas.drawPath(separators, paint);
  }

  @override
  bool shouldRepaint(covariant _BottomVectorIconPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
