import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/decode_scheduler.dart';
import 'package:shen_view/src/application/image_resource_service.dart';
import 'package:shen_view/src/application/prefetch_planner.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';

void main() {
  testWidgets(
    'on-demand prepares foreground metadata and first frame without a mounted image',
    (tester) async {
      final service = ImageResourceService();
      addTearDown(service.dispose);
      service.configurePrefetch(PrefetchLevel.onDemand);
      final file = File('testdata/formats/format_static.png');
      final stat = file.statSync();
      final entry = ImageEntry(
        file: file,
        format: ImageFormat.png,
        width: null,
        height: null,
        byteLength: stat.size,
        modifiedAt: stat.modified,
      );
      var ready = false;
      Object? failure;
      unawaited(() async {
        try {
          await service.metadata(entry, priority: DecodePriority.foreground);
          final stream = service
              .provider(entry, targetWidth: 256, targetHeight: 144)
              .resolve(ImageConfiguration.empty);
          final done = Completer<void>();
          final listener = ImageStreamListener(
            (_, _) {
              if (!done.isCompleted) done.complete();
            },
            onError: (Object error, StackTrace? stack) {
              if (!done.isCompleted) done.completeError(error, stack);
            },
          );
          stream.addListener(listener);
          try {
            await done.future;
          } finally {
            stream.removeListener(listener);
          }
          ready = true;
        } catch (error) {
          failure = error;
        }
      }());
      for (var i = 0; i < 200 && !ready && failure == null; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
      }
      expect(failure, isNull);
      expect(ready, isTrue);
    },
  );
}
