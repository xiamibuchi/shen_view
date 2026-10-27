import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as imaging;
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/decoder_registry.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/settings_page.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';

import 'support/style_review_fonts.dart';

const _capture = ValueKey('ui-icons.capture');

void main() {
  test('resvg density variants preserve dimensions and transparency', () {
    for (final (name, size) in [('app-icon', 52), ('info', 18)]) {
      for (final density in [1, 2, 3, 4]) {
        final directory = density == 1 ? 'assets/ui' : 'assets/ui/$density.0x';
        final image = imaging.decodePng(
          File('$directory/$name.png').readAsBytesSync(),
        )!;
        expect(image.width, size * density);
        expect(image.height, size * density);
        expect(image.getPixel(0, 0).a, 0);
        expect(image.any((pixel) => pixel.a > 200), isTrue);
      }
    }
  });

  for (final dark in [false, true]) {
    testWidgets(
      'UI icons retain size, tint and semantics at every DPR dark=$dark',
      (tester) async {
        await loadStyleReviewFonts(tester);
        const channel = MethodChannel('window_manager');
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (const [
            'isFullScreen',
            'isMaximized',
            'isAlwaysOnTop',
          ].contains(call.method)) {
            return false;
          }
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final directory = Directory.systemTemp.createTempSync(
          'shenview-ui-icons-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final config = AppConfigStore(
          filePath: '${directory.path}/settings.json',
        );
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        for (final density in [1.0, 2.0, 3.0, 4.0]) {
          tester.view.devicePixelRatio = density;
          tester.view.physicalSize = Size(960 * density, 720 * density);
          await tester.pumpWidget(
            _host(
              ViewerPage(
                configStore: config,
                initialSettings: const ViewerSettings(),
              ),
              dark: dark,
            ),
          );
          await tester.pumpAndSettle();
          final info = _asset('info');
          await _decode(tester, info);
          _expectResolution(tester, info, 18, density);
          final color = ViewerThemeTokens.of(tester.element(info)).textPrimary;
          expect(tester.widget<Image>(info).color, color);
          expect(tester.widget<Image>(info).excludeFromSemantics, isTrue);
          expect(tester.getRect(info).center.dx, closeTo(480, 0.5));
          if (density == 1) await _save(tester, 'info-$dark');
          await mouse.moveTo(tester.getCenter(info));
          await tester.pumpAndSettle();
          expect(tester.widget<Image>(info).color, color);
          if (density == 1) await _save(tester, 'info-hover-$dark');
          await mouse.moveTo(Offset.zero);
          await tester.pumpWidget(const SizedBox.shrink());

          await tester.pumpWidget(
            _host(
              SettingsPage(
                settings: const ViewerSettings(),
                decoderRegistry: DecoderRegistry(),
                onChanged: (_) {},
              ),
              dark: dark,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('settings.nav.about')));
          await tester.pumpAndSettle();
          final brand = _asset('app-icon');
          await _decode(tester, brand);
          _expectResolution(tester, brand, 52, density);
          expect(tester.widget<Image>(brand).semanticLabel, '神羊看图');
          expect(tester.widget<Image>(brand).color, isNull);
          if (density == 1) await _save(tester, 'about-$dark');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }
}

Widget _host(Widget child, {required bool dark}) => RepaintBoundary(
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

Finder _asset(String name) => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is AssetImage &&
      (widget.image as AssetImage).assetName == 'assets/ui/$name.png',
);

Future<void> _decode(WidgetTester tester, Finder finder) async {
  await tester.runAsync(
    () => precacheImage(
      tester.widget<Image>(finder).image,
      tester.element(finder),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectResolution(
  WidgetTester tester,
  Finder finder,
  int size,
  double density,
) {
  expect(tester.getSize(finder), Size.square(size.toDouble()));
  final raw = tester.widget<RawImage>(
    find.descendant(of: finder, matching: find.byType(RawImage)),
  );
  expect(raw.image, isNotNull);
  expect(raw.image!.width, size * density);
  expect(raw.image!.height, size * density);
  expect(raw.scale, density);
}

Future<void> _save(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File('../../artifacts/ui-icons/$name.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
