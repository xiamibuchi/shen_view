import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as imaging;
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/svg_resources.dart';
import 'package:shen_view/src/application/svg_webview_session.dart';
import 'package:shen_view/src/presentation/components/app_notification.dart';
import 'package:shen_view/src/presentation/svg_image.dart';
import 'package:shen_view/src/presentation/svg_live_image.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

import 'support/style_review_fonts.dart';

final _png = Uint8List.fromList(
  imaging.encodePng(
    imaging.Image(width: 200, height: 100, numChannels: 4)
      ..clear(imaging.ColorRgba8(210, 20, 50, 255)),
  ),
);

class _Session extends SvgWebViewSession {
  _Session({this.initialize});
  final Future<WebViewEnvironment?> Function()? initialize;
  @override
  Future<WebViewEnvironment?> environment() =>
      initialize?.call() ?? Future.value();
}

class _Controller extends PlatformInAppWebViewController {
  _Controller()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 'test'),
      );
  bool dead = false, screenshotFails = false;
  Completer<Object?>? pendingProbe;
  Completer<CallAsyncJavaScriptResult?>? pendingLoad;
  int disposed = 0;
  Uint8List? frame;
  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    if (dead) throw StateError('renderer exited');
    if (pendingProbe != null) return pendingProbe!.future;
    return true;
  }

  @override
  Future<CallAsyncJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    Map<String, dynamic> arguments = const {},
    ContentWorld? contentWorld,
  }) async => pendingLoad?.future ?? CallAsyncJavaScriptResult(value: true);
  @override
  Future<Uint8List?> takeScreenshot({
    ScreenshotConfiguration? screenshotConfiguration,
  }) async {
    if (screenshotFails) throw StateError('capture failed');
    return frame ?? _png;
  }

  @override
  Future<void> disposeKeepAlive(InAppWebViewKeepAlive keepAlive) async {
    disposed++;
  }

  @override
  void dispose({bool isKeepAlive = false}) {}
}

class _Platform extends InAppWebViewPlatform {
  final controller = _Controller();
  bool failCreation = false;
  @override
  PlatformInAppWebViewController createPlatformInAppWebViewControllerStatic() =>
      controller;
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    if (failCreation) throw StateError('native view unavailable');
    return _PlatformWidget(params);
  }
}

class _PlatformWidget extends PlatformInAppWebViewWidget {
  _PlatformWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;
  @override
  void dispose() {}
}

Widget _host(Widget child) => MaterialApp(home: SizedBox.expand(child: child));

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (ready()) return;
  }
  fail('SVG did not reach the expected display state');
}

bool _hasPixels(WidgetTester tester) => tester
    .widgetList<RawImage>(find.byType(RawImage))
    .any((image) => image.image != null);

