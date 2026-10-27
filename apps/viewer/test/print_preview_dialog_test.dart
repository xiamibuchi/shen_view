import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';
import 'package:shen_view/src/presentation/print_preview_dialog.dart';
import 'package:shen_view/src/presentation/components/app_button.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'support/style_review_fonts.dart';

void main() {
  testWidgets('printing shows busy feedback and does not submit a second job', (
    tester,
  ) async {
    final completion = Completer<void>();
    final platform = _PrintingStub(tester, printCompletion: completion.future)
      ..install();
    await _show(tester);
    await _waitForPreview(tester);
    final submit = find.byKey(const ValueKey('print.submit'));
    await tester.tap(submit);
    await tester.pump();
    expect(tester.widget<AppButton>(submit).busy, isTrue);
    await tester.tap(submit);
    await tester.pump();
    expect(platform.printCalls, 1);
    completion.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<AppButton>(submit).busy, isFalse);
    expect(platform.printCalls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shared print controls preserve printer and PDF settings', (
    tester,
  ) async {
    final platform = _PrintingStub(tester)..install();
    await _show(tester);
    await _waitForPreview(tester);
    expect(find.text('离线打印机'), findsNothing);

    await _select(tester, 'orientation', '横向');
    await _select(tester, 'paper', 'A5');
    await _select(tester, 'margins', '自定义');
    final marginField = find.byKey(const ValueKey('print.customMargin'));
    for (final invalid in ['', '51']) {
      await tester.enterText(marginField, invalid);
      await tester.pump();
      expect(find.text('请输入 0 到 50 之间的数字。'), findsOneWidget);
      expect(
        tester
            .widget<AppButton>(find.byKey(const ValueKey('print.submit')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<PdfPreview>(find.byType(PdfPreview))
            .initialPageFormat!
            .marginLeft,
        20 * PdfPageFormat.mm,
      );
    }
    await tester.enterText(
      find.byKey(const ValueKey('print.customMargin')),
      '12,5',
    );
    await tester.pump();
    await _select(tester, 'fit', '填充页面');
    await _select(tester, 'printer', '照片打印机');
    await _waitForPreview(tester);

    final format = tester
        .widget<PdfPreview>(find.byType(PdfPreview))
        .initialPageFormat!;
    expect(format.width, PdfPageFormat.a5.landscape.width);
    expect(format.height, PdfPageFormat.a5.landscape.height);
    expect(format.marginLeft, closeTo(12.5 * PdfPageFormat.mm, 0.001));
    expect(format.marginRight, format.marginLeft);
    expect(format.marginTop, format.marginLeft);
    expect(format.marginBottom, format.marginLeft);
    expect(platform.previewDocument, isNotEmpty);
    expect(String.fromCharCodes(platform.previewDocument!.take(4)), '%PDF');

    // Selecting the current option must leave the existing preview mounted.
    final previewState = tester.state(find.byType(PdfPreview));
    final rasters = platform.rasterRequests;
    await _select(tester, 'paper', 'A5');
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.state(find.byType(PdfPreview)), same(previewState));
    expect(platform.rasterRequests, rasters);

    await tester.ensureVisible(find.byKey(const ValueKey('print.submit')));
    await tester.tap(find.byKey(const ValueKey('print.submit')));
    await tester.pumpAndSettle();
    expect(platform.printArguments!['printer'], 'photo');
    expect(platform.printArguments!['width'], format.width);
    expect(platform.printArguments!['height'], format.height);
    expect(platform.printArguments!['marginLeft'], format.marginLeft);
    expect(platform.printArguments!['dynamic'], isFalse);
    expect(find.byType(PrintPreviewDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'printer loading, empty lists and errors retain system printing',
    (tester) async {
      for (final fail in [false, true]) {
        final printers = Completer<List<Map<String, Object?>>>();
        final platform = _PrintingStub(tester, printers: printers.future)
          ..install();
        await _show(tester);
        await tester.pump();
        expect(find.text('正在读取打印机…'), findsOneWidget);
        if (fail) {
          printers.completeError(PlatformException(code: 'unavailable'));
        } else {
          printers.complete([]);
        }
        await _waitForPreview(tester);
        expect(find.text(fail ? '打印机列表不可用' : '默认打印机'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('print.submit')));
        await tester.pumpAndSettle();
        expect(platform.printArguments!.containsKey('printer'), isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets('print preview fits both themes and a short window', (
    tester,
  ) async {
    _PrintingStub(tester).install();
    final capture = Platform.environment['PRINT_PREVIEW_CAPTURE_DIR'];
    if (capture != null) await _loadReviewFonts(tester);
    for (final dark in [true, false]) {
      for (final (size, locale, scale) in [
        (const Size(1200, 900), 'zh', 1.0),
        (const Size(800, 600), 'zh', 1.0),
        (const Size(560, 640), 'zh', 1.5),
        (const Size(440, 640), 'en', 1.5),
        (const Size(440, 500), 'en', 2.0),
      ]) {
        await _show(
          tester,
          dark: dark,
          size: size,
          reviewFont: capture != null,
          locale: locale,
          scale: scale,
        );
        await _waitForPreview(tester);
        await _select(tester, 'margins', locale == 'zh' ? '自定义' : 'Custom');
        await _waitForPreview(tester);
        final submit = find.byKey(const ValueKey('print.submit'));
        final actions = tester.getRect(
          find.byKey(const ValueKey('print.actions')),
        );
        expect(submit.hitTestable(), findsOneWidget);
        final settings = find.byKey(const ValueKey('print.settingsScroll'));
        final preview = tester.getRect(find.byType(PdfPreview));
        final settingsRect = tester.getRect(settings);
        if (size.width < 768) {
          expect(settingsRect.top, greaterThanOrEqualTo(preview.bottom));
          expect(settingsRect.width, greaterThan(300));
        } else {
          expect(settingsRect.left, greaterThan(preview.right));
          expect(settingsRect.top, preview.top);
          expect(settingsRect.bottom, preview.bottom);
        }
        final close = tester.getRect(
          find.byTooltip(locale == 'zh' ? '关闭' : 'Close'),
        );
        expect(close.right, greaterThan(size.width - 80));
        await tester.ensureVisible(find.byKey(const ValueKey('print.fit')));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const ValueKey('print.actions'))),
          actions,
        );
        expect(submit.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (capture != null) {
          final themeName = dark ? 'dark' : 'light';
          final suffix = '$themeName-${size.width.toInt()}-$locale-$scale.png';
          await _capture(tester, '$capture/print-$suffix');
          await tester.ensureVisible(
            find.byKey(const ValueKey('print.orientation')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('print.orientation')));
          await tester.pumpAndSettle();
          expect(find.byType(MenuItemButton), findsNWidgets(2));
          await _capture(tester, '$capture/print-menu-$suffix');
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        }
        final field = find.byKey(const ValueKey('print.customMargin'));
        await tester.ensureVisible(field);
        await tester.enterText(field, '51');
        await tester.pumpAndSettle();
        expect(tester.widget<AppButton>(submit).onPressed, isNull);
        if (capture != null) {
          await _capture(
            tester,
            '$capture/print-error-${dark ? 'dark' : 'light'}-${size.width.toInt()}-$locale-$scale.png',
          );
        }
        await tester.pumpWidget(const SizedBox());
      }
    }
  });
}

Future<void> _show(
  WidgetTester tester, {
  bool dark = true,
  Size size = const Size(1200, 900),
  bool reviewFont = false,
  String locale = 'zh',
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final theme = dark ? AppTheme.dark() : AppTheme.light();
  final image = img.Image(width: 120, height: 180);
  img.fill(image, color: img.ColorRgb8(62, 116, 130));
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('print.capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: reviewFont
            ? theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'PrintReview'),
              )
            : theme,
        locale: Locale(locale),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PrintPreviewDialog(
            entry: ImageEntry(
              file: File('预览示例.png'),
              format: ImageFormat.png,
              width: image.width,
              height: image.height,
              byteLength: 100,
              modifiedAt: DateTime(2026, 10, 20),
            ),
            imageBytes: Uint8List.fromList(img.encodePng(image)),
          ),
        ),
      ),
    ),
  );
}

Future<void> _select(WidgetTester tester, String key, String label) async {
  final control = find.byKey(ValueKey('print.$key'));
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(find.widgetWithText(MenuItemButton, label));
  await tester.pump();
  await _waitForPreview(tester);
}

Future<void> _waitForPreview(WidgetTester tester) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    if (find.byType(Image).evaluate().isNotEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('The print preview did not produce a page');
}

Future<void> _loadReviewFonts(WidgetTester tester) => tester.runAsync(() async {
  final fonts = FontLoader('PrintReview')
    ..addFont(
      File(windowsFontPath('msyh.ttc'))
          .readAsBytes()
          .then(ByteData.sublistView),
    );
  await fonts.load();
  final icons =
      FontLoader(
        'packages/fluentui_system_icons/FluentSystemIcons-Regular',
      )..addFont(
        rootBundle.load(
          'packages/fluentui_system_icons/fonts/FluentSystemIcons-Regular.ttf',
        ),
      );
  await icons.load();
});

Future<void> _capture(WidgetTester tester, String path) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('print.capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

/// Native calls are stubbed: these tests never enumerate or use real printers.
class _PrintingStub {
  _PrintingStub(this.tester, {this.printers, this.printCompletion});

  final WidgetTester tester;
  final Future<List<Map<String, Object?>>>? printers;
  final Future<void>? printCompletion;
  int printCalls = 0;
  Map<Object?, Object?>? printArguments;
  Uint8List? previewDocument;
  int rasterRequests = 0;
  static const _channel = MethodChannel('net.nfet.printing');

  void install() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
      call,
    ) async {
      switch (call.method) {
        case 'printingInfo':
          return {'canRaster': true, 'canPrint': true, 'directPrint': true};
        case 'listPrinters':
          return printers ??
              Future.value([
                const Printer(
                  url: 'default',
                  name: '默认打印机',
                  isDefault: true,
                ).toMap(),
                const Printer(url: 'photo', name: '照片打印机').toMap(),
                const Printer(
                  url: 'offline',
                  name: '离线打印机',
                  isAvailable: false,
                ).toMap(),
              ]);
        case 'rasterPdf':
          final args = call.arguments as Map<Object?, Object?>;
          previewDocument = args['doc']! as Uint8List;
          rasterRequests++;
          // A deterministic A4-sized raster isolates the preview layout from
          // the system PDF renderer while exercising real PDF generation.
          final pixels = Uint8List(210 * 297 * 4);
          for (var y = 0; y < 297; y++) {
            for (var x = 0; x < 210; x++) {
              final inside = x >= 25 && x < 185 && y >= 28 && y < 269;
              final offset = (y * 210 + x) * 4;
              pixels[offset] = inside ? 62 : 255;
              pixels[offset + 1] = inside ? 116 : 255;
              pixels[offset + 2] = inside ? 130 : 255;
              pixels[offset + 3] = 255;
            }
          }
          _send('onPageRasterized', {
            'job': args['job'],
            'width': 210,
            'height': 297,
            'image': pixels,
          });
          _send('onPageRasterEnd', {'job': args['job']});
          return null;
        case 'printPdf':
          printCalls++;
          printArguments = call.arguments as Map<Object?, Object?>;
          if (printCompletion != null) await printCompletion;
          _send('onCompleted', {
            'job': printArguments!['job'],
            'completed': false,
          });
          return 1;
      }
      throw UnsupportedError(call.method);
    });
  }

  void _send(String method, Map<String, Object?> arguments) {
    unawaited(
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        _channel.name,
        _channel.codec.encodeMethodCall(MethodCall(method, arguments)),
        null,
      ),
    );
  }
}
