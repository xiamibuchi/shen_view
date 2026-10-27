import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart';

class ZoomableViewportCommands extends ChangeNotifier {
  double _pendingHorizontalDelta = 0;
  double _pendingVerticalDelta = 0;
  double? _pendingScale;
  bool _pendingReset = false;
  double? Function(double direction)? _horizontalDistance;
  double? Function(double direction)? _verticalDistance;

  double? remainingHorizontalDistance(double direction) =>
      _horizontalDistance?.call(direction);

  void _attachHorizontal(double? Function(double direction) distance) {
    _horizontalDistance = distance;
  }

  void _detachHorizontal(double? Function(double direction) distance) {
    if (_horizontalDistance == distance) _horizontalDistance = null;
  }

  double? remainingVerticalDistance(double direction) =>
      _verticalDistance?.call(direction);

  void _attach(double? Function(double direction) distance) {
    _verticalDistance = distance;
  }

  void _detach(double? Function(double direction) distance) {
    if (_verticalDistance == distance) _verticalDistance = null;
  }

  void moveVertically(double delta) {
    _pendingVerticalDelta += delta;
    notifyListeners();
  }

  void moveHorizontally(double delta) {
    _pendingHorizontalDelta += delta;
    notifyListeners();
  }

  void setScale(double scale) {
    _pendingScale = scale;
    notifyListeners();
  }

  void resetView() {
    _pendingReset = true;
    notifyListeners();
  }

  bool consumeReset() {
    final reset = _pendingReset;
    _pendingReset = false;
    return reset;
  }

  double consumeHorizontalDelta() {
    final delta = _pendingHorizontalDelta;
    _pendingHorizontalDelta = 0;
    return delta;
  }

  double consumeVerticalDelta() {
    final delta = _pendingVerticalDelta;
    _pendingVerticalDelta = 0;
    return delta;
  }

  double? consumeScale() {
    final scale = _pendingScale;
    _pendingScale = null;
    return scale;
  }
}

enum VerticalScrollBoundary { start, end, none }

class ZoomableViewport extends StatefulWidget {
  const ZoomableViewport({
    required this.child,
    required this.contentSize,
    required this.controller,
    this.startAtTop = false,
    this.startAtLeft = false,
    this.startAtRight = false,
    this.zoomAroundCenter = false,
    this.minScale = 0.05,
    this.maxScale = 16,
    this.onWheel,
    this.commands,
    this.onVerticalBoundary,
    this.onHorizontalBoundary,
    this.wheelPan,
    this.zoomOnWheel = false,
    this.wheelScrollSpeed = 1,
    this.wheelZoomSpeed = 1,
    this.reconcileTransform,
    this.reconcileScenePoint,
    this.contentRevision = 0,
    this.resetRequest = 0,
    this.onInteractionUpdate,
    this.onInteractionEnd,
    this.onHorizontalSwipe,
    this.initialTransform,
    this.resetTransform,
    super.key,
  });

  final Widget child;
  final Size contentSize;
  final TransformationController controller;
  final bool startAtTop;
  final bool startAtLeft;
  final bool startAtRight;
  final bool zoomAroundCenter;
  final double minScale;
  final double maxScale;
  final ValueChanged<Offset>? onWheel;
  final ZoomableViewportCommands? commands;
  final ValueChanged<VerticalScrollBoundary>? onVerticalBoundary;
  final ValueChanged<VerticalScrollBoundary>? onHorizontalBoundary;
  final Offset Function(Offset delta)? wheelPan;
  final bool zoomOnWheel;
  final double wheelScrollSpeed;
  final double wheelZoomSpeed;
  final Matrix4? Function(Matrix4 previous, Size viewport)? reconcileTransform;
  final Offset Function(Offset previousScenePoint)? reconcileScenePoint;
  final int contentRevision;
  final int resetRequest;
  final ValueChanged<double>? onInteractionUpdate;
  final VoidCallback? onInteractionEnd;

