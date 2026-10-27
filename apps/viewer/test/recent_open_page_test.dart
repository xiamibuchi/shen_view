import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as paths;
import 'package:shen_view/src/application/viewer_controller.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/archive_service.dart';
import 'package:shen_view/src/application/decoder_registry.dart';
import 'package:shen_view/src/application/recent_open_store.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/components/app_switch.dart';
import 'package:shen_view/src/presentation/recent_open_page.dart';
import 'package:shen_view/src/presentation/grid_overview.dart';
import 'package:shen_view/src/presentation/chapter_directory_tree.dart';
import 'package:shen_view/src/presentation/settings_page.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';
import 'package:shen_view/src/presentation/viewer_bottom_bar.dart';

import 'support/style_review_fonts.dart';

const capture = ValueKey('recent.capture');

Future<void> _pump(WidgetTester tester, Widget widget) async {
  await tester.runAsync(() => tester.pumpWidget(widget));
}

Future<void> _flush(WidgetTester tester, ViewerController controller) async {
  var flushed = false;
  await tester.runAsync(() async {
    unawaited(controller.flushPersistence().then((_) => flushed = true));
  });
  await _wait(tester, () => flushed);
}

void main() {
  final windowCalls = <MethodCall>[];
  setUp(() {
    windowCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          windowCalls.add(call);
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

  for (final dark in [false, true]) {
    for (final width in [440.0, 1200.0]) {
      testWidgets('recent list search, remove, clear and layout ($dark, $width)', (
        tester,
      ) async {
        final (root, config, store) = await _fixture(tester);
        addTearDown(
          () => tester.runAsync(() async {
            await root.delete(recursive: true);
          }),
        );
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await _pump(
          tester,
          _host(
            RecentOpenPage(
              store: store,
              enabled: true,
              limit: 20,
              onOpenFile: () {},
              onOpenFolder: () {},
              onOpenPath: (_) async {},
            ),
            dark: dark,
          ),
        );
        await _wait(tester, () => find.text('样例图片.png').evaluate().isNotEmpty);
        // Check painted content anchors, not just the enclosing button boxes.
        final headingX = tester.getTopLeft(find.text('开始')).dx;
        final actions = [
          find.byKey(const ValueKey('recent.start.openFile')),
          find.byKey(const ValueKey('recent.start.openFolder')),
        ];
        final icons = actions
            .map(
              (action) =>
                  find.descendant(of: action, matching: find.byType(Icon)),
            )
            .toList();
        for (final icon in icons) {
          expect(tester.getTopLeft(icon).dx, closeTo(headingX, 0.1));
        }
        expect(
          tester.getTopLeft(find.text('打开图片或压缩包')).dx,
          tester.getTopLeft(find.text('打开文件夹')).dx,
        );
        expect(
          tester.getRect(actions.last).top,
          greaterThanOrEqualTo(tester.getRect(actions.first).bottom + 8),
        );
        await _capture(
          tester,
          '../../artifacts/recent-open/list-${dark ? 'dark' : 'light'}-${width.toInt()}.png',
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: tester.getCenter(actions.first));
        await mouse.moveTo(tester.getCenter(actions.first));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(icons.first).dx, closeTo(headingX, 0.1));
        final actionText = tester.widget<RichText>(
          find.descendant(
            of: find.text('打开图片或压缩包'),
            matching: find.byType(RichText),
          ),
        );
        expect(actionText.text.style!.decoration, TextDecoration.underline);
        expect(
          actionText.text.style!.fontFamily,
          Theme.of(tester.element(actions.first))
              .textTheme
              .bodyMedium!
              .fontFamily,
        );
        expect(
          actionText.text.style!.color,
          ViewerThemeTokens.of(tester.element(actions.first)).accentStrong,
        );
        expect(
          tester
              .widget<Material>(
                find
                    .descendant(
                      of: actions.first,
                      matching: find.byType(Material),
                    )
                    .first,
              )
              .color,
          Colors.transparent,
        );
        await _capture(
          tester,
          '../../artifacts/style-followup/welcome-hover-${dark ? 'dark' : 'light'}-${width.toInt()}.png',
        );
        await mouse.removePointer();
        expect(tester.takeException(), isNull);
        await tester.enterText(
          find.descendant(
            of: find.byKey(const ValueKey('recent.search')),
            matching: find.byType(EditableText),
          ),
          '漫画',
        );
        await tester.pumpAndSettle();
        expect(find.text('漫画.cbz'), findsOneWidget);
        expect(find.text('样例图片.png'), findsNothing);
        await tester.tap(find.byTooltip('清空搜索'));
        await tester.pumpAndSettle();
        expect(find.text('样例图片.png'), findsOneWidget);
        final searchEditor = tester.widget<EditableText>(
          find.descendant(
            of: find.byKey(const ValueKey('recent.search')),
            matching: find.byType(EditableText),
          ),
        );
        expect(searchEditor.controller.text, isEmpty);
        expect(searchEditor.focusNode.hasFocus, isTrue);
        // A missing entry remains in the list and can be retried or removed.
        await tester.runAsync(() => tester.tap(find.text('样例图片.png')));
        await _wait(
          tester,
          () => find.textContaining('找不到此项目').evaluate().isNotEmpty,
        );
        expect(find.textContaining('找不到此项目'), findsOneWidget);
        await tester.runAsync(
          () => tester.tap(find.byTooltip('从最近打开移除').first),
        );
        await _wait(tester, () => find.text('样例图片.png').evaluate().isEmpty);
        await tester.runAsync(
          () => tester.tap(find.byKey(const ValueKey('recent.clear'))),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(find.text('漫画.cbz'), findsOneWidget);
        await tester.runAsync(
          () => tester.tap(find.byKey(const ValueKey('recent.clear'))),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() => tester.tap(find.text('清空').last));
        await _wait(
          tester,
          () => find.text('还没有最近打开的项目').evaluate().isNotEmpty,
        );
        await _capture(
          tester,
          '../../artifacts/recent-open/empty-${dark ? 'dark' : 'light'}-${width.toInt()}.png',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final dark in [false, true]) {
    for (final width in [440.0, 1200.0]) {
      testWidgets(
        'new-window option opens list without restoring the old folder ($dark, $width)',
        (tester) async {
          final (root, config, _) = await _fixture(tester);
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.runAsync(
            () => config.update((value) {
              value['session'] = {'recentFolder': root.path};
              return value;
            }),
          );
          await _pump(
            tester,
            _host(
              ViewerPage(
                configStore: config,
                initialSettings: const ViewerSettings(
                  showDirectoryPanel: false,
                  openRecentOnNewWindow: true,
                ),
                archiveService: ArchiveService(
                  cachePolicy: ArchiveCachePolicy(
                    directory: Directory('${root.path}/cache'),
                  ),
                ),
              ),
              dark: dark,
            ),
          );
          await _wait(
            tester,
            () => find.byType(RecentOpenPage).evaluate().isNotEmpty,
          );
          expect(find.byType(RecentOpenPage), findsOneWidget);
          expect(find.byType(Scaffold), findsOneWidget);
          expect(find.text('返回查看器'), findsNothing);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
          await tester.pump();
          expect(find.byType(RecentOpenPage), findsOneWidget);
          expect(find.byType(GridOverview), findsNothing);
          await _wait(
            tester,
            () => find.text('样例图片.png').evaluate().isNotEmpty,
          );
          await _capture(
            tester,
            '../../artifacts/recent-open/welcome-window-${dark ? 'dark' : 'light'}-${width.toInt()}.png',
          );
          expect((await tester.runAsync(config.read))!['session'], {
            'recentFolder': root.path,
          });
          if (width == 1200) {
            await _expectGridAvailability(tester, enabled: false);
            await tester.tap(find.byTooltip(RegExp('^查看方式 · ')));
            await tester.pumpAndSettle();
            await _capture(
              tester,
              dark
                  ? '../../artifacts/recent-open/grid-disabled-dark.png'
                  : '../../artifacts/recent-open/grid-disabled-light.png',
            );
          }
          await _pump(tester, const SizedBox.shrink());
          await tester.runAsync(() async {
            await root.delete(recursive: true);
          });
        },
      );
    }
  }

  for (final toolbar in [ToolbarMode.normal, ToolbarMode.floating]) {
    testWidgets('pinned empty directory preserves the canvas with $toolbar', (
      tester,
    ) async {
      final (root, config, _) = await _fixture(tester);
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(
        tester,
        _host(
          ViewerPage(
            configStore: config,
            initialSettings: ViewerSettings(
              pinDirectoryPanel: true,
              directoryPanelWidth: 280,
              toolbarMode: toolbar,
            ),
            archiveService: ArchiveService(
              cachePolicy: ArchiveCachePolicy(
                directory: Directory('${root.path}/cache'),
              ),
            ),
          ),
        ),
      );
      await _wait(
        tester,
        () =>
            find.byKey(const ValueKey('directory.empty')).evaluate().isNotEmpty,
      );
      final canvas = find.byKey(const ValueKey('viewer.content'));
      final left = tester.getRect(canvas).left;
      expect(left, 280);
      expect(tester.getRect(canvas).bottom, 760);
      final titleBar = tester.getRect(
        find.byKey(const ValueKey('viewer-top-bar')),
      );
      expect(titleBar.left, 0);
      expect(titleBar.width, 1200);
      expect(
        tester.getRect(find.byKey(const ValueKey('directory.search'))).top,
        greaterThanOrEqualTo(titleBar.bottom),
      );
      expect(
        tester
            .getRect(find.byKey(const ValueKey('directory.sizedPanel')))
            .bottom,
        760,
      );
      expect(find.text('尚未打开文件夹'), findsOneWidget);
      await _wait(tester, () => find.text('样例图片.png').evaluate().isNotEmpty);
      await _capture(
        tester,
        '../../artifacts/style-followup/directory-no-folder-${toolbar.name}.png',
      );
      final controller = tester
          .widget<ChapterDirectoryTree>(find.byType(ChapterDirectoryTree))
          .controller;
      final empty = Directory('${root.path}/empty')..createSync();
      await tester.runAsync(() async {
        unawaited(controller.openFolder(empty.path));
      });
      await _wait(
        tester,
        () => controller.folderPath == empty.path && !controller.isIndexing,
      );
      await _wait(
        tester,
        () => find
            .byKey(const ValueKey('directory.noChildren'))
            .evaluate()
            .isNotEmpty,
      );
      expect(find.byKey(const ValueKey('directory.empty')), findsNothing);
      expect(tester.getRect(canvas).left, left);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('directory.sizedPanel')))
            .width,
        280,
      );
      await _capture(
        tester,
        '../../artifacts/style-followup/directory-empty-folder-${toolbar.name}.png',
      );
      for (final width in [440.0, 1200.0]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpAndSettle();
        final expected = width == 440 ? 240.0 : 280.0;
        expect(tester.getRect(canvas).left, expected);
        expect(tester.getRect(canvas).bottom, 760);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('directory.sizedPanel')))
              .width,
          expected,
        );
        expect(
          find.byKey(const ValueKey('directory.noChildren')),
          findsOneWidget,
        );
        await _capture(
          tester,
          '../../artifacts/style-followup/directory-empty-${toolbar.name}-${width.toInt()}.png',
        );
        expect(tester.takeException(), isNull);
      }
      expect(tester.takeException(), isNull);
      await _flush(tester, controller);
      await _pump(tester, const SizedBox.shrink());
      var persisted = false;
      await tester.runAsync(() async {
        unawaited(
          config.update((value) => value).then((_) => persisted = true),
        );
      });
      await _wait(tester, () => persisted);
      await tester.runAsync(() => root.delete(recursive: true));
    });
  }

  testWidgets('explicit image takes priority over new-window recent list', (
    tester,
  ) async {
    final (root, config, _) = await _fixture(tester);
    final image = (await tester.runAsync(
      () =>
          File('testdata/formats/format_static.webp')
              .copy('${root.path}/sample.webp'),
    ))!;
    await _pump(
      tester,
      _host(
        ViewerPage(
          configStore: config,
          initialPath: image.path,
          archiveService: ArchiveService(
            cachePolicy: ArchiveCachePolicy(
              directory: Directory('${root.path}/cache'),
            ),
          ),
          initialSettings: const ViewerSettings(
            showDirectoryPanel: false,
            openRecentOnNewWindow: true,
          ),
        ),
      ),
    );
    await _wait(
      tester,
      () =>
          find.byType(ViewerBottomBar).evaluate().isNotEmpty &&
          tester
                  .widget<ViewerBottomBar>(find.byType(ViewerBottomBar))
                  .controller
                  .currentEntry !=
              null,
    );
    expect(find.byType(RecentOpenPage), findsNothing);
    await _wait(tester, () {
      try {
        final saved = jsonDecode(
          File(config.filePath).readAsStringSync(),
        ) as Map<String, dynamic>;
        return (saved['recentOpen'] as List).any(
          (entry) => (entry as Map)['path'].toString().endsWith('sample.webp'),
        );
      } on FileSystemException {
        return false;
      } on FormatException {
        return false;
      }
    });
    await _pump(tester, const SizedBox.shrink());
    await tester.runAsync(() async {
      await root.delete(recursive: true);
    });
  });

  testWidgets('blank canvas and both navigation edges open recent submenu', (
    tester,
  ) async {
    final (root, config, store) = await _fixture(tester);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final empty = Directory('${root.path}/empty')..createSync();
    final image = await tester.runAsync(
      () =>
          File('testdata/formats/format_static.webp')
              .copy('${root.path}/open-from-menu.webp'),
    );
    await tester.runAsync(
      () => store.record(paths.normalize(image!.path), RecentOpenKind.image),
    );
    await _pump(
      tester,
      _host(
        ViewerPage(
          initialPath: empty.path,
          configStore: config,
          initialSettings: const ViewerSettings(showDirectoryPanel: false),
          archiveService: ArchiveService(
            cachePolicy: ArchiveCachePolicy(
              directory: Directory('${root.path}/cache'),
            ),
          ),
        ),
      ),
    );
    await _wait(
      tester,
      () =>
          find.byType(ViewerBottomBar).evaluate().isNotEmpty &&
          tester
                  .widget<ViewerBottomBar>(find.byType(ViewerBottomBar))
                  .controller
                  .folderPath !=
              null,
    );
    final controller = tester
        .widget<ViewerBottomBar>(find.byType(ViewerBottomBar))
        .controller;
    await _expectGridAvailability(tester, enabled: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(find.byType(GridOverview), findsNothing);
    final bounds = tester.getRect(find.byKey(const ValueKey('viewer.content')));
    for (final point in [
      bounds.topLeft + const Offset(180, 60),
      Offset(bounds.left + 20, bounds.center.dy),
      Offset(bounds.right - 20, bounds.center.dy),
    ]) {
      await tester.runAsync(
        () => tester.tapAt(point, buttons: kSecondaryMouseButton),
      );
      await _wait(tester, () => find.text('最近打开').evaluate().isNotEmpty);
      await tester.tapAt(bounds.center);
      await tester.pumpAndSettle();
    }
    await tester.runAsync(
      () => tester.tapAt(bounds.center, buttons: kSecondaryMouseButton),
    );
    await _wait(tester, () => find.text('最近打开').evaluate().isNotEmpty);
    final saveAs = tester.widget<MenuItemButton>(
      find.ancestor(
        of: find.text('另存为'),
        matching: find.byType(MenuItemButton),
      ),
    );
    expect(saveAs.onPressed, isNull);
    for (final label in ['复制文件', '删除', '打印', '另存为']) {
      expect(
        tester
            .widget<MenuItemButton>(
              find.ancestor(
                of: find.text(label),
                matching: find.byType(MenuItemButton),
              ),
            )
            .onPressed,
        isNull,
      );
    }
    final inactiveActionSpan =
        tester
            .getRect(
              find.ancestor(
                of: find.text('另存为'),
                matching: find.byType(MenuItemButton),
              ),
            )
            .right -
        tester
            .getRect(
              find.ancestor(
                of: find.text('复制文件'),
                matching: find.byType(MenuItemButton),
              ),
            )
            .left;
    expect(inactiveActionSpan, 256);
    final openRow = find.ancestor(
      of: find.text('打开图片'),
      matching: find.byType(MenuItemButton),
    );
    final recentIcon = find
        .descendant(
          of: find.ancestor(
            of: find.text('最近打开'),
            matching: find.byType(MenuItemButton),
          ),
          matching: find.byType(Icon),
        )
        .first;
    final openIcon = find
        .descendant(of: openRow, matching: find.byType(Icon))
        .first;
    expect(tester.getRect(recentIcon).left, tester.getRect(openIcon).left);
    expect(tester.getSize(recentIcon), tester.getSize(openIcon));
    expect(
      tester.getTopLeft(find.text('最近打开')).dx,
      tester.getTopLeft(find.text('打开图片')).dx,
    );
    await _capture(tester, '../../artifacts/style-followup/context-empty.png');
    await tester.tap(find.text('最近打开'));
    await _wait(
      tester,
      () => find
          .byKey(ValueKey(('recent.menu', paths.normalize(image!.path))))
          .evaluate()
          .isNotEmpty,
    );
    await _capture(
      tester,
      '../../artifacts/recent-open/context-recent-submenu.png',
    );
    await tester.runAsync(
      () => tester.tap(
        find.byKey(ValueKey(('recent.menu', paths.normalize(image!.path)))),
      ),
    );
    await _wait(
      tester,
      () => controller.currentEntry?.file.path == paths.normalize(image!.path),
    );
    expect(find.byType(RecentOpenPage), findsNothing);
    await _expectGridAvailability(tester, enabled: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(find.byType(GridOverview), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(find.byType(GridOverview), findsNothing);
    // Returning to the welcome screen disables grid even with retained images.
    await tester.runAsync(
      () => tester.tapAt(bounds.center, buttons: kSecondaryMouseButton),
    );
    await _wait(tester, () => find.text('最近打开').evaluate().isNotEmpty);
    expect(
      tester
          .widget<MenuItemButton>(
            find.ancestor(
              of: find.text('另存为'),
              matching: find.byType(MenuItemButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
    await _capture(
      tester,
      '../../artifacts/style-followup/context-save-as.png',
    );
    expect(
      tester
              .getRect(
                find.ancestor(
                  of: find.text('另存为'),
                  matching: find.byType(MenuItemButton),
                ),
              )
              .right -
          tester
              .getRect(
                find.ancestor(
                  of: find.text('复制文件'),
                  matching: find.byType(MenuItemButton),
                ),
              )
              .left,
      inactiveActionSpan,
    );
    await tester.tap(find.text('最近打开'));
    await _wait(tester, () => find.text('查看全部最近打开').evaluate().isNotEmpty);
    await tester.tap(find.text('查看全部最近打开'));
    await _wait(
      tester,
      () => find.byType(RecentOpenPage).evaluate().isNotEmpty,
    );
    expect(controller.entries, isNotEmpty);
    await _wait(
      tester,
      () => find.text('open-from-menu.webp').evaluate().isNotEmpty,
    );
    await _expectGridAvailability(tester, enabled: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(find.byType(RecentOpenPage), findsOneWidget);
    expect(find.byType(GridOverview), findsNothing);
    await tester.runAsync(
      () => tester.tapAt(
        bounds.topLeft + const Offset(40, 24),
        buttons: kSecondaryMouseButton,
      ),
    );
    await _wait(tester, () => find.text('另存为').evaluate().isNotEmpty);
    // Retained reading state must not enable image actions on the welcome page.
    for (final label in ['复制文件', '删除', '打印', '另存为']) {
      expect(
        tester
            .widget<MenuItemButton>(
              find.ancestor(
                of: find.text(label),
                matching: find.byType(MenuItemButton),
              ),
            )
            .onPressed,
        isNull,
      );
    }
    expect(find.text('置顶'), findsNothing);
    await _capture(
      tester,
      '../../artifacts/style-followup/context-welcome-retained-image.png',
    );
    await tester.tapAt(bounds.topRight - const Offset(20, -20));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    await _flush(tester, controller);
    await _pump(tester, const SizedBox.shrink());
    var persisted = false;
    await tester.runAsync(() async {
      unawaited(config.update((value) => value).then((_) => persisted = true));
    });
    await _wait(tester, () => persisted);
    await tester.runAsync(() => root.delete(recursive: true));
  });

  testWidgets(
    'close releases native prevent-close even when saving is blocked',
    (tester) async {
      final (root, _, _) = await _fixture(tester);
      final config = _BlockedConfigStore('${root.path}/close.json');
      final image = await tester.runAsync(
        () =>
            File('testdata/formats/format_static.webp')
                .copy('${root.path}/close.webp'),
      );
      await _pump(
        tester,
        _host(
          ViewerPage(
            initialPath: image!.path,
            configStore: config,
            initialSettings: const ViewerSettings(showDirectoryPanel: false),
            archiveService: ArchiveService(
              cachePolicy: ArchiveCachePolicy(
                directory: Directory('${root.path}/cache'),
              ),
            ),
          ),
        ),
      );
      await _wait(
        tester,
        () =>
            find.byType(ViewerBottomBar).evaluate().isNotEmpty &&
            tester
                    .widget<ViewerBottomBar>(find.byType(ViewerBottomBar))
                    .controller
                    .currentEntry !=
                null,
      );
      final controller = tester
          .widget<ViewerBottomBar>(find.byType(ViewerBottomBar))
          .controller;
      await _flush(tester, controller);
      config.block = true;
      unawaited(controller.recordRecentImage(image.path));
      final listener = tester.state(find.byType(ViewerPage)) as WindowListener;
      await tester.runAsync(() async {
        listener.onWindowClose();
        listener.onWindowClose();
      });
      await _wait(
        tester,
        () => windowCalls.any((call) => call.method == 'close'),
      );
      expect(windowCalls.where((call) => call.method == 'close'), hasLength(1));
      expect(windowCalls.where((call) => call.method == 'destroy'), isEmpty);
      final released = windowCalls.lastWhere(
        (call) => call.method == 'setPreventClose',
      );
      expect((released.arguments as Map)['isPreventClose'], isFalse);
      config.block = false;
      config.pending.complete();
      await _flush(tester, controller);
      await _pump(tester, const SizedBox.shrink());
      await tester.runAsync(() => root.delete(recursive: true));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reset all keeps recent records beyond the restored limit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (root, config, _) = await _fixture(tester);
    const initial = ViewerSettings(
      recentOpenLimit: 100,
      showDirectoryPanel: false,
    );
    final records = List.generate(
      30,
      (index) => RecentOpenEntry(
        path: paths.join(root.path, 'keep-$index.png'),
        kind: RecentOpenKind.image,
        openedAt: DateTime.utc(2026, 10, 23, 0, index),
      ).toJson(),
    );
    await tester.runAsync(() async {
      await initial.save(store: config);
      await config.update((value) => {...value, 'recentOpen': records});
    });
    await _pump(
      tester,
      _host(
        ViewerPage(
          configStore: config,
          initialSettings: initial,
          archiveService: ArchiveService(
            cachePolicy: ArchiveCachePolicy(
              directory: Directory(paths.join(root.path, 'cache')),
            ),
          ),
        ),
      ),
    );
    await _wait(
      tester,
      () => find.byKey(const ValueKey('viewer.content')).evaluate().isNotEmpty,
    );
    await tester.runAsync(
      () => tester.tapAt(
        tester
                .getRect(find.byKey(const ValueKey('viewer.content')))
                .bottomRight -
            const Offset(30, 30),
        buttons: kSecondaryMouseButton,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('设置')));
    await _wait(tester, () => find.byType(SettingsPage).evaluate().isNotEmpty);
    final page = tester.widget<SettingsPage>(find.byType(SettingsPage));
    expect(page.onResetAll, isNotNull);
    await tester.runAsync(() async {
      page.onResetAll!(const ViewerSettings());
    });
    var restored = false;
    for (var attempt = 0; attempt < 100 && !restored; attempt++) {
      restored =
          (await tester.runAsync(() => ViewerSettings.load(store: config))) ==
          const ViewerSettings();
      if (!restored) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
      }
      await tester.pump();
    }
    expect(restored, isTrue);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    final saved = await tester.runAsync(config.read);
    expect(saved!['recentOpen'], records);
    await _pump(tester, const SizedBox.shrink());
    await tester.runAsync(() => root.delete(recursive: true));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'general settings expose independent recording and new-window preferences',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var settings = const ViewerSettings(showDirectoryPanel: false);
      var cleared = false;
      await _pump(
        tester,
        _host(
          SettingsPage(
            settings: settings,
            onChanged: (value) => settings = value,
            decoderRegistry: DecoderRegistry(),
            onClearRecentOpen: () async => cleared = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _capture(tester, '../../artifacts/recent-open/settings-dark.png');
      final recording = find.ancestor(
        of: find.text('记录最近打开'),
        matching: find.byType(AppSwitch),
      );
      // Switch rows make the whole label clickable.
      expect(recording, findsOneWidget);
      await tester.tap(find.text('记录最近打开'));
      await tester.pumpAndSettle();
      expect(settings.recentOpenEnabled, isFalse);
      await tester.ensureVisible(find.text('新窗口显示最近打开'));
      await tester.tap(find.text('新窗口显示最近打开'));
      await tester.pumpAndSettle();
      expect(settings.openRecentOnNewWindow, isTrue);
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings.clearRecentOpen')),
      );
      await tester.runAsync(
        () =>
            tester.tap(find.byKey(const ValueKey('settings.clearRecentOpen'))),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.text('清空').last));
      await tester.pumpAndSettle();
      expect(cleared, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<(Directory, AppConfigStore, RecentOpenStore)> _fixture(
  WidgetTester tester,
) async {
  await _loadFonts(tester);
  return (await tester.runAsync(() async {
    final root = await Directory.systemTemp.createTemp('recent-page-');
    final config = AppConfigStore(filePath: '${root.path}/config.json');
    final store = RecentOpenStore(config);
    final displayRoot = Platform.isWindows ? 'D:' : root.path;
    await config.write({
      'recentOpen': [
        RecentOpenEntry(
          path: '$displayRoot/图片/样例图片.png',
          kind: RecentOpenKind.image,
          openedAt: DateTime.utc(2026, 10, 22, 10),
        ).toJson(),
        RecentOpenEntry(
          path: '$displayRoot/阅读/漫画.cbz',
          kind: RecentOpenKind.archive,
          openedAt: DateTime.utc(2026, 10, 22, 9),
        ).toJson(),
        RecentOpenEntry(
          path: '$displayRoot/照片/旅行',
          kind: RecentOpenKind.folder,
          openedAt: DateTime.utc(2026, 10, 21, 8),
        ).toJson(),
      ],
    });
    return (root, config, store);
  }))!;
}

Widget _host(Widget page, {bool dark = true}) => RepaintBoundary(
  key: capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark
        ? AppTheme.dark(
            platform: Platform.isWindows ? TargetPlatform.windows : null,
          )
        : AppTheme.light(
            platform: Platform.isWindows ? TargetPlatform.windows : null,
          ),
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: page,
  ),
);

Future<void> _wait(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
  await tester.pump(const Duration(milliseconds: 400));
  expect(done(), isTrue);
}

Future<void> _expectGridAvailability(
  WidgetTester tester, {
  required bool enabled,
}) async {
  await tester.tap(find.byTooltip(RegExp('^查看方式 · ')));
  await _wait(tester, () => find.text('网格总览').evaluate().isNotEmpty);
  final item = tester.widget<MenuItemButton>(
    find.ancestor(of: find.text('网格总览'), matching: find.byType(MenuItemButton)),
  );
  expect(item.onPressed != null, enabled);
  await tester.tapAt(
    tester.getCenter(find.byKey(const ValueKey('viewer.content'))),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _capture(WidgetTester tester, String path) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _loadFonts(WidgetTester tester) async {
  await loadStyleReviewFonts(tester);
}

class _BlockedConfigStore extends AppConfigStore {
  _BlockedConfigStore(String path) : super(filePath: path);
  bool block = false;
  final pending = Completer<void>();

  @override
  Future<void> update(
    Map<String, dynamic> Function(Map<String, dynamic>) transform,
  ) => block ? pending.future : super.update(transform);
}
