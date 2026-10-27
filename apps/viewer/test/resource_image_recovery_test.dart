import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/image_resource_service.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';
import 'package:shen_view/src/presentation/resource_image.dart';

void main() {
  testWidgets(
    'visible resource failure recovers after capacity returns without navigating away',
    (tester) async {
      final resources = ImageResourceService();
      addTearDown(resources.dispose);
      final file = File('testdata/formats/format_static.png');
      final entry = ImageEntry(
        file: file,
        format: ImageFormat.png,
        width: 32,
        height: 32,
        byteLength: 64 * 1024,
        modifiedAt: DateTime(2026),
      );
      resources.applyWorkingSet(
        protectedIds: {entry.id},
        retainedIds: {entry.id},
        memoryBudgetBytes: 1024,
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ResourceImage(
            resources: resources,
            entry: entry,
            errorBuilder: (_, error, _) => Text(
              error is ImageResourceUnavailable
                  ? 'resource unavailable'
                  : 'unexpected error',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('resource unavailable'), findsOneWidget);
      resources.setActive(false);
      resources.applyWorkingSet(
        protectedIds: {entry.id},
        retainedIds: {entry.id},
        memoryBudgetBytes: 4 * 1024 * 1024,
      );
      resources.setActive(true);
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        final raw = tester.widgetList<RawImage>(find.byType(RawImage));
        if (raw.any((image) => image.image != null)) break;
      }
      expect(find.text('resource unavailable'), findsNothing);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(resources.inflightBytes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('permanent file errors do not retry on every focus event', (
    tester,
  ) async {
    final resources = ImageResourceService();
    addTearDown(resources.dispose);
    final entry = ImageEntry(
      file: File('does-not-exist.png'),
      format: ImageFormat.png,
      width: 32,
      height: 32,
      byteLength: 100,
      modifiedAt: DateTime(2026),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ResourceImage(
          resources: resources,
          entry: entry,
          errorBuilder: (_, error, _) => const Text('file error'),
        ),
      ),
    );
    for (var i = 0; i < 30 && find.text('file error').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(find.text('file error'), findsOneWidget);
    final imageState = tester.state(find.byType(Image));
    resources.setActive(false);
    resources.setActive(true);
    await tester.pump();
    await tester.pump();
    expect(tester.state(find.byType(Image)), same(imageState));
    expect(find.text('file error'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
