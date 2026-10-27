import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:vector_math/vector_math_64.dart';

import '../domain/image_entry.dart';
import '../domain/comic_layout_direction.dart';
import '../domain/view_scale_mode.dart';
import '../application/prefetch_planner.dart';
import '../application/decode_request.dart';
import 'zoomable_viewport.dart';
import 'view_scale_layout.dart';

/// Captures the page and relative point at the viewport center before unmounting.
class ComicPositionController {
  ComicReadingPosition? Function()? _capture;
  VoidCallback? _flush;
  bool Function()? _layoutReady;
  ComicReadingPosition? capture() => _capture?.call();
  void flushCurrentPage() => _flush?.call();
  bool get layoutReady => _layoutReady?.call() ?? false;
}

class ComicStripViewport extends StatefulWidget {
  const ComicStripViewport({
    required this.entries,
    required this.currentIndex,
    required this.jumpToken,
    required this.viewport,
    required this.baseWidth,
    required this.controller,
    required this.commands,
    required this.onVerticalBoundary,
    required this.pageGap,
    required this.buildPage,
    required this.loadSize,
    required this.onCurrentPageChanged,
    required this.layoutDirection,
    this.minScale = 0.05,
    this.maxScale = 16,
    this.wheelScrollSpeed = 1,
    this.wheelZoomSpeed = 1,
    this.originalSize = false,
    this.scaleMode,
    this.resetRequest = 0,
    this.uniformPageSize = true,
    this.onReferenceScaleChanged,
    this.zoomAroundCenter = false,
    this.onVisiblePagesChanged,
    this.metadataPreloadPages = 3,
    this.maxConcurrentSizeLoads = 1,
    this.admittedPageIds,
    this.positionController,
    this.initialPosition,
    super.key,
  });

  final List<ImageEntry> entries;
  final int currentIndex;
  final int jumpToken;
  final Size viewport;
  final double baseWidth;
  final bool originalSize;
  final ViewScaleMode? scaleMode;
  final int resetRequest;
  final bool uniformPageSize;
  final ValueChanged<double>? onReferenceScaleChanged;
  final bool zoomAroundCenter;
  final TransformationController controller;
  final ZoomableViewportCommands commands;
  final ValueChanged<VerticalScrollBoundary> onVerticalBoundary;
  final double pageGap;
  final Widget Function(ImageEntry entry, bool isCurrent) buildPage;
  final Future<Size?> Function(String path) loadSize;
  final ValueChanged<int> onCurrentPageChanged;
  final ComicLayoutDirection layoutDirection;
  final double minScale;
  final double maxScale;
  final double wheelScrollSpeed;
  final double wheelZoomSpeed;
  final void Function(
    Set<int> visiblePages,
    List<PageGeometry> geometry,
    double viewportStart,
    double viewportEnd,
  )?
  onVisiblePagesChanged;
  final int metadataPreloadPages;
  final int maxConcurrentSizeLoads;

  /// Visible pages always build. Offscreen pages build only after admission.
  final Set<String>? admittedPageIds;
  final ComicPositionController? positionController;
  final ComicReadingPosition? initialPosition;

  @override
  State<ComicStripViewport> createState() => _ComicStripViewportState();
}

