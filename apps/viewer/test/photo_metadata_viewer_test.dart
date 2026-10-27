import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/components/app_info_field.dart';
import 'package:shen_view/src/presentation/color_picker_target.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';

import 'support/photo_metadata_fixtures.dart';
import 'support/style_review_fonts.dart';

const _captureKey = ValueKey('photo.info.capture');

void main() {
  StyleReviewBinding();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async =>
              [
                'isFullScreen',
                'isMaximized',
                'isAlwaysOnTop',
              ].contains(call.method)
              ? false
              : null,
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null),
  );

  for (final dark in [false, true]) {
    for (final (width, scale) in [(1100.0, 1.0), (600.0, 1.5)]) {
      testWidgets(
        'photo information fits dark=$dark width=$width scale=$scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final captures = Platform.environment['PHOTO_METADATA_CAPTURE_DIR'];
          if (captures != null) await loadStyleReviewFonts(tester);
          final dir = Directory.systemTemp.createTempSync('photo-panel');
          addTearDown(() {
            try {
              dir.deleteSync(recursive: true);
            } on FileSystemException {
              /* Background source leases can outlive widget disposal on Windows. */
            }
          });
          final path = '${dir.path}/photo.jpg';
          File(path).writeAsBytesSync(
            jpegWithXmp(
              img.encodeJpg(metadataPhoto()),
              photoXmp(title: '旅行相册：海边与山间的光影 café'),
            ),
          );
          File('${dir.path}/plain.png')
              .writeAsBytesSync(img.encodePng(img.Image(width: 16, height: 8)));
          await tester.pumpWidget(
            RepaintBoundary(
              key: _captureKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: dark
                    ? AppTheme.dark(platform: TargetPlatform.windows)
                    : AppTheme.light(platform: TargetPlatform.windows),
                locale: const Locale('zh'),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: ViewerPage(
                  initialPath: path,
                  initialSettings: const ViewerSettings(
                    showDirectoryPanel: false,
                    watchFolderChanges: false,
                  ),
                  configStore: AppConfigStore(
                    filePath: '${dir.path}/settings.json',
                  ),
                ),
              ),
            ),
          );
          await _wait(
            tester,
            () => find.byTooltip(RegExp(r' · I$')).evaluate().isNotEmpty,
          );
          await _wait(
            tester,
            () => find
                .descendant(
                  of: find.byType(ColorPickerTarget),
                  matching: find.byWidgetPredicate(
                    (w) => w is RawImage && w.image != null,
                  ),
                )
                .evaluate()
                .isNotEmpty,
          );
          await tester.tap(find.byTooltip(RegExp(r' · I$')));
          await _wait(tester, () => find.text('拍摄时间').evaluate().isNotEmpty);
          expect(find.text('2026-10-26 12:34:56.123 +08:00'), findsOneWidget);
          expect(find.text('f/2.8'), findsOneWidget);
          expect(find.text('1/125 s'), findsOneWidget);
          expect(find.text('33.500000° S, 70.666667° W'), findsOneWidget);
          expect(find.text('title'), findsNothing);
          final name = '${dark ? "dark" : "light"}-${width.toInt()}';
          for (final (label, section) in [('拍摄时间', 'camera'), ('标题', 'xmp')]) {
            await tester.ensureVisible(find.text(label));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final fields = tester.widgetList<AppInfoField>(
              find.byType(AppInfoField),
            );
            expect(fields.any((f) => f.label == '拍摄时间'), true);
            for (final finder
                in find
                    .byType(AppInfoField)
                    .evaluate()
                    .map((e) => find.byWidget(e.widget))) {
              final rect = tester.getRect(finder);
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(width));
            }
            final title = tester.getRect(find.text(label));
            final value = tester.getRect(
              find.descendant(
                of: find.byWidgetPredicate(
                  (w) => w is AppInfoField && w.label == label,
                ),
                matching: find.byType(SelectableText),
              ),
            );
            expect(value.left - title.right, greaterThanOrEqualTo(12));
            await _save(tester, captures, '$name-$section');
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await _wait(
            tester,
            () =>
                find.text('plain.png').evaluate().isNotEmpty &&
                find.text('拍摄时间').evaluate().isEmpty,
          );
          expect(find.text('标题'), findsNothing);
          expect(find.text('相机信息'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}

Future<void> _wait(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 150; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    if (condition()) return;
  }
  expect(condition(), true);
}

Future<void> _save(WidgetTester tester, String? dir, String name) async {
  if (dir == null) return;
  await tester.runAsync(() async {
    final image = await tester
        .renderObject<RenderRepaintBoundary>(find.byKey(_captureKey))
        .toImage();
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$dir/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
