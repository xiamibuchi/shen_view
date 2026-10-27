import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/presentation/split_wide_image.dart';
import 'package:shen_view/src/presentation/zoomable_viewport.dart';

void main() {
  testWidgets(
    'split scan preserves both physical halves with a centered gutter',
    (tester) async {
      const captureKey = ValueKey('split-capture');
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: captureKey,
              child: SizedBox(
                width: 600,
                height: 400,
                child: ColoredBox(
                  color: Colors.black,
                  child: SplitWideImage(
                    sourceSize: const Size(1001, 800),
                    buildImage: () => Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: const [
                        Expanded(child: ColoredBox(color: Colors.red)),
                        Expanded(child: ColoredBox(color: Colors.blue)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(captureKey),
      );
      final rendered = (await tester.runAsync(() => boundary.toImage()))!;
      final data = (await tester.runAsync(
        () => rendered.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      int rgb(int x, int y) {
        final offset = (y * rendered.width + x) * 4;
        return data.getUint8(offset) << 16 |
            data.getUint8(offset + 1) << 8 |
            data.getUint8(offset + 2);
      }

      expect(rgb(100, 200), 0xf44336);
      expect(rgb(300, 200), 0x000000);
      expect(rgb(293, 200), 0xf44336);
      expect(rgb(307, 200), 0x2196f3);
      expect(rgb(500, 200), 0x2196f3);
      final directory = Platform.environment['READING_CAPTURE_DIR'];
      if (directory != null) {
        final png = await tester.runAsync(
          () => rendered.toByteData(format: ui.ImageByteFormat.png),
        );
        final file = File('$directory/split-wide.png');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(png!.buffer.asUint8List());
      }
      rendered.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('only fit-size one-finger horizontal touch swipes turn spreads', (
    tester,
  ) async {
    final transform = TransformationController();
    final commands = ZoomableViewportCommands();
    addTearDown(transform.dispose);
    addTearDown(commands.dispose);
    final turns = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: ZoomableViewport(
              contentSize: const Size(400, 300),
              controller: transform,
              commands: commands,
              onHorizontalSwipe: turns.add,
              child: const ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final viewport = find.byType(ZoomableViewport);
    await tester.drag(
      viewport,
      const Offset(-180, 0),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    expect(turns, [1]);
    await tester.drag(
      viewport,
      const Offset(180, 0),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    expect(turns, [1, -1]);
    await tester.drag(
      viewport,
      const Offset(0, -180),
      kind: PointerDeviceKind.touch,
    );
    await tester.drag(
      viewport,
      const Offset(-180, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(turns, [1, -1]);
    final center = tester.getCenter(viewport);
    final first = await tester.startGesture(
      center - const Offset(40, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(40, 0),
      pointer: 2,
    );
    await first.moveBy(const Offset(-80, 0));
    await second.moveBy(const Offset(80, 0));
    await tester.pump();
    await second.up();
    await first.moveBy(const Offset(-100, 0));
    await first.up();
    await tester.pumpAndSettle();
    expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
    expect(turns, [1, -1], reason: 'A pinch cannot finish as a page turn.');
    await tester.drag(
      viewport,
      const Offset(-150, 0),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    expect(turns, [1, -1], reason: 'Zoomed content pans.');
  });
}
