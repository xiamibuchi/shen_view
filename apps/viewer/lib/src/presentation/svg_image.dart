import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../application/decode_request.dart';
import '../application/svg_resources.dart';
import '../application/svg_webview_session.dart';
import 'svg_live_image.dart';
import 'color_picker_target.dart';

export '../application/svg_resources.dart' show normalizeSvgSource;

typedef SvgImageErrorBuilder = Widget Function(
  BuildContext context,
  Object error,
  StackTrace? stackTrace,
);
typedef SvgBrowserBuilder = Widget Function(
  BuildContext context,
  SvgResource resource,
  Widget Function() poster,
);

/// Static SVGs and all thumbnails use resvg. Only the active main page may
/// attach to its window's single, lazily created browser session.
class SvgImage extends StatefulWidget {
  const SvgImage({
    required this.file,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.errorBuilder,
    this.onDisplayed,
    this.onFallback,
    this.version,
    this.resources,
    this.session,
    this.allowWebView = false,
    this.transform,
    this.browserBuilder,
    super.key,
  });
  final File file;
  final BoxFit fit;
  final Alignment alignment;
  final SvgImageErrorBuilder? errorBuilder;
  final VoidCallback? onDisplayed;
  final VoidCallback? onFallback;
  final SvgVersion? version;
  final SvgResources? resources;
  final SvgWebViewSession? session;
  final bool allowWebView;
  final TransformationController? transform;
  final SvgBrowserBuilder? browserBuilder;
  @override
  State<SvgImage> createState() => _SvgImageState();
}

