import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../application/decode_request.dart';
import '../application/hdr_display_service.dart';
import '../application/hdr_frame.dart';
import '../application/image_resource_service.dart';

/// Native surfaces sit above Flutter. While an overlay is open, expose the
/// identical SDR fallback below it so menus, tooltips and dialogs stay usable.
class HdrOverlayScope extends InheritedWidget {
  const HdrOverlayScope({
    required this.suspended,
    required super.child,
    super.key,
  });
  final bool suspended;
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<HdrOverlayScope>()
          ?.suspended ??
      false;

  @override
  bool updateShouldNotify(HdrOverlayScope oldWidget) =>
      suspended != oldWidget.suspended;
}

/// Defines the visible canvas, including space reserved for floating controls.
class HdrViewportBoundary extends SingleChildRenderObjectWidget {
  const HdrViewportBoundary({
    required super.child,
    this.insets = EdgeInsets.zero,
    super.key,
  });
  final EdgeInsets insets;

  @override
  RenderObject createRenderObject(BuildContext context) => _HdrBoundary(insets);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderProxyBox renderObject,
  ) {
    (renderObject as _HdrBoundary).insets = insets;
  }
}

class _HdrBoundary extends RenderProxyBox {
  _HdrBoundary(this.insets);
  EdgeInsets insets;
}

class HdrImageView extends StatefulWidget {
  const HdrImageView({
    required this.path,
    required this.revision,
    required this.sourceSize,
    required this.fit,
    required this.child,
    this.service,
    this.runDecode,
    this.decodeFrame,
    super.key,
  });
  final String path;
  final Object revision;
  final Size sourceSize;
  final BoxFit fit;
  final Widget child;
  final HdrDisplayService? service;
  final Future<HdrFrame> Function(DecodeRequest)? decodeFrame;
  final Future<bool> Function(DecodeRequest, Future<bool> Function())?
  runDecode;

  @override
  State<HdrImageView> createState() => _HdrImageViewState();
}

class _HdrImageViewState extends State<HdrImageView>
    with WidgetsBindingObserver {
  static var _nextId = 0;
  static final _live = <_HdrImageViewState>{};
  static var _registered = false;
  HdrDisplayService get _service =>
      widget.service ?? HdrDisplayService.instance;
  final _key = GlobalKey();
  final _fallbackKey = GlobalKey();
  int _id = 0;
  DecodeRequest? _request;
  Timer? _probeTimer;
  StreamSubscription<String>? _invalidationSubscription;
  bool _uploaded = false;
  bool _nativeVisible = false;
  bool _probing = false;
  bool _suspended = false;
  bool _lifecycleActive = true;
  bool _wasSuspended = true;
  String? _output;
  String? _failedOutput;
  List<double>? _lastGeometry;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _invalidationSubscription = _service.invalidations.listen(_invalidated);
    _live.add(this);
    if (!_registered) {
      _registered = true;
      // Observe existing Flutter frames without keeping the app at 60 fps.
      SchedulerBinding.instance.addPersistentFrameCallback((_) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          for (final view in _live.toList()) {
            view._geometry();
          }
        });
      });
    }
    _start();
    _probeTimer = Timer.periodic(const Duration(seconds: 2), (_) => _probe());
  }

  void _start() {
    _id = ++_nextId;
    _uploaded = false;
    _nativeVisible = false;
    _output = null;
    _failedOutput = null;
    _lastGeometry = null;
    unawaited(_probe());
  }

  void _invalidated(String reason) {
    if (!mounted) return;
    _request?.cancel();
    _request = null;
    _uploaded = false;
    _lastGeometry = null;
    _setNativeVisible(false);
    // A driver failure must not cause a retry loop on the same output.
    _failedOutput = reason == 'display-changed' ? null : _output;
    if (reason == 'display-changed') _output = null;
    unawaited(_probe());
  }

  Future<void> _probe() async {
    if (_probing || !mounted) return;
    _probing = true;
    final id = _id;
    try {
      final capabilities = await _service.capabilities();
      if (!mounted || id != _id) return;
      if (!capabilities.available) {
        _request?.cancel();
        _request = null;
        if (_uploaded) await _service.remove(id);
        _uploaded = false;
        _output = null;
        _failedOutput = null;
        _lastGeometry = null;
        _setNativeVisible(false);
        return;
      }
      if (_failedOutput == capabilities.output) return;
      if (_uploaded && _output == capabilities.output) {
        _geometry();
        return;
      }
      _output = capabilities.output;
      _uploaded = false;
      _setNativeVisible(false);
      await _service.remove(id);
      final request = _request = DecodeRequest();
      Future<bool> decodeAndUpload() async {
        final frame =
            await (widget.decodeFrame?.call(request) ??
                _service.decode(widget.path, request));
        if (!mounted || id != _id || request.cancelled) return false;
        return _service.upload(id, frame);
      }

      final uploaded = widget.runDecode == null
          ? await decodeAndUpload()
          : await widget.runDecode!(request, decodeAndUpload);
      if (!mounted || id != _id || request.cancelled) {
        await _service.remove(id);
        return;
      }
      _uploaded = uploaded;
      if (!uploaded) _failedOutput = capabilities.output;
      _output = capabilities.output;
      _lastGeometry = null;
      _geometry();
    } catch (error) {
      // Decode/device/display errors affect only this overlay, never SDR.
      await _service.remove(id);
      _uploaded = false;
      _setNativeVisible(false);
      _failedOutput =
          error is ImageResourceUnavailable || error is DecodeCancelled
          ? null
          : _output;
    } finally {
      _probing = false;
    }
  }

  @override
  void didUpdateWidget(covariant HdrImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path ||
        widget.revision != oldWidget.revision) {
      _request?.cancel();
      unawaited(_service.remove(_id));
      _start();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _suspended = HdrOverlayScope.of(context);
  }

  @override
  void didChangeMetrics() {
    _lastGeometry = null;
    unawaited(_probe());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleActive = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) {
      _setNativeVisible(false);
      unawaited(_service.geometry({'id': _id, 'visible': false}));
      _lastGeometry = null;
    } else {
      unawaited(_probe());
    }
  }

  Future<void> _geometry() async {
    if (!mounted || !_uploaded || _sending) return;
    final object = _key.currentContext?.findRenderObject();
    if (object is! RenderBox || !object.hasSize) return;
    var hidden =
        !_lifecycleActive ||
        _suspended ||
        ModalRoute.of(context)?.isCurrent == false;
    final dpr = View.of(context).devicePixelRatio;
    final clip = _nativeClip(object, MediaQuery.sizeOf(context));
    final fitted = applyBoxFit(widget.fit, widget.sourceSize, object.size);
    final scale = fitted.source.width > 0
        ? fitted.destination.width / fitted.source.width
        : 0.0;
    final rect = Alignment.center.inscribe(
      widget.sourceSize * scale,
      Offset.zero & object.size,
    );
    final p0 = object.localToGlobal(rect.topLeft) * dpr;
    final px = object.localToGlobal(rect.topRight) * dpr;
    final py = object.localToGlobal(rect.bottomLeft) * dpr;
    final values = [
      p0.dx,
      p0.dy,
      px.dx,
      px.dy,
      py.dx,
      py.dy,
      clip.left * dpr,
      clip.top * dpr,
      clip.right * dpr,
      clip.bottom * dpr,
    ];
    hidden = hidden || clip.isEmpty || values.any((v) => !v.isFinite);
    if (listEquals(values, _lastGeometry) && _wasSuspended == hidden) return;
    _fallbackKey.currentContext?.findRenderObject()?.markNeedsPaint();
    _lastGeometry = values;
    _wasSuspended = hidden;
    final id = _id;
    _sending = true;
    try {
      final okay = await _service.geometry({
        'id': id,
        'visible': !hidden,
        'geometry': Float64List.fromList(values),
      });
      if (!okay && id == _id) {
        _uploaded = false;
        await _service.remove(id);
      }
      if (mounted && id == _id) _setNativeVisible(okay && !hidden);
    } finally {
      _sending = false;
      // A final pan/resize frame may have arrived while the method channel
      // was busy. Send the latest geometry even if Flutter is now idle.
      if (mounted && _uploaded) unawaited(_geometry());
    }
  }

  @override
  void dispose() {
    _live.remove(this);
    WidgetsBinding.instance.removeObserver(this);
    _probeTimer?.cancel();
    unawaited(_invalidationSubscription?.cancel());
    _request?.cancel();
    unawaited(_service.remove(_id));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    key: _key,
    child: _HdrFallback(
      key: _fallbackKey,
      nativeVisible: _nativeVisible && !_suspended && _lifecycleActive,
      child: widget.child,
    ),
  );

  void _setNativeVisible(bool value) {
    if (mounted && _nativeVisible != value) {
      setState(() => _nativeVisible = value);
    }
  }
}