class _ComicPageLayout {
  const _ComicPageLayout({
    required this.entry,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final ImageEntry entry;
  final double left;
  final double top;
  final double width;
  final double height;
}

class ComicReadingPosition {
  const ComicReadingPosition({
    required this.path,
    required this.pageFraction,
    required this.crossFraction,
    this.fitReferenceId,
  });

  final String path;
  final double pageFraction;
  final double crossFraction;
  final String? fitReferenceId;
}

class _ComicStripViewportState extends State<ComicStripViewport> {
  final _aspects = <String, double>{};
  final _sourceWidths = <String, double>{};
  final _loadingPaths = <String>{};
  final _failedSizePaths = <String>{};
  Map<String, int> _logicalIndices = {};
  List<PageGeometry> _pageGeometry = const [];
  Set<int> _visiblePages = {};
  double? _visibleStart;
  double? _visibleEnd;
  int _lastVisibleLayoutRevision = -1;
  bool _visibleReportScheduled = false;
  Set<String> _entryPaths = const {};
  List<_ComicPageLayout> _pages = const [];
  List<_ComicPageLayout>? _previousPages;
  double? _previousBaseWidth;
  double? _previousContentHeight;
  bool? _previousWasVertical;
  double _contentWidth = 1;
  double _contentHeight = 0;
  double? _referenceWidth;
  double? _referenceHeight;
  List<ImageEntry> _sizeQueue = const [];
  int _queueIndex = 0;
  int _activeSizeLoads = 0;
  int _layoutRevision = 0;
  List<_ComicPageLayout> _builtPages = const [];
  String? _builtCurrentPath;
  Widget? _pageLayer;
  bool _layoutScheduled = false;
  ComicReadingPosition? _pendingDirectionAnchor;
  Matrix4? _initialTransform;
  String? _fitReferenceId;
  bool _resetScalePending = false;
  int _lastJumpToken = -1;
  int _jumpGeneration = 0;
  bool _jumping = false;
  bool _holdReportUntilInteraction = false;
  int _lastReportedIndex = -1;
  Timer? _reportTimer;

  @override
  void initState() {
    super.initState();
    widget.positionController?._capture = _capturePosition;
    widget.positionController?._flush = _flushCurrentPage;
    widget.positionController?._layoutReady = _layoutReadyForAutoPlay;
    widget.commands.addListener(_releaseReportHold);
    _entryPaths = widget.entries.map((entry) => entry.id).toSet();
    _setReferenceWidth();
    _fitReferenceId =
        widget.initialPosition?.fitReferenceId ??
        widget.entries.elementAtOrNull(widget.currentIndex)?.id;
    _rebuildLayout();
    _queueSizes();
  }

  @override
  void didUpdateWidget(covariant ComicStripViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Playback and decode targets can change without changing page geometry.
    _pageLayer = null;
    if (oldWidget.positionController != widget.positionController) {
      oldWidget.positionController?._capture = null;
      oldWidget.positionController?._flush = null;
      oldWidget.positionController?._layoutReady = null;
      widget.positionController?._capture = _capturePosition;
      widget.positionController?._flush = _flushCurrentPage;
      widget.positionController?._layoutReady = _layoutReadyForAutoPlay;
    }
    if (oldWidget.commands != widget.commands) {
      oldWidget.commands.removeListener(_releaseReportHold);
      widget.commands.addListener(_releaseReportHold);
    }
    if (oldWidget.layoutDirection != widget.layoutDirection) {
      _pendingDirectionAnchor = _captureAnchor(oldWidget.layoutDirection);
    }
    final resetScale =
        oldWidget.scaleMode != widget.scaleMode ||
        oldWidget.resetRequest != widget.resetRequest;
    if (resetScale) {
      _pendingDirectionAnchor = _captureAnchor(oldWidget.layoutDirection);
      _fitReferenceId = widget.entries.elementAtOrNull(widget.currentIndex)?.id;
      _resetScalePending = true;
    }
    if (oldWidget.entries != widget.entries) {
      _entryPaths = widget.entries.map((entry) => entry.id).toSet();
      _visiblePages = {};
      _visibleStart = null;
      _visibleEnd = null;
      _failedSizePaths.clear();
      _setReferenceWidth();
      _fitReferenceId = widget.entries.elementAtOrNull(widget.currentIndex)?.id;
      _previousPages = null;
      _lastJumpToken = -1;
      _jumpGeneration++;
      _jumping = false;
      _holdReportUntilInteraction = false;
      _lastReportedIndex = -1;
      _reportTimer?.cancel();
      _queueSizes();
    }
    if (oldWidget.entries != widget.entries ||
        oldWidget.baseWidth != widget.baseWidth ||
        oldWidget.originalSize != widget.originalSize ||
        resetScale ||
        oldWidget.uniformPageSize != widget.uniformPageSize ||
        oldWidget.viewport != widget.viewport ||
        oldWidget.layoutDirection != widget.layoutDirection ||
        oldWidget.pageGap != widget.pageGap) {
      _rebuildLayout();
    }
    if (oldWidget.jumpToken != widget.jumpToken) {
      _jumpTo(widget.currentIndex);
    }
    if (oldWidget.metadataPreloadPages != widget.metadataPreloadPages ||
        oldWidget.maxConcurrentSizeLoads != widget.maxConcurrentSizeLoads ||
        oldWidget.admittedPageIds != widget.admittedPageIds) {
      _queueSizes();
    }
  }

  @override
  void dispose() {
    widget.positionController?._capture = null;
    widget.positionController?._flush = null;
    widget.positionController?._layoutReady = null;
    _reportTimer?.cancel();
    widget.commands.removeListener(_releaseReportHold);
    super.dispose();
  }

  void _releaseReportHold() {
    _holdReportUntilInteraction = false;
  }

  bool _layoutReadyForAutoPlay() {
    if (_layoutScheduled || _visiblePages.isEmpty) return false;
    return _visiblePages.every((index) {
      final entry = widget.entries.elementAtOrNull(index);
      return entry != null &&
          (_aspects.containsKey(entry.id) ||
              _failedSizePaths.contains(entry.id) ||
              ((entry.width ?? 0) > 0 && (entry.height ?? 0) > 0));
    });
  }

  double _aspect(ImageEntry entry) =>
      _aspects[entry.id] ??
      (entry.width != null &&
              entry.width! > 0 &&
              entry.height != null &&
              entry.height! > 0
          ? entry.width! / entry.height!
          : 0.7);

  void _setReferenceWidth() {
    final width = widget.entries.isEmpty ? null : widget.entries.first.width;
    final height = widget.entries.isEmpty ? null : widget.entries.first.height;
    _referenceWidth = widget.entries.isEmpty
        ? null
        : _sourceWidths[widget.entries.first.id] ??
              (width != null && width > 0 ? width.toDouble() : null);
    _referenceHeight = widget.entries.isEmpty
        ? null
        : (height != null && height > 0 ? height.toDouble() : null);
  }

  void _rebuildLayout() {
    _pageLayer = null;
    if (_pages.isNotEmpty && _previousPages == null) {
      _previousPages = _pages;
      _previousBaseWidth = _contentWidth;
      _previousContentHeight = _contentHeight;
      _previousWasVertical = _vertical;
    }
    final vertical = widget.layoutDirection == ComicLayoutDirection.vertical;
    var width = vertical
        ? math.max(
            1.0,
            widget.originalSize
                ? _referenceWidth ?? widget.baseWidth
                : widget.baseWidth,
          )
        : math.max(
            1.0,
            widget.originalSize
                ? _referenceHeight ?? widget.viewport.height
                : widget.viewport.height,
          );
    var pixelScale = 1.0;
    if (widget.scaleMode != null && widget.entries.isNotEmpty) {
      final reference = widget.entries.firstWhere(
        (entry) => entry.id == _fitReferenceId,
        orElse: () => widget.entries.first,
      );
      final referenceSize = _sourceSize(reference);
      pixelScale = viewScaleFor(
        referenceSize,
        widget.viewport,
        widget.scaleMode!,
      );
      if (widget.scaleMode == ViewScaleMode.originalSize &&
          widget.uniformPageSize) {
        final first = _sourceSize(widget.entries.first);
        width = vertical ? first.width : first.height;
      } else {
        width =
            (vertical ? referenceSize.width : referenceSize.height) *
            pixelScale;
      }
      // Uniform layout uses page 1 as its pixel reference at every scale.
      final firstSize = _sourceSize(widget.entries.first);
      widget.onReferenceScaleChanged?.call(
        widget.uniformPageSize
            ? width / (vertical ? firstSize.width : firstSize.height)
            : pixelScale,
      );
    }
    var left = 0.0;
    var top = 0.0;
    final pages = <_ComicPageLayout>[];
    final orderedEntries =
        widget.layoutDirection == ComicLayoutDirection.horizontalRightToLeft
        ? widget.entries.reversed
        : widget.entries;
    for (final entry in orderedEntries) {
      final source = _sourceSize(entry);
      final pageWidth = !widget.uniformPageSize && widget.scaleMode != null
          ? source.width * pixelScale
          : vertical
          ? width
          : width * _aspect(entry);
      final pageHeight = !widget.uniformPageSize && widget.scaleMode != null
          ? source.height * pixelScale
          : vertical
          ? width / _aspect(entry)
          : width;
      pages.add(
        _ComicPageLayout(
          entry: entry,
          left: left,
          top: top,
          width: pageWidth,
          height: pageHeight,
        ),
      );
      if (vertical) {
        top += pageHeight + widget.pageGap;
      } else {
        left += pageWidth + widget.pageGap;
      }
    }
    _pages = pages;
    _contentWidth = vertical
        ? pages.fold(width, (value, page) => math.max(value, page.width))
        : math.max(0, left - widget.pageGap);
    _contentHeight = vertical
        ? math.max(0, top - widget.pageGap)
        : pages.fold(width, (value, page) => math.max(value, page.height));
    for (var index = 0; index < pages.length; index++) {
      final page = pages[index];
      pages[index] = _ComicPageLayout(
        entry: page.entry,
        left: vertical ? (_contentWidth - page.width) / 2 : page.left,
        top: vertical ? page.top : (_contentHeight - page.height) / 2,
        width: page.width,
        height: page.height,
      );
    }
    _logicalIndices = {
      for (var index = 0; index < widget.entries.length; index++)
        widget.entries[index].id: index,
    };
    final rtl =
        widget.layoutDirection == ComicLayoutDirection.horizontalRightToLeft;
    _pageGeometry = List<PageGeometry>.unmodifiable(
      <PageGeometry>[
        for (final page in pages)
          PageGeometry(
            index: _logicalIndices[page.entry.id]!,
            start: rtl
                ? _contentWidth - page.left - page.width
                : (vertical ? page.top : page.left),
            end: rtl
                ? _contentWidth - page.left
                : (vertical ? page.top + page.height : page.left + page.width),
          ),
      ]..sort((left, right) => left.index.compareTo(right.index)),
    );
    _layoutRevision++;
  }

  Size _sourceSize(ImageEntry entry) {
    final width =
        _sourceWidths[entry.id] ??
        entry.width?.toDouble() ??
        _referenceWidth ??
        widget.baseWidth;
    final safeWidth = width > 0 ? width : widget.baseWidth;
    return Size(safeWidth, safeWidth / _aspect(entry));
  }

  void _queueSizes() {
    final visible = _visiblePages.isEmpty
        ? {widget.currentIndex}
        : _visiblePages;
    final candidates = {...visible};
    final radius = math.max(0, widget.metadataPreloadPages);
    for (final index in visible) {
      for (var offset = 1; offset <= radius; offset++) {
        candidates.add(index - offset);
        candidates.add(index + offset);
      }
    }
    if (radius > 0 && _visibleStart != null && _visibleEnd != null) {
      final span = _visibleEnd! - _visibleStart!;
      for (final page in _geometryInRange(
        _visibleStart! - span,
        _visibleEnd! + span,
      )) {
        candidates.add(page.index);
      }
    }
    final sorted =
        candidates
            .where((index) => index >= 0 && index < widget.entries.length)
            .toList()
          ..sort((left, right) {
            final priority = (visible.contains(left) ? 0 : 1).compareTo(
              visible.contains(right) ? 0 : 1,
            );
            if (priority != 0) return priority;
            return (left - widget.currentIndex).abs().compareTo(
              (right - widget.currentIndex).abs(),
            );
          });
    _sizeQueue = sorted
        .map((index) => widget.entries[index])
        .where(
          (entry) =>
              (visible.contains(_logicalIndices[entry.id]) ||
                  widget.admittedPageIds == null ||
                  widget.admittedPageIds!.contains(entry.id)) &&
              !_aspects.containsKey(entry.id) &&
              !_failedSizePaths.contains(entry.id) &&
              !_loadingPaths.contains(entry.id) &&
              (entry.width == null ||
                  entry.width! <= 0 ||
                  entry.height == null ||
                  entry.height! <= 0),
        )
        .toList();
    _queueIndex = 0;
    _pumpSizeQueue();
  }

  void _pumpSizeQueue() {
    while (mounted &&
        _activeSizeLoads < math.max(1, widget.maxConcurrentSizeLoads) &&
        _queueIndex < _sizeQueue.length) {
      final entry = _sizeQueue[_queueIndex++];
      if (_loadingPaths.contains(entry.id)) continue;
      _loadingPaths.add(entry.id);
      _activeSizeLoads++;
      unawaited(_loadAspect(entry));
    }
  }

  void _scheduleLayout() {
    if (_layoutScheduled) return;
    _layoutScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _layoutScheduled = false;
      if (!mounted) return;
      setState(_rebuildLayout);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _loadAspect(ImageEntry entry) async {
    try {
      final size = await widget.loadSize(entry.id);
      if (!mounted || !_entryPaths.contains(entry.id) || size == null) {
        if (mounted && size == null) _failedSizePaths.add(entry.id);
        return;
      }
      if (size.width <= 0 || size.height <= 0) return;
      final aspect = size.width / size.height;
      if (aspect.isFinite && aspect > 0) {
        _sourceWidths[entry.id] = size.width;
        if (widget.entries.first.id == entry.id) {
          _referenceWidth = size.width;
          _referenceHeight = size.height;
        }
        _aspects[entry.id] = aspect;
        _scheduleLayout();
      }
    } on DecodeCancelled {
      // A reversed or downgraded window can need this page again later.
      return;
    } on Object {
      if (mounted) _failedSizePaths.add(entry.id);
      return;
    } finally {
      _loadingPaths.remove(entry.id);
      _activeSizeLoads--;
      _pumpSizeQueue();
    }
  }

  bool get _vertical => widget.layoutDirection == ComicLayoutDirection.vertical;

  Iterable<PageGeometry> _geometryInRange(double start, double end) sync* {
    // RTL geometry is normalized into the same monotonic logical coordinates.
    var low = 0;
    var high = _pageGeometry.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_pageGeometry[middle].end <= start) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    for (var index = low; index < _pageGeometry.length; index++) {
      final page = _pageGeometry[index];
      if (page.start >= end) break;
      if (page.end > start) yield page;
    }
  }

  void _scheduleVisibleReport() {
    if (_visibleReportScheduled) return;
    _visibleReportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibleReportScheduled = false;
      if (!mounted || _pages.isEmpty) return;
      final matrix = widget.controller.value;
      final scale = math.max(.001, matrix.getMaxScaleOnAxis());
      final translation = matrix.getTranslation();
      final offset = _vertical ? translation.y : translation.x;
      final viewportLength = _vertical
          ? widget.viewport.height
          : widget.viewport.width;
      final contentLength = _vertical ? _contentHeight : _contentWidth;
      final sceneStart = (-offset / scale).clamp(0.0, contentLength);
      final sceneEnd = ((viewportLength - offset) / scale).clamp(
        0.0,
        contentLength,
      );
      final rtl =
          widget.layoutDirection == ComicLayoutDirection.horizontalRightToLeft;
      final start = rtl ? contentLength - sceneEnd : sceneStart;
      final end = rtl ? contentLength - sceneStart : sceneEnd;
      final visible = {
        for (final page in _geometryInRange(start, end)) page.index,
      };
      if (_lastVisibleLayoutRevision == _layoutRevision &&
          _visiblePages.length == visible.length &&
          _visiblePages.containsAll(visible) &&
          _visibleStart != null &&
          (_visibleStart! - start).abs() < .5 &&
          _visibleEnd != null &&
          (_visibleEnd! - end).abs() < .5) {
        return;
      }
      _lastVisibleLayoutRevision = _layoutRevision;
      _visiblePages = visible;
      _visibleStart = start;
      _visibleEnd = end;
      // Run the viewport callback first, so the shared resource service can
      // promote visible work before nearby dimensions begin loading.
      widget.onVisiblePagesChanged?.call(
        Set.unmodifiable(visible),
        _pageGeometry,
        start,
        end,
      );
      _queueSizes();
    });
  }

