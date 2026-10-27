import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

import 'package:shen_view/main.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/locale_controller.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/hdr_image_view.dart';
import 'package:shen_view/src/presentation/zoomable_viewport.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'CR2 retains corrected white-paper brightness with automatic HDR off and on',
    (tester) async {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1264, 800));
      await windowManager.show();
      final configRoot = await Directory.systemTemp.createTemp(
        'raw-brightness-display-',
      );
      addTearDown(() => configRoot.delete(recursive: true));
      final store = AppConfigStore(
        filePath: '${configRoot.path}/settings.json',
      );
      const settings = ViewerSettings(
        localeCode: 'zh',
        autoHdr: false,
        watchFolderChanges: false,
        recentOpenEnabled: false,
        archivePrefetchMode: ArchivePrefetchMode.off,
        thumbnailPrefetchMode: ThumbnailPrefetchMode.off,
      );
      final root = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: root,
          child: ShenViewApp(
            initialSettings: settings,
            configStore: store,
            initialPath: File('testdata/formats/raw_canon_white_paper.cr2')
                .resolveSymbolicLinksSync(),
            localeController: AppLocaleController()..setPreference('zh'),
          ),
        ),
      );
      final mainImages = find.descendant(
        of: find.byType(ZoomableViewport),
        matching: find.byType(RawImage),
      );
      final mainImage = mainImages.first;
      Future<void> waitFor(bool Function() ready) async {
        final deadline = DateTime.now().add(const Duration(seconds: 40));
        while (DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('等待 CR2 显影或 HDR 设置更新超时');
      }

      await waitFor(
        () =>
            mainImages.evaluate().isNotEmpty &&
            tester.widget<RawImage>(mainImage).image != null,
      );
      expect(find.byType(HdrImageView), findsNothing);
      expect(find.text('raw_canon_white_paper.cr2'), findsWidgets);
      final image = tester.widget<RawImage>(mainImage).image!;
      expect(
        image.width / image.height,
        closeTo(1.5, 0.01),
        reason:
            'The RAW bitmap must keep its aspect ratio without black padding',
      );
      final before = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final paper = (image.height ~/ 2 * image.width + image.width ~/ 8) * 4;
      Directory('../../artifacts/hdr').createSync(recursive: true);
      final decodedPng = await image.toByteData(format: ui.ImageByteFormat.png);
      File('../../artifacts/hdr/cr2-viewer-decoded.png')
          .writeAsBytesSync(decodedPng!.buffer.asUint8List());
      await tester.pump();
      final boundary =
          root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final screenshot = await boundary.toImage();
      final screenshotPng = await screenshot.toByteData(
        format: ui.ImageByteFormat.png,
      );
      File('../../artifacts/hdr/cr2-viewer-hdr-off.png')
          .writeAsBytesSync(screenshotPng!.buffer.asUint8List());
      screenshot.dispose();
      // This is photographed white paper, not sensor-linear mid-grey. Check
      // the displayed result independently of whichever decoder was selected.
      for (var c = 0; c < 3; c++) {
        expect(before.getUint8(paper + c), inInclusiveRange(166, 252));
      }

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await waitFor(
        () => find
            .byKey(const ValueKey('settings.nav.image'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings.nav.image')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('自动 HDR 显示'));
      await tester.tap(find.text('自动 HDR 显示'));
      await tester.pumpAndSettle();
      expect((await ViewerSettings.load(store: store)).autoHdr, true);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await waitFor(
        () =>
            find.byType(HdrImageView).evaluate().isNotEmpty &&
            mainImages.evaluate().isNotEmpty &&
            tester.widget<RawImage>(mainImage).image != null,
      );
      final after = (await tester
          .widget<RawImage>(mainImage)
          .image!
          .toByteData(format: ui.ImageByteFormat.rawRgba))!;
      expect(
        Uint8List.sublistView(after),
        Uint8List.sublistView(before),
        reason: 'The SDR fallback stays correctly exposed when HDR is enabled',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
