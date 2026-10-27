import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'window_placement_store.dart';

class WindowPlacementController with WindowListener, WidgetsBindingObserver {
  WindowPlacementController(
    this.store, {
    Future<List<WindowWorkArea>> Function()? loadWorkAreas,
    double Function()? coordinateScale,
  }) : _loadWorkAreas = loadWorkAreas ?? _screenWorkAreas,
       _coordinateScale = coordinateScale ?? _windowCoordinateScale;

  final WindowPlacementStore store;
  final Future<List<WindowWorkArea>> Function() _loadWorkAreas;
  final double Function() _coordinateScale;
  final String _source =
      '$pid-${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 32)}';
  Rect? _lastBounds;
  Timer? _timer;
  int _latestEvent = 0;
  int? _pendingEvent;
  WindowPlacement? _unsaved;
  Future<void> _tail = Future<void>.value();
  bool _started = false;

  Future<void> restore() async {
    final areas = await _loadWorkAreas();
    if (areas.isEmpty) return;
    final saved = await store.load();
    final primary = areas.first;
    final placement =
        (saved ??
                WindowPlacement(
                  x: primary.x + (primary.width - 1280) / 2,
                  y: primary.y + (primary.height - 800) / 2,
                  width: 1280,
                  height: 800,
                  updatedAt: 0,
                  source: _source,
                  scaleFactor: primary.scaleFactor,
                ))
            .fitToWorkAreas(areas);
    // Windows plugins express global coordinates relative to each window's DPI.
    // Move in the current window's units to land on the target monitor first.
    final ratio = placement.scaleFactor / _coordinateScale();
    await windowManager.setBounds(
      Rect.fromLTWH(
        placement.x * ratio,
        placement.y * ratio,
        placement.width * ratio,
        placement.height * ratio,
      ),
    );
  }

  Future<void> start() async {
    _lastBounds = await windowManager.getBounds();
    _started = true;
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onWindowMove() => _schedule();
  @override
  void onWindowMoved() => _schedule(immediate: true);
  @override
  void onWindowResize() => _schedule();
  @override
  void onWindowResized() => _schedule(immediate: true);

  // Windows drag events do not cover OS snapping or external resizing.
  @override
  void didChangeMetrics() => _schedule();

  @override
  void onWindowBlur() => _schedule(immediate: true);

  void _schedule({bool immediate = false}) {
    if (!_started) return;
    _latestEvent = math.max(
      DateTime.now().microsecondsSinceEpoch,
      _latestEvent + 1,
    );
    _pendingEvent = _latestEvent;
    _timer?.cancel();
    if (immediate) {
      unawaited(_capture());
      return;
    }
    _timer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_capture()),
    );
  }

  Future<void> _capture() {
    final event = _pendingEvent;
    _pendingEvent = null;
    final operation = _tail.then((_) async {
      if (event == null || event != _latestEvent || !_started) return;
      final transient = await Future.wait([
        windowManager.isMaximized(),
        windowManager.isMinimized(),
        windowManager.isFullScreen(),
      ]);
      if (transient.any((value) => value)) return;
      final bounds = await windowManager.getBounds();
      if (event != _latestEvent ||
          !_started ||
          !bounds.isFinite ||
          bounds.isEmpty ||
          _sameBounds(bounds, _lastBounds)) {
        return;
      }
      _lastBounds = bounds;
      final placement = WindowPlacement(
        x: bounds.left,
        y: bounds.top,
        width: bounds.width,
        height: bounds.height,
        updatedAt: event,
        source: _source,
        scaleFactor: _coordinateScale(),
      );
      _unsaved = placement;
      await store.save(placement);
      if (identical(_unsaved, placement)) _unsaved = null;
    });
    _tail = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        debugPrint('Unable to save window placement: $error');
      },
    );
    return operation;
  }

  Future<void> flush() async {
    _timer?.cancel();
    if (_pendingEvent != null) await _capture();
    await _tail;
    // Keep the event time of queued samples; closing must not re-date an old drag.
    if (_started) {
      _schedule();
      _timer?.cancel();
      await _capture();
      await _tail;
    }
    final pending = _unsaved;
    if (pending != null) {
      await store.save(pending);
      if (identical(_unsaved, pending)) _unsaved = null;
    }
  }

  void dispose() {
    _started = false;
    _timer?.cancel();
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
  }

  static bool _sameBounds(Rect a, Rect? b) =>
      b != null &&
      (a.left - b.left).abs() < 0.5 &&
      (a.top - b.top).abs() < 0.5 &&
      (a.width - b.width).abs() < 0.5 &&
      (a.height - b.height).abs() < 0.5;

  static Future<List<WindowWorkArea>> _screenWorkAreas() async {
    final primary = await screenRetriever.getPrimaryDisplay();
    final displays = [primary, ...await screenRetriever.getAllDisplays()];
    return [
      for (final display in displays)
        if ((display.visibleSize ?? display.size).width > 0 &&
            (display.visibleSize ?? display.size).height > 0)
          WindowWorkArea(
            display.visiblePosition?.dx ?? 0,
            display.visiblePosition?.dy ?? 0,
            (display.visibleSize ?? display.size).width,
            (display.visibleSize ?? display.size).height,
            scaleFactor: Platform.isWindows
                ? (display.scaleFactor?.toDouble() ?? 1)
                : 1,
          ),
    ];
  }

  static double _windowCoordinateScale() => Platform.isWindows
      ? PlatformDispatcher.instance.views.first.devicePixelRatio
      : 1;
}
