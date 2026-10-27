import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/presentation/components/app_backdrop_surface.dart';
import 'package:shen_view/src/presentation/directory_panel_region.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

import 'support/style_review_fonts.dart';

const _capture = ValueKey('material.capture');

void main() {
  if (Platform.environment['MATERIAL_CAPTURE_DIR'] != null) {
    StyleReviewBinding();
  }
  for (final dark in [true, false]) {
    testWidgets(
      'frosted regions retain sharp controls and light-dismiss dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(600, 320);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        if (Platform.environment['MATERIAL_CAPTURE_DIR'] != null) {
          await loadStyleReviewFonts(tester);
        }
        final prefix = dark ? 'dark' : 'light';
        var dismissals = 0;
        var canvasTaps = 0;
        Widget scene({bool docked = false, bool highContrast = false}) =>
            MaterialApp(
              theme: dark
                  ? AppTheme.dark(platform: TargetPlatform.windows)
                  : AppTheme.light(platform: TargetPlatform.windows),
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(600, 320),
                  highContrast: highContrast,
                ),
                child: RepaintBoundary(
                  key: _capture,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ColoredBox(
                              color: Colors.red,
                              child: const SizedBox.expand(),
                            ),
                          ),
                          Expanded(
                            child: ColoredBox(
                              color: Colors.blue,
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ],
                      ),
                      Positioned.fill(
                        child: DirectoryPanelRegion(
                          availableWidth: 600,
                          minimumContentWidth: 220,
                          preferredWidth: 240,
                          docked: docked,
                          visible: true,
                          overlayTopInset: 44,
                          panel: const Material(
                            type: MaterialType.transparency,
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: Text('浏览目录'),
                              ),
                            ),
                          ),
                          onClose: () => dismissals++,
                          onWidthChanged: (_) {},
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => canvasTaps++,
                          ),
                        ),
                      ),
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 44,
                        child: AppBackdropSurface(
                          child: Material(
                            type: MaterialType.transparency,
                            child: Center(child: Text('神羊看图')),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
        await tester.pumpWidget(scene());
        await tester.pumpAndSettle();
        final image = await _pixels(tester, '$prefix-frosted');
        Color pixel(int x, int y) => image.$2(x, y);
        expect(
          pixel(500, 200).toARGB32(),
          Colors.blue.toARGB32(),
          reason: 'no whole-canvas dimming',
        );
        expect(pixel(20, 20), isNot(Colors.red));
        expect(
          (pixel(20, 10).r - pixel(260, 10).r).abs(),
          lessThan(0.015),
          reason: 'floating directory does not double-tint the toolbar corner',
        );
        expect(
          pixel(20, 120),
          isNot(pixel(20, 20)),
          reason: 'directory is denser',
        );
        expect(
          // Sample below the title so localized glyphs do not affect the probe.
          pixel(298, 38).b,
          greaterThan(pixel(20, 20).b),
          reason: 'blur samples nearby blue',
        );
        final tokens = ViewerThemeTokens.of(
          tester.element(find.byType(AppBackdropSurface).first),
        );
        expect(
          _contrast(tokens.textPrimary, pixel(20, 120)),
          greaterThanOrEqualTo(4.5),
        );
        await tester.tapAt(const Offset(500, 200));
        expect(dismissals, 1);
        expect(
          canvasTaps,
          0,
          reason: 'outside click dismisses without operating canvas',
        );
        await tester.pumpWidget(scene(docked: true));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('directory.barrier')), findsNothing);
        final docked = await _pixels(tester, '$prefix-docked');
        expect(docked.$2(20, 120), tokens.navigationSurface);
        await tester.pumpWidget(scene(highContrast: true));
        await tester.pumpAndSettle();
        expect(find.byType(BackdropFilter), findsNothing);
        final solid = await _pixels(tester, '$prefix-solid');
        expect(solid.$2(20, 120), tokens.navigationOverlay);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'native transparency and power policy updates existing surfaces',
    (tester) async {
      var enabled = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AppMaterialEffects.channel,
        (call) async => enabled,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          AppMaterialEffects.channel,
          null,
        ),
      );
      await tester.pumpWidget(
        AppMaterialEffects(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const AppBackdropSurface(child: Text('Toolbar')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      enabled = true;
      const codec = StandardMethodCodec();
      tester.binding.channelBuffers.push(
        AppMaterialEffects.channel.name,
        codec.encodeMethodCall(const MethodCall('changed')),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);
      enabled = false;
      tester.binding.channelBuffers.push(
        AppMaterialEffects.channel.name,
        codec.encodeMethodCall(const MethodCall('changed')),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + 0.05) / ((x > y ? y : x) + 0.05);
}

Future<(Size, Color Function(int, int))> _pixels(
  WidgetTester tester,
  String name,
) async => (await tester.runAsync(() async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  final image = await boundary.toImage();
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final width = image.width;
  final directory = Platform.environment['MATERIAL_CAPTURE_DIR'];
  if (directory != null) {
    final file = File('$directory/$name.png');
    await file.parent.create(recursive: true);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await file.writeAsBytes(png.buffer.asUint8List());
  }
  final size = Size(image.width.toDouble(), image.height.toDouble());
  image.dispose();
  return (
    size,
    (int x, int y) {
      final index = (y * width + x) * 4;
      return Color.fromARGB(
        bytes.getUint8(index + 3),
        bytes.getUint8(index),
        bytes.getUint8(index + 1),
        bytes.getUint8(index + 2),
      );
    },
  );
}))!;
