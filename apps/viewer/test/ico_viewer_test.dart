import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as paths;
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/archive_service.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/animation_playback_bar.dart';
import 'package:shen_view/src/presentation/color_picker_target.dart';
import 'package:shen_view/src/presentation/components/app_select.dart';
import 'package:shen_view/src/presentation/components/app_file_name_editor.dart';
import 'package:shen_view/src/presentation/ico_variant_field.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';

import 'support/style_review_fonts.dart';

const _capture = ValueKey('ico.capture');
const _select = ValueKey('info.icoVariant');

void main() {
  StyleReviewBinding();

  setUp(() {
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
  });

  for (final archive in [false, true]) {
    testWidgets(
      'ICO panel switches actual sizes, same-size versions and colors; archive=$archive',
      (tester) async {
        await _open(tester, archive: archive);
        expect(find.byType(AnimationPlaybackBar), findsNothing);
        expect(_variant(tester).value, 2);
        expect(_variant(tester).options, hasLength(5));
        expect(
          _variant(tester).options.map((v) => v.label).toSet(),
          hasLength(5),
        );
        expect(find.text('256 × 256'), findsWidgets);
        for (final (index, size, red, green, blue) in [
          (0, 16, 220, 40, 30),
          (3, 32, 240, 170, 20),
          (4, 32, 170, 50, 210),
          (2, 256, 35, 90, 230),
        ]) {
          final previous = _mainImage(tester);
          await tester.tap(find.byKey(_select));
          await tester.pump(const Duration(milliseconds: 150));
          final label = _variant(tester).options
              .singleWhere((v) => v.value == index)
              .label;
          await tester.tap(find.text(label).last);
          await _wait(
            tester,
            () =>
                _mainImage(tester) != previous &&
                _mainImage(tester)?.width == size &&
                _variant(tester).value == index,
          );
          final image = _mainImage(tester)!;
          final bytes = await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
          );
          final at = ((size ~/ 2) * size + size ~/ 2) * 4;
          expect(
            [
              bytes!.getUint8(at),
              bytes.getUint8(at + 1),
              bytes.getUint8(at + 2),
            ],
            [red, green, blue],
          );
          expect(find.text('$size × $size'), findsWidgets);
          final target = tester.widget<ColorPickerTarget>(
            find.byType(ColorPickerTarget).first,
          );
          expect(target.sourceSize, Size(size.toDouble(), size.toDouble()));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets('single ICO version is a text field', (tester) async {
    await _open(tester, name: 'format_single.ico');
    expect(find.byType(IcoVariantField), findsOneWidget);
    expect(find.byKey(_select), findsNothing);
    expect(find.text('图标版本'), findsOneWidget);
    expect(find.text('48 × 48 · 32 bit · PNG'), findsOneWidget);
    await _save(tester, 'single-version.png');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('long name and path fit a narrow panel and copy the full path', (
    tester,
  ) async {
    final path = await _open(
      tester,
      size: const Size(600, 460),
      scale: 1.5,
      displayName: '旅行相册_山间风景与晚霞_Landscape_2026_10_26_多尺寸图标.ico',
    );
    final name = tester.getRect(find.byType(AppFileNameEditor));
    final heading = tester.getRect(find.text('基本信息'));
    expect(heading.top - name.bottom, greaterThanOrEqualTo(24));
    expect(heading.left, name.left);
    expect(tester.takeException(), isNull);
    await _save(tester, 'narrow-long-name.png');
    final copy = find.byKey(const ValueKey('info.copyPath'));
    await tester.ensureVisible(copy);
    await tester.pumpAndSettle();
    final label = find.descendant(
      of: find.byKey(const ValueKey('info.path')),
      matching: find.byWidgetPredicate(
        (widget) => widget is Text && widget.semanticsLabel == path,
      ),
    );
    expect(tester.widget<Text>(label).maxLines, 2);
    expect(tester.widget<Text>(label).overflow, TextOverflow.ellipsis);
    expect(tester.getSize(copy), const Size(32, 32));
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(copy);
    await tester.pump();
    expect(copied, path);
    expect(tester.takeException(), isNull);
    await _save(tester, 'narrow-long-path.png');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('English information panel and menu fit at 150 percent', (
    tester,
  ) async {
    await _open(
      tester,
      locale: const Locale('en'),
      scale: 1.5,
      size: const Size(600, 460),
    );
    final l10n = AppLocalizations.of(
      tester.element(find.byType(IcoVariantField)),
    )!;
    expect(find.text(l10n.basicInformation), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _save(tester, 'english-narrow.png');
    await tester.ensureVisible(find.byKey(_select));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_select));
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.takeException(), isNull);
    await _save(tester, 'english-narrow-menu.png');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.25, 1.5]) {
      testWidgets('ICO panel layout dark=$dark scale=$scale', (tester) async {
        await _open(
          tester,
          dark: dark,
          scale: scale,
          size: const Size(760, 600),
        );
        expect(tester.takeException(), isNull);
        final control = tester.getRect(find.byKey(_select));
        expect(control.left, greaterThanOrEqualTo(0));
        expect(control.right, lessThanOrEqualTo(760));
        expect(control.height, greaterThanOrEqualTo(36));
        final filename = tester.getRect(find.byType(AppFileNameEditor));
        final basic = tester.getRect(find.text('基本信息'));
        expect(basic.left, filename.left);
        expect(control.left, basic.left);
        expect(basic.top - filename.bottom, greaterThanOrEqualTo(24));
        final version = tester.getRect(find.text('图标版本'));
        expect(control.top - version.bottom, closeTo(8, 0.01));
        expect(
          tester
              .getRect(
                find.byTooltip(
                  tester
                      .widget<AppFileNameEditor>(find.byType(AppFileNameEditor))
                      .renameTooltip,
                ),
              )
              .size,
          const Size(32, 32),
        );
        await _save(tester, '${dark ? 'dark' : 'light'}-$scale.png');
        await tester.tap(find.byKey(_select));
        await tester.pump(const Duration(milliseconds: 150));
        expect(tester.takeException(), isNull);
        await _save(tester, '${dark ? 'dark' : 'light'}-$scale-menu.png');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }
}

AppSelect<int> _variant(WidgetTester tester) =>
    tester.widget<AppSelect<int>>(find.byKey(_select));

ui.Image? _mainImage(WidgetTester tester) {
  final images = find.descendant(
    of: find.byType(ColorPickerTarget),
    matching: find.byType(RawImage),
  );
  if (images.evaluate().isEmpty) return null;
  return tester.renderObject<RenderImage>(images.first).image;
}

Future<String> _open(
  WidgetTester tester, {
  bool dark = true,
  double scale = 1,
  Size size = const Size(1200, 840),
  String name = 'format_multisize.ico',
  bool archive = false,
  String? displayName,
  Locale locale = const Locale('zh'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final capture = Platform.environment['ICO_CAPTURE_DIR'];
  if (capture != null) await loadStyleReviewFonts(tester);
  final dir = Directory.systemTemp.createTempSync('ico-viewer-');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // A background source lease can finish releasing after widget disposal.
    }
  });
  var path = File('testdata/formats/$name')
      .copySync('${dir.path}/${displayName ?? name}')
      .path;
  if (archive) {
    final container = Archive()
      ..addFile(
        ArchiveFile(
          'nested/$name',
          File(path).lengthSync(),
          File(path).readAsBytesSync(),
        ),
      );
    path = '${dir.path}/icons.cbz';
    File(path).writeAsBytesSync(ZipEncoder().encode(container));
  }
  await tester.pumpWidget(
    RepaintBoundary(
      key: _capture,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark
            ? AppTheme.dark(platform: TargetPlatform.windows)
            : AppTheme.light(platform: TargetPlatform.windows),
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ViewerPage(
          initialPath: path,
          archiveService: ArchiveService(
            cachePolicy: ArchiveCachePolicy(
              directory: Directory('${dir.path}/cache'),
            ),
          ),
          initialSettings: const ViewerSettings(
            showDirectoryPanel: false,
            watchFolderChanges: false,
          ),
          configStore: AppConfigStore(filePath: '${dir.path}/config.json'),
        ),
      ),
    ),
  );
  await _wait(tester, () => _mainImage(tester) != null);
  await tester.tap(find.byTooltip(RegExp(r' · I$')));
  await _wait(tester, () => find.byType(IcoVariantField).evaluate().isNotEmpty);
  await tester.pump(const Duration(milliseconds: 200));
  return paths.normalize(File(path).absolute.path);
}

Future<void> _wait(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 150; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    if (condition()) return;
  }
  expect(condition(), isTrue);
}

Future<void> _save(WidgetTester tester, String name) async {
  final dir = Platform.environment['ICO_CAPTURE_DIR'];
  if (dir == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$dir/$name');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
