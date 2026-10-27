import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

import 'package:shen_view/main.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/hdr_display_service.dart';
import 'package:shen_view/src/application/locale_controller.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/hdr_image_view.dart';
import 'package:shen_view/src/presentation/zoomable_viewport.dart';

import 'support/settings_navigation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final input in [
    ('hdr_highlights.exr', '线性 HDR（HDR / EXR）'),
    ('hdr_pq.avif', 'PQ / HLG'),
    ('hdr_gain_map.heic', 'Gain Map'),
    ('raw_canon_white_paper.cr2', 'RAW'),
    ('hdr_dovi_p81.hevc', 'Dolby Vision'),
  ]) {
    testWidgets('HDR type fallback and recovery: ${input.$1}', (tester) async {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1264, 800));
      await windowManager.show();
      final store = AppConfigStore();
      final config = File(store.filePath);
      final original = config.existsSync() ? config.readAsBytesSync() : null;
      final directory = await Directory.systemTemp.createTemp(
        'viewer-hdr-type',
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        if (original != null) {
          await config.writeAsBytes(original);
        } else if (config.existsSync()) {
          await config.delete();
        }
        await directory.delete(recursive: true);
      });
      await const ViewerSettings(localeCode: 'zh').save(store: store);
      final file = await File('testdata/formats/${input.$1}')
          .copy('${directory.path}/${input.$1}');
      await tester.pumpWidget(
        ShenViewApp(
          initialPath: file.resolveSymbolicLinksSync(),
          localeController: AppLocaleController()..setPreference('zh'),
        ),
      );
      Finder image() => find
          .descendant(
            of: find.byType(ZoomableViewport),
            matching: find.byType(RawImage),
          )
          .first;
      Future<void> waitFor(bool Function() ready) async {
        final deadline = DateTime.now().add(const Duration(seconds: 40));
        while (DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('等待 HDR 类型策略应用超时：${input.$1}');
      }

      Future<void> changeType() async {
        await openViewerSettings(tester);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('settings.nav.image')));
        await tester.pumpAndSettle();
        final toggle = find.byWidgetPredicate(
          (w) => w is AppSwitch && w.label == input.$2,
        );
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: toggle, matching: find.text(input.$2)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
      }

      await waitFor(
        () =>
            find.byType(HdrImageView).evaluate().isNotEmpty &&
            image().evaluate().isNotEmpty &&
            tester.widget<RawImage>(image()).image != null,
      );
      final expected =
          (await tester
                  .widget<RawImage>(image())
                  .image!
                  .toByteData(format: ui.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
      await changeType();
      expect((await ViewerSettings.load(store: store)).autoHdr, isTrue);
      await waitFor(
        () =>
            find.byType(HdrImageView).evaluate().isEmpty &&
            image().evaluate().isNotEmpty &&
            tester.widget<RawImage>(image()).image != null,
      );
      final actual =
          (await tester
                  .widget<RawImage>(image())
                  .image!
                  .toByteData(format: ui.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
      expect(actual, expected, reason: '禁用类型后应保留相同的 SDR 底图');
      final diagnostics = await HdrDisplayService.channel
          .invokeMapMethod<String, dynamic>('diagnostics');
      expect(diagnostics?['activeFrames'], 0);
      await changeType();
      await waitFor(() => find.byType(HdrImageView).evaluate().isNotEmpty);
      expect(tester.takeException(), isNull);
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
