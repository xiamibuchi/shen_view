import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../application/decode_request.dart';
import '../application/svg_resources.dart';
import '../application/svg_webview_session.dart';
import 'color_picker_target.dart';

const svgWebViewShell =
    '''<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; frame-src 'self'; img-src data:; font-src data:; style-src 'unsafe-inline'; script-src 'none'; base-uri 'none'; form-action 'none'"><style>html,body,#stage{margin:0;width:100%;height:100%;overflow:hidden;background:transparent}#svg-document{position:absolute;border:0;transform-origin:0 0;background:transparent}</style></head><body><div id="stage"><iframe id="svg-document" sandbox="allow-same-origin" srcdoc="<!doctype html><html><head></head><body></body></html>"></iframe></div></body></html>''';

class SvgLiveImage extends StatefulWidget {
  const SvgLiveImage({
    required this.resource,
    required this.resources,
    required this.session,
    required this.poster,
    required this.failureBuilder,
    required this.fit,
    required this.alignment,
    this.pixelScale = 1,
    this.onDisplayed,
    this.loadTimeout = const Duration(seconds: 12),
    this.healthCheckInterval = const Duration(seconds: 3),
    this.operationTimeout = const Duration(seconds: 3),
    super.key,
  });
  final SvgResource resource;
  final SvgResources resources;
  final SvgWebViewSession session;
  final Widget Function() poster;
  final Widget Function(Object error, StackTrace? stack, Uint8List? frame)
  failureBuilder;
  final BoxFit fit;
  final Alignment alignment;
  final double pixelScale;
  final VoidCallback? onDisplayed;
  final Duration loadTimeout, healthCheckInterval, operationTimeout;
  @override
  State<SvgLiveImage> createState() => _SvgLiveImageState();
}

