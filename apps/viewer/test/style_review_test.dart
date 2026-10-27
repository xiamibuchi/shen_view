import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/decoder_registry.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/settings_page.dart';
import 'package:shen_view/src/presentation/components/app_select.dart';
import 'package:flutter/services.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

import '../tool/form_components_demo.dart';
import 'support/style_review_fonts.dart';

void main() {
  if (Platform.environment['STYLE_CAPTURE_DIR'] != null) {
    StyleReviewBinding();
  }

  testWidgets(
    'settings preserve their layout with Chinese, English and enlarged text',
    (tester) async {
      final captures = Platform.environment['STYLE_CAPTURE_DIR'];
      if (captures != null) await loadStyleReviewFonts(tester);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final locale in ['zh', 'en']) {
        for (final dark in [false, true]) {
          for (final (width, scale) in [(1280.0, 1.25), (440.0, 1.5)]) {
            tester.view.physicalSize = Size(width, 900);
            await tester.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('style.capture'),
                child: MaterialApp(
                  key: UniqueKey(),
                  debugShowCheckedModeBanner: false,
                  locale: Locale(locale),
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  theme: dark
                      ? AppTheme.dark(platform: TargetPlatform.windows)
                      : AppTheme.light(platform: TargetPlatform.windows),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: SettingsPage(
                    settings: const ViewerSettings(),
                    onChanged: (_) {},
                    decoderRegistry: DecoderRegistry(),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            for (final section in [
              'general',
              'appearance',
              'browsing',
              'reading',
              'interaction',
              'archives',
              'image',
              'shortcuts',
              'about',
            ]) {
              final nav = find.byKey(ValueKey('settings.nav.$section'));
              await tester.ensureVisible(nav);
              await tester.tap(nav);
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: '$locale $dark $width $scale $section',
              );
              if (['general', 'reading', 'image', 'about'].contains(section)) {
                await _capture(
                  tester,
                  captures,
                  'settings-$locale-${dark ? 'dark' : 'light'}-${width.toInt()}-$scale-$section',
                );
              }
            }
            await tester.pumpWidget(const SizedBox());
          }
        }
      }
    },
  );

  testWidgets(
    'component review remains usable at desktop and narrow scaled sizes',
    (tester) async {
      final captures = Platform.environment['STYLE_CAPTURE_DIR'];
      if (captures != null) await loadStyleReviewFonts(tester);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final dark in [false, true]) {
        for (final (size, scale) in [
          (const Size(1200, 1500), 1.0),
          (const Size(440, 900), 1.25),
          (const Size(440, 900), 1.5),
        ]) {
          tester.view.physicalSize = size;
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('style.capture'),
              child: FormComponentsDemo(
                key: UniqueKey(),
                dark: dark,
                textScale: scale,
                platform: TargetPlatform.windows,
              ),
            ),
          );
          await _paint(tester);
          final name =
              '${dark ? 'dark' : 'light'}-${size.width.toInt()}-$scale';
          expect(tester.takeException(), isNull);
          await _capture(tester, captures, '$name-inputs');
          await tester.tap(find.byTooltip('清空搜索'));
          await _paint(tester);
          final editor = find.descendant(
            of: find.byKey(const ValueKey('demo.search')),
            matching: find.byType(EditableText),
          );
          expect(
            tester.widget<EditableText>(editor).focusNode.hasFocus,
            isTrue,
          );
          await tester.enterText(editor, '中文 Search');
          await _paint(tester);
          await _capture(tester, captures, '$name-input-focus');
          final select = find.byType(AppSelect<String>).first;
          await tester.ensureVisible(select);
          await tester.tap(select);
          await _paint(tester);
          expect(tester.takeException(), isNull);
          await _capture(tester, captures, '$name-select-open');
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _paint(tester);
          final card = find.byKey(const ValueKey('demo.card'));
          await tester.ensureVisible(card);
          await _paint(tester);
          final cardText = find.text('文件信息 · 悬停、按下与键盘聚焦');
          Focus.of(tester.element(cardText)).requestFocus();
          await _paint(tester);
          await _capture(tester, captures, '$name-card-focus');
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer();
          await mouse.moveTo(tester.getCenter(card));
          await _paint(tester);
          await mouse.down(tester.getCenter(card));
          await _paint(tester);
          await _capture(tester, captures, '$name-card-pressed');
          await mouse.up();
          await mouse.removePointer();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );
}

// The gallery deliberately includes an indeterminate loading button.
Future<void> _paint(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _capture(
  WidgetTester tester,
  String? directory,
  String name,
) async {
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('style.capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
