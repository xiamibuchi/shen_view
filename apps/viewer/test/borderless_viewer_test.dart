import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/archive_service.dart';
import 'package:shen_view/src/domain/auto_play_settings.dart';
import 'package:shen_view/src/domain/folder_browse_mode.dart';
import 'package:shen_view/src/domain/viewer_mode.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/animation_playback_bar.dart';
import 'package:shen_view/src/presentation/auto_play_status.dart';
import 'package:shen_view/src/presentation/chapter_directory_tree.dart';
import 'package:shen_view/src/presentation/directory_panel_region.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_bottom_bar.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';
import 'package:shen_view/src/presentation/zoomable_viewport.dart';

import 'support/style_review_fonts.dart';

void main() {
  for (final dark in [true, false]) {
    testWidgets(
      'fullscreen preserves all ordinary panels and borderless restores them, dark=$dark',
      (tester) async {
        final host = await _open(tester, dark: dark);
        await tester.tap(find.byTooltip('显示信息 · I'));
        await tester.pump();
        final normalViewport = tester.state(find.byType(ZoomableViewport));
        final normalDirectory = tester.state(find.byType(ChapterDirectoryTree));
        final normalThumbnails = tester.element(find.byType(ViewerBottomBar));
        final normalRect = tester.getRect(find.byType(ZoomableViewport));
        final normalWidth = tester
            .getSize(find.byKey(const ValueKey('directory.sizedPanel')))
            .width;
        final list = tester.widget<ListView>(
          find.byKey(const ValueKey('directory.rows')),
        );
        await _wait(
          tester,
          () =>
              list.controller!.hasClients &&
              list.controller!.position.maxScrollExtent > 100,
        );
        list.controller!.jumpTo(100);
        await tester.pump();
        await _capture(tester, '${dark ? 'dark' : 'light'}-ordinary');
        await tester.sendKeyEvent(LogicalKeyboardKey.f11);
        await _frames(tester);
        expect(host.fullscreen, isTrue);
        expect(find.byKey(const ValueKey('directory.docked')), findsOneWidget);
        expect(find.byTooltip('隐藏信息 · I'), findsOneWidget);
        expect(find.byTooltip('退出全屏 · F11'), findsOneWidget);
        expect(find.byType(ViewerBottomBar), findsOneWidget);
        expect(tester.getRect(find.byType(ZoomableViewport)), normalRect);
        expect(
          tester.state(find.byType(ZoomableViewport)),
          same(normalViewport),
        );
        expect(
          tester
              .widget<AnimatedOpacity>(
                find.byKey(const ValueKey('viewer-top-bar')),
              )
              .opacity,
          1,
        );
        await _capture(tester, '${dark ? 'dark' : 'light'}-fullscreen');
        await _borderless(tester);
        expect(host.fullscreen, isTrue);
        expect(find.byType(ChapterDirectoryTree), findsNothing);
        expect(find.byType(ViewerBottomBar), findsNothing);
        expect(find.byTooltip('隐藏信息 · I'), findsNothing);
        expect(
          tester.state(find.byType(ZoomableViewport)),
          same(normalViewport),
        );
        expect(
          tester
              .widget<AnimatedOpacity>(
                find.byKey(const ValueKey('viewer-top-bar')),
              )
              .opacity,
          0,
        );
        await _capture(
          tester,
          '${dark ? 'dark' : 'light'}-borderless-fullscreen',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.f11);
        await _frames(tester);
        expect(host.fullscreen, isFalse);
        expect(host.calls, contains('setAsFrameless'));
        expect(find.byType(ViewerBottomBar), findsNothing);
        await _capture(tester, '${dark ? 'dark' : 'light'}-borderless-window');
        if (Platform.environment['BORDERLESS_CAPTURE_DIR'] != null) {
          tester.view.physicalSize = const Size(440, 800);
          await _frames(tester);
          await _capture(tester, '${dark ? 'dark' : 'light'}-narrow');
          final hover = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await hover.addPointer(location: const Offset(220, 300));
          await hover.moveTo(const Offset(220, 20));
          await _frames(tester);
          await _capture(tester, '${dark ? 'dark' : 'light'}-narrow-toolbar');
          await hover.removePointer();
          tester.view.physicalSize = const Size(1280, 800);
          await _frames(tester);
        }
        // Thumbnails can reopen temporarily; directory stays reachable from
        // the context menu while the status bar is hidden in borderless mode.
        await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
        await _frames(tester);
        await tester.tapAt(
          const Offset(640, 300),
          buttons: kSecondaryMouseButton,
        );
        await _frames(tester);
        await tester.tap(find.text('展开目录面板'));
        await _frames(tester);
        expect(find.byKey(const ValueKey('directory.barrier')), findsOneWidget);
        final temporary = tester.widget<ChapterDirectoryTree>(
          find.byType(ChapterDirectoryTree),
        );
        expect(temporary.pinned, isFalse);
        tester
            .widget<DirectoryPanelRegion>(find.byType(DirectoryPanelRegion))
            .onWidthChanged(480);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('directory.pin')));
        await tester.pump();
        expect(
          tester
              .widget<ChapterDirectoryTree>(find.byType(ChapterDirectoryTree))
              .pinned,
          isTrue,
        );
        await _borderless(tester);
        expect(find.byTooltip('全屏 · F11'), findsOneWidget);
        expect(
          tester.state(find.byType(ZoomableViewport)),
          same(normalViewport),
        );
        expect(
          tester.state(find.byType(ChapterDirectoryTree)),
          same(normalDirectory),
        );
        expect(
          tester.element(find.byType(ViewerBottomBar)),
          same(normalThumbnails),
        );
        expect(list.controller!.offset, closeTo(100, 1));
        expect(
          tester
              .getSize(find.byKey(const ValueKey('directory.sizedPanel')))
              .width,
          normalWidth,
        );
        expect(find.byTooltip('隐藏信息 · I'), findsOneWidget);
        expect(host.calls, contains('setTitleBarStyle'));
        final saved = await tester.runAsync(
          () => ViewerSettings.load(store: host.store),
        );
        expect(saved!.pinDirectoryPanel, isTrue);
        expect(saved.showDirectoryPanel, isTrue);
        expect(saved.directoryPanelWidth, 360);
        expect(saved.toolbarMode, ToolbarMode.normal);
        await _capture(tester, '${dark ? 'dark' : 'light'}-restored');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'borderless and fullscreen preserve animation and active auto advance',
    (tester) async {
      final host = await _open(
        tester,
        animated: true,
        settings: const ViewerSettings(
          showDirectoryPanel: false,
          animationControlsMode: AnimationControlsMode.always,
          watchFolderChanges: false,
          autoPlay: AutoPlaySettings(intervals: {ViewerMode.single: 60}),
        ),
      );
      final animation = tester
          .widget<AnimationPlaybackBar>(find.byType(AnimationPlaybackBar))
          .controller;
      await _wait(tester, () => animation.ready);
      await tester.tap(find.byTooltip('开始自动播放 · F6'));
      await _frames(tester);
      final auto = tester
          .widget<AutoPlayStatusIndicator>(find.byType(AutoPlayStatusIndicator))
          .controller;
      final remaining = auto.remainingSeconds;
      await _borderless(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await _frames(tester);
      expect(host.fullscreen, isTrue);
      expect(auto.playing, isTrue);
      expect(auto.remainingSeconds, lessThanOrEqualTo(remaining));
      expect(
        tester
            .widget<AnimationPlaybackBar>(find.byType(AnimationPlaybackBar))
            .controller,
        same(animation),
      );
      expect(animation.playing, isTrue);
      await _borderless(tester);
      expect(host.fullscreen, isTrue);
      expect(find.byType(ViewerBottomBar), findsOneWidget);
      expect(find.byTooltip('退出全屏 · F11'), findsOneWidget);
      expect(auto.playing, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _frames(tester);
      expect(auto.active, isFalse);
      expect(host.fullscreen, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _frames(tester);
      expect(host.fullscreen, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'toolbar, keyboard focus and context menu work in borderless mode',
    (tester) async {
      await _open(
        tester,
        settings: const ViewerSettings(
          showDirectoryPanel: false,
          watchFolderChanges: false,
        ),
      );
      await tester.tap(find.byTooltip('进入无边框模式 · Ctrl+Shift+F'));
      await _frames(tester);
      expect(find.byType(ViewerBottomBar), findsNothing);
      final exit = find.byTooltip('退出无边框模式 · Ctrl+Shift+F');
      Focus.of(tester.element(exit)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _frames(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('viewer-top-bar')),
            )
            .opacity,
        1,
      );
      await tester.tapAt(const Offset(640, 300));
      await _frames(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(640, 300));
      await mouse.moveTo(const Offset(640, 20));
      await _frames(tester);
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('viewer-top-bar')),
            )
            .opacity,
        1,
      );
      await mouse.moveTo(const Offset(640, 300));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('viewer-top-bar')),
            )
            .opacity,
        0,
      );
      await tester.tapAt(
        const Offset(640, 300),
        buttons: kSecondaryMouseButton,
      );
      await _frames(tester);
      expect(find.text('进入无边框模式'), findsNothing);
      expect(find.text('退出无边框模式'), findsNothing);
      await tester.ensureVisible(find.text('显示信息'));
      await tester.tap(find.text('显示信息'));
      await _frames(tester);
      expect(find.byKey(const ValueKey('viewer.infoOverlay')), findsOneWidget);
      await _borderless(tester);
      expect(find.byKey(const ValueKey('viewer.infoOverlay')), findsNothing);
      expect(find.byTooltip('显示信息 · I'), findsOneWidget);
      expect(find.byType(ViewerBottomBar), findsOneWidget);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'native fullscreen events preserve floating preferences and hidden thumbnails',
    (tester) async {
      await _open(
        tester,
        settings: const ViewerSettings(
          showDirectoryPanel: false,
          toolbarMode: ToolbarMode.floating,
          showBottomBar: false,
          watchFolderChanges: false,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await _frames(tester);
      final window = tester.state(find.byType(ViewerPage)) as WindowListener;
      window.onWindowEnterFullScreen();
      await tester.pump();
      expect(find.byType(ViewerBottomBar), findsNothing);
      await _borderless(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await _frames(tester);
      expect(find.byType(ViewerBottomBar), findsOneWidget);
      window.onWindowLeaveFullScreen();
      await _frames(tester);
      expect(find.byType(ViewerBottomBar), findsOneWidget);
      await _borderless(tester);
      expect(find.byType(ViewerBottomBar), findsNothing);
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('viewer-top-bar')),
            )
            .opacity,
        0,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _Host {
  _Host(this.store);
  final AppConfigStore store;
  bool fullscreen = false;
  final calls = <String>[];
}

Future<_Host> _open(
  WidgetTester tester, {
  bool dark = true,
  bool animated = false,
  ViewerSettings settings = const ViewerSettings(
    pinDirectoryPanel: true,
    browseMode: FolderBrowseMode.recursiveFolders,
    watchFolderChanges: false,
  ),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final dir = Directory.systemTemp.createTempSync('borderless-viewer-');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      /* Decoder handle. */
    }
  });
  final ext = animated ? 'gif' : 'png';
  for (var i = 1; i <= 2; i++) {
    File('testdata/formats/format_${animated ? 'animated' : 'static'}.$ext')
        .copySync('${dir.path}/0$i.$ext');
  }
  if (settings.browseMode.isRecursive) {
    for (var i = 0; i < 24; i++) {
      final child = Directory(
        '${dir.path}/chapter-${i.toString().padLeft(2, '0')}',
      )..createSync();
      File('testdata/formats/format_static.png')
          .copySync('${child.path}/01.png');
    }
  }
  final host = _Host(AppConfigStore(filePath: '${dir.path}/preferences.json'));
  File(host.store.filePath).writeAsStringSync(
    jsonEncode({
      'schemaVersion': ViewerSettings.configSchemaVersion,
      'settings': {
        'pinDirectoryPanel': settings.pinDirectoryPanel,
        'directoryPanelWidth': settings.directoryPanelWidth,
        'toolbarMode': settings.toolbarMode.name,
      },
    }),
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('window_manager'), (
        call,
      ) async {
        host.calls.add(call.method);
        if (call.method == 'isFullScreen') return host.fullscreen;
        if (call.method == 'setFullScreen') {
          host.fullscreen =
              (call.arguments as Map<Object?, Object?>)['isFullScreen']!
                  as bool;
        }
        if (['isMaximized', 'isAlwaysOnTop'].contains(call.method)) {
          return false;
        }
        return null;
      });
  var theme = dark ? AppTheme.dark() : AppTheme.light();
  if (Platform.environment['BORDERLESS_CAPTURE_DIR'] != null) {
    await tester.runAsync(() async {
      for (final (family, path) in [
        ('BorderlessReview', windowsFontPath('msyh.ttc')),
        (
          'packages/fluentui_system_icons/FluentSystemIcons-Regular',
          'packages/fluentui_system_icons/fonts/FluentSystemIcons-Regular.ttf',
        ),
        (
          'packages/fluentui_system_icons/FluentSystemIcons-Filled',
          'packages/fluentui_system_icons/fonts/FluentSystemIcons-Filled.ttf',
        ),
      ]) {
        await (FontLoader(family)..addFont(loadReviewFontData(path))).load();
      }
    });
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'BorderlessReview'),
    );
  }
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('borderless.capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh'),
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ViewerPage(
          initialPath: '${dir.path}/01.$ext',
          initialSettings: settings,
          configStore: host.store,
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
    () =>
        find.byType(ZoomableViewport).evaluate().isNotEmpty &&
        find.text('01.$ext').evaluate().isNotEmpty,
  );
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
  await _frames(tester);
  return host;
}

Future<void> _borderless(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await _frames(tester);
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 3)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 120; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    if (ready()) return;
  }
  expect(ready(), isTrue);
}

Future<void> _capture(WidgetTester tester, String name) async {
  final capture = Platform.environment['BORDERLESS_CAPTURE_DIR'];
  if (capture == null) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('borderless.capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$capture/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