void main() {
  final platform = _Platform();
  setUp(() {
    InAppWebViewPlatform.instance = platform;
    platform.failCreation = false;
    platform.controller.dead = false;
    platform.controller.screenshotFails = false;
    platform.controller.pendingProbe = null;
    platform.controller.pendingLoad = null;
    platform.controller.frame = null;
  });
  final file = File('testdata/svg/css_variables.svg');

  Future<SvgResource> prepare(WidgetTester tester, SvgResources store) async =>
      (await tester.runAsync(() => store.read(file)))!;
  Future<void> startBrowser(WidgetTester tester) async {
    await _until(tester, () => find.byType(InAppWebView).evaluate().isNotEmpty);
    final params = tester
        .widget<InAppWebView>(find.byType(InAppWebView))
        .platform
        .params;
    params.onWebViewCreated!(
      InAppWebViewController.fromPlatform(platform: platform.controller),
    );
    await tester.pump();
  }

  Future<void> close(
    WidgetTester tester,
    SvgResources store,
    SvgWebViewSession session,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
    store.dispose();
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'missing runtime falls back at main-image resolution and notifies only after pixels',
    (tester) async {
      final edges = <int>[];
      final store = SvgResources(
        rasterize: (_, edge, _) async {
          edges.add(edge);
          return _png;
        },
      );
      final session = _Session(
        initialize: () async => throw StateError('missing WebView2'),
      );
      await prepare(tester, store);
      var notices = 0, displays = 0;
      await tester.pumpWidget(
        _host(
          SvgImage(
            file: file,
            resources: store,
            session: session,
            allowWebView: true,
            onFallback: () => notices++,
            onDisplayed: () => displays++,
            errorBuilder: (_, error, _) => Text('error: $error'),
          ),
        ),
      );
      expect(notices, 0);
      await _until(tester, () => notices == 1);
      expect(_hasPixels(tester), isTrue);
      expect(edges.any((edge) => edge > 512), isTrue);
      expect(displays, 1);
      await tester.pump();
      expect(notices, 1);
      await close(tester, store, session);
    },
  );

  testWidgets(
    'same-version screenshot precedes resvg; stale versions are never used',
    (tester) async {
      var renders = 0, notices = 0;
      final store = SvgResources(
        rasterize: (_, _, _) async {
          renders++;
          throw StateError('resvg missing');
        },
      );
      final resource = await prepare(tester, store);
      await tester.runAsync(
        () => store.publishSnapshot(resource.version, _png),
      );
      final session = _Session(
        initialize: () async => throw StateError('missing runtime'),
      );
      await tester.pumpWidget(
        _host(
          SvgImage(
            file: file,
            resources: store,
            session: session,
            allowWebView: true,
            onFallback: () => notices++,
          ),
        ),
      );
      await _until(tester, () => notices == 1);
      expect(renders, 0);
      expect(_hasPixels(tester), isTrue);
      await close(tester, store, session);

      final next = SvgResources(
        rasterize: (_, _, _) async => throw StateError('both failed'),
      );
      final current = await prepare(tester, next);
      await tester.runAsync(
        () => next.publishSnapshot((
          id: current.version.id,
          modified: current.version.modified - 1,
          bytes: current.version.bytes,
        ), _png),
      );
      final unavailable = _Session(
        initialize: () async => throw StateError('unavailable'),
      );
      await tester.pumpWidget(
        _host(
          SvgImage(
            file: file,
            resources: next,
            session: unavailable,
            allowWebView: true,
            errorBuilder: (_, _, _) => const Text('terminal error'),
          ),
        ),
      );
      await _until(
        tester,
        () => find.text('terminal error').evaluate().isNotEmpty,
      );
      expect(_hasPixels(tester), isFalse);
      await close(tester, next, unavailable);
    },
  );

  testWidgets(
    'native creation failure tries static rendering; failure of both backends shows error once',
    (tester) async {
      platform.failCreation = true;
      var renders = 0, notices = 0;
      final store = SvgResources(
        rasterize: (_, _, _) async {
          renders++;
          throw StateError('static failed');
        },
      );
      await prepare(tester, store);
      final session = _Session();
      await tester.pumpWidget(
        _host(
          SvgImage(
            file: file,
            resources: store,
            session: session,
            allowWebView: true,
            onFallback: () => notices++,
            errorBuilder: (_, _, _) => const Text('terminal error'),
          ),
        ),
      );
      await _until(
        tester,
        () => find.text('terminal error').evaluate().isNotEmpty,
      );
      expect(find.byType(InAppWebView), findsNothing);
      expect(notices, 0);
      final attempts = renders;
      await tester.pump(const Duration(seconds: 20));
      expect(renders, attempts);
      await close(tester, store, session);
    },
  );

  for (final phase in ['environment', 'creation', 'document']) {
    testWidgets(
      'bounded $phase loading falls back and rejects late completion',
      (tester) async {
        final store = SvgResources();
        final resource = await prepare(tester, store);
        final environment = Completer<WebViewEnvironment?>();
        final load = Completer<CallAsyncJavaScriptResult?>();
        final session = _Session(
          initialize: phase == 'environment' ? () => environment.future : null,
        );
        if (phase == 'document') platform.controller.pendingLoad = load;
        var displays = 0;
        await tester.pumpWidget(
          _host(
            SvgLiveImage(
              resource: resource,
              resources: store,
              session: session,
              poster: () => const Text('poster'),
              failureBuilder: (_, _, _) => const Text('fallback'),
              fit: BoxFit.contain,
              alignment: Alignment.center,
              loadTimeout: const Duration(milliseconds: 50),
              onDisplayed: () => displays++,
            ),
          ),
        );
        if (phase == 'document') await startBrowser(tester);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pump();
        expect(find.text('fallback'), findsOneWidget);
        expect(find.byType(InAppWebView), findsNothing);
        environment.complete(null);
        load.complete(CallAsyncJavaScriptResult(value: true));
        await tester.pump();
        expect(displays, 0);
        expect(store.snapshot(resource.version), isNull);
        // A failed session is immediately available for a different document.
        final owner = Object();
        expect(session.acquire(owner), isTrue);
        await session.run(owner, () async {});
        session.release(owner);
        await close(tester, store, session);
      },
    );
  }

  for (final failure in ['termination', 'health timeout', 'health error']) {
    testWidgets(
      '$failure retains the captured main image, then reload can recover',
      (tester) async {
        final store = SvgResources(
          rasterize: (_, _, _) async => throw StateError('no static backend'),
        );
        await prepare(tester, store);
        final session = _Session();
        var notices = 0;
        Widget app(int reload) => _host(
          SvgImage(
            key: ValueKey(reload),
            file: file,
            resources: store,
            session: session,
            allowWebView: true,
            onFallback: () => notices++,
          ),
        );
        await tester.pumpWidget(app(0));
        await startBrowser(tester);
        final kept = session.keepAlive;
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump();
        final probe = Completer<Object?>();
        if (failure == 'termination') {
          final params = tester
              .widget<InAppWebView>(find.byType(InAppWebView))
              .platform
              .params;
          params.onWebContentProcessDidTerminate!(
            InAppWebViewController.fromPlatform(platform: platform.controller),
          );
        } else if (failure == 'health timeout') {
          platform.controller.pendingProbe = probe;
          await tester.pump(const Duration(seconds: 3));
          await tester.pump(const Duration(seconds: 4));
        } else {
          platform.controller.dead = true;
          await tester.pump(const Duration(seconds: 3));
        }
        await _until(tester, () => notices == 1);
        expect(find.byType(InAppWebView), findsNothing);
        expect(_hasPixels(tester), isTrue);
        final image = tester.widget<Image>(find.byType(Image));
        expect(identical((image.image as MemoryImage).bytes, _png), isTrue);
        probe.complete(true);
        platform.controller.pendingProbe = null;
        platform.controller.dead = false;
        await tester.pumpWidget(app(1));
        await startBrowser(tester);
        expect(identical(kept, session.keepAlive), isFalse);
        await tester.pump();
        expect(find.byType(InAppWebView), findsOneWidget);
        expect(notices, 1);
        await close(tester, store, session);
      },
    );
  }

  testWidgets(
    'a corrupt retained frame continues to resvg instead of hiding the image',
    (tester) async {
      platform.controller.frame = Uint8List.fromList([1, 2, 3]);
      final store = SvgResources(rasterize: (_, _, _) async => _png);
      await prepare(tester, store);
      final session = _Session();
      var notices = 0;
      await tester.pumpWidget(
        _host(
          SvgImage(
            file: file,
            resources: store,
            session: session,
            allowWebView: true,
            onFallback: () => notices++,
            errorBuilder: (_, _, _) => const Text('terminal error'),
          ),
        ),
      );
      await startBrowser(tester);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      final params = tester
          .widget<InAppWebView>(find.byType(InAppWebView))
          .platform
          .params;
      params.onWebContentProcessDidTerminate!(
        InAppWebViewController.fromPlatform(platform: platform.controller),
      );
      await _until(tester, () => notices == 1);
      expect(_hasPixels(tester), isTrue);
      expect(find.text('terminal error'), findsNothing);
      await close(tester, store, session);
    },
  );

  testWidgets(
    'screenshot failure alone keeps the live document and does not notify',
    (tester) async {
      platform.controller.screenshotFails = true;
      final store = SvgResources(rasterize: (_, _, _) async => _png);
      final resource = await prepare(tester, store);
      final session = _Session();
      var notices = 0;
      await tester.pumpWidget(
        _host(
          SvgImage(
            file: file,
            resources: store,
            session: session,
            allowWebView: true,
            onFallback: () => notices++,
          ),
        ),
      );
      await startBrowser(tester);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(seconds: 4));
      expect(find.byType(InAppWebView), findsOneWidget);
      expect(store.snapshot(resource.version), isNull);
      expect(notices, 0);
      await close(tester, store, session);
    },
  );

  testWidgets(
    'a displayed poster survives a slow or failed higher-resolution fallback',
    (tester) async {
      final larger = Completer<Uint8List>();
      final load = Completer<CallAsyncJavaScriptResult?>();
      platform.controller.pendingLoad = load;
      final store = SvgResources(
        rasterize: (_, edge, _) async => edge <= 512 ? _png : larger.future,
      );
      await prepare(tester, store);
      final session = _Session();
      var notices = 0;
      await tester.pumpWidget(
        _host(
          SvgImage(
            file: file,
            resources: store,
            session: session,
            allowWebView: true,
            onFallback: () => notices++,
            errorBuilder: (_, _, _) => const Text('terminal error'),
          ),
        ),
      );
      await startBrowser(tester);
      await _until(tester, () => _hasPixels(tester));
      expect(notices, 0);
      final params = tester
          .widget<InAppWebView>(find.byType(InAppWebView))
          .platform
          .params;
      params.onWebContentProcessDidTerminate!(
        InAppWebViewController.fromPlatform(platform: platform.controller),
      );
      await _until(tester, () => notices == 1);
      expect(_hasPixels(tester), isTrue);
      larger.completeError(StateError('large render failed'));
      load.complete(CallAsyncJavaScriptResult(value: true));
      await tester.pump();
      expect(_hasPixels(tester), isTrue);
      expect(find.text('terminal error'), findsNothing);
      expect(notices, 1);
      await close(tester, store, session);
    },
  );

  for (final dpr in [1.0, 1.25, 1.5, 2.0]) {
    testWidgets(
      'browser backing density stays separate from display geometry at DPR $dpr',
      (tester) async {
        tester.view.devicePixelRatio = dpr;
        tester.view.physicalSize = Size(800 * dpr, 600 * dpr);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final store = SvgResources();
        final resource = await prepare(tester, store);
        final session = _Session();
        InAppWebViewKeepAlive? kept;
        for (final scale in [0.5, 1.0, 2.0, 20.0]) {
          await tester.pumpWidget(
            _host(
              Center(
                child: SizedBox(
                  width: 400,
                  height: 200,
                  child: SvgLiveImage(
                    resource: resource,
                    resources: store,
                    session: session,
                    poster: () => const SizedBox.expand(),
                    failureBuilder: (_, _, _) => const Text('failed'),
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    pixelScale: scale,
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          final browser = find.byType(InAppWebView);
          expect(browser, findsOneWidget);
          final displayed = tester.getRect(browser);
          expect(displayed.width, closeTo(400, 0.001));
          expect(displayed.height, closeTo(200, 0.001));
          final backing = tester.getSize(browser);
          expect(backing.width * dpr, lessThanOrEqualTo(4096));
          expect(
            backing.width * backing.height * dpr * dpr,
            lessThanOrEqualTo(4 * 1024 * 1024 + 1),
          );
          if (scale <= 2) expect(backing.width, closeTo(400 * scale, 0.001));
          kept ??= session.keepAlive;
          expect(identical(session.keepAlive, kept), isTrue);
        }
        await close(tester, store, session);
      },
    );
  }

  for (final dark in [false, true]) {
    testWidgets(
      'static fallback warning leaves image visible in a narrow window, dark=$dark',
      (tester) async {
        await loadStyleReviewFonts(tester);
        tester.view.physicalSize = const Size(440, 460);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = SvgResources(rasterize: (_, _, _) async => _png);
        await prepare(tester, store);
        final session = _Session(
          initialize: () async => throw StateError('no runtime'),
        );
        final notices = AppNotificationController();
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: dark
                ? AppTheme.dark(platform: TargetPlatform.windows)
                : AppTheme.light(platform: TargetPlatform.windows),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => RepaintBoundary(
                key: boundary,
                child: AppNotificationHost(
                  controller: notices,
                  child: SvgImage(
                    file: file,
                    resources: store,
                    session: session,
                    allowWebView: true,
                    onFallback: () => notices.show(
                      AppLocalizations.of(context)!.svgStaticPreview,
                      type: AppNotificationType.warning,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await _until(
          tester,
          () =>
              find.byType(AppNotificationCard).evaluate().isNotEmpty &&
              _hasPixels(tester),
        );
        await tester.pump(const Duration(milliseconds: 200));
        final text = find.text('SVG 已切换为静态预览。动画不会播放，字体和部分效果可能有差异。');
        expect(text, findsOneWidget);
        expect(
          tester.getRect(find.byType(AppNotificationCard)).left,
          greaterThanOrEqualTo(16),
        );
        expect(
          tester.getRect(find.byType(AppNotificationCard)).right,
          lessThanOrEqualTo(424),
        );
        final object =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final screenshot = (await tester.runAsync(() => object.toImage()))!;
        final bytes = (await tester.runAsync(
          () => screenshot.toByteData(format: ui.ImageByteFormat.png),
        ))!;
        Directory('../../artifacts/svg-fallback').createSync(recursive: true);
        File('../../artifacts/svg-fallback/narrow-$dark.png')
            .writeAsBytesSync(bytes.buffer.asUint8List());
        screenshot.dispose();
        await close(tester, store, session);
        notices.dispose();
      },
    );
  }
}
