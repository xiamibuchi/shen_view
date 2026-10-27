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
import 'package:shen_view/src/application/archive_service.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/animation_playback_bar.dart';
import 'package:shen_view/src/presentation/color_picker_overlay.dart';
import 'package:shen_view/src/presentation/color_picker_target.dart';
import 'package:shen_view/src/presentation/hdr_image_view.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';
import 'package:shen_view/src/presentation/zoomable_viewport.dart';

import 'support/style_review_fonts.dart';

const _captureKey = ValueKey('colorPicker.capture');

void main() {
  String? clipboard;
  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') {
            return {'text': clipboard};
          }
          return null;
        });
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

  for (final dark in [true, false]) {
    testWidgets(
      'context menu opens in one frame without rebuilding the canvas ($dark)',
      (tester) async {
        await _open(tester, dark: dark);
        await tester.pump(const Duration(milliseconds: 300));
        final viewport = tester.widget<ZoomableViewport>(
          find.byType(ZoomableViewport),
        );
        await tester.tapAt(
          const Offset(250, 180),
          buttons: kSecondaryMouseButton,
        );
        await tester.pump();
        expect(find.text('最近打开'), findsOneWidget);
        expect(
          identical(
            tester.widget<ZoomableViewport>(find.byType(ZoomableViewport)),
            viewport,
          ),
          isTrue,
        );
        expect(
          tester
              .widget<HdrOverlayScope>(find.byType(HdrOverlayScope))
              .suspended,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(find.text('最近打开'), findsNothing);
        expect(
          tester
              .widget<HdrOverlayScope>(find.byType(HdrOverlayScope))
              .suspended,
          isFalse,
        );
        await tester.tapAt(
          const Offset(450, 220),
          buttons: kSecondaryMouseButton,
        );
        await tester.pump();
        expect(find.text('最近打开'), findsOneWidget);
        final moved = tester.getRect(find.text('最近打开'));
        expect(moved.left, greaterThan(450));
        await tester.tapAt(const Offset(24, 300));
        await tester.pump();
        expect(find.text('最近打开'), findsNothing);
        await tester.tapAt(
          const Offset(250, 180),
          buttons: kSecondaryMouseButton,
        );
        await tester.pump();
        await tester.tapAt(
          const Offset(250, 180),
          buttons: kSecondaryMouseButton,
        );
        await tester.pump();
        expect(find.text('最近打开'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'context menu omits image tools; toolbar entry, lock, nudge, copy and Escape work',
    (tester) async {
      final captureDir = Platform.environment['COLOR_PICKER_CAPTURE_DIR'];
      if (captureDir != null) await _loadFonts(tester);
      await _open(tester);
      await tester.tapAt(
        const Offset(250, 180),
        buttons: kSecondaryMouseButton,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await _wait(tester, () => find.text('最近打开').evaluate().isNotEmpty);
      expect(find.text('颜色拾取'), findsNothing);
      expect(find.text('进入无边框模式'), findsNothing);
      expect(find.text('退出无边框模式'), findsNothing);
      expect(find.text('新建窗口'), findsNothing);
      expect(find.text('在新窗口打开'), findsNothing);
      if (captureDir != null) {
        await _save(tester, '$captureDir/context-menu.png');
      }
      await tester.tapAt(const Offset(24, 300));
      await _wait(tester, () => find.text('最近打开').evaluate().isEmpty);
      await tester.tap(find.byTooltip('颜色拾取 · Ctrl+Shift+C'));
      await tester.pump(const Duration(milliseconds: 200));
      await _wait(
        tester,
        () => find.byType(ColorPickerOverlay).evaluate().isNotEmpty,
      );
      final overlay = tester.widget<ColorPickerOverlay>(
        find.byType(ColorPickerOverlay),
      );
      final c = overlay.controller;
      expect(c.active, isTrue);
      final scope = tester.widget<HdrOverlayScope>(
        find.byType(HdrOverlayScope),
      );
      expect(scope.suspended, isTrue);
      final raw = find
          .descendant(
            of: find.byType(ColorPickerTarget),
            matching: find.byType(RawImage),
          )
          .first;
      await _wait(
        tester,
        () => tester.renderObject<RenderImage>(raw).image != null,
      );
      final render = tester.renderObject<RenderImage>(raw);
      final point = render.localToGlobal(
        Offset(render.size.width * 0.2, render.size.height * 0.2),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: point);
      await mouse.moveTo(point + const Offset(1, 0));
      await tester.tapAt(point);
      await _wait(tester, () => c.selected != null);
      expect(c.selected!.color.hex, '#EF4444');
      expect(c.selected!.previewOnly, isFalse);
      final oldX = c.selected!.x;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _wait(tester, () => c.selected!.x == oldX + 1);
      final expected = c.selected!.color.hex;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, expected);
      expect(c.active, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(ColorPickerOverlay), findsNothing);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      await _open(tester, instanceMode: InstanceMode.multiProcess);
      await tester.tapAt(
        const Offset(250, 180),
        buttons: kSecondaryMouseButton,
      );
      await _wait(tester, () => find.text('最近打开').evaluate().isNotEmpty);
      for (final label in ['新建窗口', '在新窗口打开']) {
        expect(find.text(label), findsOneWidget);
        final item = tester.widget<MenuItemButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(MenuItemButton),
          ),
        );
        expect(item.onPressed, isNotNull);
      }
      if (captureDir != null) {
        await _save(tester, '$captureDir/context-menu-multi.png');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'current animation frame is frozen and resumes its previous intent',
    (tester) async {
      await _open(tester, animation: true);
      await _wait(
        tester,
        () => find.byType(AnimationPlaybackBar).evaluate().isNotEmpty,
      );
      final playback = tester
          .widget<AnimationPlaybackBar>(find.byType(AnimationPlaybackBar))
          .controller;
      await _wait(tester, () => playback.ready);
      playback.seekFrame(1);
      await _wait(tester, () => playback.frame == 1);
      playback.setPlaying(true);
      await _toggleShortcut(tester);
      final c = tester
          .widget<ColorPickerOverlay>(find.byType(ColorPickerOverlay))
          .controller;
      final frozen = playback.frame;
      await tester.pump(const Duration(seconds: 1));
      expect(playback.frame, frozen);
      final raw = find
          .descendant(
            of: find.byType(ColorPickerTarget),
            matching: find.byType(RawImage),
          )
          .first;
      final render = tester.renderObject<RenderImage>(raw);
      final point = render.localToGlobal(render.size.center(Offset.zero));
      await tester.tapAt(point);
      await _wait(tester, () => c.selected != null);
      expect(c.selected!.color.hex, '#2563EB');
      playback.seekFrame(0);
      await _wait(tester, () => c.hover?.color.hex == '#EF4444');
      expect(c.selected, isNull);
      expect(c.recent.single.hex, '#2563EB');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(playback.playing, isTrue);
      playback.setPlaying(false);
      await _toggleShortcut(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(playback.playing, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets('color picker visual review ${dark ? 'dark' : 'light'}', (
      tester,
    ) async {
      final captureDir = Platform.environment['COLOR_PICKER_CAPTURE_DIR'];
      if (captureDir != null) await _loadFonts(tester);
      await _open(tester, dark: dark);
      await _toggleShortcut(tester);
      final c = tester
          .widget<ColorPickerOverlay>(find.byType(ColorPickerOverlay))
          .controller;
      final raw = find
          .descendant(
            of: find.byType(ColorPickerTarget),
            matching: find.byType(RawImage),
          )
          .first;
      await _wait(
        tester,
        () => tester.renderObject<RenderImage>(raw).image != null,
      );
      final render = tester.renderObject<RenderImage>(raw);
      final point = render.localToGlobal(
        Offset(render.size.width * 0.25, render.size.height * 0.45),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: point);
      await mouse.moveTo(point + const Offset(1, 0));
      await tester.tapAt(point);
      await _wait(tester, () => c.selected != null && c.hover != null);
      expect(
        find.byKey(const ValueKey('colorPicker.magnifier')),
        findsOneWidget,
      );
      if (captureDir != null) {
        await tester.pump(const Duration(milliseconds: 300));
        await _save(tester, '$captureDir/${dark ? 'dark' : 'light'}.png');
        tester.view.physicalSize = const Size(600, 460);
        await tester.pump(const Duration(milliseconds: 300));
        final recentRect = tester.getRect(
          find.byKey(ValueKey('colorPicker.recent.${c.recent.first.hexAlpha}')),
        );
        final cardRect = tester.getRect(
          find.byKey(const ValueKey('colorPicker.card')),
        );
        expect(cardRect.contains(recentRect.topLeft), isTrue);
        expect(recentRect.right, lessThanOrEqualTo(cardRect.right));
        expect(recentRect.bottom, lessThanOrEqualTo(cardRect.bottom));
        await _save(
          tester,
          '$captureDir/${dark ? 'dark' : 'light'}-compact.png',
        );
        final scrollBefore = tester.getRect(
          find.byKey(const ValueKey('colorPicker.scroll')),
        );
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: scrollBefore.center,
            scrollDelta: const Offset(0, 240),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final visibleRecent = tester.getRect(
          find.byKey(ValueKey('colorPicker.recent.${c.recent.first.hexAlpha}')),
        );
        final scrollRect = tester.getRect(
          find.byKey(const ValueKey('colorPicker.scroll')),
        );
        expect(visibleRecent.top, greaterThanOrEqualTo(scrollRect.top));
        expect(visibleRecent.bottom, lessThanOrEqualTo(scrollRect.bottom));
        final closeRect = tester.getRect(
          find.byKey(const ValueKey('colorPicker.close')),
        );
        expect(closeRect.top, greaterThanOrEqualTo(0));
        expect(closeRect.bottom, lessThan(460));
        await _save(
          tester,
          '$captureDir/${dark ? 'dark' : 'light'}-compact-recent.png',
        );
      }
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

Future<void> _toggleShortcut(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _open(
  WidgetTester tester, {
  bool animation = false,
  bool dark = true,
  InstanceMode instanceMode = InstanceMode.singleProcess,
}) async {
  tester.view.physicalSize = const Size(1060, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final dir = Directory.systemTemp.createTempSync('color-picker-viewer-');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      /* A decoder may still be releasing the file. */
    }
  });
  final image = imaging.Image(width: 160, height: 120, numChannels: 4);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final red = x < 80 && y < 60;
      final blue = x >= 80 && y < 60;
      final green = x < 80 && y >= 60;
      image.setPixelRgba(
        x,
        y,
        red
            ? 239
            : blue
            ? 37
            : green
            ? 34
            : 250,
        red
            ? 68
            : blue
            ? 99
            : green
            ? 197
            : 204,
        red
            ? 68
            : blue
            ? 235
            : green
            ? 94
            : 21,
        255,
      );
    }
  }
  final path = '${dir.path}/颜色样本.${animation ? 'gif' : 'png'}';
  if (animation) {
    final first = imaging.Image(width: 160, height: 120)..frameDuration = 200;
    imaging.fill(first, color: imaging.ColorRgb8(239, 68, 68));
    final second = imaging.Image(width: 160, height: 120)..frameDuration = 200;
    imaging.fill(second, color: imaging.ColorRgb8(37, 99, 235));
    first.addFrame(second);
    File(path).writeAsBytesSync(imaging.encodeGif(first));
  } else {
    File(path).writeAsBytesSync(imaging.encodePng(image));
  }
  var theme = dark ? AppTheme.dark() : AppTheme.light();
  if (Platform.environment['COLOR_PICKER_CAPTURE_DIR'] != null) {
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'ColorPickerReview'),
    );
  }
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ViewerPage(
          key: ValueKey(path),
          initialPath: path,
          initialSettings: ViewerSettings(
            showDirectoryPanel: false,
            instanceMode: instanceMode,
            animationAutoPlay: false,
            watchFolderChanges: false,
          ),
          configStore: AppConfigStore(filePath: '${dir.path}/config.json'),
          archiveService: ArchiveService(
            cachePolicy: ArchiveCachePolicy(
              directory: Directory('${dir.path}/cache'),
            ),
          ),
        ),
      ),
    ),
  );
  await _wait(
    tester,
    () => find.byType(ColorPickerTarget).evaluate().isNotEmpty,
  );
  await _wait(
    tester,
    () => find
        .descendant(
          of: find.byType(ColorPickerTarget),
          matching: find.byType(RawImage),
        )
        .evaluate()
        .isNotEmpty,
  );
}

Future<void> _wait(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    if (condition()) return;
  }
  expect(condition(), isTrue);
}

Future<void> _loadFonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final (family, path) in [
      ('ColorPickerReview', windowsFontPath('msyh.ttc')),
      (
        'packages/fluentui_system_icons/FluentSystemIcons-Regular',
        'packages/fluentui_system_icons/fonts/FluentSystemIcons-Regular.ttf',
      ),
    ]) {
      await (FontLoader(family)..addFont(loadReviewFontData(path))).load();
    }
  });
}

Future<void> _save(WidgetTester tester, String path) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
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