  double _pageStart(_ComicPageLayout page) => _vertical ? page.top : page.left;

  double _pageLength(_ComicPageLayout page) =>
      _vertical ? page.height : page.width;

  int _pageAt(double primary) =>
      _pageAtIn(_pages, primary, vertical: _vertical);

  int _pageAtIn(
    List<_ComicPageLayout> pages,
    double primary, {
    required bool vertical,
  }) {
    var low = 0;
    var high = pages.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final page = pages[middle];
      final start = vertical ? page.top : page.left;
      final length = vertical ? page.height : page.width;
      if (start + length < primary) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low.clamp(0, math.max(0, pages.length - 1));
  }

  Offset _reconcileScenePoint(Offset scene) {
    final previous = _previousPages;
    final previousWidth = _previousBaseWidth;
    final previousHeight = _previousContentHeight;
    final previousWasVertical = _previousWasVertical;
    _previousPages = null;
    _previousBaseWidth = null;
    _previousContentHeight = null;
    _previousWasVertical = null;
    if (previous == null || previous.isEmpty || _pages.isEmpty) return scene;
    final oldVertical = previousWasVertical ?? true;
    final oldPrimary = oldVertical ? scene.dy : scene.dx;
    final index = _pageAtIn(previous, oldPrimary, vertical: oldVertical);
    final oldPage = previous[index];
    final currentIndex = _pages.indexWhere(
      (page) => page.entry.id == oldPage.entry.id,
    );
    if (currentIndex < 0) return scene;
    final current = _pages[currentIndex];
    final oldStart = oldVertical ? oldPage.top : oldPage.left;
    final oldLength = oldVertical ? oldPage.height : oldPage.width;
    final fraction = ((oldPrimary - oldStart) / oldLength).clamp(0.0, 1.0);
    final newPrimary = _pageStart(current) + fraction * _pageLength(current);
    final cross = oldVertical
        ? scene.dx / (previousWidth ?? _contentWidth) * _contentWidth
        : scene.dy / (previousHeight ?? _contentHeight) * _contentHeight;
    return _vertical ? Offset(cross, newPrimary) : Offset(newPrimary, cross);
  }

