import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as imaging;
import 'package:shen_view/src/application/svg_resources.dart';
import 'package:shen_view/src/application/svg_webview_session.dart';
import 'package:shen_view/src/presentation/svg_image.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'single native browser updates complex SVG thumbnails without thumbnail browsers',
    (tester) async {
      const root = String.fromEnvironment('SVG_FIXTURES');
      const output = String.fromEnvironment('SVG_ARTIFACTS');
      expect(root, isNotEmpty, reason: 'Pass absolute SVG_FIXTURES');
      final store = SvgResources();
      final session = SvgWebViewSession(
        idleDelay: const Duration(milliseconds: 100),
      );
      final boundary = GlobalKey();
      Object? browserError;
      var displays = 0;
      Widget app(String name) => MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: boundary,
            child: SizedBox(
              width: 400,
              height: 200,
              child: SvgImage(
                file: File('$root/$name'),
                resources: store,
                session: session,
                allowWebView: true,
                onDisplayed: () {
                  displays++;
                },
                errorBuilder: (context, error, stack) {
                  browserError = error;
                  return Text('$error');
                },
              ),
            ),
          ),
        ),
      );
      Future<void> until(bool Function() ready) async {
        for (var i = 0; i < 400; i++) {
          await tester.pump(const Duration(milliseconds: 30));
          await Future<void>.delayed(const Duration(milliseconds: 30));
          if (browserError != null) fail('$browserError');
          if (ready()) return;
        }
        fail('SVG browser did not produce a current-version thumbnail');
      }

      final css = await store.read(File('$root/css_variables.svg'));
      final before = imaging.decodePng(
        await store.raster(css, 128, thumbnail: true),
      )!;
      // The approximate static poster cannot preserve scoped variables.
      expect(
        before.getPixel(before.width ~/ 4, before.height ~/ 2).b,
        greaterThan(200),
      );
      await tester.pumpWidget(app('css_variables.svg'));
      await until(() => store.snapshot(css.version) != null);
      final after = imaging.decodePng(store.snapshot(css.version)!)!;
      expect(
        after.getPixel(after.width ~/ 4, after.height ~/ 2).r,
        closeTo(192, 3),
      );
      expect(
        after.getPixel(after.width * 3 ~/ 4, after.height ~/ 2).b,
        greaterThan(245),
      );
      final kept = session.keepAlive;
      if (output.isNotEmpty) {
        Directory(output).createSync(recursive: true);
        File('$output/css-browser.png')
            .writeAsBytesSync(store.snapshot(css.version)!);
      }
      for (final name in [
        'embedded_font.svg',
        'smil.svg',
        'css_animation.svg',
        'foreign_object.svg',
      ]) {
        final resource = await store.read(File('$root/$name'));
        await tester.pumpWidget(app(name));
        await until(() => store.snapshot(resource.version) != null);
        expect(identical(kept, session.keepAlive), isTrue);
        final image = imaging.decodePng(store.snapshot(resource.version)!)!;
        expect(image.width, greaterThan(0));
        if (name == 'embedded_font.svg') {
          expect(image.data!.any((pixel) => pixel.a > 0), isTrue);
        }
        if (output.isNotEmpty) {
          File('$output/$name.png')
              .writeAsBytesSync(store.snapshot(resource.version)!);
        }
      }
      // Verify the actual Flutter texture changes, not just the browser's clock.
      final previousDisplays = displays;
      await tester.pumpWidget(app('smil.svg'));
      await until(() => displays > previousDisplays);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 33));
      }
      Future<List<int>> readFrame() async {
        final object =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await object.toImage();
        try {
          return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List()
              .toList();
        } finally {
          image.dispose();
        }
      }

      final first = await readFrame();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 33));
      }
      final second = await readFrame();
      expect(
        first,
        isNot(equals(second)),
        reason: 'SMIL must animate inside the Flutter texture',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 250));
      session.dispose();
      store.dispose();
      expect(tester.takeException(), isNull);
    },
    skip: !Platform.isWindows,
  );

  testWidgets('unavailable WebView displays real resvg fallback pixels once', (
    tester,
  ) async {
    const root = String.fromEnvironment('SVG_FIXTURES');
    final store = SvgResources();
    final session = _UnavailableSession();
    var notices = 0, displays = 0;
    Object? failure;
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: boundary,
            child: SizedBox(
              width: 400,
              height: 200,
              child: SvgImage(
                file: File('$root/css_variables.svg'),
                resources: store,
                session: session,
                allowWebView: true,
                onFallback: () => notices++,
                onDisplayed: () => displays++,
                errorBuilder: (_, error, _) {
                  failure = error;
                  return Text('$error');
                },
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 200 && notices == 0 && failure == null; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(failure, isNull);
    expect(notices, 1);
    expect(displays, 1);
    expect(find.byType(InAppWebView), findsNothing);
    final object =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await object.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final decoded = imaging.decodePng(bytes.buffer.asUint8List())!;
    expect(decoded.getPixel(100, 100).b, greaterThan(245));
    const output = String.fromEnvironment('SVG_ARTIFACTS');
    if (output.isNotEmpty) {
      Directory(output).createSync(recursive: true);
      File('$output/static-fallback.png')
          .writeAsBytesSync(bytes.buffer.asUint8List());
    }
    image.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
    store.dispose();
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);
  testWidgets(
    'browser zoom preserves SVG viewport units and applies visual scale once',
    (tester) async {
      const root = String.fromEnvironment('SVG_FIXTURES');
      const output = String.fromEnvironment('SVG_ARTIFACTS');
      final store = SvgResources();
      final session = SvgWebViewSession();
      final transform = TransformationController();
      final boundary = GlobalKey();
      Object? failure;
      var displays = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: boundary,
              child: SizedBox(
                width: 1000,
                height: 600,
                child: Center(
                  child: AnimatedBuilder(
                    animation: transform,
                    builder: (context, _) => Transform(
                      transform: transform.value,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: 400,
                        height: 200,
                        child: SvgImage(
                          file: File('$root/zoom_viewport.svg'),
                          resources: store,
                          session: session,
                          transform: transform,
                          allowWebView: true,
                          onDisplayed: () => displays++,
                          onFallback: () => failure = StateError(
                            'Unexpected static fallback',
                          ),
                          errorBuilder: (_, error, _) {
                            failure = error;
                            return Text('$error');
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 300 && displays == 0 && failure == null; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(failure, isNull);
      expect(displays, 1);
      final kept = session.keepAlive;
      for (final zoom in [0.5, 1.0, 2.0]) {
        transform.value = Matrix4.identity()..scaleByDouble(zoom, zoom, 1, 1);
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 30));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(failure, isNull);
        final object =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await object.toImage();
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final pixels = imaging.decodePng(bytes.buffer.asUint8List())!;
        var left = pixels.width,
            right = -1,
            redLeft = pixels.width,
            redRight = -1;
        var top = pixels.height, bottom = -1, green = 0;
        for (final pixel in pixels) {
          if (pixel.a > 200 && pixel.g > 200 && pixel.r < 40 && pixel.b < 40) {
            green++;
          }
          if (pixel.a < 200 || (pixel.r < 140 && pixel.b < 140)) continue;
          if (pixel.x < left) left = pixel.x;
          if (pixel.x > right) right = pixel.x;
          if (pixel.y < top) top = pixel.y;
          if (pixel.y > bottom) bottom = pixel.y;
          if (pixel.r > 140 && pixel.b < 60) {
            if (pixel.x < redLeft) redLeft = pixel.x;
            if (pixel.x > redRight) redRight = pixel.x;
          }
        }
        expect(
          right - left + 1,
          closeTo(400 * zoom, 3),
          reason: 'Zoom must be applied once',
        );
        expect(bottom - top + 1, closeTo(200 * zoom, 3));
        expect(
          green,
          0,
          reason: 'Zoom must not change SVG media-query breakpoints',
        );
        expect(
          (redRight - redLeft + 1) / (right - left + 1),
          closeTo(0.1, 0.015),
          reason:
              '10vw must stay 10% of the authored SVG viewport at zoom $zoom',
        );
        expect(identical(session.keepAlive, kept), isTrue);
        expect(displays, 1, reason: 'Zooming must not reload the SVG document');
        if (output.isNotEmpty) {
          Directory(output).createSync(recursive: true);
          File('$output/zoom-$zoom.png')
              .writeAsBytesSync(bytes.buffer.asUint8List());
        }
        image.dispose();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      transform.dispose();
      session.dispose();
      store.dispose();
      expect(tester.takeException(), isNull);
    },
    skip: !Platform.isWindows,
  );
}

class _UnavailableSession extends SvgWebViewSession {
  @override
  Future<WebViewEnvironment?> environment() async =>
      throw StateError('WebView unavailable');
}
