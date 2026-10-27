import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

import 'package:shen_view/main.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/hdr_display_service.dart';
import 'package:shen_view/src/application/image_resource_service.dart';
import 'package:shen_view/src/application/locale_controller.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/hdr_image_view.dart';
import 'package:shen_view/src/presentation/zoomable_viewport.dart';

import 'support/settings_navigation.dart';

Future<ui.Image> _load(ImageProvider<Object> provider) async {
  final done = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      done.complete(info.image.clone());
      stream.removeListener(listener);
    },
    onError: (Object error, StackTrace? stack) {
      done.completeError(error, stack);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return done.future;
}

ImageEntry _entry(String name) {
  final file = File('testdata/formats/$name').absolute;
  final stat = file.statSync();
  return ImageEntry(
    file: file,
    format: ImageFormat.heic,
    width: 700,
    height: 476,
    byteLength: stat.size,
    modifiedAt: stat.modified,
  );
}

Future<Uint8List> _pixels(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
        .asUint8List();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HEIF main image, thumbnails and HDR-off use the SDR base', (
    tester,
  ) async {
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1264, 800));
    await windowManager.show();
    final store = AppConfigStore();
    final config = File(store.filePath);
    final original = config.existsSync() ? config.readAsBytesSync() : null;
    addTearDown(() async {
      if (original != null) {
        await config.writeAsBytes(original);
      } else if (await config.exists()) {
        await config.delete();
      }
    });
    await const ViewerSettings(
      localeCode: 'zh',
      autoHdr: true,
    ).save(store: store);
    final resources = ImageResourceService();
    addTearDown(resources.dispose);
    final reference = await _load(
      resources.provider(_entry('format_alpha.heif')),
    );
    addTearDown(reference.dispose);
    final expected = await _pixels(reference);
    Directory('../../artifacts/hdr').createSync(recursive: true);

    // The fixture's primary HEVC item is byte-for-byte the same dinosaur as
    // format_alpha.heif. Its synthetic enhancement must not alter any SDR pixels.
    for (final name in ['hdr_gain_map.heic', 'hdr_gain_map.heif']) {
      for (final thumbnail in [false, true]) {
        final actual = await _load(
          resources.provider(
            _entry(name),
            targetWidth: thumbnail ? 96 : null,
            targetHeight: thumbnail ? 72 : null,
          ),
        );
        final base = thumbnail
            ? await _load(
                resources.provider(
                  _entry('format_alpha.heif'),
                  targetWidth: 96,
                  targetHeight: 72,
                ),
              )
            : reference;
        expect(
          await _pixels(actual),
          thumbnail ? await _pixels(base) : expected,
        );
        actual.dispose();
        if (thumbnail) base.dispose();
      }
    }

    final root = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: root,
        child: ShenViewApp(
          initialPath: _entry('hdr_gain_map.heic').file
              .resolveSymbolicLinksSync(),
          localeController: AppLocaleController()..setPreference('zh'),
        ),
      ),
    );
    Finder mainImage() => find
        .descendant(
          of: find.byType(ZoomableViewport),
          matching: find.byType(RawImage),
        )
        .first;
    Future<void> waitFor(bool Function() ready) async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        if (ready()) return;
      }
      fail('等待 HEIF 显示或 HDR 设置更新超时');
    }

    await waitFor(
      () =>
          find.byType(HdrImageView).evaluate().isNotEmpty &&
          mainImage().evaluate().isNotEmpty &&
          tester.widget<RawImage>(mainImage()).image != null,
    );
    final enabledImage = tester.widget<RawImage>(mainImage()).image!;
    expect(await _pixels(enabledImage), expected);

    await openViewerSettings(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings.nav.image')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('自动 HDR 显示'));
    await tester.tap(find.text('自动 HDR 显示'));
    await tester.pumpAndSettle();
    expect((await ViewerSettings.load(store: store)).autoHdr, false);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await waitFor(
      () =>
          find.byType(HdrImageView).evaluate().isEmpty &&
          mainImage().evaluate().isNotEmpty &&
          tester.widget<RawImage>(mainImage()).image != null,
    );
    final disabledImage = tester.widget<RawImage>(mainImage()).image!;
    expect(await _pixels(disabledImage), expected);
    final diagnostics = await HdrDisplayService.channel
        .invokeMapMethod<String, dynamic>('diagnostics');
    expect(diagnostics?['activeFrames'], 0);
    final png = await disabledImage.toByteData(format: ui.ImageByteFormat.png);
    File('../../artifacts/hdr/gain-map-sdr-image.png')
        .writeAsBytesSync(png!.buffer.asUint8List());
    await tester.pump();
    final boundary =
        root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final screenshot = await boundary.toImage();
    final screenshotPng = await screenshot.toByteData(
      format: ui.ImageByteFormat.png,
    );
    File('../../artifacts/hdr/gain-map-hdr-disabled.png')
        .writeAsBytesSync(screenshotPng!.buffer.asUint8List());
    screenshot.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }, timeout: const Timeout(Duration(seconds: 120)));
}