  ComicReadingPosition? _capturePosition() =>
      _captureAnchor(widget.layoutDirection);

  ComicReadingPosition? _captureAnchor(ComicLayoutDirection direction) {
    if (_pages.isEmpty) return null;
    final vertical = direction == ComicLayoutDirection.vertical;
    final matrix = widget.controller.value;
    final scale = math.max(0.001, matrix.getMaxScaleOnAxis());
    final translation = matrix.getTranslation();
    final primary = vertical
        ? (widget.viewport.height / 2 - translation.y) / scale
        : (widget.viewport.width / 2 - translation.x) / scale;
    final cross = vertical
        ? (widget.viewport.width / 2 - translation.x) / scale
        : (widget.viewport.height / 2 - translation.y) / scale;
    final page = _pages[_pageAtIn(_pages, primary, vertical: vertical)];
    final pageStart = vertical ? page.top : page.left;
    final pageLength = vertical ? page.height : page.width;
    return ComicReadingPosition(
      path: page.entry.id,
      fitReferenceId: _fitReferenceId,
      pageFraction: ((primary - pageStart) / pageLength).clamp(0.0, 1.0),
      crossFraction: (cross / (vertical ? _contentWidth : _contentHeight))
          .clamp(0.0, 1.0),
    );
  }

  Matrix4? _reconcileTransform(Matrix4 previous, Size viewport) {
    final anchor = _pendingDirectionAnchor;
    if (anchor == null) return null;
    _pendingDirectionAnchor = null;
    _previousPages = null;
    _previousBaseWidth = null;
    _previousContentHeight = null;
    _previousWasVertical = null;
    if (_resetScalePending) {
      _resetScalePending = false;
      return _transformForAnchor(anchor, Matrix4.identity(), viewport);
    }
    return _transformForAnchor(anchor, previous, viewport);
  }

