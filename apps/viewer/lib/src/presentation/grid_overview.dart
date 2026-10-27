import 'dart:async';
import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../application/decode_scheduler.dart';
import '../application/image_resource_service.dart';
import '../domain/image_entry.dart';
import '../domain/image_format.dart';
import 'components/app_button.dart';
import 'components/app_icon_button.dart';
import 'components/app_input.dart';
import 'components/app_slider.dart';
import 'resource_image.dart';
import 'source_image_view.dart';
import 'svg_image.dart';
import '../application/svg_resources.dart' show svgVersion;
import 'theme/app_styles.dart';
import 'theme/app_theme.dart';

/// A temporary image index. Selection does not commit the reader's position.
class GridOverview extends StatefulWidget {
  const GridOverview({
    required this.entries,
    required this.resources,
    required this.selectedId,
    required this.readingId,
    required this.scopeLabel,
    required this.onSelect,
    required this.onOpen,
    required this.onClose,
    required this.onSizeChanged,
    this.onOpenDirectory,
    this.onOpenFolder,
    this.emptyMessage,
    this.itemWidth = 180,
    this.searchFocusNode,
    super.key,
  });
  final List<ImageEntry> entries;
  final ImageResourceService resources;
  final String? selectedId;
  final String? readingId;
  final String scopeLabel;
  final ValueChanged<ImageEntry> onSelect;
  final ValueChanged<ImageEntry> onOpen;
  final VoidCallback onClose;
  final VoidCallback? onOpenDirectory;
  final VoidCallback? onOpenFolder;
  final String? emptyMessage;
  final double itemWidth;
  final FocusNode? searchFocusNode;
  final ValueChanged<double> onSizeChanged;
  @override
  State<GridOverview> createState() => GridOverviewState();
}

