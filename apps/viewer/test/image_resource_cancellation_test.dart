import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/decode_scheduler.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/image_resource_service.dart';
import 'package:shen_view/src/application/prefetch_planner.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';

void main() {
  testWidgets(
    'a cancelled prefetch cannot evict its replacement foreground stream',
    (tester) async {
      final resources = ImageResourceService();
      addTearDown(resources.dispose);
      resources.configurePrefetch(PrefetchLevel.onDemand);
      final file = File('testdata/formats/format_static.png');
      final entry = ImageEntry(
        file: file,
        format: ImageFormat.png,
        width: 32,
        height: 32,
        byteLength: file.lengthSync(),
        modifiedAt: DateTime(2026),
      );
      final provider = resources.provider(
        entry,
        priority: DecodePriority.adjacent,
      );
      final key = await provider.obtainKey(ImageConfiguration.empty);
      await tester.runAsync(() async {
        provider.resolve(ImageConfiguration.empty);
        resources.refreshPolicy();
        // Replace the cancelled request before its asynchronous catch runs.
        final stream = resources
            .provider(entry)
            .resolve(ImageConfiguration.empty);
        final ready = Completer<void>();
        final listener = ImageStreamListener(
          (image, _) {
            image.dispose();
            if (!ready.isCompleted) ready.complete();
          },
          onError: (Object error, StackTrace? stack) =>
              ready.completeError(error, stack),
        );
        stream.addListener(listener);
        await ready.future.timeout(const Duration(seconds: 5));
        expect(
          PaintingBinding.instance.imageCache.statusForKey(key).keepAlive,
          isTrue,
        );
        stream.removeListener(listener);
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelled queued codecs notify error owners without reporting a decode failure',
    (tester) async {
      final resources = ImageResourceService();
      addTearDown(resources.dispose);
      resources.configurePrefetch(PrefetchLevel.onDemand);
      final file = File('testdata/formats/format_static.png');
      final entry = ImageEntry(
        file: file,
        format: ImageFormat.png,
        width: 32,
        height: 32,
        byteLength: file.lengthSync(),
        modifiedAt: DateTime(2026),
      );
      final provider = resources.provider(
        entry,
        priority: DecodePriority.adjacent,
      );
      provider.resolve(ImageConfiguration.empty);
      final key = await provider.obtainKey(ImageConfiguration.empty);
      // ImageCache keeps a success listener without an error callback.
      resources.refreshPolicy();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        PaintingBinding.instance.imageCache.statusForKey(key).pending,
        isFalse,
      );
      Object? cancellation;
      final stream = resources
          .provider(entry, targetWidth: 16, priority: DecodePriority.adjacent)
          .resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener(
        (_, _) {},
        onError: (Object error, StackTrace? _) => cancellation = error,
      );
      stream.addListener(listener);
      resources.refreshPolicy();
      await tester.pump();
      expect(cancellation, isA<DecodeCancelled>());
      stream.removeListener(listener);
      // A new visible request can replace the cancelled cache entry.
      await tester.runAsync(() async {
        final ready = Completer<void>();
        final visible = resources
            .provider(entry)
            .resolve(ImageConfiguration.empty);
        final onImage = ImageStreamListener(
          (image, _) {
            image.dispose();
            if (!ready.isCompleted) ready.complete();
          },
          onError: (Object error, StackTrace? stack) =>
              ready.completeError(error, stack),
        );
        visible.addListener(onImage);
        await ready.future.timeout(const Duration(seconds: 5));
        visible.removeListener(onImage);
      });
      expect(resources.inflightBytes, 0);
    },
  );
}