  Matrix4? _transformForAnchor(
    ComicReadingPosition anchor,
    Matrix4 previous,
    Size viewport,
  ) {
    _ComicPageLayout? page;
    for (final candidate in _pages) {
      if (candidate.entry.id == anchor.path) {
        page = candidate;
        break;
      }
    }
    if (page == null) return null;
    final scale = previous.getMaxScaleOnAxis();
    final primary = _pageStart(page) + anchor.pageFraction * _pageLength(page);
    final cross =
        anchor.crossFraction * (_vertical ? _contentWidth : _contentHeight);
    final translation = _vertical
        ? Offset(
            viewport.width / 2 - cross * scale,
            viewport.height / 2 - primary * scale,
          )
        : Offset(
            viewport.width / 2 - primary * scale,
            viewport.height / 2 - cross * scale,
          );
    return Matrix4.identity()
      ..scaleByDouble(scale, scale, scale, 1)
      ..setTranslation(Vector3(translation.dx, translation.dy, 0));
  }

  void _flushCurrentPage() {
    _reportCurrent(widget.controller.value);
    _reportTimer?.cancel();
    if (_lastReportedIndex >= 0 && _lastReportedIndex < widget.entries.length) {
      widget.onCurrentPageChanged(_lastReportedIndex);
    }
  }

