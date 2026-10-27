import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/decoder_registry.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/components/app_select.dart';
import 'package:shen_view/src/presentation/components/app_search_text.dart';
import 'package:shen_view/src/presentation/settings_page.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

import 'support/style_review_fonts.dart';

void main() {
  test('thumbnail preference persists independently and invalid values use automatic', () async {
    final directory = await Directory.systemTemp.createTemp(
      'thumbnail-settings-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = AppConfigStore(filePath: '${directory.path}/settings.json');
    for (final mode in ThumbnailPrefetchMode.values) {
      final settings = const ViewerSettings(
        archivePrefetchMode: ArchivePrefetchMode.off,
      ).copyWith(thumbnailPrefetchMode: mode);
      await settings.save(store: store);
      expect(await ViewerSettings.load(store: store), settings);
      expect(settings.hashCode, settings.copyWith().hashCode);
    }
    await store.write({
      'settings': {'thumbnailPrefetchMode': 'unknown', 'localeCode': 'en'},
    });
    expect(
      (await ViewerSettings.load(store: store)).thumbnailPrefetchMode,
      ThumbnailPrefetchMode.automatic,
    );
  });

  for (final width in [1280.0, 440.0]) {
    for (final dark in [false, true]) {
      testWidgets('thumbnail setting layout and menu at $width dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final capture = Platform.environment['THUMBNAIL_PREFETCH_CAPTURE_DIR'];
        if (capture != null) await loadStyleReviewFonts(tester);
        var settings = const ViewerSettings(
          archivePrefetchMode: ArchivePrefetchMode.off,
        );
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: dark
                ? AppTheme.dark(platform: TargetPlatform.windows)
                : AppTheme.light(platform: TargetPlatform.windows),
            home: RepaintBoundary(
              key: const ValueKey('capture'),
              child: SettingsPage(
                settings: settings,
                onChanged: (value) => settings = value,
                decoderRegistry: DecoderRegistry(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final nav = find.byKey(const ValueKey('settings.nav.image'));
        await tester.ensureVisible(nav);
        await tester.tap(nav);
        await tester.pumpAndSettle();
        final control = find.byKey(
          const ValueKey('settings.thumbnailPrefetchMode'),
        );
        expect(
          tester.widget<AppSelect<ThumbnailPrefetchMode>>(control).value,
          ThumbnailPrefetchMode.automatic,
        );
        final title = find.byWidgetPredicate(
          (widget) => widget is AppSearchText && widget.data == '缩略图预加载',
        );
        final controlRect = tester.getRect(control);
        final titleRect = tester.getRect(title);
        expect(controlRect.left, greaterThanOrEqualTo(16));
        expect(controlRect.right, lessThanOrEqualTo(width - 16));
        expect(controlRect.height, greaterThanOrEqualTo(32));
        if (width == 440) {
          expect((titleRect.left - controlRect.left).abs(), lessThan(1));
          expect(controlRect.top - titleRect.bottom, greaterThanOrEqualTo(12));
        } else {
          expect(controlRect.left - titleRect.right, greaterThanOrEqualTo(20));
        }
        if (capture != null) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '$capture/thumbnail-$width-${dark ? 'dark' : 'light'}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        await tester.tap(control);
        await tester.pumpAndSettle();
        await tester.tap(find.text('保守').last);
        await tester.pumpAndSettle();
        expect(
          settings.thumbnailPrefetchMode,
          ThumbnailPrefetchMode.conservative,
        );
        expect(settings.archivePrefetchMode, ArchivePrefetchMode.off);
        await tester.tap(control);
        await tester.pumpAndSettle();
        await tester.tap(find.text('关闭').last);
        await tester.pumpAndSettle();
        expect(settings.thumbnailPrefetchMode, ThumbnailPrefetchMode.off);
        await tester.tap(find.byKey(const ValueKey('settings.resetSection')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('恢复默认').last);
        await tester.pumpAndSettle();
        expect(settings.thumbnailPrefetchMode, ThumbnailPrefetchMode.automatic);
        expect(settings.archivePrefetchMode, ArchivePrefetchMode.off);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
