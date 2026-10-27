import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as bitmap;
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/archive_service.dart';
import 'package:shen_view/src/application/viewer_controller.dart';
import 'package:shen_view/src/domain/comic_layout_direction.dart';
import 'package:shen_view/src/domain/folder_browse_mode.dart';
import 'package:shen_view/src/domain/viewer_mode.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/animation_playback_bar.dart';
import 'package:shen_view/src/presentation/auto_play_status.dart';
import 'package:shen_view/src/presentation/chapter_directory_tree.dart';
import 'package:shen_view/src/presentation/components/app_file_name_editor.dart';
import 'package:shen_view/src/presentation/comic_strip_viewport.dart';
import 'package:shen_view/src/presentation/grid_overview.dart';
import 'package:shen_view/src/presentation/settings_page.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_bottom_bar.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';
import 'package:shen_view/src/presentation/zoomable_viewport.dart';

import 'support/style_review_fonts.dart';

const _capture = ValueKey('keyboard.capture');

void main() {
  String? copiedText;
  var fullscreen = false;
  setUp(() {
    copiedText = null;
    fullscreen = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (
      call,
    ) async {
      if (call.method == 'setFullScreen') {
        fullscreen = (call.arguments as Map)['isFullScreen'] as bool;
      }
      if (call.method == 'isFullScreen') return fullscreen;
      if (['isMaximized', 'isAlwaysOnTop'].contains(call.method)) return false;
      return null;
    });
  });

  testWidgets(
    'reading shortcuts change modes, zoom, pages and lock independently',
    (tester) async {
      await _open(tester);
      final controller = _controller(tester);
      await _press(tester, LogicalKeyboardKey.pageDown);
      expect(controller.currentIndex, 1);
      await _press(tester, LogicalKeyboardKey.end, control: true);
      expect(controller.currentIndex, 5);
      await _press(tester, LogicalKeyboardKey.home, control: true);
      expect(controller.currentIndex, 0);
      await _press(tester, LogicalKeyboardKey.keyK, control: true);
      await _press(tester, LogicalKeyboardKey.keyW);
      var viewport = tester.widget<ZoomableViewport>(
        find.byType(ZoomableViewport),
      );
      expect(
        viewport.contentSize.width,
        closeTo(tester.getSize(find.byType(ZoomableViewport)).width, 1),
      );
      final scale = viewport.controller.value.getMaxScaleOnAxis();
      await _press(tester, LogicalKeyboardKey.equal, shift: true);
      expect(viewport.controller.value.getMaxScaleOnAxis(), greaterThan(scale));
      await _press(tester, LogicalKeyboardKey.digit0);
      viewport = tester.widget<ZoomableViewport>(find.byType(ZoomableViewport));
      expect(viewport.contentSize, const Size(400, 1800));
      await _press(tester, LogicalKeyboardKey.digit2, control: true);
      expect(
        tester.widget<ViewerBottomBar>(find.byType(ViewerBottomBar)).mode,
        ViewerMode.doublePage,
      );
      await _press(tester, LogicalKeyboardKey.arrowRight, shift: true);
      expect(controller.currentIndex, 1);
      await _press(tester, LogicalKeyboardKey.digit3, control: true);
      expect(
        tester.widget<ViewerBottomBar>(find.byType(ViewerBottomBar)).mode,
        ViewerMode.longImage,
      );
      await _press(tester, LogicalKeyboardKey.digit4, control: true);
      expect(find.byType(ComicStripViewport), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.digit1, control: true);
      expect(
        tester.widget<ViewerBottomBar>(find.byType(ViewerBottomBar)).mode,
        ViewerMode.single,
      );
      await _press(tester, LogicalKeyboardKey.keyG, control: true);
      expect(find.byType(GridOverview), findsNothing);
      await _press(tester, LogicalKeyboardKey.keyT, control: true, shift: true);
      expect(find.byType(ViewerBottomBar), findsOneWidget);
      await _close(tester);
    },
  );

  for (final direction in ComicLayoutDirection.values) {
    testWidgets(
      'page and boundary shortcuts scroll $direction without changing zoom',
      (tester) async {
        await _open(
          tester,
          tall: direction == ComicLayoutDirection.vertical,
          settings: ViewerSettings(
            showDirectoryPanel: false,
            watchFolderChanges: false,
            defaultViewerMode: ViewerMode.comic,
            comicLayoutDirection: direction,
          ),
        );
        await _wait(
          tester,
          () => tester
              .widget<ComicStripViewport>(find.byType(ComicStripViewport))
              .positionController!
              .layoutReady,
        );
        final viewport = tester.widget<ZoomableViewport>(
          find.byType(ZoomableViewport),
        );
        final transform = viewport.controller;
        final before = transform.value.clone();
        await _press(tester, LogicalKeyboardKey.pageDown);
        final delta =
            transform.value.getTranslation() - before.getTranslation();
        if (direction == ComicLayoutDirection.vertical) {
          expect(delta.y, lessThan(-100));
        } else if (direction == ComicLayoutDirection.horizontalLeftToRight) {
          expect(delta.x, lessThan(-100));
        } else {
          expect(delta.x, greaterThan(100));
        }
        expect(transform.value.getMaxScaleOnAxis(), before.getMaxScaleOnAxis());
        await _press(tester, LogicalKeyboardKey.end);
        final forward = direction == ComicLayoutDirection.horizontalRightToLeft
            ? 1.0
            : -1.0;
        expect(
          direction == ComicLayoutDirection.vertical
              ? viewport.commands!.remainingVerticalDistance(forward)
              : viewport.commands!.remainingHorizontalDistance(forward),
          closeTo(0, 0.1),
        );
        await _press(tester, LogicalKeyboardKey.home);
        expect(
          direction == ComicLayoutDirection.vertical
              ? viewport.commands!.remainingVerticalDistance(-forward)
              : viewport.commands!.remainingHorizontalDistance(-forward),
          closeTo(0, 0.1),
        );
        await _close(tester);
      },
    );
  }

  testWidgets(
    'long image page keys preserve the picture and reach exact bounds',
    (tester) async {
      await _open(
        tester,
        settings: const ViewerSettings(
          showDirectoryPanel: false,
          watchFolderChanges: false,
          defaultViewerMode: ViewerMode.longImage,
        ),
      );
      final c = _controller(tester);
      final viewport = tester.widget<ZoomableViewport>(
        find.byType(ZoomableViewport),
      );
      final before = viewport.controller.value.clone();
      await _press(tester, LogicalKeyboardKey.pageDown);
      expect(
        viewport.controller.value.getTranslation().y,
        lessThan(before.getTranslation().y),
      );
      expect(c.currentIndex, 0);
      await _press(tester, LogicalKeyboardKey.end);
      expect(viewport.commands!.remainingVerticalDistance(-1), closeTo(0, 0.1));
      await _press(tester, LogicalKeyboardKey.home);
      expect(viewport.commands!.remainingVerticalDistance(1), closeTo(0, 0.1));
      expect(
        viewport.controller.value.getMaxScaleOnAxis(),
        before.getMaxScaleOnAxis(),
      );
      await _close(tester);
    },
  );

  testWidgets(
    'grid files use selection, search preserves text, F2 focuses filename',
    (tester) async {
      await _open(tester);
      final controller = _controller(tester);
      await _press(tester, LogicalKeyboardKey.keyG);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      final selected = tester
          .widget<GridOverview>(find.byType(GridOverview))
          .selectedId;
      expect(selected, endsWith('02.png'));
      expect(controller.currentIndex, 0);
      await _press(tester, LogicalKeyboardKey.keyC, control: true, alt: true);
      expect(copiedText, selected);
      await _press(tester, LogicalKeyboardKey.delete);
      expect(find.textContaining('02.png', findRichText: true), findsWidgets);
      expect(
        find
            .textContaining('01.png', findRichText: true)
            .evaluate()
            .where((e) => e.findAncestorWidgetOfExactType<Dialog>() != null),
        isEmpty,
      );
      await tester.tap(find.text('取消'));
      await _press(tester, LogicalKeyboardKey.keyF, control: true);
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>(),
        isNotNull,
      );
      final search = find.descendant(
        of: find.byKey(const ValueKey('grid.search')),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, '03');
      await _press(tester, LogicalKeyboardKey.keyG);
      expect(find.byType(GridOverview), findsOneWidget);
      expect(tester.widget<TextField>(search).controller!.text, '03');
      await _press(tester, LogicalKeyboardKey.escape);
      await _press(tester, LogicalKeyboardKey.home, control: true);
      expect(
        tester.widget<GridOverview>(find.byType(GridOverview)).selectedId,
        endsWith('03.png'),
      );
      expect(controller.currentIndex, 0);
      await _press(tester, LogicalKeyboardKey.f2);
      final filename = find.descendant(
        of: find.byType(AppFileNameEditor),
        matching: find.byType(TextField),
      );
      await _wait(tester, () => filename.evaluate().isNotEmpty);
      expect(filename, findsOneWidget);
      expect(tester.widget<TextField>(filename).focusNode!.hasFocus, isTrue);
      expect(tester.widget<TextField>(filename).controller!.text, '03');
      await _press(tester, LogicalKeyboardKey.escape);
      await _close(tester);
    },
  );

  testWidgets(
    'directory focus preserves local keys and allows fullscreen and settings',
    (tester) async {
      await _open(tester);
      final controller = _controller(tester);
      await _press(tester, LogicalKeyboardKey.keyD);
      expect(find.byType(ChapterDirectoryTree), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.keyF, control: true);
      final field = find.descendant(
        of: find.byKey(const ValueKey('directory.search')),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      await tester.enterText(field, 'g');
      await _press(tester, LogicalKeyboardKey.keyG);
      expect(find.byType(GridOverview), findsNothing);
      expect(controller.currentIndex, 0);
      await _press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(ChapterDirectoryTree), findsNothing);
      await _press(tester, LogicalKeyboardKey.keyD);
      await _press(tester, LogicalKeyboardKey.keyF, control: true);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      await _press(tester, LogicalKeyboardKey.f11);
      expect(fullscreen, isTrue);
      await _press(tester, LogicalKeyboardKey.comma, control: true);
      await _wait(
        tester,
        () => find.byType(SettingsPage).evaluate().isNotEmpty,
      );
      expect(find.byType(SettingsPage), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await _wait(tester, () => find.byType(SettingsPage).evaluate().isEmpty);
      await _press(tester, LogicalKeyboardKey.escape);
      await _press(tester, LogicalKeyboardKey.keyF, control: true, shift: true);
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.keyD);
      await _press(tester, LogicalKeyboardKey.keyF, control: true);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      await tester.enterText(field, 'borderless');
      await _press(tester, LogicalKeyboardKey.escape);
      await _press(tester, LogicalKeyboardKey.keyF, control: true, shift: true);
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.keyD);
      await _press(tester, LogicalKeyboardKey.keyF, control: true);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      await tester.tap(find.byKey(const ValueKey('directory.pin')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('directory.resize')));
      final dividerFocus = tester.widget<Focus>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('directory.resize')),
              matching: find.byType(Focus),
            )
            .first,
      );
      expect(dividerFocus.focusNode!.hasFocus, isTrue);
      await _press(tester, LogicalKeyboardKey.delete);
      expect(find.byType(Dialog), findsNothing);
      expect(controller.currentIndex, 0);
      await _close(tester);
    },
  );

  testWidgets('chapter shortcuts and parent navigation stay within root', (
    tester,
  ) async {
    await _open(
      tester,
      chapters: true,
      settings: const ViewerSettings(
        showDirectoryPanel: false,
        watchFolderChanges: false,
        browseMode: FolderBrowseMode.recursiveFolders,
      ),
    );
    final c = _controller(tester);
    final root = c.folderPath;
    await _press(tester, LogicalKeyboardKey.bracketRight);
    await _wait(tester, () => c.currentEntry?.name == 'chapter1.png');
    await _press(tester, LogicalKeyboardKey.bracketRight);
    await _wait(tester, () => c.currentEntry?.name == 'chapter2.png');
    await _press(tester, LogicalKeyboardKey.bracketLeft);
    await _wait(tester, () => c.currentEntry?.name == 'chapter1.png');
    await _press(tester, LogicalKeyboardKey.arrowUp, alt: true);
    await _wait(tester, () => c.folderPath == root);
    await _press(tester, LogicalKeyboardKey.arrowUp, alt: true);
    expect(c.folderPath, root);
    await _close(tester);
  });

  testWidgets(
    'archive delete and rename are unavailable, animation and auto play stay separate',
    (tester) async {
      await _open(tester, archive: true, animated: true);
      await _press(tester, LogicalKeyboardKey.delete);
      expect(find.byType(Dialog), findsNothing);
      await _press(tester, LogicalKeyboardKey.f2);
      expect(find.byType(AppFileNameEditor), findsNothing);
      await _wait(
        tester,
        () => find.byType(AnimationPlaybackBar).evaluate().isNotEmpty,
      );
      final animation = tester
          .widget<AnimationPlaybackBar>(find.byType(AnimationPlaybackBar))
          .controller;
      await _wait(tester, () => animation.ready);
      await _press(tester, LogicalKeyboardKey.period);
      await _wait(tester, () => animation.frame == 1);
      expect(animation.playing, isFalse);
      await _press(tester, LogicalKeyboardKey.comma);
      await _wait(tester, () => animation.frame == 0);
      await _press(tester, LogicalKeyboardKey.space);
      expect(animation.playing, isTrue);
      expect(find.byType(AutoPlayStatusIndicator), findsNothing);
      await _press(tester, LogicalKeyboardKey.f6);
      final playback = tester
          .widget<AutoPlayStatusIndicator>(find.byType(AutoPlayStatusIndicator))
          .controller;
      expect(playback.playing, isTrue);
      await _press(tester, LogicalKeyboardKey.f6);
      expect(playback.playing, isFalse);
      await _press(tester, LogicalKeyboardKey.f6, shift: true);
      expect(playback.active, isFalse);
      await _close(tester);
    },
  );

  for (final width in [1280.0, 440.0]) {
    for (final dark in [false, true]) {
      for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
        testWidgets(
          'shortcut menu and settings render at $width dark=$dark $platform',
          (tester) async {
            await loadStyleReviewFonts(tester);
            if (Platform.isWindows) {
              await tester.runAsync(() async {
                await (FontLoader('Segoe UI Symbol')..addFont(
                      File(windowsFontPath('seguisym.ttf'))
                          .readAsBytes()
                          .then(ByteData.sublistView),
                    ))
                    .load();
              });
            }
            await _open(tester, width: width, dark: dark, platform: platform);
            final primary = platform == TargetPlatform.macOS ? '⌘' : 'Ctrl';
            final alt = platform == TargetPlatform.macOS ? '⌥' : 'Alt';
            final fullscreen = platform == TargetPlatform.macOS
                ? '⌃+⌘+F'
                : 'F11';
            await tester.tapAt(
              Offset(width / 2, 220),
              buttons: kSecondaryMouseButton,
            );
            await _wait(tester, () => find.text('复制文件').evaluate().isNotEmpty);
            expect(find.text('$primary+Shift+O'), findsOneWidget);
            expect(find.text(fullscreen), findsOneWidget);
            final menuItems = tester.widgetList<MenuItemButton>(
              find.byType(MenuItemButton),
            );
            expect(
              menuItems.where((item) => item.onPressed != null),
              isNotEmpty,
            );
            for (final label in [
              '$primary+Shift+O',
              '$primary+Shift+S',
              '$primary+$alt+C',
              fullscreen,
            ]) {
              final text = find.text(label);
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(of: text, matching: find.byType(RichText)),
              );
              expect(
                paragraph.didExceedMaxLines,
                isFalse,
                reason: '$label is readable at $width',
              );
            }
            final copyRect = tester.getRect(find.text('复制文件'));
            final deleteRect = tester.getRect(find.text('删除'));
            expect(deleteRect.left - copyRect.right, greaterThanOrEqualTo(8));
            await _save(tester, 'menu-$width-$dark-${platform.name}');
            await _press(tester, LogicalKeyboardKey.escape);
            await tester.tapAt(const Offset(12, 180));
            await _press(
              tester,
              LogicalKeyboardKey.comma,
              control: platform != TargetPlatform.macOS,
              meta: platform == TargetPlatform.macOS,
            );
            await _wait(
              tester,
              () => find.byType(SettingsPage).evaluate().isNotEmpty,
            );
            await tester.pumpAndSettle();
            await tester.ensureVisible(
              find.byKey(const ValueKey('settings.nav.shortcuts')),
            );
            await tester.tap(
              find.byKey(const ValueKey('settings.nav.shortcuts')),
            );
            await tester.pumpAndSettle();
            final action = tester.getRect(
              find.text('打开图片或压缩包', findRichText: true),
            );
            final binding = tester.getRect(
              find.text('$primary+O', findRichText: true),
            );
            if (width >= 600) {
              expect(binding.left - action.right, greaterThanOrEqualTo(12));
            } else {
              expect(binding.top - action.bottom, greaterThanOrEqualTo(6));
            }
            await _save(tester, 'settings-files-$width-$dark-${platform.name}');
            await tester.ensureVisible(
              find.text('开始或暂停自动播放', findRichText: true),
            );
            await tester.pumpAndSettle();
            await _save(
              tester,
              'settings-playback-$width-$dark-${platform.name}',
            );
            await tester.ensureVisible(find.text('切换全屏', findRichText: true));
            await tester.pumpAndSettle();
            expect(find.text(fullscreen), findsOneWidget);
            await _save(
              tester,
              'settings-windows-$width-$dark-${platform.name}',
            );
            expect(tester.takeException(), isNull);
            await _close(tester);
          },
        );
      }
    }
  }
}

