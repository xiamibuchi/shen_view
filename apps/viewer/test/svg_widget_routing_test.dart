import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as imaging;
import 'package:shen_view/src/application/svg_resources.dart';
import 'package:shen_view/src/presentation/svg_image.dart';

Uint8List colorPng(int red, int blue) => Uint8List.fromList(
  imaging.encodePng(
    imaging.Image(width: 4, height: 2, numChannels: 4)
      ..clear(imaging.ColorRgba8(red, 0, blue, 255)),
  ),
);

void main() {
  testWidgets(
    'only complex main routes to browser; mounted thumbnails receive its screenshot',
    (tester) async {
      final store = SvgResources(
        rasterize: (_, edge, request) async => colorPng(0, 255),
      );
      addTearDown(store.dispose);
      final file = File('testdata/svg/css_variables.svg');
      final resource = (await tester.runAsync(() => store.read(file)))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              SizedBox(
                width: 300,
                height: 150,
                child: SvgImage(
                  file: file,
                  resources: store,
                  allowWebView: true,
                  browserBuilder: (_, doc, poster) =>
                      const Text('live-browser'),
                ),
              ),
              SizedBox(
                width: 100,
                height: 50,
                child: SvgImage(file: file, resources: store),
              ),
              SizedBox(
                width: 100,
                height: 50,
                child: SvgImage(file: file, resources: store),
              ),
            ],
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (find.byType(Image).evaluate().length == 2) break;
      }
      expect(find.text('live-browser'), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(2));
      await tester.runAsync(
        () => store.publishSnapshot(resource.version, colorPng(255, 0)),
      );
      await tester.pump();
      expect(find.text('live-browser'), findsOneWidget);
      for (final widget in tester.widgetList<Image>(find.byType(Image))) {
        final provider = widget.image as MemoryImage;
        expect(imaging.decodePng(provider.bytes)!.getPixel(0, 0).r, 255);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('static filter main never invokes browser builder', (
    tester,
  ) async {
    final store = SvgResources(
      rasterize: (_, edge, request) async => colorPng(255, 0),
    );
    addTearDown(store.dispose);
    final file = File('testdata/svg/static_filter.svg');
    await tester.runAsync(() => store.read(file));
    await tester.pumpWidget(
      MaterialApp(
        home: SvgImage(
          file: file,
          resources: store,
          allowWebView: true,
          browserBuilder: (_, doc, poster) {
            fail('Static SVG attempted to create a browser');
          },
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (find.byType(Image).evaluate().isNotEmpty) break;
    }
    expect(find.byType(Image), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
