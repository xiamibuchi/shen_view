import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/archive_service.dart';
import 'package:shen_view/src/domain/viewer_mode.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/animated_image_view.dart';
import 'package:shen_view/src/presentation/animation_playback_bar.dart';
import 'package:shen_view/src/presentation/components/app_slider.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';
import 'package:shen_view/src/presentation/viewer_bottom_bar.dart';

import 'support/style_review_fonts.dart';

const _capture = ValueKey('animation.capture');

void main() {
  setUp(() {
    var fullscreen = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          if (call.method == 'setFullScreen') {
            fullscreen =
                (call.arguments as Map<Object?, Object?>)['isFullScreen']!
                    as bool;
          }
          if (call.method == 'isFullScreen') return fullscreen;
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

  testWidgets('photo video controls fit light/dark and narrow windows', (
    tester,
  ) async {
    final captures = Platform.environment['PHOTO_MEDIA_CAPTURE_DIR'];
    await _loadFonts(tester, captures);
    for (final dark in [false, true]) {
      for (final width in [1280.0, 600.0, 360.0, 240.0]) {
        await _open(
          tester,
          'motion-h264.jpg',
          fixtureDirectory: 'testdata/photo_media',
          width: width,
          dark: dark,
        );
        final c = tester
            .widget<AnimationPlaybackBar>(find.byType(AnimationPlaybackBar))
            .controller;
        await _wait(tester, () => c.ready || c.error != null);
        expect(c.error, isNull);
        expect(c.audioTrackCount, 1);
        expect(c.muted, isTrue);
        await tester.pump(const Duration(milliseconds: 200));
        final bar = tester.getRect(find.byType(AnimationPlaybackBar));
        expect(bar.left, greaterThanOrEqualTo(0));
        expect(bar.right, lessThanOrEqualTo(width));
        expect(tester.takeException(), isNull, reason: '$dark/$width');
        if (captures != null) {
          await _save(
            tester,
            '$captures/${dark ? 'dark' : 'light'}-${width.toInt()}.png',
          );
        }
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  for (final extension in ['gif', 'webp', 'apng', 'avif']) {
    testWidgets('$extension exposes playback, stepping, scrubbing and Space', (
      tester,
    ) async {
      await _open(tester, 'format_animated.$extension');
      final c = tester
          .widget<AnimationPlaybackBar>(find.byType(AnimationPlaybackBar))
          .controller;
      await _wait(tester, () => c.ready);
      expect(c.error, isNull);
      expect(c.frame, 0);
      await tester.tap(find.byKey(const ValueKey('animation.step.1')));
      await _wait(tester, () => c.frame == 1);
      expect(c.playing, isFalse);
      final slider = tester.widget<AppSlider>(
        find.byKey(const ValueKey('animation.progress')),
      );
      slider.onChangeStart!(0);
      slider.onChanged!(c.timeline.durationMs.toDouble());
      slider.onChangeEnd!(c.timeline.durationMs.toDouble());
      await _wait(tester, () => c.frame == c.frameCount - 1);
      expect(c.playing, isFalse);
      Focus.of(tester.element(find.byKey(const ValueKey('animation.play'))))
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.pump();
      expect(find.byType(ViewerBottomBar), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.pump();
      expect(find.byType(ViewerBottomBar), findsOneWidget);
      // Clicking the canvas restores keyboard focus from the playback controls.
      await tester.tapAt(const Offset(420, 200));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(c.playing, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(c.playing, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('static WebP does not show playback controls', (tester) async {
    await _open(tester, 'format_static.webp', animated: false);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.byType(AnimationPlaybackBar), findsNothing);
    expect(find.text('无法解码动图'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'AVIF animation switches to a static image without playback controls',
    (tester) async {
      final captureDir = Platform.environment['AVIF_CAPTURE_DIR'];
      await _loadFonts(tester, captureDir);
      for (final dark in [true, false]) {
        await _open(
          tester,
          'format_animated.avif',
          dark: dark,
          siblings: ['format_static.avif'],
        );
        final c = tester
            .widget<AnimationPlaybackBar>(find.byType(AnimationPlaybackBar))
            .controller;
        await _wait(tester, () => c.ready);
        c.step(1);
        await _wait(tester, () => c.frame == 1);
        if (captureDir != null) {
          await _save(
            tester,
            '$captureDir/${dark ? 'dark' : 'light'}-animated.png',
          );
        }
        await tester.tapAt(const Offset(420, 200));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await _wait(
          tester,
          () =>
              find.byType(AnimationPlaybackBar).evaluate().isEmpty &&
              find.byType(AnimatedImageView).evaluate().isEmpty &&
              find.byType(CircularProgressIndicator).evaluate().isEmpty &&
              find
                  .descendant(
                    of: find.byKey(const ValueKey('viewer.content')),
                    matching: find.byType(RawImage),
                  )
                  .evaluate()
                  .any(
                    (element) =>
                        ((element.widget as RawImage).image?.width ?? 0) >= 256,
                  ),
        );
        if (captureDir != null) {
          await _save(
            tester,
            '$captureDir/${dark ? 'dark' : 'light'}-static.png',
          );
        }
        expect(find.byType(AnimatedImageView), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await _wait(
          tester,
          () => find.byType(AnimationPlaybackBar).evaluate().isNotEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      }
      for (final name in [
        'format_single_frame.avif',
        'format_progressive.avif',
      ]) {
        await _open(tester, name, animated: false);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
        expect(find.byType(AnimationPlaybackBar), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('animation defaults and bar visibility apply from settings', (
    tester,
  ) async {
    await _open(
      tester,
      'format_animated.gif',
      settings: const ViewerSettings(
        showDirectoryPanel: false,
        animationAutoPlay: false,
        animationSpeed: 0.5,
        animationControlsMode: AnimationControlsMode.always,
      ),
    );
    final c = tester
        .widget<AnimationPlaybackBar>(find.byType(AnimationPlaybackBar))
        .controller;
    await _wait(tester, () => c.ready);
    expect(c.speed, 0.5);
    c.setPlaying(true);
    await tester.pump(const Duration(seconds: 3));
    final opacity = find.descendant(
      of: find.byType(AnimationPlaybackBar),
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
    c.setPlaying(false);
    c.setSpeed(2);
    await tester.pump();
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('viewer.content'))),
      buttons: kSecondaryMouseButton,
    );
    await _wait(tester, () => find.text('设置').evaluate().isNotEmpty);
    await tester.runAsync(() => tester.tap(find.text('设置')));
    await _wait(tester, () => find.text('播放').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings.nav.playback')));
    await tester.pumpAndSettle();
    // A temporary playback speed must not overwrite the saved default.
    expect(find.text('0.5×'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings.animationSpeed')),
    );
    await tester.tap(find.byKey(const ValueKey('settings.animationSpeed')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('1.5×').last));
    await tester.pumpAndSettle();
    final visibility = find.byKey(
      const ValueKey('settings.animationControlsMode'),
    );
    await tester.ensureVisible(visibility);
    await tester.tap(visibility);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('隐藏').last));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(AnimationPlaybackBar), findsNothing);
    expect(c.speed, 1.5);
    expect(c.playing, isFalse);
    await tester.tapAt(const Offset(420, 200));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('double-page click selects which animation the bar controls', (
    tester,
  ) async {
    await _open(
      tester,
      'format_animated.gif',
      siblings: ['format_animated.webp'],
      settings: const ViewerSettings(
        showDirectoryPanel: false,
        animationAutoPlay: false,
        defaultViewerMode: ViewerMode.doublePage,
        doublePageFirstAlone: false,
        doublePageWideAlone: false,
      ),
    );
    await _wait(
      tester,
      () => find.byType(AnimatedImageView).evaluate().length == 2,
    );
    final first = tester
        .widget<AnimationPlaybackBar>(find.byType(AnimationPlaybackBar))
        .controller;
    await tester.tap(find.byType(AnimatedImageView).last);
    await _wait(
      tester,
      () =>
          find.byType(AnimationPlaybackBar).evaluate().isNotEmpty &&
          !identical(
            first,
            tester
                .widget<AnimationPlaybackBar>(find.byType(AnimationPlaybackBar))
                .controller,
          ),
    );
    final second = tester
        .widget<AnimationPlaybackBar>(find.byType(AnimationPlaybackBar))
        .controller;
    await _wait(tester, () => second.ready);
    second.step(1);
    await _wait(tester, () => second.frame == 1);
    expect(first.frame, 0);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'playback bar renders in dark/light, narrow windows and fullscreen',
    (tester) async {
      final captureDir = Platform.environment['ANIMATION_CAPTURE_DIR'];
      await _loadFonts(tester, captureDir);
      for (final dark in [true, false]) {
        for (final width in [1280.0, 600.0, 360.0, 240.0]) {
          await _open(tester, 'format_animated.apng', width: width, dark: dark);
          final c = tester
              .widget<AnimationPlaybackBar>(find.byType(AnimationPlaybackBar))
              .controller;
          await _wait(tester, () => c.ready);
          await tester.pump(const Duration(milliseconds: 200));
          expect(tester.takeException(), isNull, reason: '$dark/$width');
          if (captureDir != null) {
            await _save(
              tester,
              '$captureDir/${dark ? 'dark' : 'light'}-${width.toInt()}.png',
            );
          }
          if (width == 1280) {
            final normalBar = tester.getRect(find.byType(AnimationPlaybackBar));
            await tester.tap(find.byKey(const ValueKey('animation.more')));
            await tester.pumpAndSettle();
            expect(find.text('遵循文件'), findsOneWidget);
            if (captureDir != null) {
              await _save(
                tester,
                '$captureDir/${dark ? 'dark' : 'light'}-menu.png',
              );
            }
            await tester.tap(find.text('无限循环'));
            await tester.pumpAndSettle();
            expect(c.loopMode.name, 'infinite');
            c.setSpeed(0.5);
            c.step(1);
            await _wait(tester, () => c.frame == 1);
            await tester.tapAt(const Offset(500, 200));
            await tester.sendKeyEvent(LogicalKeyboardKey.f11);
            await _wait(
              tester,
              () =>
                  find.byType(AnimationPlaybackBar).evaluate().isNotEmpty &&
                  find.byType(CircularProgressIndicator).evaluate().isEmpty,
            );
            await tester.pump(const Duration(milliseconds: 200));
            expect(find.byType(AnimationPlaybackBar), findsOneWidget);
            final fullscreenPlayback = tester
                .widget<AnimationPlaybackBar>(find.byType(AnimationPlaybackBar))
                .controller;
            expect(fullscreenPlayback.frame, 1);
            expect(fullscreenPlayback.speed, 0.5);
            expect(fullscreenPlayback.playing, isFalse);
            expect(fullscreenPlayback.loopMode.name, 'infinite');
            expect(
              tester.getRect(find.byType(AnimationPlaybackBar)).bottom,
              closeTo(normalBar.bottom, 0.5),
            );
            if (captureDir != null) {
              await _save(
                tester,
                '$captureDir/${dark ? 'dark' : 'light'}-fullscreen.png',
              );
            }
            await tester.sendKeyEvent(LogicalKeyboardKey.f11);
            await _wait(
              tester,
              () =>
                  find.byType(AnimationPlaybackBar).evaluate().isNotEmpty &&
                  find.byType(CircularProgressIndicator).evaluate().isEmpty,
            );
            await tester.pump(const Duration(milliseconds: 200));
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );

  testWidgets(
    'playing controls fade and return on hover; paused controls stay visible',
    (tester) async {
      await _open(tester, 'format_animated.gif');
      final c = tester
          .widget<AnimationPlaybackBar>(find.byType(AnimationPlaybackBar))
          .controller;
      await _wait(tester, () => c.ready);
      c.setPlaying(true);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 150));
      final opacity = find.descendant(
        of: find.byType(AnimationPlaybackBar),
        matching: find.byType(AnimatedOpacity),
      );
      expect(tester.widget<AnimatedOpacity>(opacity).opacity, 0);
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: const Offset(100, 100));
      await mouse.moveTo(tester.getCenter(find.byType(AnimationPlaybackBar)));
      await tester.pump();
      expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
      c.setPlaying(false);
      await mouse.moveTo(const Offset(100, 100));
      await tester.pump(const Duration(seconds: 3));
      expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _open(
  WidgetTester tester,
  String name, {
  String fixtureDirectory = 'testdata/formats',
  bool animated = true,
  double width = 1280,
  bool dark = true,
  List<String> siblings = const [],
  ViewerSettings settings = const ViewerSettings(
    showDirectoryPanel: false,
    animationAutoPlay: false,
  ),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final dir = Directory.systemTemp.createTempSync('animation-viewer-test');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      /* Decoder may briefly hold a Windows file handle. */
    }
  });
  final path = '${dir.path}/$name';
  File('$fixtureDirectory/$name').copySync(path);
  for (final sibling in siblings) {
    File('testdata/formats/$sibling').copySync('${dir.path}/$sibling');
  }
  final platform =
      Platform.environment['ANIMATION_CAPTURE_DIR'] == null &&
          Platform.environment['PHOTO_MEDIA_CAPTURE_DIR'] == null &&
          Platform.environment['AVIF_CAPTURE_DIR'] == null
      ? null
      : TargetPlatform.windows;
  final theme = dark
      ? AppTheme.dark(platform: platform)
      : AppTheme.light(platform: platform);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _capture,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: theme,
        home: ViewerPage(
          key: ValueKey(path),
          initialPath: path,
          initialSettings: settings,
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
    () => animated
        ? find.byType(AnimationPlaybackBar).evaluate().isNotEmpty
        : find.text(name).evaluate().isNotEmpty,
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

Future<void> _loadFonts(WidgetTester tester, String? captureDir) async {
  if (captureDir == null) return;
  await loadStyleReviewFonts(tester);
}

Future<void> _save(WidgetTester tester, String path) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
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
