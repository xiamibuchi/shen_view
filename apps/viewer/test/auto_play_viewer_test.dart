import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/archive_service.dart';
import 'package:shen_view/src/application/auto_play_controller.dart';
import 'package:shen_view/src/domain/auto_play_settings.dart';
import 'package:shen_view/src/domain/comic_layout_direction.dart';
import 'package:shen_view/src/domain/viewer_mode.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/animation_playback_bar.dart';
import 'package:shen_view/src/presentation/auto_play_status.dart';
import 'package:shen_view/src/presentation/comic_strip_viewport.dart';
import 'package:shen_view/src/presentation/components/app_button.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';
import 'package:shen_view/src/presentation/zoomable_viewport.dart';

import 'support/style_review_fonts.dart';

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
          if (['isMaximized', 'isAlwaysOnTop'].contains(call.method)) {
            return false;
          }
          return null;
        });
  });

  testWidgets(
    'navigation resets interval, pause retains time, end stops without wrapping',
    (tester) async {
      await _open(tester);
      await _start(tester);
      final c = _status(tester).controller;
      await _frames(tester, 15);
      expect(c.remainingSeconds, inExclusiveRange(3, 4));
      await tester.tap(find.byTooltip('暂停自动播放 · F6'));
      final remaining = c.remainingSeconds;
      await tester.pump(const Duration(seconds: 10));
      expect(c.remainingSeconds, remaining);
      await tester.tap(find.byTooltip('开始自动播放 · F6'));
      await _frames(tester, 40);
      await _wait(tester, () => _status(tester).position == '2 / 3');
      expect(c.remainingSeconds, greaterThan(4));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _wait(tester, () => _status(tester).position == '3 / 3');
      expect(c.remainingSeconds, greaterThan(4));
      await _wait(tester, () => c.remainingSeconds < 5);
      await _frames(tester, 55);
      expect(c.status, AutoPlayStatus.stopped);
      expect(find.byType(AutoPlayStatusIndicator), findsNothing);
      expect(find.byTooltip('停止自动播放 · Shift+F6'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'double-page playback advances by groups and loops within the current list',
    (tester) async {
      await _open(
        tester,
        count: 4,
        settings: const ViewerSettings(
          showDirectoryPanel: false,
          defaultViewerMode: ViewerMode.doublePage,
          doublePageFirstAlone: false,
          doublePageWideAlone: false,
          autoPlay: AutoPlaySettings(
            intervals: {ViewerMode.doublePage: 0.5},
            loop: true,
          ),
        ),
      );
      await _start(tester);
      await _frames(tester, 6);
      await _wait(tester, () => _status(tester).position == '3 / 4');
      await _wait(
        tester,
        () => _status(tester).controller.remainingSeconds < 0.5,
      );
      await _frames(tester, 6);
      await _wait(tester, () => _status(tester).position == '1 / 4');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'top toolbar stops paused playback and keeps both commands together in overflow',
    (tester) async {
      await _open(tester);
      expect(find.byTooltip('停止自动播放 · Shift+F6'), findsNothing);
      final capture = Platform.environment['AUTO_PLAY_CAPTURE_DIR'];
      if (capture != null) {
        await _save(tester, '$capture/toolbar-before-start.png');
      }
      await _start(tester);
      final play = tester.getRect(find.byTooltip('暂停自动播放 · F6'));
      final stop = tester.getRect(find.byTooltip('停止自动播放 · Shift+F6'));
      expect(stop.center.dy, play.center.dy);
      expect(stop.left - play.right, closeTo(8, 0.5));
      final controller = _status(tester).controller;
      await _frames(tester, 10);
      await tester.tap(find.byTooltip('暂停自动播放 · F6'));
      await tester.pump();
      expect(controller.status, AutoPlayStatus.paused);
      expect(find.byTooltip('停止自动播放 · Shift+F6'), findsOneWidget);
      if (capture != null) {
        await _save(tester, '$capture/toolbar-paused.png');
      }
      await tester.tap(find.byTooltip('停止自动播放 · Shift+F6'));
      await tester.pump();
      expect(controller.status, AutoPlayStatus.stopped);
      expect(controller.remainingSeconds, 5);
      expect(find.byType(AutoPlayStatusIndicator), findsNothing);
      expect(find.byTooltip('停止自动播放 · Shift+F6'), findsNothing);
      if (capture != null) {
        await _save(tester, '$capture/toolbar-after-stop.png');
      }
      await _start(tester);
      // At this width a single playback command could fit, but the pair must
      // move to the menu together rather than separating pause from stop.
      tester.view.physicalSize = const Size(600, 800);
      await tester.pump();
      final top = find.byKey(const ValueKey('viewer-top-bar'));
      expect(
        find.descendant(of: top, matching: find.byTooltip('暂停自动播放 · F6')),
        findsNothing,
      );
      expect(
        find.descendant(of: top, matching: find.byTooltip('停止自动播放 · Shift+F6')),
        findsNothing,
      );
      await tester.tap(
        find.descendant(of: top, matching: find.byTooltip('更多操作')),
      );
      await tester.pump();
      final pauseItem = tester.getRect(find.text('暂停自动播放'));
      final stopItem = tester.getRect(find.text('停止自动播放'));
      expect(stopItem.center.dy - pauseItem.center.dy, closeTo(48, 0.5));
      await tester.tap(find.text('停止自动播放'));
      await _wait(
        tester,
        () => find.byType(AutoPlayStatusIndicator).evaluate().isEmpty,
      );
      expect(controller.status, AutoPlayStatus.stopped);
      expect(find.byType(AutoPlayStatusIndicator), findsNothing);
      expect(find.byTooltip('停止自动播放 · Shift+F6'), findsNothing);
      expect(find.text('停止自动播放'), findsNothing);
      tester.view.physicalSize = const Size(440, 800);
      await tester.pump();
      await tester.tap(
        find.descendant(of: top, matching: find.byTooltip('更多操作')),
      );
      await tester.pump();
      expect(find.text('停止自动播放'), findsNothing);
      await tester.tap(find.text('开始自动播放'));
      await _wait(
        tester,
        () => find.byType(AutoPlayStatusIndicator).evaluate().isNotEmpty,
      );
      expect(controller.playing, isTrue);
      expect(find.text('开始自动播放'), findsNothing);
      await tester.tap(
        find.descendant(of: top, matching: find.byTooltip('更多操作')),
      );
      await tester.pump();
      expect(find.text('暂停自动播放'), findsOneWidget);
      expect(find.text('停止自动播放'), findsOneWidget);
      await tester.tap(find.text('停止自动播放'));
      await _wait(
        tester,
        () => find.byType(AutoPlayStatusIndicator).evaluate().isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final direction in ComicLayoutDirection.values) {
    testWidgets(
      'continuous reading scrolls in $direction and pauses for manual interaction',
      (tester) async {
        await _open(
          tester,
          fixture: direction == ComicLayoutDirection.vertical
              ? 'format_long.png'
              : 'format_static.png',
          count: 10,
          settings: ViewerSettings(
            showDirectoryPanel: false,
            defaultViewerMode: ViewerMode.comic,
            comicLayoutDirection: direction,
            autoPlay: const AutoPlaySettings(
              scrollSpeeds: {ViewerMode.comic: 120},
            ),
          ),
        );
        await _wait(
          tester,
          () => find.byType(ComicStripViewport).evaluate().isNotEmpty,
        );
        final viewport = tester.widget<ComicStripViewport>(
          find.byType(ComicStripViewport),
        );
        await _frames(tester, 4);
        if (direction != ComicLayoutDirection.vertical) {
          viewport.commands.moveHorizontally(
            direction == ComicLayoutDirection.horizontalLeftToRight
                ? 100000
                : -100000,
          );
          await _frames(tester, 4);
        }
        await _start(tester);
        final before = viewport.controller.value.getTranslation();
        await _frames(tester, 10);
        final after = viewport.controller.value.getTranslation();
        if (direction == ComicLayoutDirection.vertical) {
          expect(after.y, lessThan(before.y));
        } else if (direction == ComicLayoutDirection.horizontalLeftToRight) {
          expect(after.x, lessThan(before.x));
        } else {
          expect(after.x, greaterThan(before.x));
        }
        await tester.drag(find.byType(ComicStripViewport), const Offset(0, 30));
        await tester.pump();
        expect(_status(tester).controller.status, AutoPlayStatus.paused);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('long image scrolls to next picture and preserves user control', (
    tester,
  ) async {
    await _open(
      tester,
      fixture: 'format_long.png',
      settings: const ViewerSettings(
        showDirectoryPanel: false,
        defaultViewerMode: ViewerMode.longImage,
        autoPlay: AutoPlaySettings(scrollSpeeds: {ViewerMode.longImage: 1000}),
      ),
    );
    await _start(tester);
    await _frames(tester, 120);
    await _wait(tester, () => _status(tester).position != '1 / 3');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'animation stop policy pauses navigation without stopping animation',
    (tester) async {
      await _open(
        tester,
        fixture: 'format_animated.gif',
        settings: const ViewerSettings(
          showDirectoryPanel: false,
          autoPlay: AutoPlaySettings(
            animationPolicy: AutoPlayAnimationPolicy.stop,
          ),
        ),
      );
      await _wait(
        tester,
        () => find.byType(AnimationPlaybackBar).evaluate().isNotEmpty,
      );
      final animation = tester
          .widget<AnimationPlaybackBar>(find.byType(AnimationPlaybackBar))
          .controller;
      await _wait(tester, () => animation.ready);
      await _start(tester);
      await _frames(tester, 2);
      expect(_status(tester).controller.status, AutoPlayStatus.paused);
      expect(animation.playing, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'minimizing suspends time and fullscreen preserves the paused countdown',
    (tester) async {
      await _open(tester);
      await _start(tester);
      await _frames(tester, 10);
      final c = _status(tester).controller;
      final window = tester.state(find.byType(ViewerPage)) as WindowListener;
      window.onWindowMinimize();
      final remaining = c.remainingSeconds;
      await _frames(tester, 30);
      expect(c.remainingSeconds, remaining);
      expect(c.playing, isTrue);
      window.onWindowRestore();
      await _frames(tester, 5);
      expect(c.remainingSeconds, lessThan(remaining));
      c.pause();
      final paused = c.remainingSeconds;
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pumpAndSettle();
      expect(c.remainingSeconds, paused);
      expect(c.status, AutoPlayStatus.paused);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final dark in [true, false]) {
    testWidgets(
      'auto advance status and animation transport stay distinct, dark=$dark',
      (tester) async {
        await _open(
          tester,
          dark: dark,
          fixture: 'format_animated.gif',
          settings: const ViewerSettings(
            showDirectoryPanel: false,
            animationControlsMode: AnimationControlsMode.always,
            autoPlay: AutoPlaySettings(
              intervals: {ViewerMode.single: 60},
              animationPolicy: AutoPlayAnimationPolicy.fixedInterval,
            ),
          ),
        );
        final animation = tester
            .widget<AnimationPlaybackBar>(find.byType(AnimationPlaybackBar))
            .controller;
        await _wait(tester, () => animation.ready);
        await _start(tester);
        final controller = _status(tester).controller;
        expect(find.text('动图'), findsOneWidget);
        expect(find.textContaining('自动换图'), findsWidgets);
        expect(find.byKey(const ValueKey('autoPlay.toggle')), findsNothing);
        final statusRect = tester.getRect(find.byType(AutoPlayStatusIndicator));
        final animationRect = tester.getRect(find.byType(AnimationPlaybackBar));
        expect(statusRect.bottom, lessThan(animationRect.top));
        expect(statusRect.top, lessThan(150));
        final capture = Platform.environment['AUTO_PLAY_CAPTURE_DIR'];
        if (capture != null) {
          await _save(
            tester,
            '$capture/${dark ? 'dark' : 'light'}-animation-wide.png',
          );
          await _frames(tester, 24);
          await tester.pump(const Duration(milliseconds: 200));
          await _save(
            tester,
            '$capture/${dark ? 'dark' : 'light'}-status-hidden.png',
          );
          final hover = await tester.createGesture(
            kind: ui.PointerDeviceKind.mouse,
          );
          await hover.addPointer(location: const Offset(640, 400));
          await hover.moveTo(
            tester.getCenter(find.byType(AutoPlayStatusIndicator)),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          await _save(
            tester,
            '$capture/${dark ? 'dark' : 'light'}-status-revealed.png',
          );
          await hover.removePointer();
        }
        await tester.tap(find.byTooltip('暂停自动播放 · F6'));
        await tester.pump();
        expect(controller.playing, isFalse);
        expect(animation.playing, isTrue);
        await tester.tap(find.byTooltip('开始自动播放 · F6'));
        await tester.pump();
        final step = animation.frame == animation.frameCount - 1 ? -1 : 1;
        await tester.tap(find.byKey(ValueKey('animation.step.$step')));
        await _wait(tester, () => !controller.playing);
        expect(animation.playing, isFalse);
        await tester.tap(find.byTooltip('开始自动播放 · F6'));
        await tester.pump();
        expect(animation.playing, isTrue);
        await tester.tap(find.byKey(const ValueKey('autoPlay.options')));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byKey(const ValueKey('autoPlay.stop')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(controller.status, AutoPlayStatus.stopped);
        expect(animation.playing, isTrue);
        expect(find.byType(AutoPlayStatusIndicator), findsNothing);
        await _start(tester);
        await tester.tap(find.byTooltip('停止自动播放 · Shift+F6'));
        await tester.pump();
        expect(controller.status, AutoPlayStatus.stopped);
        expect(animation.playing, isTrue);
        await _start(tester);
        tester.view.physicalSize = const Size(360, 800);
        await tester.pump();
        if (capture != null) {
          await _save(
            tester,
            '$capture/${dark ? 'dark' : 'light'}-animation-narrow.png',
          );
        }
        expect(tester.takeException(), isNull);
        tester.view.physicalSize = const Size(1280, 800);
        await tester.sendKeyEvent(LogicalKeyboardKey.f11);
        await _frames(tester, 3);
        // Reveal the floating toolbar and verify the status stays beneath it.
        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: const Offset(640, 2));
        await mouse.moveTo(const Offset(640, 20));
        await _frames(tester, 3);
        final toolbar = tester.getRect(
          find.byKey(const ValueKey('viewer-top-bar')),
        );
        expect(
          tester.getTopLeft(find.byType(AutoPlayStatusIndicator)).dy,
          greaterThanOrEqualTo(toolbar.bottom),
        );
        if (capture != null) {
          await _save(
            tester,
            '$capture/${dark ? 'dark' : 'light'}-animation-fullscreen.png',
          );
        }
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets(
      'auto controls fit a 120 pixel canvas beside a pinned directory, dark=$dark',
      (tester) async {
        final controller = AutoPlayController()
          ..start()
          ..pause();
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Center(
              child: SizedBox(
                width: 120,
                child: AutoPlayStatusIndicator(
                  controller: controller,
                  onOptions: () {},
                  position: '1 / 3',
                ),
              ),
            ),
          ),
        );
        expect(find.text('自动换图'), findsOneWidget);
        expect(find.byKey(const ValueKey('autoPlay.options')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );
    testWidgets(
      'controls and options render at wide and narrow widths, dark=$dark',
      (tester) async {
        await _open(tester, dark: dark);
        await _start(tester);
        await tester.tap(find.byTooltip('暂停自动播放 · F6'));
        final capture = Platform.environment['AUTO_PLAY_CAPTURE_DIR'];
        if (capture != null) {
          await _save(tester, '$capture/${dark ? 'dark' : 'light'}-wide.png');
        }
        tester.view.physicalSize = const Size(360, 800);
        await tester.pump();
        if (capture != null) {
          await _save(tester, '$capture/${dark ? 'dark' : 'light'}-narrow.png');
        }
        await tester.tap(find.byKey(const ValueKey('autoPlay.options')));
        await tester.pumpAndSettle();
        expect(find.text('自动播放设置'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('autoPlay.parameter')),
          '0',
        );
        await tester.pump();
        expect(
          tester
              .widget<AppButton>(find.byKey(const ValueKey('autoPlay.save')))
              .onPressed,
          isNull,
        );
        if (capture != null) {
          await _save(
            tester,
            '$capture/${dark ? 'dark' : 'light'}-invalid-options.png',
          );
        }
        await tester.enterText(
          find.byKey(const ValueKey('autoPlay.parameter')),
          '7.5',
        );
        await tester.pump();
        if (capture != null) {
          await _save(
            tester,
            '$capture/${dark ? 'dark' : 'light'}-options.png',
          );
        }
        await tester.tap(find.byKey(const ValueKey('autoPlay.save')));
        await tester.pumpAndSettle();
        expect(
          _status(tester).controller.settings.intervalFor(ViewerMode.single),
          7.5,
        );
        tester.view.physicalSize = const Size(1280, 800);
        await tester.sendKeyEvent(LogicalKeyboardKey.f11);
        await tester.pumpAndSettle();
        if (capture != null) {
          await _save(
            tester,
            '$capture/${dark ? 'dark' : 'light'}-fullscreen.png',
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

AutoPlayStatusIndicator _status(WidgetTester tester) => tester
    .widget<AutoPlayStatusIndicator>(find.byType(AutoPlayStatusIndicator));

Future<void> _start(WidgetTester tester) async {
  await tester.tap(find.byTooltip('开始自动播放 · F6'));
  await tester.pump();
  await _frames(tester, 1);
  final c = _status(tester).controller;
  if (!c.scrolling &&
      c.settings.animationPolicy != AutoPlayAnimationPolicy.stop) {
    await _wait(
      tester,
      () => c.remainingSeconds < c.settings.intervalFor(c.mode),
    );
  } else if (c.scrolling) {
    final viewport = tester.widget<ZoomableViewport>(
      find.byType(ZoomableViewport),
    );
    final before = viewport.controller.value.getTranslation();
    await _wait(
      tester,
      () => viewport.controller.value.getTranslation() != before,
    );
  }
}

Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    if (ready()) return;
  }
  expect(ready(), isTrue);
}

Future<void> _open(
  WidgetTester tester, {
  String fixture = 'format_static.png',
  int count = 3,
  bool dark = true,
  ViewerSettings settings = const ViewerSettings(showDirectoryPanel: false),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final dir = Directory.systemTemp.createTempSync('auto-play-viewer-');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      /* Decoder may hold a handle. */
    }
  });
  final extension = fixture.split('.').last;
  final longImage = fixture == 'format_long.png'
      ? await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          canvas.drawRect(
            const Rect.fromLTWH(0, 0, 400, 1800),
            ui.Paint()..color = const ui.Color(0xFF246688),
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(400, 1800);
          try {
            return (await image.toByteData(format: ui.ImageByteFormat.png))!
                .buffer
                .asUint8List();
          } finally {
            image.dispose();
            picture.dispose();
          }
        })
      : null;
  for (var i = 1; i <= count; i++) {
    if (longImage != null) {
      File('${dir.path}/0$i.$extension').writeAsBytesSync(longImage);
    } else {
      File('testdata/formats/$fixture').copySync('${dir.path}/0$i.$extension');
    }
  }
  var theme = dark ? AppTheme.dark() : AppTheme.light();
  if (Platform.environment['AUTO_PLAY_CAPTURE_DIR'] != null) {
    await tester.runAsync(() async {
      for (final (family, path) in [
        ('AutoPlayReview', windowsFontPath('msyh.ttc')),
        (
          'packages/fluentui_system_icons/FluentSystemIcons-Regular',
          'packages/fluentui_system_icons/fonts/FluentSystemIcons-Regular.ttf',
        ),
      ]) {
        await (FontLoader(family)..addFont(loadReviewFontData(path))).load();
      }
    });
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'AutoPlayReview'),
    );
  }
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('autoPlay.capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: theme,
        home: ViewerPage(
          initialPath: '${dir.path}/01.$extension',
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
  await _wait(tester, () => find.text('01.$extension').evaluate().isNotEmpty);
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
  await _frames(tester, 4);
}

Future<void> _save(WidgetTester tester, String path) async {
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('autoPlay.capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