class GridOverviewState extends State<GridOverview> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  List<int> _matches = [];
  int _columns = 1;
  double _rowHeight = 180;
  double _tileWidth = 180;
  bool _viewportScheduled = false;
  double _lastViewportOffset = 0;

  void _scheduleViewport() {
    if (_viewportScheduled) return;
    _viewportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportScheduled = false;
      if (!mounted || !_scroll.hasClients || _matches.isEmpty) return;
      final ratio = MediaQuery.devicePixelRatioOf(context);
      final offset = _scroll.offset;
      widget.resources.thumbnails.updateViewport(
        owner: 'grid',
        entries: widget.entries,
        indices: _matches,
        first: (offset / _rowHeight).floor() * _columns,
        last:
            ((offset + _scroll.position.viewportDimension) / _rowHeight)
                    .ceil() *
                _columns -
            1,
        targetWidth: (_tileWidth * ratio).ceil(),
        targetHeight: (_tileWidth * .75 * ratio).ceil(),
        direction: (offset - _lastViewportOffset).sign.toInt(),
      );
      _lastViewportOffset = offset;
    });
  }

  bool _positionScheduled = false;
  final _retries = <String, int>{};
  Timer? _tapResetTimer;
  String? _lastTapId;
  Offset? _lastTapPosition;
  Offset? _pendingTapPosition;
  String _copy(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scheduleViewport);
    _filter();
    _revealSelected();
  }

  @override
  void didUpdateWidget(covariant GridOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId &&
        widget.selectedId != _lastTapId) {
      _resetTap();
    }
    if (!identical(oldWidget.entries, widget.entries)) {
      String? anchorId;
      double rowOffset = 0;
      if (_scroll.hasClients && _matches.isNotEmpty) {
        final row = (_scroll.offset / _rowHeight).floor();
        final position = (row * _columns).clamp(0, _matches.length - 1);
        anchorId = oldWidget.entries[_matches[position]].id;
        rowOffset = _scroll.offset - row * _rowHeight;
      }
      _filter();
      final ids = widget.entries.map((entry) => entry.id).toSet();
      _retries.removeWhere((id, _) => !ids.contains(id));
      if (anchorId != null && oldWidget.selectedId == widget.selectedId) {
        final position = _matches.indexWhere(
          (i) => widget.entries[i].id == anchorId,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scroll.hasClients || position < 0) return;
          final offset = (position ~/ _columns) * _rowHeight + rowOffset;
          _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
        });
      }
    }
    if (oldWidget.selectedId != widget.selectedId ||
        oldWidget.itemWidth != widget.itemWidth) {
      _revealSelected();
    }
  }

  void _filter() {
    _resetTap();
    final query = _search.text.trim().toLowerCase();
    _matches = [
      for (var i = 0; i < widget.entries.length; i++)
        if (query.isEmpty ||
            widget.entries[i].relativePath.toLowerCase().contains(query))
          i,
    ];
  }

  void _resetTap() {
    _tapResetTimer?.cancel();
    _tapResetTimer = null;
    _lastTapId = null;
    _lastTapPosition = null;
    _pendingTapPosition = null;
  }

  void _tapEntry(ImageEntry entry) {
    final position = _pendingTapPosition;
    final doubleClick =
        position != null &&
        _tapResetTimer?.isActive == true &&
        _lastTapId == entry.id &&
        (position - _lastTapPosition!).distance <= kDoubleTapSlop;
    _resetTap();
    // Keep the normal tap recognizer so release selects immediately and drags
    // can cancel. Remember a completed tap without delaying its selection.
    widget.onSelect(entry);
    if (doubleClick) {
      widget.onOpen(entry);
    } else if (position != null) {
      _lastTapId = entry.id;
      _lastTapPosition = position;
      _tapResetTimer = Timer(kDoubleTapTimeout, _resetTap);
    }
  }

  void _revealSelected() {
    if (_positionScheduled) return;
    _positionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _positionScheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      final position = _matches.indexWhere(
        (i) => widget.entries[i].id == widget.selectedId,
      );
      if (position < 0) return;
      final start = (position ~/ _columns) * _rowHeight;
      final end = start + _rowHeight;
      final view = _scroll.position.viewportDimension;
      final offset = _scroll.offset;
      final target = start < offset
          ? start
          : end > offset + view
          ? end - view
          : offset;
      _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  KeyEventResult handleKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    final primaryBoundary =
        (Theme.of(context).platform == TargetPlatform.macOS
            ? keyboard.isMetaPressed && !keyboard.isControlPressed
            : keyboard.isControlPressed && !keyboard.isMetaPressed) &&
        (event.logicalKey == LogicalKeyboardKey.home ||
            event.logicalKey == LogicalKeyboardKey.end);
    if (((keyboard.isControlPressed || keyboard.isMetaPressed) &&
            !primaryBoundary) ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_matches.isEmpty) {
      return const [
            LogicalKeyboardKey.arrowLeft,
            LogicalKeyboardKey.arrowRight,
            LogicalKeyboardKey.arrowUp,
            LogicalKeyboardKey.arrowDown,
            LogicalKeyboardKey.pageUp,
            LogicalKeyboardKey.pageDown,
            LogicalKeyboardKey.home,
            LogicalKeyboardKey.end,
            LogicalKeyboardKey.enter,
            LogicalKeyboardKey.numpadEnter,
          ].contains(event.logicalKey)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final current = _matches.indexWhere(
      (i) => widget.entries[i].id == widget.selectedId,
    );
    final page = _scroll.hasClients
        ? math.max(
                1,
                (_scroll.position.viewportDimension / _rowHeight).floor(),
              ) *
              _columns
        : _columns;
    final target = switch (key) {
      LogicalKeyboardKey.arrowLeft => current - 1,
      LogicalKeyboardKey.arrowRight => current + 1,
      LogicalKeyboardKey.arrowUp => current - _columns,
      LogicalKeyboardKey.arrowDown => current + _columns,
      LogicalKeyboardKey.pageUp => current - page,
      LogicalKeyboardKey.pageDown => current + page,
      LogicalKeyboardKey.home => 0,
      LogicalKeyboardKey.end => _matches.length - 1,
      _ => null,
    };
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      widget.onOpen(widget.entries[_matches[math.max(0, current)]]);
      return KeyEventResult.handled;
    }
    if (target == null) return KeyEventResult.ignored;
    widget.onSelect(
      widget.entries[_matches[target.clamp(0, _matches.length - 1)]],
    );
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _resetTap();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !(HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      widget.onSizeChanged(
        (widget.itemWidth - event.scrollDelta.dy.sign * 24).clamp(96, 320),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    return ColoredBox(
      color: tokens.appBackground,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Row(
                  children: [
                    AppIconButton(
                      icon: FluentIcons.arrow_left_20_regular,
                      tooltip: _copy('返回阅读', 'Return to reading'),
                      onPressed: widget.onClose,
                    ),
                    if (widget.onOpenDirectory != null)
                      AppIconButton(
                        icon: FluentIcons.folder_open_20_regular,
                        tooltip: _copy('浏览目录', 'Browse directories'),
                        onPressed: widget.onOpenDirectory,
                      ),
                    Expanded(
                      child: Tooltip(
                        message: widget.scopeLabel,
                        child: Text(
                          '${_copy('网格总览', 'Grid overview')} · ${widget.scopeLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.compactTitle.copyWith(
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      '${_matches.length} / ${widget.entries.length}',
                      style: AppTextStyles.caption.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final search = AppInput(
                      key: const ValueKey('grid.search'),
                      focusNode: widget.searchFocusNode,
                      controller: _search,
                      hint: _copy('搜索当前图片列表', 'Search current images'),
                      leadingIcon: FluentIcons.search_20_regular,
                      clearTooltip: _copy('清空搜索', 'Clear search'),
                      clearable: true,
                      onChanged: (_) {
                        setState(_filter);
                        _revealSelected();
                      },
                    );
                    final size = Row(
                      children: [
                        AppIconButton(
                          icon: FluentIcons.subtract_20_regular,
                          tooltip: _copy('缩小缩略图', 'Smaller thumbnails'),
                          size: 30,
                          onPressed: widget.itemWidth <= 96
                              ? null
                              : () => widget.onSizeChanged(
                                  (widget.itemWidth - 24).clamp(96, 320),
                                ),
                        ),
                        Expanded(
                          child: Tooltip(
                            message: _copy('缩略图大小', 'Thumbnail size'),
                            child: AppSlider(
                              key: const ValueKey('grid.size'),
                              value: widget.itemWidth,
                              min: 96,
                              max: 320,
                              onChanged: widget.onSizeChanged,
                            ),
                          ),
                        ),
                        AppIconButton(
                          icon: FluentIcons.add_20_regular,
                          tooltip: _copy('放大缩略图', 'Larger thumbnails'),
                          size: 30,
                          onPressed: widget.itemWidth >= 320
                              ? null
                              : () => widget.onSizeChanged(
                                  (widget.itemWidth + 24).clamp(96, 320),
                                ),
                        ),
                      ],
                    );
                    if (constraints.maxWidth < 360) {
                      return Column(
                        children: [
                          search,
                          SizedBox(height: 32, child: size),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: search),
                        const SizedBox(width: 8),
                        SizedBox(width: 180, height: 36, child: size),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _matches.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _search.text.trim().isNotEmpty
                                ? _copy('没有匹配的图片', 'No matching images')
                                : widget.emptyMessage ??
                                      _copy(
                                        '此范围内没有图片',
                                        'No images in this scope',
                                      ),
                            textAlign: TextAlign.center,
                            style: AppTextStyles.body.copyWith(
                              color: tokens.textSecondary,
                            ),
                          ),
                          if (widget.entries.isEmpty &&
                              widget.onOpenFolder != null) ...[
                            const SizedBox(height: 8),
                            AppButton(
                              label: AppLocalizations.of(context)!.openFolder,
                              onPressed: widget.onOpenFolder,
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = math.max(
                        1,
                        ((constraints.maxWidth - 16) / (widget.itemWidth + 8))
                            .floor(),
                      );
                      final width = math.max(
                        1.0,
                        (constraints.maxWidth - 16 - (columns - 1) * 8) /
                            columns,
                      );
                      final rowHeight = width * 0.75 + 40;
                      _tileWidth = width;
                      _scheduleViewport();
                      if (_columns != columns || _rowHeight != rowHeight) {
                        _columns = columns;
                        _rowHeight = rowHeight;
                        _revealSelected();
                      }
                      return ScrollConfiguration(
                        behavior: const MaterialScrollBehavior().copyWith(
                          scrollbars: false,
                        ),
                        child: Scrollbar(
                          controller: _scroll,
                          interactive: true,
                          child: _ThumbnailGrid(
                            onPointerSignal: _handlePointerSignal,
                            key: const ValueKey('grid.images'),
                            controller: _scroll,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            scrollCacheExtent: const ScrollCacheExtent.pixels(
                              0,
                            ),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisExtent: rowHeight - 8,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                ),
                            itemCount: _matches.length,
                            itemBuilder: (context, position) {
                              final index = _matches[position];
                              final entry = widget.entries[index];
                              final selected = entry.id == widget.selectedId;
                              final reading = entry.id == widget.readingId;
                              return Tooltip(
                                message: entry.relativePath,
                                child: Semantics(
                                  label: entry.relativePath,
                                  selected: selected,
                                  button: true,
                                  child: Material(
                                    color: selected
                                        ? tokens.accent.withValues(alpha: 0.12)
                                        : tokens.surfaceSubtle,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      side: BorderSide(
                                        color: selected
                                            ? tokens.accent
                                            : tokens.border,
                                        width: selected ? 2 : 1,
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      key: ValueKey('grid.item.${entry.id}'),
                                      canRequestFocus: false,
                                      onTapUp: (details) =>
                                          _pendingTapPosition =
                                              details.globalPosition,
                                      onTapCancel: _resetTap,
                                      onTap: () => _tapEntry(entry),
                                      hoverColor: tokens.surfaceHover,
                                      child: Padding(
                                        padding: const EdgeInsets.all(6),
                                        child: Column(
                                          children: [
                                            Expanded(
                                              child: SizedBox(
                                                width: double.infinity,
                                                child: _thumbnail(entry, width),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Text(
                                                  '${index + 1}',
                                                  style: AppTextStyles.finePrint
                                                      .copyWith(
                                                        color:
                                                            tokens.textTertiary,
                                                      ),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    entry.relativePath,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: AppTextStyles.caption
                                                        .copyWith(
                                                          color: tokens
                                                              .textPrimary,
                                                        ),
                                                  ),
                                                ),
                                                if (reading)
                                                  Tooltip(
                                                    message: _copy(
                                                      '正在阅读',
                                                      'Currently reading',
                                                    ),
                                                    child: Icon(
                                                      FluentIcons
                                                          .book_open_16_regular,
                                                      size: 16,
                                                      color: tokens.accent,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _thumbnail(ImageEntry entry, double width) {
    final tokens = ViewerThemeTokens.of(context);
    final retry = _retries[entry.id] ?? 0;
    Widget placeholder() => Center(
      child: AppIconButton(
        icon: FluentIcons.arrow_clockwise_20_regular,
        color: tokens.textTertiary,
        tooltip: _copy('加载失败，点击重试', 'Failed to load. Click to retry'),
        onPressed: () {
          widget.resources.invalidate(entry.id);
          setState(() => _retries[entry.id] = retry + 1);
        },
      ),
    );
    if (entry.format == ImageFormat.svg) {
      if (!entry.isMaterialized) {
        return SourceImageView(
          key: ValueKey((entry.id, retry)),
          entry: entry,
          showRetryButton: false,
          builder: (resolved) => _thumbnail(resolved, width),
          errorBuilder: (_) => placeholder(),
        );
      }
      return SvgImage(
        key: ValueKey((entry.id, retry)),
        file: entry.file,
        version: svgVersion(entry),
        fit: BoxFit.contain,
        errorBuilder: (_, error, stack) => placeholder(),
      );
    }
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return ResourceImage(
      key: ValueKey((entry.id, retry)),
      resources: widget.resources,
      entry: entry,
      targetWidth: (width * ratio).ceil(),
      targetHeight: (width * 0.75 * ratio).ceil(),
      priority: DecodePriority.visibleThumbnail,
      frameBuilder: (context, child, frame, sync) => sync || frame != null
          ? child
          : Center(
              child: Icon(
                FluentIcons.image_20_regular,
                color: tokens.textDisabled,
              ),
            ),
      errorBuilder: (context, failure, stack) => placeholder(),
    );
  }
}

// Register modified wheel input inside Scrollable's listener so scrolling
// cannot consume the gesture before the thumbnail-size control sees it.
class _ThumbnailGrid extends GridView {
  _ThumbnailGrid({
    required this.onPointerSignal,
    required super.gridDelegate,
    required super.itemBuilder,
    super.key,
    super.controller,
    super.padding,
    super.scrollCacheExtent,
    super.itemCount,
  }) : super.builder();
  final PointerSignalEventListener onPointerSignal;

  @override
  Widget buildViewport(
    BuildContext context,
    ViewportOffset offset,
    AxisDirection axisDirection,
    List<Widget> slivers,
  ) => Listener(
    onPointerSignal: onPointerSignal,
    child: super.buildViewport(context, offset, axisDirection, slivers),
  );
}