class _SvgImageState extends State<SvgImage> {
  late SvgResources _resources;
  late Future<SvgResource> _source;
  SvgWebViewSession? _ownedSession;
  SvgResource? _resource;
  SvgVersion? _displayed;
  DecodeRequest? _request;
  Future<Uint8List>? _raster;
  Object? _rasterKey;
  Uint8List? _lastPoster;
  bool _picking = false;
  bool _fallbackNotified = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _picking = ColorPickerScope.of(context)?.active ?? false;
  }

  @override
  void initState() {
    super.initState();
    _resources = widget.resources ?? SvgResources.shared;
    _resources.addListener(_onCacheUpdated);
    _load();
  }

  void _load() {
    _request?.cancel();
    _request = DecodeRequest();
    _raster = null;
    _rasterKey = null;
    _lastPoster = null;
    _resource = null;
    _displayed = null;
    _fallbackNotified = false;
    _source = _resources.read(widget.file, version: widget.version);
  }

  void _onCacheUpdated() {
    if (mounted && _resource != null) setState(() {});
  }

  @override
  void didUpdateWidget(covariant SvgImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resources != widget.resources) {
      _resources.removeListener(_onCacheUpdated);
      _resources = widget.resources ?? SvgResources.shared;
      _resources.addListener(_onCacheUpdated);
    }
    if (oldWidget.file.path != widget.file.path ||
        oldWidget.version != widget.version ||
        oldWidget.resources != widget.resources) {
      _load();
    }
  }

  @override
  void dispose() {
    _request?.cancel();
    _resources.removeListener(_onCacheUpdated);
    _ownedSession?.dispose();
    super.dispose();
  }

  void _didDisplay(SvgVersion version, {bool fallback = false}) {
    final displayed = _displayed != version;
    final notifyFallback = fallback && !_fallbackNotified;
    if (!displayed && !notifyFallback) return;
    _displayed = version;
    if (notifyFallback) _fallbackNotified = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _resource?.version != version) return;
      if (displayed) widget.onDisplayed?.call();
      if (notifyFallback) widget.onFallback?.call();
    });
  }

  Widget _poster(
    SvgResource resource, {
    bool approximate = false,
    bool fallback = false,
    Uint8List? retainedFrame,
    bool skipSnapshot = false,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final thumbnail = !widget.allowWebView || approximate;
      final doc = resource.document;
      final source = Size(doc.width, doc.height);
      final available = Size(
        constraints.maxWidth.isFinite ? constraints.maxWidth : doc.width,
        constraints.maxHeight.isFinite ? constraints.maxHeight : doc.height,
      );
      final fitted = applyBoxFit(widget.fit, source, available).destination;
      final zoom = thumbnail
          ? 1.0
          : widget.transform?.value.getMaxScaleOnAxis() ?? 1.0;
      final desired = math.max(
        1,
        (math.max(fitted.width, fitted.height) *
                MediaQuery.devicePixelRatioOf(context) *
                zoom)
            .ceil(),
      );
      final limit = thumbnail ? 512 : 4096;
      var edge = 64;
      while (edge < desired && edge < limit) {
        edge *= 2;
      }
      if (_picking) {
        edge = math.max(
          1,
          math.min(4096, math.max(doc.width, doc.height).ceil()),
        );
      }
      final shot = !skipSnapshot && (thumbnail || fallback)
          ? retainedFrame ?? _resources.snapshot(resource.version)
          : null;
      if (shot != null) {
        return _image(
          shot,
          resource,
          edge,
          notify: !approximate,
          fallback: fallback,
          decodeError: () => _poster(
            resource,
            approximate: approximate,
            fallback: fallback,
            skipSnapshot: true,
          ),
        );
      }
      final useSnapshot = thumbnail && !skipSnapshot;
      final key = (resource.version, edge, useSnapshot);
      if (_rasterKey != key) {
        _rasterKey = key;
        _raster = _resources.raster(
          resource,
          edge,
          request: _request,
          thumbnail: useSnapshot,
        );
      }
      return FutureBuilder<Uint8List>(
        future: _raster,
        builder: (context, snapshot) {
          final previous = fallback ? _lastPoster : null;
          if (snapshot.hasError) {
            // An approximate loading poster must not fail an otherwise healthy
            // browser document (or mark automatic playback as failed).
            if (approximate) return const SizedBox.expand();
            if (snapshot.error is DecodeCancelled) {
              return const SizedBox.expand();
            }
            if (previous != null) {
              return _image(
                previous,
                resource,
                edge,
                notify: true,
                fallback: true,
              );
            }
            return _error(snapshot.error!, snapshot.stackTrace);
          }
          final bytes = snapshot.data ?? previous;
          return bytes == null
              ? const SizedBox.expand()
              : _image(
                  bytes,
                  resource,
                  edge,
                  notify: !approximate,
                  fallback: fallback,
                  decodeError: approximate
                      ? () => const SizedBox.expand()
                      : null,
                );
        },
      );
    },
  );

  Widget _image(
    Uint8List bytes,
    SvgResource resource,
    int edge, {
    required bool notify,
    bool fallback = false,
    Widget Function()? decodeError,
  }) => Image.memory(
    bytes,
    fit: widget.fit,
    alignment: widget.alignment,
    scale: svgPngScale(bytes, resource.document),
    gaplessPlayback: false,
    frameBuilder: (context, child, frame, synchronous) {
      if (!fallback && (frame != null || synchronous)) _lastPoster = bytes;
      if (notify && (frame != null || synchronous)) {
        _didDisplay(resource.version, fallback: fallback);
      }
      return child;
    },
    errorBuilder: (context, error, stack) =>
        decodeError?.call() ?? _error(error, stack),
  );

  Widget _error(Object error, StackTrace? stack) =>
      widget.errorBuilder?.call(context, error, stack) ??
      const SizedBox.expand();

  @override
  Widget build(BuildContext context) {
    Widget content() => FutureBuilder<SvgResource>(
      future: _source,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _error(snapshot.error!, snapshot.stackTrace);
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.expand();
        }
        final resource = snapshot.data;
        if (resource == null) return const SizedBox.expand();
        _resource = resource;
        if (widget.allowWebView &&
            resource.document.needsWebView &&
            (widget.browserBuilder != null ||
                Platform.isWindows ||
                Platform.isMacOS)) {
          Widget poster() => _poster(resource, approximate: true);
          final builder = widget.browserBuilder;
          if (builder != null) return builder(context, resource, poster);
          return SvgLiveImage(
            key: ValueKey(resource.version),
            resource: resource,
            resources: _resources,
            session: widget.session ?? (_ownedSession ??= SvgWebViewSession()),
            poster: poster,
            fit: widget.fit,
            alignment: widget.alignment,
            pixelScale: widget.transform?.value.getMaxScaleOnAxis() ?? 1,
            failureBuilder: (error, stack, frame) =>
                _poster(resource, fallback: true, retainedFrame: frame),
            onDisplayed: () => _didDisplay(resource.version),
          );
        }
        return _poster(
          resource,
          fallback: widget.allowWebView && resource.document.needsWebView,
        );
      },
    );
    final transform = widget.transform;
    return transform == null
        ? content()
        : AnimatedBuilder(
            animation: transform,
            builder: (context, _) => content(),
          );
  }
}
