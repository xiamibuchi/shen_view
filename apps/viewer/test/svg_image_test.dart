import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shen_view/src/presentation/svg_image.dart';
import 'package:shen_view/src/application/svg_resources.dart';

void main() {
  testWidgets(
    'SVG fixture renders authored primaries and transparent patches',
    (tester) async {
      final key = GlobalKey();
      await tester.runAsync(() async {
        final source = await SvgResources.shared.read(
          File('testdata/formats/format_color_patches.svg'),
        );
        await SvgResources.shared.raster(source, 256, thumbnail: true);
        await SvgResources.shared.raster(source, 512, thumbnail: true);
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 240,
                  height: 120,
                  child: SvgImage(
                    file: File('testdata/formats/format_color_patches.svg'),
                    errorBuilder: (context, error, stack) =>
                        Error.throwWithStackTrace(
                          error,
                          stack ?? StackTrace.current,
                        ),
                  ),
                ),
              ),
            ),
          ),
        );
        // Let file IO and vector compilation finish outside fake test time.
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 100; attempt++) {
        if (tester
            .widgetList<RawImage>(find.byType(RawImage))
            .any((widget) => widget.image != null)) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .any((widget) => widget.image != null),
        isTrue,
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = (await tester.runAsync(() => boundary.toImage()))!;
      addTearDown(image.dispose);
      final rgba = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawStraightRgba),
      ))!;
      for (var c = 0; c < 3; c++) {
        for (final probe in [(40, 255), (100, 128)]) {
          final offset = (probe.$1 * 240 + c * 80 + 40) * 4;
          for (var channel = 0; channel < 3; channel++) {
            expect(rgba.getUint8(offset + channel), channel == c ? 255 : 0);
          }
          expect(rgba.getUint8(offset + 3), closeTo(probe.$2, 1));
        }
      }
      await tester.runAsync(() async {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('../../artifacts/formats').createSync(recursive: true);
        File('../../artifacts/formats/svg-patches.png')
            .writeAsBytesSync(png!.buffer.asUint8List());
      });
    },
  );

  test('normalizes CSS variables and removes embedded font faces', () {
    const source = '''
<svg xmlns="http://www.w3.org/2000/svg">
  <style>
    @font-face { font-family: Demo; src: url(data:font/ttf;base64,AAAA); }
    :root { --ink: #111; --fallback: #abc; }
  </style>
  <path fill="var(--ink)" stroke="var(--missing, #f00)"/>
</svg>
''';

    final normalized = normalizeSvgSource(source);

    expect(normalized, isNot(contains('@font-face')));
    expect(normalized, contains('fill="#111"'));
    expect(normalized, contains('stroke="#f00"'));
  });
}