  void _reportCurrent(Matrix4 matrix) {
    if (_pages.isEmpty || _jumping || _holdReportUntilInteraction) return;
    final scale = matrix.getMaxScaleOnAxis();
    final safeScale = math.max(0.001, scale);
    final translation = matrix.getTranslation();
    final vertical = _vertical;
    final rtl =
        !vertical &&
        widget.layoutDirection == ComicLayoutDirection.horizontalRightToLeft;
    final contentLength = vertical ? _contentHeight : _contentWidth;
    final viewportLength = vertical
        ? widget.viewport.height
        : widget.viewport.width;
    if (contentLength * scale <= viewportLength + 0.5) {
      // Everything is visible at once. Keep the page chosen by the thumbnail
      // strip instead of deriving a page from the scroll position.
      return;
    }
    final offset = vertical ? translation.y : translation.x;
    final minTranslation = math.min(
      0.0,
      viewportLength - contentLength * scale,
    );
    // RTL starts at the right edge and scrolls toward the left, so its start
    // and end translations are the mirror of LTR and vertical layouts.
    final atStart = rtl ? offset <= minTranslation + 0.5 : offset >= -0.5;
    final atEnd = rtl ? offset >= -0.5 : offset <= minTranslation + 0.5;
    final anchor = vertical
        ? -translation.y / safeScale
        : rtl
        ? (widget.viewport.width - translation.x) / safeScale
        : -translation.x / safeScale;
    final _ComicPageLayout page;
    if (atStart) {
      page = rtl ? _pages.last : _pages.first;
    } else if (atEnd) {
      page = rtl ? _pages.first : _pages.last;
    } else {
      page = _pages[_pageAt(anchor.clamp(0.0, contentLength))];
    }
    final index = _logicalIndices[page.entry.id];
    if (index == null) return;
    if (index == _lastReportedIndex) return;
    _lastReportedIndex = index;
    _reportTimer?.cancel();
    _reportTimer = Timer(const Duration(milliseconds: 160), () {
      if (mounted) widget.onCurrentPageChanged(index);
    });
  }