ViewerController _controller(WidgetTester tester) =>
    tester.widget<ViewerBottomBar>(find.byType(ViewerBottomBar)).controller;

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
  bool alt = false,
  bool meta = false,
}) async {
  final modifiers = [
    if (control) LogicalKeyboardKey.controlLeft,
    if (shift) LogicalKeyboardKey.shiftLeft,
    if (alt) LogicalKeyboardKey.altLeft,
    if (meta) LogicalKeyboardKey.metaLeft,
  ];
  for (final modifier in modifiers) {
    await tester.sendKeyDownEvent(modifier);
  }
  await tester.sendKeyEvent(key);
  for (final modifier in modifiers.reversed) {
    await tester.sendKeyUpEvent(modifier);
  }
  await tester.pump(const Duration(milliseconds: 30));
}

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
  }
  expect(ready(), isTrue);
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _open(
  WidgetTester tester, {
  bool animated = false,
  bool tall = true,
  bool archive = false,
  bool chapters = false,
  bool dark = true,
  double width = 1280,
  TargetPlatform platform = TargetPlatform.windows,
  ViewerSettings settings = const ViewerSettings(
    showDirectoryPanel: false,
    watchFolderChanges: false,
  ),
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final dir = Directory.systemTemp.createTempSync('viewer-keyboard-');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      /* Decoder lease may still be closing. */
    }
  });
  final bytes = animated
      ? File('testdata/formats/format_animated.gif').readAsBytesSync()
      : bitmap.encodePng(
          bitmap.fill(
            bitmap.Image(width: tall ? 400 : 1200, height: tall ? 1800 : 700),
            color: bitmap.ColorRgb8(45, 120, 160),
          ),
        );
  final extension = animated ? 'gif' : 'png';
  for (var i = 1; i <= 6; i++) {
    File('${dir.path}/0$i.$extension').writeAsBytesSync(bytes);
  }
  if (chapters) {
    for (var i = 1; i <= 2; i++) {
      final folder = Directory('${dir.path}/chapter$i')..createSync();
      File('${folder.path}/chapter$i.png').writeAsBytesSync(bytes);
    }
  }
  var initialPath = '${dir.path}/01.$extension';
  if (archive) {
    final contents = Archive();
    for (var i = 1; i <= 3; i++) {
      contents.addFile(ArchiveFile('0$i.$extension', bytes.length, bytes));
    }
    initialPath = '${dir.path}/book.cbz';
    File(initialPath).writeAsBytesSync(ZipEncoder().encode(contents));
  }
  // Windows captures use installed fonts while retaining macOS key mappings.
  final fontPlatform = Platform.isWindows ? TargetPlatform.windows : platform;
  final theme = dark
      ? AppTheme.dark(platform: fontPlatform)
      : AppTheme.light(platform: fontPlatform);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _capture,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: theme.copyWith(
          platform: platform,
          textTheme: Platform.isWindows
              ? theme.textTheme.apply(
                  fontFamilyFallback: const [
                    'Segoe UI Symbol',
                    'Microsoft YaHei UI',
                  ],
                )
              : theme.textTheme,
        ),
        home: ViewerPage(
          initialPath: initialPath,
          initialSettings: settings.copyWith(animationAutoPlay: false),
          configStore: AppConfigStore(filePath: '${dir.path}/settings.json'),
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
        find.byType(ViewerBottomBar).evaluate().isNotEmpty &&
        _controller(tester).currentEntry != null,
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
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _save(WidgetTester tester, String name) async {
  final dir = Platform.environment['KEYBOARD_CAPTURE_DIR'];
  if (dir == null) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$dir/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
