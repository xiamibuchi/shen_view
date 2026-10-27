import 'dart:io';

import 'package:flutter/material.dart';
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
    'cached HDR thumbnails survive navigation and leave room for RAW',
    (tester) async {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1264, 800));
      await windowManager.show();
      const supplied = String.fromEnvironment('NATIVE_DECODER_FIXTURES');
      final fixtures = Directory(
        supplied.isEmpty ? 'testdata/formats' : supplied,
      );
      final root = await Directory.systemTemp.createTemp(
        'hdr-thumbnail-recovery-',
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await root.delete(recursive: true);
      });
      // More than one viewport lets offscreen HDR prefetch be skipped before the
      // same thumbnail is demanded, loaded, unmounted and shown again.
      for (final name in [
        'hdr_dovi_p81.hevc',
        'hdr_gain_map.avif',
        'hdr_gain_map.heic',
        'hdr_gain_map.heif',
        'hdr_gain_map.jpg',
        'hdr_gradient.exr',
        'hdr_gradient.hdr',
        'hdr_highlights.exr',
        'hdr_highlights.hdr',
        'hdr_hlg.avif',
        'hdr_hlg.png',
        'hdr_pq_alpha.png',
        'hdr_pq.avif',
        'hdr_pq.png',
        'hdr_rec2020.exr',
        'hdr_transparent.exr',
        'raw_canon_white_paper.cr2',
      ]) {
        await File('${fixtures.path}/$name').copy('${root.path}/$name');
      }
      await tester.pumpWidget(
        ShenViewApp(
          initialPath: '${root.path}/hdr_dovi_p81.hevc',
          initialSettings: const ViewerSettings(
            localeCode: 'zh',
            autoHdr: true,
            showDirectoryPanel: false,
            watchFolderChanges: false,
          ),
          configStore: AppConfigStore(filePath: '${root.path}/config.json'),
          localeController: AppLocaleController()..setPreference('zh'),
        ),
      );
      Finder thumbnails() => find.byWidgetPredicate(
        (w) =>
            w is ResourceImage && w.priority == DecodePriority.visibleThumbnail,
      );
      bool ready(Finder scope) => find
          .descendant(of: scope, matching: find.byType(RawImage))
          .evaluate()
          .any((e) => (e.widget as RawImage).image != null);
      Future<void> until(bool Function() condition, String reason) async {
        final deadline = DateTime.now().add(const Duration(seconds: 40));
        while (!condition() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(condition(), isTrue, reason: reason);
      }

      Future<void> settleThumbnails() => until(
        () =>
            thumbnails().evaluate().isNotEmpty &&
            thumbnails().evaluate().every(
              (e) => ready(find.byWidget(e.widget)),
            ),
        'visible HDR thumbnails settle',
      );
      await settleThumbnails();
      const navigation = [
        'hdr_dovi_p81.hevc',
        'hdr_gain_map.avif',
        'hdr_hlg.avif',
        'hdr_pq.avif',
        'raw_canon_white_paper.cr2',
      ];
      final loaded = <String>{};
      for (var page = 0; page < navigation.length * 3; page++) {
        for (final tile in thumbnails().evaluate()) {
          if (ready(find.byWidget(tile.widget))) {
            loaded.add((tile.widget as ResourceImage).entry.id);
          }
        }
        final name = navigation[page % navigation.length];
        final bar = tester.widget<ViewerBottomBar>(
          find.byType(ViewerBottomBar),
        );
        bar.onSelect(bar.controller.entries.indexWhere((e) => e.name == name));
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
          for (final tile in thumbnails().evaluate()) {
            final item = tile.widget as ResourceImage;
            if (loaded.contains(item.entry.id)) {
              expect(
                ready(find.byWidget(item)),
                isTrue,
                reason: 'cached thumbnail reloaded: ${item.entry.name}',
              );
            }
          }
        }
        await until(
          () => ready(
            find.byWidgetPredicate(
              (w) =>
                  w is ResourceImage &&
                  w.priority == DecodePriority.foreground &&
                  w.entry.name == name,
            ),
          ),
          'main image displays: $name',
        );
        await settleThumbnails();
        expect(find.textContaining('当前图像资源不足'), findsNothing);
      }
      final resources = tester
          .widget<ViewerBottomBar>(find.byType(ViewerBottomBar))
          .resources;
      await until(
        () => resources.inflightBytes == 0,
        'decode reservations released after navigation',
      );
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
