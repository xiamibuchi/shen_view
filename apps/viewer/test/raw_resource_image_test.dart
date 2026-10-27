import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/decode_scheduler.dart';
import 'package:shen_view/src/application/image_resource_service.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';
import 'package:shen_view/src/domain/image_resource_key.dart';
import 'package:shen_view/src/presentation/raw_resource_image.dart';

class _Resources extends ImageResourceService {
  final sizes = <(int?, int?)>[];
  @override
  ImageProvider<ImageResourceKey> provider(
    ImageEntry entry, {
    int? targetWidth,
    int? targetHeight,
    ImageRegion? region,
    DecodePriority priority = DecodePriority.foreground,
    double distance = 0,
  }) {
    sizes.add((targetWidth, targetHeight));
    return super.provider(
      entry,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      region: region,
      priority: priority,
      distance: distance,
    );
  }
}

void main() {
  testWidgets(
    'RAW draw demand follows DPI and zoom, coalesces gestures and retains detail on pan',
    (tester) async {
      final resources = _Resources();
      final transform = TransformationController();
      final entry = ImageEntry(
        file: File('testdata/formats/format_static.png'),
        format: ImageFormat.png,
        width: 2400,
        height: 1600,
        byteLength: 1024,
        modifiedAt: DateTime(2026, 10, 24),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 2),
            child: Center(
              child: SizedBox(
                width: 300,
                height: 200,
                child: RawResourceImage(
                  resources: resources,
                  entry: entry,
                  transform: transform,
                  sourceSize: const Size(2400, 1600),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => const SizedBox(),
                ),
              ),
            ),
          ),
        ),
      );
      expect(resources.sizes.last, (600, 400));
      transform.value = Matrix4.diagonal3Values(1.5, 1.5, 1);
      await tester.pump();
      expect(resources.sizes.last, (600, 400));
      transform.value = Matrix4.diagonal3Values(2, 2, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 170));
      await tester.pump();
      expect(resources.sizes.last, (1200, 800));
      transform.value = Matrix4.copy(transform.value)
        ..setTranslationRaw(80, 40, 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(resources.sizes.last, (1200, 800));
      transform.value = Matrix4.identity();
      await tester.pump(const Duration(milliseconds: 200));
      expect(resources.sizes.last, (1200, 800));
      await tester.pumpWidget(const SizedBox());
      resources.dispose();
      transform.dispose();
      await tester.pump();
    },
  );
}