Rect _nativeClip(RenderBox object, Size viewSize) {
  var clip = Offset.zero & viewSize;
  RenderObject? ancestor = object.parent;
  while (ancestor != null) {
    if (ancestor is RenderBox &&
        ancestor.hasSize &&
        (ancestor is _HdrBoundary || ancestor is RenderClipRect)) {
      var rect = Offset.zero & ancestor.size;
      if (ancestor is _HdrBoundary) rect = ancestor.insets.deflateRect(rect);
      clip = clip.intersect(
        MatrixUtils.transformRect(ancestor.getTransformTo(null), rect),
      );
    }
    ancestor = ancestor.parent;
  }
  return clip.intersect(
    MatrixUtils.transformRect(
      object.getTransformTo(null),
      Offset.zero & object.size,
    ),
  );
}

/// Show the SDR proxy only outside the native clip, notably beneath the
/// translucent toolbar. Never double-composite transparent native pixels.
class _HdrFallback extends SingleChildRenderObjectWidget {
  const _HdrFallback({
    required this.nativeVisible,
    required super.child,
    super.key,
  });
  final bool nativeVisible;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _HdrFallbackPaint(nativeVisible, MediaQuery.sizeOf(context));

  @override
  void updateRenderObject(
    BuildContext context,
    _HdrFallbackPaint renderObject,
  ) {
    renderObject.update(nativeVisible, MediaQuery.sizeOf(context));
  }
}

class _HdrFallbackPaint extends RenderProxyBox {
  _HdrFallbackPaint(this._nativeVisible, this._viewSize);
  bool _nativeVisible;
  Size _viewSize;

  void update(bool nativeVisible, Size viewSize) {
    if (nativeVisible == _nativeVisible && viewSize == _viewSize) return;
    _nativeVisible = nativeVisible;
    _viewSize = viewSize;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_nativeVisible) {
      super.paint(context, offset);
      return;
    }
    final inverse = Matrix4.tryInvert(getTransformTo(null));
    if (inverse == null) return;
    final nativePath = (Path()..addRect(_nativeClip(this, _viewSize)))
        .transform(inverse.storage);
    final proxy = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      nativePath,
    );
    if (proxy.getBounds().isEmpty) return;
    context.pushClipPath(
      needsCompositing,
      offset,
      Offset.zero & size,
      proxy,
      super.paint,
      clipBehavior: Clip.hardEdge,
    );
  }
}