  /// One-finger touch only, at fit size: -1 for a rightward swipe, +1 leftward.
  final ValueChanged<int>? onHorizontalSwipe;
  final Matrix4? initialTransform;
  final Matrix4? resetTransform;

  @override
  State<ZoomableViewport> createState() => _ZoomableViewportState();
}

class _ZoomableViewportState extends State<ZoomableViewport> {
  Offset? _lastFocalPoint;
  double _lastGestureScale = 1;
  Size? _viewportSize;
  bool _applyingMatrix = false;
  bool _centerScheduled = false;
  bool _contentReconcileScheduled = false;
  Size? _pendingOldContentSize;
  bool _viewportReconcileScheduled = false;
  bool _resetPending = false;
  bool _resetPublishScheduled = false;
  Matrix4? _resetPaintMatrix;
  Size? _pendingPreviousViewport;
  Size? _pendingViewport;
  Timer? _inertiaTimer;
  Offset _inertiaVelocity = Offset.zero;
  DateTime? _lastInertiaTick;
  final _touchPointers = <int>{};
  bool _swipeEligible = false;
  Offset _swipeDelta = Offset.zero;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    widget.commands?.addListener(_onCommand);
    widget.commands?._attachHorizontal(_remainingHorizontalDistance);
    widget.commands?._attach(_remainingVerticalDistance);
  }

  @override
  void didUpdateWidget(covariant ZoomableViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    if (oldWidget.commands != widget.commands) {
      oldWidget.commands?.removeListener(_onCommand);
      oldWidget.commands?._detachHorizontal(_remainingHorizontalDistance);
      oldWidget.commands?._detach(_remainingVerticalDistance);
      widget.commands?.addListener(_onCommand);
      widget.commands?._attachHorizontal(_remainingHorizontalDistance);
      widget.commands?._attach(_remainingVerticalDistance);
    }
    if (widget.resetRequest != oldWidget.resetRequest ||
        (widget.resetTransform != null &&
            widget.resetTransform != oldWidget.resetTransform)) {
      _swipeEligible = false;
      _stopInertia();
      _resetPending = true;
      _pendingOldContentSize = null;
    } else if (oldWidget.contentSize != widget.contentSize ||
        oldWidget.contentRevision != widget.contentRevision) {
      _stopInertia();
      _scheduleContentReconcile(oldWidget.contentSize);
    }
  }

  @override
  void dispose() {
    _inertiaTimer?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    widget.commands?.removeListener(_onCommand);
    widget.commands?._detachHorizontal(_remainingHorizontalDistance);
    widget.commands?._detach(_remainingVerticalDistance);
    super.dispose();
  }

  void _onCommand() {
    if (!mounted) return;
    if (widget.commands?.consumeReset() ?? false) {
      _stopInertia();
      final viewport = _viewportSize;
      if (viewport != null) {
        // Apply the final placement directly, without painting an identity
        // transform for one frame before the image is centered again.
        _setMatrix(1, _initialTranslation(viewport, 1));
      }
    }
    final requestedScale = widget.commands?.consumeScale();
    if (requestedScale != null) {
      _stopInertia();
      final current = widget.controller.value.getMaxScaleOnAxis();
      if (current > 0) {
        _zoomAt(
          _viewportSize?.center(Offset.zero) ?? Offset.zero,
          requestedScale / current,
        );
      }
    }
    final horizontal = widget.commands?.consumeHorizontalDelta() ?? 0;
    if (horizontal != 0 && _remainingHorizontalDistance(horizontal) != null) {
      _stopInertia();
      _panBy(Offset(horizontal, 0));
      final boundary = (_remainingHorizontalDistance(horizontal) ?? 0) <= 0.01
          ? horizontal < 0
                ? VerticalScrollBoundary.end
                : VerticalScrollBoundary.start
          : VerticalScrollBoundary.none;
      widget.onHorizontalBoundary?.call(boundary);
    }
    final delta = widget.commands?.consumeVerticalDelta() ?? 0;
    if (delta == 0) return;
    if (_remainingVerticalDistance(delta) == null) return;
    _stopInertia();
    _panBy(Offset(0, delta));
    final boundary =
        (_remainingVerticalDistance(delta) ?? double.infinity) <= 0.01
        ? delta < 0
              ? VerticalScrollBoundary.end
              : VerticalScrollBoundary.start
        : VerticalScrollBoundary.none;
    widget.onVerticalBoundary?.call(boundary);
  }

  double? _remainingVerticalDistance(double direction) {
    final viewport = _viewportSize;
    if (viewport == null || widget.contentSize.isEmpty) return null;
    final matrix = widget.controller.value;
    final height = widget.contentSize.height * matrix.getMaxScaleOnAxis();
    if (height <= viewport.height) return 0;
    final translation = matrix.getTranslation();
    return math.max(
      0,
      direction < 0 ? translation.y + height - viewport.height : -translation.y,
    );
  }

  double? _remainingHorizontalDistance(double direction) {
    final viewport = _viewportSize;
    if (viewport == null || widget.contentSize.isEmpty) return null;
    final matrix = widget.controller.value;
    final width = widget.contentSize.width * matrix.getMaxScaleOnAxis();
    if (width <= viewport.width) return 0;
    final translation = matrix.getTranslation();
    return math.max(
      0,
      direction < 0 ? translation.x + width - viewport.width : -translation.x,
    );
  }

  void _onControllerChanged() {
    if (_applyingMatrix || !mounted) return;
    final matrix = widget.controller.value;
    final translation = matrix.getTranslation();
    if (matrix.getMaxScaleOnAxis() <= 1.000001 &&
        translation.x.abs() < 0.001 &&
        translation.y.abs() < 0.001) {
      _scheduleCenter();
    }
  }

  void _scheduleCenter() {
    if (_centerScheduled) return;
    _centerScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerScheduled = false;
      if (!mounted || _viewportSize == null) return;
      final viewport = _viewportSize!;
      final matrix = widget.controller.value;
      final scale = matrix.getMaxScaleOnAxis();
      _setMatrix(scale, _initialTranslation(viewport, scale));
    });
  }

  Offset _initialTranslation(Size viewport, double scale) {
    final width = widget.contentSize.width * scale;
    final height = widget.contentSize.height * scale;
    return Offset(
      widget.startAtLeft
          ? 0
          : widget.startAtRight
          ? viewport.width - width
          : (viewport.width - width) / 2,
      widget.startAtTop ? 0 : (viewport.height - height) / 2,
    );
  }

  void _placeBeforePaint(Size viewport, double scale, {Offset? offset}) {
    final nextScale = _clampScale(scale);
    final translation = _clampTranslation(
      nextScale,
      offset ?? _initialTranslation(viewport, nextScale),
    );
    _resetPaintMatrix = Matrix4.identity()
      ..scaleByDouble(nextScale, nextScale, nextScale, 1)
      ..setTranslationRaw(translation.dx, translation.dy, 0);
    if (_resetPublishScheduled) return;
    _resetPublishScheduled = true;
    // Paint at the final position immediately. Publish the shared controller
    // after layout so status controls and session listeners can safely rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resetPublishScheduled = false;
      final matrix = _resetPaintMatrix;
      _resetPaintMatrix = null;
      if (!mounted || matrix == null) return;
      final offset = matrix.getTranslation();
      _setMatrix(matrix.getMaxScaleOnAxis(), Offset(offset.x, offset.y));
    });
  }

  void _scheduleContentReconcile(Size oldContentSize) {
    _pendingOldContentSize ??= oldContentSize;
    if (_contentReconcileScheduled) return;
    _contentReconcileScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _contentReconcileScheduled = false;
      final previousContentSize = _pendingOldContentSize;
      _pendingOldContentSize = null;
      if (!mounted ||
          _viewportSize == null ||
          previousContentSize == null ||
          previousContentSize.isEmpty ||
          widget.contentSize.isEmpty) {
        return;
      }
      final matrix = widget.controller.value;
      final reconciledTransform = widget.reconcileTransform?.call(
        matrix,
        _viewportSize!,
      );
      if (reconciledTransform != null) {
        final translation = reconciledTransform.getTranslation();
        _setMatrix(
          reconciledTransform.getMaxScaleOnAxis(),
          Offset(translation.x, translation.y),
        );
        return;
      }
      final scale = matrix.getMaxScaleOnAxis();
      final translation = matrix.getTranslation();
      final oldScene = Offset(
        ((_viewportSize!.width / 2) - translation.x) / scale,
        ((_viewportSize!.height / 2) - translation.y) / scale,
      );
      final anchor = Offset(
        oldScene.dx / previousContentSize.width,
        oldScene.dy / previousContentSize.height,
      );
      final reconciledScene = widget.reconcileScenePoint?.call(oldScene);
      final scaledHeight = widget.contentSize.height * scale;
      final keepTop =
          widget.startAtTop &&
          scaledHeight > _viewportSize!.height &&
          translation.y.abs() < 1;
      _setMatrix(
        scale,
        Offset(
          _viewportSize!.width / 2 -
              (reconciledScene?.dx ?? anchor.dx * widget.contentSize.width) *
                  scale,
          keepTop
              ? 0
              : _viewportSize!.height / 2 -
                    (reconciledScene?.dy ??
                            anchor.dy * widget.contentSize.height) *
                        scale,
        ),
      );
    });
  }

  void _scheduleViewportReconcile(Size previousViewport, Size viewport) {
    _pendingPreviousViewport ??= previousViewport;
    _pendingViewport = viewport;
    if (_viewportReconcileScheduled) return;
    _viewportReconcileScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportReconcileScheduled = false;
      final previous = _pendingPreviousViewport;
      final current = _pendingViewport;
      _pendingPreviousViewport = null;
      _pendingViewport = null;
      if (!mounted || previous == null || current == null) return;
      final matrix = widget.controller.value;
      final scale = matrix.getMaxScaleOnAxis();
      final translation = matrix.getTranslation();
      final scene = Offset(
        (previous.width / 2 - translation.x) / scale,
        (previous.height / 2 - translation.y) / scale,
      );
      _setMatrix(
        scale,
        Offset(
          current.width / 2 - scene.dx * scale,
          current.height / 2 - scene.dy * scale,
        ),
      );
    });
  }

  double _clampScale(double scale) =>
      scale.clamp(widget.minScale, widget.maxScale);

  Offset _clampTranslation(double scale, Offset translation) {
    final viewport = _viewportSize!;
    final scaledWidth = widget.contentSize.width * scale;
    final scaledHeight = widget.contentSize.height * scale;
    final x = scaledWidth <= viewport.width
        ? (viewport.width - scaledWidth) / 2
        : translation.dx.clamp(viewport.width - scaledWidth, 0.0);
    final y = scaledHeight <= viewport.height
        ? (viewport.height - scaledHeight) / 2
        : translation.dy.clamp(viewport.height - scaledHeight, 0.0);
    return Offset(x, y);
  }

  void _setMatrix(double scale, Offset translation) {
    final viewport = _viewportSize;
    if (viewport == null || widget.contentSize.isEmpty) return;
    final nextScale = _clampScale(scale);
    final currentTranslation = widget.controller.value.getTranslation();
    final nextTranslation = _clampTranslation(nextScale, translation);
    final next = Matrix4.identity()
      ..scaleByDouble(nextScale, nextScale, nextScale, 1)
      ..setTranslation(Vector3(nextTranslation.dx, nextTranslation.dy, 0));
    if ((nextScale - widget.controller.value.getMaxScaleOnAxis()).abs() <
            0.000001 &&
        (nextTranslation.dx - currentTranslation.x).abs() < 0.001 &&
        (nextTranslation.dy - currentTranslation.y).abs() < 0.001) {
      return;
    }
    _applyingMatrix = true;
    widget.controller.value = next;
    _applyingMatrix = false;
    widget.onInteractionUpdate?.call(nextScale);
  }

  Offset _scenePoint(Matrix4 matrix, Offset viewportPoint) {
    final scale = matrix.getMaxScaleOnAxis();
    final translation = matrix.getTranslation();
    return Offset(
      (viewportPoint.dx - translation.x) / scale,
      (viewportPoint.dy - translation.y) / scale,
    );
  }

  void _zoomAt(Offset focalPoint, double factor) {
    if (_viewportSize == null) return;
    final matrix = widget.controller.value;
    final oldScale = matrix.getMaxScaleOnAxis();
    final nextScale = _clampScale(oldScale * factor);
    final zoomPoint = widget.zoomAroundCenter
        ? _viewportSize!.center(Offset.zero)
        : focalPoint;
    final scene = _scenePoint(matrix, zoomPoint);
    _setMatrix(
      nextScale,
      Offset(
        zoomPoint.dx - scene.dx * nextScale,
        zoomPoint.dy - scene.dy * nextScale,
      ),
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    _stopInertia();
    _lastFocalPoint = details.localFocalPoint;
    _lastGestureScale = 1;
    _swipeEligible =
        widget.onHorizontalSwipe != null &&
        _touchPointers.length == 1 &&
        details.pointerCount == 1 &&
        !_canPan;
    _swipeDelta = Offset.zero;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final previousFocal = _lastFocalPoint;
    if (previousFocal == null) return;
    final scaleDelta = details.scale / _lastGestureScale;
    _swipeDelta += details.localFocalPoint - previousFocal;
    if (details.pointerCount != 1 || (details.scale - 1).abs() > 0.001) {
      _swipeEligible = false;
    }
    if ((scaleDelta - 1).abs() > 0.000001) {
      _zoomAt(details.localFocalPoint, scaleDelta);
    }
    final current = widget.controller.value.getTranslation();
    _setMatrix(
      widget.controller.value.getMaxScaleOnAxis(),
      Offset(current.x, current.y) + (details.localFocalPoint - previousFocal),
    );
    _lastFocalPoint = details.localFocalPoint;
    _lastGestureScale = details.scale;
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _lastFocalPoint = null;
    _lastGestureScale = 1;
    _setMatrix(
      widget.controller.value.getMaxScaleOnAxis(),
      Offset(
        widget.controller.value.getTranslation().x,
        widget.controller.value.getTranslation().y,
      ),
    );
    final swipe =
        _swipeEligible &&
        !_canPan &&
        _swipeDelta.dx.abs() >= 64 &&
        _swipeDelta.dx.abs() > _swipeDelta.dy.abs() * 1.5;
    _swipeEligible = false;
    if (swipe) {
      widget.onHorizontalSwipe?.call(_swipeDelta.dx < 0 ? 1 : -1);
    } else {
      _startInertia(details.velocity.pixelsPerSecond);
    }
    widget.onInteractionEnd?.call();
  }

  void _startInertia(Offset velocity) {
    _stopInertia();
    if (velocity.distance < 80 || !_canPan) return;
    _inertiaVelocity = velocity;
    _inertiaTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final now = DateTime.now();
      final previous = _lastInertiaTick;
      _lastInertiaTick = now;
      final elapsed = previous == null
          ? 1 / 60
          : now.difference(previous).inMicroseconds / 1000000;
      final applied = _panBy(_inertiaVelocity * elapsed);
      _inertiaVelocity *= math.pow(0.0025, elapsed).toDouble();
      if (applied.distance < 0.01 || _inertiaVelocity.distance < 24) {
        _stopInertia();
      }
    });
  }

  bool get _canPan {
    final scale = widget.controller.value.getMaxScaleOnAxis();
    final viewport = _viewportSize;
    if (viewport == null) return false;
    return widget.contentSize.width * scale > viewport.width ||
        widget.contentSize.height * scale > viewport.height;
  }

  Offset _panBy(Offset delta) {
    final current = widget.controller.value.getTranslation();
    final before = Offset(current.x, current.y);
    _setMatrix(widget.controller.value.getMaxScaleOnAxis(), before + delta);
    final next = widget.controller.value.getTranslation();
    return Offset(next.x, next.y) - before;
  }

  void _stopInertia() {
    _inertiaTimer?.cancel();
    _inertiaTimer = null;
    _inertiaVelocity = Offset.zero;
    _lastInertiaTick = null;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final ctrlPressed =
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight);
    if (!event.scrollDelta.dx.isFinite ||
        !event.scrollDelta.dy.isFinite ||
        event.scrollDelta == Offset.zero) {
      return;
    }
    if (ctrlPressed || widget.zoomOnWheel) {
      if (event.scrollDelta.dy == 0) return;
      _zoomAt(
        event.localPosition,
        math.exp(-event.scrollDelta.dy * widget.wheelZoomSpeed / 240),
      );
    } else {
      if (widget.wheelPan != null) {
        _stopInertia();
        _panBy(widget.wheelPan!(event.scrollDelta * widget.wheelScrollSpeed));
        return;
      }
      if (widget.onWheel != null) {
        final current = widget.controller.value.getTranslation();
        _setMatrix(
          widget.controller.value.getMaxScaleOnAxis(),
          Offset(
            current.x,
            current.y - event.scrollDelta.dy * widget.wheelScrollSpeed,
          ),
        );
        widget.onWheel!.call(event.scrollDelta);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          if (_viewportSize != viewport) {
            final previousViewport = _viewportSize;
            _viewportSize = viewport;
            if (previousViewport == null) {
              final initial = widget.initialTransform;
              final translation = initial?.getTranslation();
              _placeBeforePaint(
                viewport,
                (initial ?? widget.controller.value).getMaxScaleOnAxis(),
                offset: translation == null
                    ? null
                    : Offset(translation.x, translation.y),
              );
            } else {
              _scheduleViewportReconcile(previousViewport, viewport);
            }
          }
          if (_resetPending) {
            _resetPending = false;
            final reset = widget.resetTransform;
            final offset = reset?.getTranslation();
            _placeBeforePaint(
              viewport,
              reset?.getMaxScaleOnAxis() ?? 1,
              offset: offset == null ? null : Offset(offset.x, offset.y),
            );
          }
          return AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => Listener(
              onPointerDown: (event) {
                if (event.kind == PointerDeviceKind.touch) {
                  _touchPointers.add(event.pointer);
                  if (_touchPointers.length > 1) _swipeEligible = false;
                }
              },
              onPointerUp: (event) => _touchPointers.remove(event.pointer),
              onPointerCancel: (event) {
                _touchPointers.remove(event.pointer);
                _swipeEligible = false;
              },
              onPointerSignal: _onPointerSignal,
              child: RawGestureDetector(
                behavior: HitTestBehavior.opaque,
                gestures: {
                  ScaleGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        ScaleGestureRecognizer
                      >(
                        () => ScaleGestureRecognizer(
                          debugOwner: this,
                          // Keep right clicks available even if an old scale
                          // gesture missed its release event.
                          allowedButtonsFilter: (buttons) =>
                              buttons == kPrimaryButton,
                        ),
                        (instance) => instance
                          ..onStart = _onScaleStart
                          ..onUpdate = _onScaleUpdate
                          ..onEnd = _onScaleEnd
                          ..gestureSettings = MediaQuery.maybeGestureSettingsOf(
                            context,
                          ),
                      ),
                },
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: 0,
                    minHeight: 0,
                    maxWidth: double.infinity,
                    maxHeight: double.infinity,
                    child: Transform(
                      alignment: Alignment.topLeft,
                      transform: _resetPaintMatrix ?? widget.controller.value,
                      child: SizedBox(
                        width: widget.contentSize.width,
                        height: widget.contentSize.height,
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