class _SvgLiveImageState extends State<SvgLiveImage> {
  late Future<WebViewEnvironment?> _environment;
  InAppWebViewController? _controller;
  SvgVersion? _loading;
  Timer? _snapshotTimer;
  Timer? _loadTimer, _healthTimer;
  Uint8List? _png;
  Object? _error;
  StackTrace? _stack;
  int _generation = 0;
  bool _claimed = false, _picking = false, _ready = false;
  bool _allowShellNavigation = true;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_claim);
    _claim();
  }

  void _claim() {
    if (_claimed || !mounted || _error != null) return;
    final claimed = widget.session.acquire(this);
    if (claimed) {
      _claimed = true;
      final generation = _generation;
      _watchLoad(generation);
      _environment = widget.session.environment().timeout(widget.loadTimeout);
      unawaited(
        _environment.then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            if (_current(generation)) _fail(error, stack);
          },
        ),
      );
      if (_controller != null) unawaited(_load());
      if (mounted) setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final picking = ColorPickerScope.of(context)?.active ?? false;
    if (_picking != picking) {
      _picking = picking;
      if (picking && _ready) unawaited(_capture(_generation));
    }
  }

  @override
  void didUpdateWidget(covariant SvgLiveImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resource.version != widget.resource.version) {
      _generation++;
      _loading = null;
      _ready = false;
      _png = null;
      _error = null;
      _snapshotTimer?.cancel();
      _healthTimer?.cancel();
      if (!_claimed) {
        _controller = null;
        _allowShellNavigation = true;
        _claim();
      } else {
        _watchLoad(_generation);
        if (_controller != null) unawaited(_load());
      }
    }
  }

  bool _current(int generation) =>
      mounted && generation == _generation && widget.session.owns(this);

  void _watchLoad(int generation) {
    _loadTimer?.cancel();
    _loadTimer = Timer(widget.loadTimeout, () {
      if (_current(generation) && !_ready) {
        _fail(
          TimeoutException('SVG WebView 初始化或加载超时。', widget.loadTimeout),
          StackTrace.current,
        );
      }
    });
  }

  void _fail(Object error, StackTrace? stack) {
    if (!mounted || _error != null) return;
    _generation++;
    _loadTimer?.cancel();
    _healthTimer?.cancel();
    _snapshotTimer?.cancel();
    setState(() {
      _error = error;
      _stack = stack;
      _ready = false;
      _claimed = false;
    });
    widget.session.release(
      this,
      discard: true,
      afterDetach: WidgetsBinding.instance.endOfFrame,
    );
    _controller = null;
  }

  void _watchHealth(int generation) {
    _healthTimer?.cancel();
    _healthTimer = Timer(widget.healthCheckInterval, () async {
      if (!_current(generation) || !_ready) return;
      try {
        final controller = _controller!;
        // Windows 0.6.0 has no renderer-exit callback. Bound a small probe so a
        // dead or hung renderer follows the same path as WKWebView termination.
        final alive = await widget.session.run(this, () {
          if (!_current(generation)) throw DecodeCancelled();
          return controller
              .evaluateJavascript(
                source: "document.getElementById('svg-document')?.contentDocument?.body?.firstElementChild?.localName === 'svg'",
              )
              .timeout(widget.operationTimeout);
        });
        if (!_current(generation)) return;
        if (alive != true) throw StateError('SVG WebView 已失去响应。');
        _watchHealth(generation);
      } catch (error, stack) {
        if (_current(generation)) _fail(error, stack);
      }
    });
  }

  Future<void> _load() async {
    final controller = _controller;
    if (controller == null ||
        !_claimed ||
        _loading == widget.resource.version) {
      return;
    }
    final generation = _generation;
    final resource = widget.resource;
    _loading = resource.version;
    try {
      await widget.session.run(this, () async {
        if (!_current(generation)) throw DecodeCancelled();
        final result = await controller
            .callAsyncJavaScript(
              functionBody: '''
          const parsed = new DOMParser().parseFromString(source, 'image/svg+xml');
          const frame = document.getElementById('svg-document');
          if (!frame.contentDocument || frame.contentDocument.readyState === 'loading') {
            await new Promise(resolve => frame.addEventListener('load', resolve, {once:true}));
          }
          const doc = frame.contentDocument;
          const root = doc.importNode(parsed.documentElement, true);
          if (root.localName !== 'svg') throw new Error('Invalid SVG');
          if (!root.hasAttribute('viewBox')) root.setAttribute('viewBox', '0 0 ' + width + ' ' + height);
          root.setAttribute('width', '100%'); root.setAttribute('height', '100%');
          // Keep layout units (vw/vh, media queries, foreignObject text) in the
          // authored viewport. Only the outer compositing surface follows zoom
          // and device pixels; resizing it must not reflow the SVG document.
          frame.style.width = width + 'px'; frame.style.height = height + 'px';
          Object.assign(doc.documentElement.style, {margin:'0',width:'100%',height:'100%',overflow:'hidden'});
          Object.assign(doc.body.style, {margin:'0',width:'100%',height:'100%',overflow:'hidden'});
          root.style.display = 'block';
          doc.body.replaceChildren(root);
          const stage = document.getElementById('stage');
          const resize = () => {
            const scale = Math.min(stage.clientWidth / width, stage.clientHeight / height);
            const x = (stage.clientWidth - width * scale) / 2;
            const y = (stage.clientHeight - height * scale) / 2;
            frame.style.transform = 'translate(' + x + 'px,' + y + 'px) scale(' + scale + ')';
          };
          window.svgResizeObserver?.disconnect();
          window.svgResizeObserver = new ResizeObserver(resize);
          window.svgResizeObserver.observe(stage);
          resize();
          root.getBoundingClientRect();
          const timeout = new Promise((_, reject) => setTimeout(() => reject(new Error('SVG font loading timed out')), 8000));
          await Promise.race([doc.fonts.ready, timeout]);
          await Promise.all([...doc.images].map(img => img.decode().catch(() => {})));
          await Promise.race([new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))), new Promise(r => setTimeout(r, 150))]);
          const failed = [...doc.fonts].some(font => font.status === 'error');
          if (failed) throw new Error('SVG embedded font failed to load');
          return true;
        ''',
              arguments: {
                'source': resource.document.source,
                'width': resource.document.width,
                'height': resource.document.height,
              },
            )
            .timeout(widget.loadTimeout);
        if (result == null || result.error != null || result.value != true) {
          throw StateError('SVG 浏览器渲染失败：${result?.error ?? '未返回就绪状态'}');
        }
      });
      if (!_current(generation)) return;
      _loadTimer?.cancel();
      setState(() {
        _ready = true;
      });
      widget.onDisplayed?.call();
      _watchHealth(generation);
      _snapshotTimer = Timer(const Duration(milliseconds: 200), () {
        unawaited(_capture(generation));
      });
    } on DecodeCancelled {
      // A source replacement cannot publish into the next document.
    } catch (error, stack) {
      if (_current(generation)) {
        _fail(error, stack);
      }
    }
  }

  Future<void> _capture(int generation) async {
    if (!_current(generation) || !_ready || _controller == null) return;
    final version = widget.resource.version;
    try {
      final png = await widget.session.run(this, () async {
        if (!_current(generation)) throw DecodeCancelled();
        return _controller!
            .takeScreenshot(
              screenshotConfiguration: ScreenshotConfiguration(
                compressFormat: CompressFormat.PNG,
              ),
            )
            .timeout(widget.operationTimeout);
      });
      if (png == null || !_current(generation)) return;
      setState(() {
        _png = png;
      });
      await widget.resources.publishSnapshot(
        version,
        png,
        isCurrent: () =>
            _current(generation) && widget.resource.version == version,
      );
    } catch (_) {
      // Optional thumbnail capture cannot blank a successfully displayed SVG.
    }
  }

  Future<void> _created(InAppWebViewController controller) async {
    _controller = controller;
    widget.session.created(this);
    try {
      final ready = await controller
          .evaluateJavascript(source: "!!document.getElementById('stage')")
          .timeout(widget.operationTimeout);
      if (ready == true && mounted) unawaited(_load());
    } catch (_) {
      /* Initial navigation will invoke onLoadStop. */
    }
  }

  @override
  void dispose() {
    _generation++;
    _snapshotTimer?.cancel();
    _loadTimer?.cancel();
    _healthTimer?.cancel();
    widget.session.removeListener(_claim);
    widget.session.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return widget.failureBuilder(_error!, _stack, _png);
    if (!_claimed) return widget.poster();
    return FutureBuilder<WebViewEnvironment?>(
      future: _environment,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return widget.failureBuilder(
            snapshot.error!,
            snapshot.stackTrace,
            _png,
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.poster();
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final doc = widget.resource.document;
            final source = Size(doc.width, doc.height);
            final available = Size(
              constraints.maxWidth.isFinite ? constraints.maxWidth : doc.width,
              constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : doc.height,
            );
            final destination = applyBoxFit(
              widget.fit,
              source,
              available,
            ).destination;
            final ratio = MediaQuery.devicePixelRatioOf(context);
            final density = math.min(
              math.min(
                    destination.width / doc.width,
                    destination.height / doc.height,
                  ) *
                  ratio *
                  widget.pixelScale,
              math.min(
                4096 / math.max(doc.width, doc.height),
                math.sqrt(4 * 1024 * 1024 / (doc.width * doc.height)),
              ),
            );
            final webWidth = math.max(1.0, doc.width * density) / ratio;
            final webHeight = math.max(1.0, doc.height * density) / ratio;
            late Widget browser;
            try {
              widget.session.created(this);
              browser = InAppWebView(
                keepAlive: widget.session.keepAlive,
                webViewEnvironment: snapshot.data,
                initialData: InAppWebViewInitialData(data: svgWebViewShell),
                initialSettings: InAppWebViewSettings(
                  transparentBackground: true,
                  javaScriptEnabled: true,
                  javaScriptCanOpenWindowsAutomatically: false,
                  supportZoom: false,
                  disableContextMenu: true,
                  verticalScrollBarEnabled: false,
                  horizontalScrollBarEnabled: false,
                  isInspectable: false,
                  incognito: true,
                  cacheEnabled: false,
                  useShouldOverrideUrlLoading: true,
                ),
                onWebViewCreated: (controller) {
                  unawaited(_created(controller));
                },
                onLoadStop: (controller, url) {
                  unawaited(_load());
                },
                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame == true) {
                    _fail(StateError(error.description), StackTrace.current);
                  }
                },
                onWebContentProcessDidTerminate: (controller) {
                  _fail(StateError('SVG WebView 进程已退出。'), StackTrace.current);
                },
                onRenderProcessGone: (controller, detail) {
                  _fail(StateError('SVG WebView 进程已退出。'), StackTrace.current);
                },
                shouldOverrideUrlLoading: (controller, navigation) async {
                  // The single sandboxed srcdoc frame is part of the fixed
                  // host shell; SVG files cannot add frames or navigate it.
                  final url = navigation.request.url?.toString();
                  if (navigation.isForMainFrame == false &&
                      (url == 'about:srcdoc' || url == 'about:blank')) {
                    return NavigationActionPolicy.ALLOW;
                  }
                  if (!_allowShellNavigation) {
                    return NavigationActionPolicy.CANCEL;
                  }
                  _allowShellNavigation = false;
                  final scheme = navigation.request.url?.scheme;
                  return scheme == 'about' || scheme == 'data'
                      ? NavigationActionPolicy.ALLOW
                      : NavigationActionPolicy.CANCEL;
                },
                onCreateWindow: (controller, action) async => false,
                onPermissionRequest: (controller, request) async =>
                    PermissionResponse(
                      resources: request.resources,
                      action: PermissionResponseAction.DENY,
                    ),
              );
            } catch (error, stack) {
              final generation = _generation;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_current(generation)) _fail(error, stack);
              });
              return widget.failureBuilder(error, stack, _png);
            }
            final live = ClipRect(
              child: FittedBox(
                fit: widget.fit,
                alignment: widget.alignment,
                child: SizedBox(
                  width: doc.width,
                  height: doc.height,
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: SizedBox(
                      width: webWidth,
                      height: webHeight,
                      child: IgnorePointer(child: browser),
                    ),
                  ),
                ),
              ),
            );
            final png = _png;
            if (_picking && png != null) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  Offstage(offstage: true, child: live),
                  Image.memory(
                    png,
                    scale: svgPngScale(png, widget.resource.document),
                    fit: widget.fit,
                    alignment: widget.alignment,
                    gaplessPlayback: true,
                  ),
                ],
              );
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                if (!_ready) widget.poster(),
                Opacity(opacity: _ready ? 1 : 0, child: live),
              ],
            );
          },
        );
      },
    );
  }
}
