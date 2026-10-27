import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as bitmap;
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/image_histogram.dart';
import 'package:shen_view/src/application/image_resource_service.dart';
import 'package:shen_view/src/application/image_source.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/histogram_sample.dart';
import 'package:shen_view/src/presentation/image_histogram_section.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';
import 'package:shen_view/src/presentation/zoomable_viewport.dart';

import 'support/style_review_fonts.dart';

const _capture = ValueKey('histogram.capture');

void main() {
  test('histogram preserves black/white endpoints, luma and alpha weights', () {
    final data = ImageHistogram.fromRgba(
      Uint8List.fromList([
        0,
        0,
        0,
        255,
        255,
        255,
        255,
        255,
        255,
        0,
        0,
        128,
        0,
        255,
        0,
        255,
        0,
        0,
        255,
        255,
        123,
        45,
        67,
        0,
      ]),
    );
    expect(data.samples, 5);
    expect(data.luminance[0], 255);
    expect(data.luminance[255], 255);
    expect(data.luminance[54], 128);
    expect(data.luminance[182], 255);
    expect(data.luminance[18], 255);
    expect(data.red[123], 0);
    expect(data.red[255], 383);
    for (final channel in [data.luminance, data.red, data.green, data.blue]) {
      expect(channel.length, 256);
      expect(channel.reduce((a, b) => a + b), 1148);
    }
    expect(ImageHistogram.fromRgba(Uint8List(4)).samples, 0);
  });

  testWidgets('sampling bounds raster size and reads animation first frame', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('histogram-sample-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final resources = ImageResourceService();
    addTearDown(resources.dispose);
    final still = bitmap.Image(width: 1024, height: 512)
      ..clear(bitmap.ColorRgb8(255, 0, 0));
    final png = File('${directory.path}/large.png')
      ..writeAsBytesSync(bitmap.encodePng(still));
    final animation = bitmap.Image(width: 2, height: 2)
      ..clear(bitmap.ColorRgb8(255, 0, 0))
      ..frameDuration = 100;
    animation.addFrame(
      bitmap.Image(width: 2, height: 2)
        ..clear(bitmap.ColorRgb8(0, 0, 255))
        ..frameDuration = 100,
    );
    final gif = File('${directory.path}/animated.gif')
      ..writeAsBytesSync(bitmap.encodeGif(animation));
    for (final (file, format, samples) in [
      (png, ImageFormat.png, 512 * 256),
      (gif, ImageFormat.gif, 4),
    ]) {
      final data = await tester.runAsync(
        () => readImageHistogram(
          resources,
          _entry(file, format),
          DecodeRequest(),
        ),
      );
      expect(data!.samples, samples);
      final first = bitmap.decodeImage(file.readAsBytesSync())!.getPixel(0, 0);
      expect(data.red[first.r.toInt()], samples * 255);
      expect(data.blue[first.b.toInt()], samples * 255);
    }
  });

  testWidgets('SVG sampling releases its archive source lease', (tester) async {
    final resources = ImageResourceService();
    addTearDown(resources.dispose);
    final dir = Directory.systemTemp.createTempSync('histogram-svg-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/sample.svg')
      ..writeAsStringSync(
        '<svg xmlns="http://www.w3.org/2000/svg" width="2" height="2">'
        '<rect width="2" height="2" fill="#00ff00"/></svg>',
      );
    var released = false;
    final source = _DeferredSource();
    final entry = ImageEntry.fromSource(
      source: source,
      format: ImageFormat.svg,
      byteLength: file.lengthSync(),
      modifiedAt: DateTime(2026),
    );
    source.ready.complete(
      SourceFileLease(
        file,
        onRelease: () async {
          released = true;
        },
      ),
    );
    final data = await tester.runAsync(
      () => readImageHistogram(resources, entry, DecodeRequest()),
    );
    expect(data!.green[255], 4 * 255);
    expect(data.luminance[182], 4 * 255);
    expect(released, isTrue);
  });

  testWidgets(
    'replacing an unfinished image cannot publish its old histogram',
    (tester) async {
      final resources = ImageResourceService();
      addTearDown(resources.dispose);
      final source = _DeferredSource();
      final entry = ImageEntry.fromSource(
        source: source,
        format: ImageFormat.svg,
        byteLength: 0,
        modifiedAt: DateTime(2026),
      );
      Widget host(ImageEntry value) =>
          _app(ImageHistogramSection(entry: value, resources: resources));
      await tester.pumpWidget(host(entry));
      expect(find.text('正在计算直方图…'), findsOneWidget);
      final current = _entry(
        File('testdata/formats/format_static.png'),
        ImageFormat.png,
      );
      await tester.pumpWidget(host(current));
      await _wait(
        tester,
        () =>
            find.byKey(const ValueKey('histogram.chart')).evaluate().isNotEmpty,
      );
      final before = _painter(tester).data;
      var released = false;
      source.ready.complete(
        SourceFileLease(
          File('testdata/formats/format_static.svg'),
          onRelease: () async {
            released = true;
          },
        ),
      );
      await _wait(tester, () => released);
      expect(identical(_painter(tester).data, before), isTrue);
      await tester.tap(find.text('RGB'));
      await tester.pumpAndSettle();
      expect(_painter(tester).rgb, isTrue);
      expect(find.text('R'), findsOneWidget);
      expect(find.text('G'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed samples can retry and same-path edits refresh the chart',
    (tester) async {
      final resources = ImageResourceService();
      addTearDown(resources.dispose);
      final dir = Directory.systemTemp.createTempSync('histogram-retry-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/editable.svg')
        ..writeAsStringSync('invalid svg');
      Widget host() => _app(
        ImageHistogramSection(
          entry: _entry(file, ImageFormat.svg),
          resources: resources,
        ),
      );
      await tester.pumpWidget(host());
      await _wait(tester, () => find.text('暂时无法生成直方图').evaluate().isNotEmpty);
      void write(String color) => file.writeAsStringSync(
        '<svg xmlns="http://www.w3.org/2000/svg" width="2" height="2">'
        '<rect width="2" height="2" fill="$color"/></svg>',
      );
      write('#ff0000');
      await tester.tap(find.text('重试'));
      await _wait(
        tester,
        () =>
            find.byKey(const ValueKey('histogram.chart')).evaluate().isNotEmpty,
      );
      expect(_painter(tester).data.red[255], 1020);
      write('#00ff00');
      file.setLastModifiedSync(DateTime(2026, 10, 22));
      await tester.pumpWidget(host());
      await _wait(tester, () {
        final chart = find.byKey(const ValueKey('histogram.chart'));
        return chart.evaluate().isNotEmpty &&
            _painter(tester).data.green[255] == 1020;
      });
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'information panel histogram renders and follows navigation ($dark)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1100, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('window_manager'), (
              call,
            ) async {
              if ([
                'isFullScreen',
                'isMaximized',
                'isAlwaysOnTop',
              ].contains(call.method)) {
                return false;
              }
              return null;
            });
        final dir = Directory.systemTemp.createTempSync('histogram-viewer-');
        addTearDown(() => tester.runAsync(() => _removeFixture(dir)));
        for (final name in ['format_static.png', 'format_static.jpg']) {
          File('testdata/formats/$name').copySync('${dir.path}/$name');
        }
        await _fonts(tester);
        await tester.pumpWidget(
          RepaintBoundary(
            key: _capture,
            child: _app(
              ViewerPage(
                initialSettings: const ViewerSettings(
                  showDirectoryPanel: false,
                ),
                initialPath: '${dir.path}/format_static.png',
                configStore: AppConfigStore(
                  filePath: '${dir.path}/settings.json',
                ),
              ),
              dark: dark,
            ),
          ),
        );
        await _wait(
          tester,
          () => find.byTooltip('显示信息 · I').evaluate().isNotEmpty,
        );
        await tester.tap(find.byTooltip('显示信息 · I'));
        await _wait(
          tester,
          () => find
              .byKey(const ValueKey('histogram.chart'))
              .evaluate()
              .isNotEmpty,
        );
        final before = _painter(tester).data;
        await tester.ensureVisible(find.text('直方图'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('基于 SDR 预览采样'));
        await tester.pumpAndSettle();
        await _save(tester, dark ? 'dark-luminance' : 'light-luminance');
        await tester.tap(find.text('RGB'));
        await tester.pumpAndSettle();
        expect(_painter(tester).rgb, isTrue);
        await tester.ensureVisible(find.text('基于 SDR 预览采样'));
        await tester.pumpAndSettle();
        await _wait(
          tester,
          () => tester
              .widgetList<RawImage>(
                find.descendant(
                  of: find.byType(ZoomableViewport),
                  matching: find.byType(RawImage),
                ),
              )
              .any((image) => image.image != null),
        );
        await _save(tester, dark ? 'dark' : 'light');
        await tester.tapAt(const Offset(300, 300));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await _wait(tester, () {
          final chart = find.byKey(const ValueKey('histogram.chart'));
          return chart.evaluate().isNotEmpty &&
              !identical(_painter(tester).data, before);
        });
        tester.view.physicalSize = const Size(620, 760);
        await tester.pump();
        await _wait(
          tester,
          () => find
              .byKey(const ValueKey('histogram.chart'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.ensureVisible(find.text('基于 SDR 预览采样'));
        await tester.pumpAndSettle();
        await _save(tester, dark ? 'dark-narrow' : 'light-narrow');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 300));
      },
    );
  }
}

ImageEntry _entry(File file, ImageFormat format) {
  final stat = file.statSync();
  return ImageEntry(
    file: file,
    format: format,
    width: null,
    height: null,
    byteLength: stat.size,
    modifiedAt: stat.modified,
  );
}

Widget _app(Widget child, {bool dark = false}) {
  final theme = dark ? AppTheme.dark() : AppTheme.light();
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: Platform.environment['HISTOGRAM_CAPTURE_DIR'] == null
        ? theme
        : theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'HistogramReview'),
          ),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: child is ViewerPage ? null : 280, child: child),
      ),
    ),
  );
}

HistogramPainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(find.byKey(const ValueKey('histogram.chart')))
            .painter!
        as HistogramPainter;

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 180; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    if (ready()) return;
  }
  expect(ready(), isTrue);
}

Future<void> _fonts(WidgetTester tester) async {
  if (Platform.environment['HISTOGRAM_CAPTURE_DIR'] == null) return;
  await tester.runAsync(() async {
    for (final (family, path) in [
      ('HistogramReview', windowsFontPath('msyh.ttc')),
      (
        'packages/fluentui_system_icons/FluentSystemIcons-Regular',
        'packages/fluentui_system_icons/fonts/FluentSystemIcons-Regular.ttf',
      ),
    ]) {
      await (FontLoader(family)..addFont(loadReviewFontData(path))).load();
    }
  });
}

Future<void> _save(WidgetTester tester, String name) async {
  final dir = Platform.environment['HISTOGRAM_CAPTURE_DIR'];
  if (dir == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$dir/histogram-$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _removeFixture(Directory directory) async {
  // Windows decoding and config writes can briefly outlive widget disposal.
  for (var attempt = 0; attempt < 40; attempt++) {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 39) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

class _DeferredSource implements ImageSource {
  final ready = Completer<SourceFileLease>();
  @override
  String get id => 'archive://histogram/pending.svg';
  @override
  String get name => 'pending.svg';
  @override
  String get relativePath => name;
  @override
  bool get sensitive => false;
  @override
  Future<SourceFileLease> acquireFile({DecodeRequest? request}) => ready.future;
}
