import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/color_picker_controller.dart';
import 'package:shen_view/src/application/color_picker_service.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/domain/image_resource_key.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/color_picker_overlay.dart';
import 'package:shen_view/src/presentation/color_picker_target.dart';
import 'package:shen_view/src/presentation/components/app_select.dart';
import 'package:shen_view/src/presentation/svg_image.dart';
import 'package:shen_view/src/application/svg_resources.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

void main() {
  testWidgets(
    'SVG sampling reads native pixels and keeps the image visible on exit',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('color-picker-svg-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/color.svg')
        ..writeAsStringSync(
          '<svg xmlns="http://www.w3.org/2000/svg" width="80" height="60"><style>:root { --sample: #2563eb; }</style><rect width="80" height="60" fill="var(--sample)"/></svg>',
        );
      final controller = ColorPickerController()..setActive(true);
      await tester.runAsync(() async {
        final source = await SvgResources.shared.read(file);
        await SvgResources.shared.raster(source, 80, thumbnail: true);
        await SvgResources.shared.raster(source, 256, thumbnail: true);
        await SvgResources.shared.raster(source, 512, thumbnail: true);
      });
      addTearDown(controller.dispose);
      Widget app() => MaterialApp(
        home: ColorPickerScope(
          controller: controller,
          active: controller.active,
          child: Center(
            child: SizedBox(
              width: 160,
              height: 120,
              child: ColorPickerTarget(
                id: file.path,
                name: 'color.svg',
                sourceSize: const Size(80, 60),
                kind: ColorSampleKind.svg,
                child: SvgImage(file: file),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await _wait(
        tester,
        () => find
            .byType(RawImage)
            .evaluate()
            .any((element) => (element.widget as RawImage).image != null),
      );
      await tester.tap(find.byType(RawImage));
      await _wait(tester, () => controller.selected != null);
      expect(controller.selected!.color.hex, '#2563EB');
      expect(controller.selected!.kind, ColorSampleKind.svg);
      expect(controller.selected!.previewOnly, isFalse);
      controller.setActive(false);
      await tester.pumpWidget(app());
      await tester.pump();
      await _wait(
        tester,
        () => find
            .byType(RawImage)
            .evaluate()
            .any((element) => (element.widget as RawImage).image != null),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  test('copy formats preserve alpha and handle achromatic colors', () {
    const red = PickedColor(red: 255, green: 0, blue: 0, alpha: 128);
    expect(red.hex, '#FF0000');
    expect(red.hexAlpha, '#FF000080');
    expect(red.format(ColorCopyFormat.rgb), 'rgb(255, 0, 0)');
    expect(red.format(ColorCopyFormat.rgba), 'rgba(255, 0, 0, 0.502)');
    expect(red.format(ColorCopyFormat.hsl), 'hsl(0, 100%, 50%)');
    expect(red.format(ColorCopyFormat.hsla), 'hsla(0, 100%, 50%, 0.502)');
    expect(red.format(ColorCopyFormat.hsv), 'hsv(0, 100%, 100%)');
    expect(red.format(ColorCopyFormat.yuv), 'yuv(0.299, -0.1471, 0.6148)');
    const black = PickedColor(red: 0, green: 0, blue: 0, alpha: 255);
    expect(black.format(ColorCopyFormat.hsl), 'hsl(0, 0%, 0%)');
    expect(black.format(ColorCopyFormat.hsv), 'hsv(0, 0%, 0%)');
    expect(black.format(ColorCopyFormat.yuv), 'yuv(0, 0, 0)');
    const white = PickedColor(red: 255, green: 255, blue: 255, alpha: 255);
    expect(white.format(ColorCopyFormat.yuv), 'yuv(1, 0, 0)');
    expect(
      const PickedColor(
        red: 0,
        green: 0,
        blue: 255,
        alpha: 0,
      ).format(ColorCopyFormat.hsl),
      'hsl(240, 100%, 50%)',
    );
  });

  test('copy format persists without disturbing unrelated settings', () async {
    final directory = Directory.systemTemp.createTempSync('color-format-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = AppConfigStore(filePath: '${directory.path}/config.json');
    const settings = ViewerSettings(
      alwaysOnTop: true,
      colorPickerFormat: ColorCopyFormat.rgba,
    );
    await settings.save(store: store);
    final restored = await ViewerSettings.load(store: store);
    expect(restored.colorPickerFormat, ColorCopyFormat.rgba);
    expect(restored.alwaysOnTop, isTrue);
    expect(
      restored.copyWith(showBottomBar: false).colorPickerFormat,
      ColorCopyFormat.rgba,
    );
    expect(
      restored,
      isNot(restored.copyWith(colorPickerFormat: ColorCopyFormat.hex)),
    );
    await store.write({
      'settings': {'colorPickerFormat': 'invalid'},
    });
    expect(
      (await ViewerSettings.load(store: store)).colorPickerFormat,
      ColorCopyFormat.hex,
    );
    for (final format in ColorCopyFormat.values) {
      await settings.copyWith(colorPickerFormat: format).save(store: store);
      expect(
        (await ViewerSettings.load(store: store)).colorPickerFormat,
        format,
      );
    }
  });

  testWidgets(
    'decoded-frame sampling preserves alpha, edges and pixel values',
    (tester) async {
      final image = (await tester.runAsync(_image))!;
      addTearDown(image.dispose);
      final service = ColorPickerService();
      await tester.runAsync(() async {
        final red = await service.capture(image, 0, 0);
        expect(red!.color.hexAlpha, '#FF0000FF');
        expect(red.pixels.first, isNull);
        final alpha = await service.capture(image, 2, 0);
        expect(alpha!.color.alpha, 128);
        expect(alpha.color.green, greaterThanOrEqualTo(254));
        expect(alpha.color.red, 0);
        expect(await service.capture(image, -1, 0), isNull);
        expect(await service.capture(image, 3, 0), isNull);
      });
    },
  );

  for (final transformed in [false, true]) {
    testWidgets(
      'target inverts fit/rotation/flip and maps tile coordinates ($transformed)',
      (tester) async {
        final image = (await tester.runAsync(_image))!;
        final c = ColorPickerController()..setActive(true);
        addTearDown(c.dispose);
        addTearDown(image.dispose);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        Widget target = ColorPickerTarget(
          id: 'tile',
          name: 'tile.png',
          region: const ImageRegion(left: 100, top: 200, width: 30, height: 20),
          child: SizedBox(
            width: 300,
            height: 240,
            child: RawImage(image: image, fit: BoxFit.contain),
          ),
        );
        if (transformed) {
          target = RotatedBox(
            quarterTurns: 1,
            child: Transform.flip(flipX: true, child: target),
          );
        }
        await tester.pumpWidget(
          MaterialApp(
            home: ColorPickerScope(
              controller: c,
              active: true,
              child: Center(child: target),
            ),
          ),
        );
        final render = tester.renderObject<RenderImage>(find.byType(RawImage));
        final fitted = applyBoxFit(
          BoxFit.contain,
          const Size(3, 2),
          render.size,
        );
        final destination = Alignment.center.inscribe(
          fitted.destination,
          Offset.zero & render.size,
        );
        final point = render.localToGlobal(
          destination.topLeft +
              Offset(destination.width * 0.5, destination.height * 0.25),
        );
        await mouse.moveTo(point);
        await tester.tapAt(point);
        await _wait(tester, () => c.selected != null);
        expect(c.selected!.color.hex, '#0000FF');
        expect((c.selected!.x, c.selected!.y), (110, 200));
        expect(c.selected!.previewOnly, isTrue);
        c.nudge(1, 0);
        await _wait(tester, () => c.selected?.x == 120);
        expect(c.selected!.color.alpha, 128);
        // Moving off the image clears the live preview, not the locked result.
        await mouse.moveTo(const Offset(1, 1));
        await tester.pump();
        expect(c.hover, isNull);
        expect(c.selected!.x, 120);
        c.resetImage();
        final blank = render.localToGlobal(const Offset(10, 1));
        await tester.tapAt(blank);
        await tester.pump();
        expect(c.selected, isNull);
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('leaving or changing image discards an in-flight sample', (
    tester,
  ) async {
    final image = (await tester.runAsync(_image))!;
    addTearDown(image.dispose);
    final c = ColorPickerController()..setActive(true);
    addTearDown(c.dispose);
    final request = ColorPickerRequest(
      image: image,
      pixel: Offset.zero,
      sourcePixel: Offset.zero,
      id: 'old',
      name: 'old.png',
      kind: ColorSampleKind.srgb,
      previewOnly: false,
      nudge: (_, _) {},
    );
    final pending = c.lock(request);
    c.resetImage();
    await tester.runAsync(() => pending);
    expect(c.selected, isNull);
    final exiting = c.lock(request);
    c.setActive(false);
    await tester.runAsync(() => exiting);
    expect(c.selected, isNull);
    expect(c.recent, isEmpty);
  });

  for (final size in [const Size(900, 640), const Size(260, 200)]) {
    testWidgets('result card copies and fits constrained canvas $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = ColorPickerController()..setActive(true);
      addTearDown(c.dispose);
      const color = PickedColor(red: 23, green: 120, blue: 240, alpha: 128);
      c.selected = ColorPick(
        patch: ColorSamplePatch(List.filled(81, color)),
        id: 'a',
        name: '透明图.png',
        x: 12,
        y: 34,
        kind: ColorSampleKind.sdrMapped,
        previewOnly: true,
      );
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied =
                  (call.arguments as Map<Object?, Object?>)['text'] as String?;
            }
            return null;
          });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          locale: const Locale('zh'),
          home: Scaffold(
            body: ColorPickerOverlay(
              controller: c,
              onClose: () {},
              onFormatChanged: (_) {},
            ),
          ),
        ),
      );
      expect(find.textContaining('SDR'), findsOneWidget);
      expect(find.text('透明图.png'), findsNothing);
      expect(find.text('More formats'), findsNothing);
      expect(find.textContaining('Click to lock'), findsNothing);
      final select = tester.widget<AppSelect<ColorCopyFormat>>(
        find.byKey(const ValueKey('colorPicker.format')),
      );
      expect(select.options.map((option) => option.label), [
        'HEX',
        'RGB',
        'RGBA',
        'HSL',
        'HSLA',
        'HSV',
        'YUV',
      ]);
      expect(tester.takeException(), isNull);
      if (size.width > 500) {
        final initialCard = tester.getRect(
          find.byKey(const ValueKey('colorPicker.card')),
        );
        final initialValue = tester.getRect(
          find.byKey(const ValueKey('colorPicker.value')),
        );
        for (final format in ColorCopyFormat.values) {
          c.setFormat(format);
          await tester.pump();
          expect(
            tester.getRect(find.byKey(const ValueKey('colorPicker.card'))),
            initialCard,
          );
          expect(
            tester
                .getRect(find.byKey(const ValueKey('colorPicker.value')))
                .topLeft,
            initialValue.topLeft,
          );
        }
        c.setFormat(ColorCopyFormat.hex);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('colorPicker.copy')));
        await tester.pump();
        expect(copied, '#1778F0');
        expect(find.text('Copied'), findsOneWidget);
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('Copied'), findsNothing);
        c.setFormat(ColorCopyFormat.hsla);
        await tester.pump();
        for (final format in [
          ColorCopyFormat.hex,
          ColorCopyFormat.rgba,
          ColorCopyFormat.hsl,
        ]) {
          await tester.tap(
            find.byKey(ValueKey('colorPicker.quickCopy.${format.name}')),
          );
          await tester.pump();
          expect(copied, color.format(format));
          expect(c.format, ColorCopyFormat.hsla);
          await tester.pump(const Duration(seconds: 2));
        }
        final helpRect = tester.getRect(
          find.byKey(const ValueKey('colorPicker.help')),
        );
        final titleRect = tester.getRect(find.text('Color picker'));
        expect(helpRect.left - titleRect.right, inInclusiveRange(0, 8));
        await tester.tap(find.byKey(const ValueKey('colorPicker.help')));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.textContaining('Click to lock'), findsOneWidget);
        expect(find.textContaining('one pixel'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

Future<ui.Image> _image() async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(
    Uint8List.fromList([
      255,
      0,
      0,
      255,
      0,
      0,
      255,
      255,
      0,
      255,
      0,
      128,
      255,
      255,
      255,
      255,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      255,
    ]),
  );
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: 3,
    height: 2,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}

Future<void> _wait(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 80; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (condition()) return;
  }
  expect(condition(), isTrue);
}