  void _jumpTo(int index) {
    if (_pages.isEmpty || index < 0 || index >= _pages.length) return;
    _lastJumpToken = widget.jumpToken;
    final generation = ++_jumpGeneration;
    _jumping = true;
    _holdReportUntilInteraction = true;
    _lastReportedIndex = index;
    _reportTimer?.cancel();
    if (_initialTransform == null) {
      _initialTransform = _pageTransform(
        index,
        position: widget.initialPosition,
      );
      _jumping = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _jumpGeneration || _pages.isEmpty) return;
      widget.controller.value = _pageTransform(index);
      _jumping = false;
    });
  }

  Matrix4 _pageTransform(int index, {ComicReadingPosition? position}) {
    final scale = widget.controller.value.getMaxScaleOnAxis();
    final path = widget.entries[index].id;
    final page = _pages.firstWhere((candidate) => candidate.entry.id == path);
    final scaledWidth = _contentWidth * scale;
    final scaledHeight = _contentHeight * scale;
    final x = scaledWidth <= widget.viewport.width
        ? (widget.viewport.width - scaledWidth) / 2
        : widget.controller.value.getTranslation().x.clamp(
            widget.viewport.width - scaledWidth,
            0.0,
          );
    final y = scaledHeight <= widget.viewport.height
        ? (widget.viewport.height - scaledHeight) / 2
        : (-page.top * scale).clamp(widget.viewport.height - scaledHeight, 0.0);
    final targetX = _vertical
        ? x
        : scaledWidth <= widget.viewport.width
        ? (widget.viewport.width - scaledWidth) / 2
        : (widget.layoutDirection == ComicLayoutDirection.horizontalRightToLeft
                  ? widget.viewport.width - (page.left + page.width) * scale
                  : -page.left * scale)
              .clamp(widget.viewport.width - scaledWidth, 0.0);
    final targetY = _vertical
        ? y
        : (scaledHeight <= widget.viewport.height
              ? (widget.viewport.height - scaledHeight) / 2
              : widget.controller.value.getTranslation().y.clamp(
                  widget.viewport.height - scaledHeight,
                  0.0,
                ));
    var target = Matrix4.identity()
      ..scaleByDouble(scale, scale, scale, 1)
      ..setTranslation(Vector3(_vertical ? x : targetX, targetY, 0));
    if (position != null) {
      target = _transformForAnchor(position, target, widget.viewport) ?? target;
      final translation = target.getTranslation();
      target.setTranslationRaw(
        scaledWidth <= widget.viewport.width
            ? (widget.viewport.width - scaledWidth) / 2
            : translation.x.clamp(widget.viewport.width - scaledWidth, 0.0),
        scaledHeight <= widget.viewport.height
            ? (widget.viewport.height - scaledHeight) / 2
            : translation.y.clamp(widget.viewport.height - scaledHeight, 0.0),
        0,
      );
    }
    return target;
  }

  @override
  Widget build(BuildContext context) {
    if (_lastJumpToken != widget.jumpToken) _jumpTo(widget.currentIndex);
    final currentPath =
        widget.currentIndex >= 0 && widget.currentIndex < widget.entries.length
        ? widget.entries[widget.currentIndex].id
        : null;
    return Listener(
      onPointerDown: (_) => _releaseReportHold(),
      onPointerPanZoomStart: (_) => _releaseReportHold(),
      onPointerSignal: (_) => _releaseReportHold(),
      child: ZoomableViewport(
        initialTransform: _initialTransform,
        contentSize: Size(_contentWidth, _contentHeight),
        controller: widget.controller,
        commands: widget.commands,
        onVerticalBoundary: widget.onVerticalBoundary,
        onHorizontalBoundary: widget.onVerticalBoundary,
        reconcileScenePoint: _reconcileScenePoint,
        reconcileTransform: _reconcileTransform,
        contentRevision: _layoutRevision,
        startAtTop: true,
        startAtLeft:
            widget.layoutDirection ==
            ComicLayoutDirection.horizontalLeftToRight,
        startAtRight:
            widget.layoutDirection ==
            ComicLayoutDirection.horizontalRightToLeft,
        zoomAroundCenter: widget.zoomAroundCenter,
        minScale: widget.minScale,
        maxScale: widget.maxScale,
        wheelScrollSpeed: widget.wheelScrollSpeed,
        wheelZoomSpeed: widget.wheelZoomSpeed,
        wheelPan: (delta) => _vertical
            ? Offset(0, -delta.dy)
            : Offset(
                delta.dy == 0
                    ? -delta.dx
                    : widget.layoutDirection ==
                          ComicLayoutDirection.horizontalRightToLeft
                    ? delta.dy
                    : -delta.dy,
                0,
              ),
        child: SizedBox(
          width: _contentWidth,
          height: _contentHeight,
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final matrix = widget.controller.value;
              _reportCurrent(matrix);
              _scheduleVisibleReport();
              final scale = math.max(0.001, matrix.getMaxScaleOnAxis());
              final translation = matrix.getTranslation();
              final preload = widget.metadataPreloadPages == 0
                  ? 0.0
                  : (_vertical
                            ? widget.viewport.height
                            : widget.viewport.width) /
                        scale;
              final visibleStart =
                  (_vertical ? -translation.y : -translation.x) / scale;
              final visibleEnd =
                  ((_vertical
                      ? widget.viewport.height - translation.y
                      : widget.viewport.width - translation.x) /
                  scale);
              final sceneStart = math.max(
                0,
                (_vertical ? -translation.y : -translation.x) / scale - preload,
              );
              final sceneEnd = math.min(
                _vertical ? _contentHeight : _contentWidth,
                ((_vertical
                            ? widget.viewport.height - translation.y
                            : widget.viewport.width - translation.x) /
                        scale) +
                    preload,
              );
              final pages = <_ComicPageLayout>[];
              final firstVisible = _pageAt(sceneStart.toDouble());
              for (var index = firstVisible; index < _pages.length; index++) {
                final page = _pages[index];
                if (_pageStart(page) > sceneEnd) break;
                final isVisible =
                    _pageStart(page) < visibleEnd &&
                    _pageStart(page) + _pageLength(page) > visibleStart;
                if (!isVisible &&
                    widget.admittedPageIds != null &&
                    !widget.admittedPageIds!.contains(page.entry.id)) {
                  continue;
                }
                pages.add(page);
              }
              if (_pageLayer != null &&
                  _builtCurrentPath == currentPath &&
                  listEquals(_builtPages, pages)) {
                return _pageLayer!;
              }
              _builtPages = pages;
              _builtCurrentPath = currentPath;
              return _pageLayer = Stack(
                children: [
                  for (final page in pages)
                    Positioned(
                      key: ValueKey(page.entry.id),
                      left: page.left,
                      top: page.top,
                      width: page.width,
                      height: page.height,
                      child: widget.buildPage(
                        page.entry,
                        page.entry.id == currentPath,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
