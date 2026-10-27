import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shen_view/main.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/decode_priority.dart';
import 'package:shen_view/src/application/locale_controller.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/resource_image.dart';
import 'package:shen_view/src/presentation/viewer_bottom_bar.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'cached HEVC survives arrow navigation beyond the prefetch range',
    (tester) async {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1264, 800));
      await windowManager.show();
      final temporary = await Directory.systemTemp.createTemp(
        'hevc-arrow-cache-',
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await temporary.delete(recursive: true);
      });
      const supplied = String.fromEnvironment('NATIVE_DECODER_FIXTURES');
      final fixtures = Directory(
        supplied.isEmpty ? 'testdata/formats' : supplied,
      );
      await tester.pumpWidget(
        ShenViewApp(
          initialPath: File('${fixtures.path}/hdr_dovi_p81.hevc').absolute.path,
          initialSettings: const ViewerSettings(
            localeCode: 'zh',
            autoHdr: true,
            showDirectoryPanel: false,
            watchFolderChanges: false,
          ),
          configStore: AppConfigStore(
            filePath: '${temporary.path}/config.json',
          ),
          localeController: AppLocaleController()..setPreference('zh'),
        ),
      );
      ViewerBottomBar bar() =>
          tester.widget<ViewerBottomBar>(find.byType(ViewerBottomBar));
      Finder mainImage(String name) => find.byWidgetPredicate(
        (w) =>
            w is ResourceImage &&
            w.priority == DecodePriority.foreground &&
            w.entry.name == name,
      );
      bool ready(String name) => find
          .descendant(of: mainImage(name), matching: find.byType(RawImage))
          .evaluate()
          .any((e) => (e.widget as RawImage).image != null);
      Future<void> waitFor(String name) async {
        final watch = Stopwatch()..start();
        while (!ready(name) && watch.elapsed < const Duration(seconds: 40)) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(ready(name), isTrue, reason: name);
      }

      const hevc = 'hdr_dovi_p81.hevc';
      await waitFor(hevc);
      await tester.pump(const Duration(seconds: 2));
      final main = tester.widget<ResourceImage>(mainImage(hevc).first);
      final trackedKey = await main.resources
          .provider(
            main.entry,
            targetWidth: main.targetWidth,
            targetHeight: main.targetHeight,
          )
          .obtainKey(ImageConfiguration.empty);
      final cache = PaintingBinding.instance.imageCache;
      void record(String event, [int? elapsed]) {
        final status = cache.statusForKey(trackedKey);
        expect(
          status.keepAlive,
          isTrue,
          reason: 'HEVC main cache evicted at $event',
        );
        final state = bar();
        final row = <String, Object?>{
          'event': event,
          'current': state.controller.currentEntry?.name,
          'ms': elapsed,
          'hevcMainPending': status.pending,
          'hevcMainLive': status.live,
          'hevcMainKeepAlive': status.keepAlive,
          'targetWidth': trackedKey.targetWidth,
          'targetHeight': trackedKey.targetHeight,
          'policy': state.resources.policy.level.name,
          'policyReason': state.resources.policy.reason,
          'budget': state.resources.memoryBudgetBytes,
          'cacheBytes': cache.currentSizeBytes,
          'cacheLimit': cache.maximumSizeBytes,
        };
        debugPrint(jsonEncode(row));
      }

      Future<void> arrow(bool forward, String event) async {
        final state = bar();
        final expected = state
            .controller
            .entries[state.controller.currentIndex + (forward ? 1 : -1)]
            .name;
        final watch = Stopwatch()..start();
        await tester.sendKeyEvent(
          forward
              ? LogicalKeyboardKey.arrowRight
              : LogicalKeyboardKey.arrowLeft,
        );
        await tester.pump();
        expect(bar().controller.currentEntry?.name, expected);
        await waitFor(expected);
        final elapsed = watch.elapsedMilliseconds;
        await tester.pump(const Duration(milliseconds: 500));
        record(event, elapsed);
      }

      record('initial');
      for (var round = 0; round < 3; round++) {
        await arrow(true, 'adjacent right $round');
        await arrow(false, 'adjacent left $round');
      }
      for (var step = 1; step <= 4; step++) {
        await arrow(true, 'walk right $step');
      }
      for (var step = 1; step <= 4; step++) {
        await arrow(false, 'walk left $step');
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
