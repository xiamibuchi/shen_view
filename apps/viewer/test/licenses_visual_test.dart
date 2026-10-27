import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/decoder_registry.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/components/app_text_action.dart';
import 'package:shen_view/src/presentation/licenses_page.dart';
import 'package:shen_view/src/presentation/settings_page.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

import 'support/style_review_fonts.dart';

const _capture = ValueKey('license-review');

void main() {
  for (final width in [440.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets('about footer and license details at $width dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadStyleReviewFonts(tester);
        Widget host(Widget child) => RepaintBoundary(
          key: _capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark
                ? AppTheme.dark(platform: TargetPlatform.windows)
                : AppTheme.light(platform: TargetPlatform.windows),
            locale: const Locale('zh'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: child,
          ),
        );
        await tester.pumpWidget(
          host(
            SettingsPage(
              settings: const ViewerSettings(),
              decoderRegistry: DecoderRegistry(),
              onChanged: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('settings.nav.about')));
        await tester.pumpAndSettle();
        final link = find.byKey(const ValueKey('settings.openLicenses'));
        await tester.ensureVisible(link);
        await tester.pumpAndSettle();
        expect(tester.widget(link), isA<AppTextAction>());
        final footnote = find.textContaining('用于 Dolby Vision');
        final linkRect = tester.getRect(link);
        final noteRect = tester.getRect(footnote);
        expect((linkRect.left - noteRect.left).abs(), lessThanOrEqualTo(2));
        expect(linkRect.top, greaterThanOrEqualTo(noteRect.bottom));
        expect(linkRect.height, lessThanOrEqualTo(40));
        await _save(tester, 'about-$width-$dark');

        await tester.pumpWidget(
          host(
            LicensesPage(
              source: Stream.fromIterable([
                const LicenseEntryWithLineBreaks(
                  ['7-Zip'],
                  '7-Zip\nCopyright (C) Igor Pavlov.\n\nGNU LGPL 2.1 or later; BSD and unRAR terms apply.',
                ),
                const LicenseEntryWithLineBreaks([
                  '7-Zip',
                ], 'Corresponding source\n\nhttps://www.7-zip.org/'),
                const _CenteredLicense(),
                const LicenseEntryWithLineBreaks([
                  'abseil-cpp',
                ], 'Additional copyright notice'),
                const LicenseEntryWithLineBreaks([
                  'flutter',
                ], 'Flutter BSD license'),
              ]),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('abseil-cpp'), findsOneWidget);
        await _save(tester, 'list-$width-$dark');
        await tester.tap(find.text('abseil-cpp'));
        await tester.pumpAndSettle();
        expect(find.text('Centered license heading'), findsOneWidget);
        await _save(tester, 'detail-$width-$dark');
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _CenteredLicense extends LicenseEntry {
  const _CenteredLicense();

  @override
  Iterable<String> get packages => ['abseil-cpp'];

  @override
  Iterable<LicenseParagraph> get paragraphs => const [
    LicenseParagraph(
      'Centered license heading',
      LicenseParagraph.centeredIndent,
    ),
    LicenseParagraph(
      'Copyright notice and permission to use this software. This paragraph remains selectable and wraps in narrow windows.',
      0,
    ),
    LicenseParagraph('Indented license terms.', 1),
  ];
}

Future<void> _save(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('../../artifacts/license-review/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
