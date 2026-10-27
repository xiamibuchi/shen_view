import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shen_view/main.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/locale_controller.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/raw_resource_image.dart';
import 'package:shen_view/src/presentation/zoomable_viewport.dart';

import 'raw_display_test.dart' as exposure;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  exposure.main();
  testWidgets(
    'real ARW and NEF refine main detail after zoom in the Windows viewer',
    (tester) async {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1264, 800));
      await windowManager.show();
      final store = AppConfigStore();
      final config = File(store.filePath);
      final saved = config.existsSync() ? config.readAsBytesSync() : null;
      addTearDown(() async {
        if (saved != null) {
          await config.writeAsBytes(saved);
        } else if (await config.exists()) {
          await config.delete();
        }
      });
      await const ViewerSettings(
        localeCode: 'zh',
        autoHdr: false,
      ).save(store: store);
      final output = Directory('../../artifacts/raw-preview')
        ..createSync(recursive: true);
      for (final name in ['raw_sony_a7s.arw', 'raw_nikon_d2h.nef']) {
        final root = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: root,
            child: ShenViewApp(
              initialPath: File('testdata/formats/$name')
                  .resolveSymbolicLinksSync(),
              localeController: AppLocaleController()..setPreference('zh'),
            ),
          ),
        );
        final images = find.descendant(
          of: find.byType(ZoomableViewport),
          matching: find.byType(RawImage),
        );
        Future<ui.Image> waitForImage({int minimumWidth = 1}) async {
          final deadline = DateTime.now().add(const Duration(seconds: 45));
          while (DateTime.now().isBefore(deadline)) {
            await tester.pump(const Duration(milliseconds: 100));
            if (images.evaluate().isNotEmpty) {
              final image = tester.widget<RawImage>(images.first).image;
              if (image != null && image.width >= minimumWidth) return image;
            }
          }
          throw StateError('等待 RAW 主图或高分辨率细节超时：$name');
        }

        Future<void> capture(String suffix) async {
          await tester.pump();
          final boundary =
              root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final screenshot = await boundary.toImage();
          final bytes = await screenshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File('${output.path}/$name-$suffix.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          screenshot.dispose();
        }

        final initial = await waitForImage();
        expect(initial.width / initial.height, closeTo(1.5, .03));
        await capture('fit');
        final raw = tester.widget<RawResourceImage>(
          find.byType(RawResourceImage),
        );
        raw.transform.value = Matrix4.diagonal3Values(3, 3, 1);
        final refined = await waitForImage(minimumWidth: 2200);
        expect(refined.width / refined.height, closeTo(1.5, .03));
        await capture('zoom');
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
    timeout: const Timeout(Duration(seconds: 150)),
  );
}
