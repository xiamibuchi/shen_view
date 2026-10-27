import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:path/path.dart' as paths;
import 'package:shen_view/src/presentation/components/app_select.dart';
import 'package:shen_view/src/presentation/components/app_notification.dart';
import 'package:shen_view/src/presentation/components/field_frame.dart';
import 'package:shen_view/src/presentation/components/app_repeat_icon_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:image/image.dart' as bitmap;
import 'package:window_manager/window_manager.dart';
import 'package:shen_view/src/application/prefetch_planner.dart'
    hide ReadingDirection;
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/archive_service.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/image_source.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';
import 'package:shen_view/src/domain/folder_browse_mode.dart';
import 'package:shen_view/src/domain/viewer_mode.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/domain/view_scale_mode.dart';
import 'package:shen_view/src/presentation/archive_password_dialog.dart';
import 'package:shen_view/src/presentation/comic_strip_viewport.dart';
import 'package:shen_view/src/presentation/hdr_image_view.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/source_image_view.dart';
import 'package:shen_view/src/presentation/viewer_bottom_bar.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';
import 'package:shen_view/src/presentation/zoomable_viewport.dart';
import 'package:shen_view/src/presentation/split_wide_image.dart';
import 'package:shen_view/src/presentation/resource_image.dart';
import 'package:shen_view/src/presentation/grid_overview.dart';
import 'package:shen_view/src/presentation/viewer_shortcuts.dart';
import 'package:shen_view/src/presentation/settings_page.dart';

import 'support/style_review_fonts.dart';

const _captureKey = ValueKey('archive-viewer-capture');
const _colors = [
  (205, 65, 75),
  (52, 155, 96),
  (65, 105, 205),
  (175, 95, 190),
  (210, 140, 45),
  (35, 150, 165),
];

void main() {
  testWidgets(
    'custom shortcuts replace defaults and preserve held navigation and grid keys',
    (tester) async {
      _mockHost(tester);
      final root = Directory.systemTemp.createTempSync('custom-shortcuts-');
      addTearDown(() => _deleteFixture(root));
      final source = _scrollFixture(root, false);
      final settings = const ViewerSettings(
        showDirectoryPanel: false,
        interaction: ViewerInteractionSettings(
          holdNavigation: true,
          holdDelayMs: 500,
          holdIntervalMs: 500,
        ),
        shortcutOverrides: {
          'windows.nextImage': ViewerShortcutBinding(
            key: LogicalKeyboardKey.keyB,
          ),
          'windows.toggleGrid': ViewerShortcutBinding(
            key: LogicalKeyboardKey.keyU,
          ),
        },
      );
      await _pumpArchiveHost(
        tester,
        _host(
          source,
          settings: settings,
          themeOverride: AppTheme.dark(platform: TargetPlatform.windows),
        ),
      );
      await _waitForSelectedImage(tester);
      final controller = _bar(tester)!.controller;
      expect(controller.currentIndex, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _drain(tester);
      expect(controller.currentIndex, 0);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
      await _waitFor(tester, () => controller.currentIndex == 1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)),
      );
      await _drain(tester);
      expect(controller.currentIndex, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await _drain(tester);
      expect(find.byType(GridOverview), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
      await _drain(tester);
      expect(find.byType(GridOverview), findsOneWidget);
      final selected = tester
          .widget<GridOverview>(find.byType(GridOverview))
          .selectedId;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _drain(tester);
      expect(
        tester.widget<GridOverview>(find.byType(GridOverview)).selectedId,
        isNot(selected),
      );
      expect(controller.currentIndex, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _drain(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _waitFor(
        tester,
        () => find.byType(SettingsPage).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('settings.nav.shortcuts')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('settings.shortcuts.search')),
          matching: find.byType(TextField),
        ),
        '网格',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shortcuts.edit.toggleGrid')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shortcuts.recorder')));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shortcuts.save')));
      await _drain(tester);
      await tester.tap(find.byTooltip('返回'));
      await _drain(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
      await _drain(tester);
      expect(find.byType(GridOverview), findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _drain(tester);
      expect(find.byType(GridOverview), findsOneWidget);
      final saved = await tester.runAsync(
        () => ViewerSettings.load(
          store: AppConfigStore(filePath: '${source.parent.path}/config.json'),
        ),
      );
      expect(
        saved!.shortcutOverrides['windows.toggleGrid'],
        const ViewerShortcutBinding(
          key: LogicalKeyboardKey.keyY,
          control: true,
          shift: true,
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _drain(tester);
    },
  );

  for (final archiveView in [false, true]) {
    testWidgets(
      'grid overview keeps filmstrip and restores reading ($archiveView)',
      (tester) async {
        _mockHost(tester);
        await _loadCaptureFonts(tester);
        final root = Directory.systemTemp.createTempSync('grid-reading-');
        addTearDown(() => _deleteFixture(root));
        final source = _scrollFixture(root, archiveView);
        await _pumpArchiveHost(tester, _host(source));
        await _waitForSelectedImage(tester);
        final bar = _bar(tester)!;
        final first = bar.controller.currentEntry!;
        final zoom = tester.widget<ZoomableViewport>(
          find.byType(ZoomableViewport),
        );
        zoom.controller.value = Matrix4.identity()
          ..scaleByDouble(1.5, 1.5, 1.5, 1);
        await _drain(tester);
        final transform = Matrix4.copy(zoom.controller.value);
        final filmstripRect = tester.getRect(find.byType(ViewerBottomBar));
        await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
        await _drain(tester);
        expect(find.byType(GridOverview), findsOneWidget);
        expect(find.byType(ViewerBottomBar), findsOneWidget);
        await _waitFor(
          tester,
          () =>
              tester
                  .widgetList<RawImage>(
                    find.descendant(
                      of: find.byType(GridOverview),
                      matching: find.byType(RawImage),
                    ),
                  )
                  .where((image) => image.image != null)
                  .length >=
              3,
          attempts: 800,
        );
        expect(tester.getRect(find.byType(ViewerBottomBar)), filmstripRect);
        expect(find.byType(ZoomableViewport), findsNothing);
        tester
            .widget<GridOverview>(find.byType(GridOverview))
            .onSizeChanged(320);
        await tester.pump();
        final originalWidth = tester
            .widget<GridOverview>(find.byType(GridOverview))
            .itemWidth;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(
              find.byKey(const ValueKey('grid.images')),
            ),
            scrollDelta: const Offset(0, 40),
          ),
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(
          tester.widget<GridOverview>(find.byType(GridOverview)).itemWidth,
          lessThan(originalWidth),
        );
        final third = bar.controller.entries[2];
        await tester.tap(find.byKey(ValueKey('grid.item.${third.id}')));
        await tester.pump();
        expect(bar.controller.currentEntry!.id, first.id);
        expect(
          tester.widget<GridOverview>(find.byType(GridOverview)).selectedId,
          third.id,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _drain(tester);
        expect(find.byType(GridOverview), findsNothing);
        expect(bar.controller.currentEntry!.id, first.id);
        expect(zoom.controller.value, transform);

        await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
        await _drain(tester);
        // The filmstrip retains its existing immediate navigation semantics.
        _bar(tester)!.onSelect(1);
        await _waitFor(tester, () => bar.controller.currentIndex == 1);
        await _drain(tester);
        expect(
          tester.widget<GridOverview>(find.byType(GridOverview)).selectedId,
          bar.controller.entries[1].id,
        );
        final search = find.descendant(
          of: find.byKey(const ValueKey('grid.search')),
          matching: find.byType(EditableText),
        );
        await tester.enterText(search, 'nothing-matches');
        await tester.pump();
        expect(find.text('没有匹配的图片'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        expect(bar.controller.currentIndex, 1);
        await tester.enterText(search, '003');
        await tester.pump();
        expect(
          tester
              .widget<GridView>(find.byKey(const ValueKey('grid.images')))
              .semanticChildCount,
          1,
        );
        await tester.tap(find.byKey(ValueKey('grid.item.${third.id}')));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await _waitFor(
          tester,
          () => find.byType(GridOverview).evaluate().isEmpty,
        );
        expect(bar.controller.currentEntry!.id, third.id);
        await _waitForSelectedImage(tester);
        if (!archiveView) {
          for (final mode in ['双页', '长图', '连续阅读']) {
            await _chooseMode(tester, mode);
            await _waitForSelectedImage(tester);
            final viewport = find.byType(ZoomableViewport).first;
            final viewportState = tester.state(viewport);
            final viewportWidget = tester.widget<ZoomableViewport>(viewport);
            viewportWidget.commands!.setScale(1.4);
            await _drain(tester);
            final before = Matrix4.copy(viewportWidget.controller.value);
            final readingId = bar.controller.currentEntry!.id;
            await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
            await tester.pump();
            final firstCard = find.byKey(ValueKey('grid.item.${first.id}'));
            await tester.ensureVisible(firstCard);
            await tester.tap(firstCard);
            await tester.pump(const Duration(milliseconds: 350));
            await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
            await _drain(tester);
            expect(tester.state(viewport), same(viewportState), reason: mode);
            expect(viewportWidget.controller.value, before, reason: mode);
            expect(bar.controller.currentEntry!.id, readingId, reason: mode);
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
          await tester.pump();
          expect(find.byType(ViewerBottomBar), findsNothing);
          final firstCard = find.byKey(ValueKey('grid.item.${first.id}'));
          await tester.ensureVisible(firstCard);
          await tester.tap(firstCard);
          await tester.pump(const Duration(milliseconds: 100));
          await tester.tap(firstCard);
          await _waitFor(
            tester,
            () => find.byType(GridOverview).evaluate().isEmpty,
          );
          expect(bar.controller.currentEntry!.id, first.id);
          expect(find.byType(ViewerBottomBar), findsNothing);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
        await _finishViewer(tester, source);
      },
    );
  }

  for (final dark in [false, true]) {
    testWidgets(
      'grid overview shares pinned directory at wide and narrow sizes ($dark)',
      (tester) async {
        _mockHost(tester);
        await _loadCaptureFonts(tester);
        final root = Directory.systemTemp.createTempSync('grid-directory-');
        addTearDown(() => _deleteFixture(root));
        final source = _navigationArchive(root);
        await _pumpArchiveHost(
          tester,
          _host(
            source,
            themeOverride: dark ? AppTheme.dark() : AppTheme.light(),
            settings: const ViewerSettings(
              pinDirectoryPanel: true,
              directoryPanelWidth: 260,
            ),
          ),
        );
        await _waitForSelectedImage(tester);
        final before = _bar(tester)!.controller.currentEntry!.id;
        await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
        await _drain(tester);
        for (final width in [1280.0, 440.0]) {
          tester.view.physicalSize = Size(width, 800);
          await _drain(tester);
          expect(find.byKey(const ValueKey('directory.panel')), findsOneWidget);
          expect(find.byType(GridOverview), findsOneWidget);
          expect(find.byType(ViewerBottomBar), findsOneWidget);
          await _waitForImage(tester);
          {
            await _waitFor(
              tester,
              () =>
                  tester
                      .widgetList<RawImage>(
                        find.descendant(
                          of: find.byType(GridOverview),
                          matching: find.byType(RawImage),
                        ),
                      )
                      .where((image) => image.image != null)
                      .length >=
                  (width > 1000 ? 4 : 3),
              attempts: 800,
            );
          }
          expect(
            (await _pixels(
              tester,
              'grid-$dark-${width.toInt()}',
            )).fold<int>(0, (a, b) => a + b),
            greaterThan(500),
          );
          expect(tester.takeException(), isNull);
        }
        // A focused grid control must not be mistaken for directory focus.
        await tester.tap(find.byKey(const ValueKey('grid.size')));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
        await tester.pump();
        expect(find.byType(GridOverview), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
        await tester.pump();
        // Selecting a later page in continuous scope also updates the chapter
        // navigation without leaving the grid or changing its reading mode.
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pump();
        expect(_bar(tester)!.controller.currentEntry!.id, before);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await _waitFor(
          tester,
          () => find.byType(GridOverview).evaluate().isEmpty,
        );
        await _finishViewer(tester, source);
      },
    );
  }

  testWidgets('empty archives use a closable error without moving the image', (
    tester,
  ) async {
    _mockHost(tester);
    await _loadCaptureFonts(tester);
    final root = Directory.systemTemp.createTempSync('viewer-notification-');
    addTearDown(() => _deleteFixture(root));
    final source = _scrollFixture(root, false);
    final empty = Archive()
      ..addFile(ArchiveFile.bytes('readme.txt', utf8.encode('No images')));
    File('${source.parent.path}/empty.zip')
        .writeAsBytesSync(ZipEncoder().encode(empty));
    await _pumpArchiveHost(tester, _host(source));
    await _waitForSelectedImage(tester);
    final beforeCanvas = tester.getRect(find.byType(ZoomableViewport));
    final beforeBottom = tester.getRect(find.byType(ViewerBottomBar));
    final bar = _bar(tester)!;
    final archive = bar.controller.containers.firstWhere(
      (entry) => entry.name == 'empty.zip',
    );
    await tester.runAsync(() async => bar.onOpenArchive(archive));
    await _waitFor(
      tester,
      () => find.byType(AppNotificationCard).evaluate().isNotEmpty,
    );
    await _drain(tester);
    final card = tester.widget<AppNotificationCard>(
      find.byType(AppNotificationCard),
    );
    expect(card.notification.type, AppNotificationType.error);
    expect(card.notification.message, '压缩包内没有可浏览的图片');
    expect(find.text('在资源管理器中显示'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.getRect(find.byType(ZoomableViewport)), beforeCanvas);
    expect(tester.getRect(find.byType(ViewerBottomBar)), beforeBottom);
    expect(bar.controller.currentEntry!.name, source.uri.pathSegments.last);
    await tester.pump(const Duration(seconds: 30));
    expect(find.byType(AppNotificationCard), findsOneWidget);
    expect(
      (await _pixels(tester, 'empty-archive-error-notification'))[0],
      greaterThan(5000),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AppNotificationCard),
        matching: find.byTooltip('关闭'),
      ),
    );
    await _drain(tester);
    expect(find.byType(AppNotificationCard), findsNothing);
    expect(tester.takeException(), isNull);
    await _finishViewer(tester, source);
  });

  for (final archiveView in [false, true]) {
    testWidgets(
      'reading preferences survive restart and stay isolated (${archiveView ? 'archive' : 'folder'})',
      (tester) async {
        _mockHost(tester);
        await _loadCaptureFonts(tester);
        final root = Directory.systemTemp.createTempSync(
          'viewer-reading-memory-',
        );
        addTearDown(() => _deleteFixture(root));
        final source = _scrollFixture(root, archiveView);
        final store = AppConfigStore(
          filePath: '${root.path}/shared-config.json',
        );
        await _pumpArchiveHost(tester, _host(source, configStore: store));
        await _waitForSelectedImage(tester);
        await _chooseMode(tester, '双页');
        await _chooseSizing(tester, '实际大小');
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ViewerPage)),
        )!;
        await _tapNavigation(tester, find.byTooltip('查看方式 · 双页'));
        await _tapNavigation(tester, find.text(l10n.rightToLeftManga));
        await _drain(tester);
        expect(find.text(l10n.rightToLeftManga), findsNothing);
        _bar(tester)!.onSelect(2);
        await _waitFor(
          tester,
          () => _bar(tester)!.controller.currentIndex == 2,
        );
        await _waitForSelectedImage(tester);
        final scope = _bar(tester)!.controller.readingScopeKey!;
        final zoom = tester.widget<ZoomableViewport>(
          find.byType(ZoomableViewport),
        );
        zoom.controller.value = Matrix4.identity()..scaleByDouble(2, 2, 2, 1);
        await _drain(tester);
        await _finishViewer(tester, source);

        final other = Directory('${root.path}/other')..createSync();
        final otherFile = File('${other.path}/photo.png')
          ..writeAsBytesSync(
            bitmap.encodePng(bitmap.Image(width: 100, height: 100)),
          );
        await _pumpArchiveHost(tester, _host(otherFile, configStore: store));
        await _waitForSelectedImage(tester);
        expect(_bar(tester)!.mode, ViewerMode.single);
        await _finishViewer(tester, otherFile);

        // Reopening a folder resumes its page; opening a particular image would
        // deliberately select that image while keeping the folder preferences.
        final reopen = archiveView ? source : File(source.parent.path);
        await _pumpArchiveHost(tester, _host(reopen, configStore: store));
        await _waitForSelectedImage(tester);
        expect(_bar(tester)!.mode, ViewerMode.doublePage);
        expect(_bar(tester)!.controller.currentEntry!.name, '003.png');
        final restored = tester.widget<ZoomableViewport>(
          find.byType(ZoomableViewport),
        );
        expect(
          restored.controller.value.getMaxScaleOnAxis(),
          closeTo(1, 0.001),
        );
        final saved = _bar(tester)!.controller.readingStates[scope]!;
        expect(saved.scales[ViewerMode.doublePage], ViewScaleMode.originalSize);
        expect(saved.readingDirection, ReadingDirection.rightToLeft);
        expect(
          (await tester.runAsync(() => ViewerSettings.load(store: store)))!
              .readingDirection,
          ReadingDirection.leftToRight,
        );
        await _pixels(
          tester,
          'reading-memory-${archiveView ? 'archive' : 'folder'}-restored',
        );
        await _finishViewer(tester, source);
      },
    );
  }

  testWidgets(
    'continuous reading restores the relative page point after restart',
    (tester) async {
      _mockHost(tester);
      await _loadCaptureFonts(tester);
      final root = Directory.systemTemp.createTempSync(
        'viewer-reading-anchor-',
      );
      addTearDown(() => _deleteFixture(root));
      final source = _scrollFixture(root, true);
      await _pumpArchiveHost(tester, _host(source));
      await _waitForSelectedImage(tester);
      await _chooseMode(tester, '连续阅读');
      await _chooseSizing(tester, '适应宽度');
      _bar(tester)!.onSelect(3);
      await _drain(tester);
      var comic = tester.widget<ComicStripViewport>(
        find.byType(ComicStripViewport),
      );
      comic.commands.moveVertically(-180);
      await _drain(tester);
      final before = comic.positionController!.capture()!;
      final beforeEntry = _bar(tester)!.controller.entries
          .firstWhere((entry) => entry.id == before.path)
          .relativePath;
      await _finishViewer(tester, source);
      await _pumpArchiveHost(tester, _host(source));
      await _waitForSelectedImage(tester);
      expect(_bar(tester)!.mode, ViewerMode.comic);
      comic = tester.widget<ComicStripViewport>(
        find.byType(ComicStripViewport),
      );
      final after = comic.positionController!.capture()!;
      final afterEntry = _bar(tester)!.controller.entries
          .firstWhere((entry) => entry.id == after.path)
          .relativePath;
      expect(afterEntry, beforeEntry);
      expect(after.pageFraction, closeTo(before.pageFraction, 0.003));
      expect(comic.controller.value.getMaxScaleOnAxis(), closeTo(1, 0.001));
      await _pixels(tester, 'reading-memory-continuous-restored');
      await _finishViewer(tester, source);
    },
  );

  testWidgets(
    'all sizing choices apply to complete single, double and long-image content',
    (tester) async {
      _mockHost(tester);
      await _loadCaptureFonts(tester);
      final directory = Directory.systemTemp.createTempSync('viewer-sizing-');
      addTearDown(() => _deleteFixture(directory));
      final source = _scrollFixture(directory, false);
      final peer = bitmap.Image(width: 240, height: 360);
      bitmap.fill(
        peer,
        color: bitmap.ColorRgb8(_colors[1].$1, _colors[1].$2, _colors[1].$3),
      );
      File(paths.join(source.parent.path, '002.png'))
          .writeAsBytesSync(bitmap.encodePng(peer));
      await _pumpArchiveHost(
        tester,
        _host(
          source,
          settings: const ViewerSettings(
            showDirectoryPanel: false,
            doublePageFirstAlone: false,
            interaction: ViewerInteractionSettings(
              zoomCenter: ZoomCenter.viewport,
            ),
          ),
        ),
      );
      await _waitForSelectedImage(tester);
      for (final mode in ['单页', '双页', '长图']) {
        await _chooseMode(tester, mode);
        await _waitForSelectedImage(tester, minimum: mode == '双页' ? 2 : 1);
        for (final label in ['适应窗口', '适应宽度', '适应高度', '实际大小']) {
          await _chooseSizing(tester, label);
          final widget = tester.widget<ZoomableViewport>(
            find.byType(ZoomableViewport),
          );
          final viewport = tester.getSize(find.byType(ZoomableViewport));
          final natural = mode == '双页'
              ? const Size(732, 720)
              : const Size(480, 720);
          final expectedScale = switch (label) {
            '适应窗口' =>
              viewport.width / natural.width < viewport.height / natural.height
                  ? viewport.width / natural.width
                  : viewport.height / natural.height,
            '适应宽度' => viewport.width / natural.width,
            '适应高度' => viewport.height / natural.height,
            _ => 1.0,
          };
          expect(
            widget.contentSize.width,
            closeTo(natural.width * expectedScale, 0.01),
            reason: '$mode / $label',
          );
          expect(
            widget.contentSize.height,
            closeTo(natural.height * expectedScale, 0.01),
            reason: '$mode / $label',
          );
          expect(widget.zoomAroundCenter, isTrue);
          expect(
            widget.controller.value.getMaxScaleOnAxis(),
            closeTo(1, 0.0001),
          );
        }
        await _pixels(tester, 'sizing-$mode-native');
      }
      expect(tester.takeException(), isNull);
      await _finishViewer(tester, source);
    },
  );

  for (final keepPosition in [false, true]) {
    testWidgets(
      'keeping actual zoom across different image sizes (position=$keepPosition)',
      (tester) async {
        _mockHost(tester);
        final directory = Directory.systemTemp.createTempSync(
          'viewer-keep-zoom-',
        );
        addTearDown(() => _deleteFixture(directory));
        final source = _scrollFixture(directory, false);
        final second = bitmap.Image(width: 960, height: 1440);
        bitmap.fill(second, color: bitmap.ColorRgb8(52, 155, 96));
        File(paths.join(source.parent.path, '002.png'))
            .writeAsBytesSync(bitmap.encodePng(second));
        await _pumpArchiveHost(
          tester,
          _host(
            source,
            settings: ViewerSettings(
              showDirectoryPanel: false,
              interaction: ViewerInteractionSettings(
                keepZoom: true,
                keepZoomPosition: keepPosition,
              ),
            ),
          ),
        );
        await _waitForSelectedImage(tester);
        await _chooseSizing(tester, '适应宽度');
        var viewport = tester.widget<ZoomableViewport>(
          find.byType(ZoomableViewport),
        );
        final initialViewport = tester.getSize(find.byType(ZoomableViewport));
        viewport.commands!.setScale(3 / (initialViewport.width / 480));
        await _drain(tester);
        await tester.drag(
          find.byType(ZoomableViewport),
          const Offset(-70, -130),
        );
        await _drain(tester);
        final oldMatrix = Matrix4.copy(viewport.controller.value);
        final viewSize = tester.getSize(find.byType(ZoomableViewport));
        final oldTranslation = oldMatrix.getTranslation();
        final anchor = Offset(
          (viewSize.width / 2 - oldTranslation.x) / 3 / 480,
          (viewSize.height / 2 - oldTranslation.y) / 3 / 720,
        );
        await tester.runAsync(
          () => tester.sendKeyEvent(LogicalKeyboardKey.arrowRight),
        );
        await _waitForSelectedImage(tester);
        await _waitFor(
          tester,
          () =>
              tester
                  .widget<ZoomableViewport>(find.byType(ZoomableViewport))
                  .contentSize
                  .height ==
              1920,
        );
        await _drain(tester);
        viewport = tester.widget<ZoomableViewport>(
          find.byType(ZoomableViewport),
        );
        expect(_bar(tester)!.controller.currentIndex, 1);
        expect(
          viewport.controller.value.getMaxScaleOnAxis(),
          closeTo(3 / (viewSize.width / 960), 0.0001),
        );
        final translation = viewport.controller.value.getTranslation();
        if (keepPosition) {
          expect(
            (viewSize.width / 2 - translation.x) / 3 / 960,
            closeTo(anchor.dx, 0.002),
          );
          expect(
            (viewSize.height / 2 - translation.y) / 3 / 1440,
            closeTo(anchor.dy, 0.002),
          );
        } else {
          expect(translation.x, closeTo((viewSize.width - 960 * 3) / 2, 0.01));
          expect(translation.y, closeTo(0, 0.01));
        }
        // Sizing shortcuts must leave the independent lock enabled.
        await _chooseSizing(tester, '适应宽度');
        expect(
          tester
              .widget<ZoomableViewport>(find.byType(ZoomableViewport))
              .controller
              .value
              .getMaxScaleOnAxis(),
          closeTo(1, 0.0001),
        );
        await tester.tap(find.byKey(const ValueKey('viewer.zoomMenu')));
        await tester.pump();
        final lock = find.ancestor(
          of: find.text('换图时保持缩放比例'),
          matching: find.byType(MenuItemButton),
        );
        expect(
          find.descendant(
            of: lock,
            matching: find.byIcon(FluentIcons.checkmark_16_regular),
          ),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        expect(tester.takeException(), isNull);
        await _finishViewer(tester, source);
      },
    );
  }

  testWidgets(
    'sizing and view menus render in light and dark at wide and narrow widths',
    (tester) async {
      _mockHost(tester);
      await _loadCaptureFonts(tester);
      final directory = Directory.systemTemp.createTempSync(
        'viewer-sizing-menus-',
      );
      addTearDown(() => _deleteFixture(directory));
      final source = _scrollFixture(directory, false);
      for (final light in [false, true]) {
        for (final width in [1280.0, 440.0]) {
          tester.view.physicalSize = Size(width, 800);
          await _pumpArchiveHost(
            tester,
            _host(
              source,
              key: ValueKey('sizing-$light-$width'),
              themeOverride: light ? AppTheme.light() : AppTheme.dark(),
            ),
          );
          await _waitForSelectedImage(tester);
          final trigger = find.byKey(const ValueKey('viewer.zoomMenu'));
          await _tapNavigation(
            tester,
            trigger.evaluate().isNotEmpty ? trigger : find.byTooltip('更多缩放操作'),
          );
          await _drain(tester);
          expect(find.text('适应宽度'), findsOneWidget);
          expect(find.text('适应高度'), findsOneWidget);
          expect(find.text('以中心缩放'), findsNothing);
          await _pixels(tester, 'sizing-menu-$light-${width.toInt()}');
          await _tapNavigation(tester, find.text('适应高度'));
          await _drain(tester);
          final viewTrigger = find.byTooltip(RegExp('^查看方式 · '));
          if (viewTrigger.evaluate().isNotEmpty) {
            await _tapNavigation(tester, viewTrigger);
          } else {
            await _tapNavigation(tester, find.byTooltip('更多操作'));
            await _tapNavigation(tester, find.text('查看方式'));
          }
          await _drain(tester);
          await _pixels(tester, 'view-menu-$light-${width.toInt()}');
          await _tapNavigation(tester, find.text('连续阅读'));
          await _waitForSelectedImage(tester);
          expect(find.byType(ComicStripViewport), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _finishViewer(tester, source);
        }
      }
    },
  );

  for (final pinned in [true, false]) {
    testWidgets(
      'turning recursion off retains only pinned directory and hides folder children (pinned=$pinned)',
      (tester) async {
        _mockHost(tester);
        await _loadCaptureFonts(tester);
        final directory = Directory.systemTemp.createTempSync(
          'viewer-recursion-toggle-',
        );
        addTearDown(() => _deleteFixture(directory));
        final source = File(
          paths.normalize(_scrollFixture(directory, false).path),
        );
        final folder = source.parent;
        final chapter = Directory(paths.join(folder.path, 'chapter'))
          ..createSync();
        source.copySync(paths.join(chapter.path, '001.png'));
        File(paths.join(directory.path, 'scroll.cbz'))
            .copySync(paths.join(folder.path, 'book.cbz'));
        await _pumpArchiveHost(
          tester,
          _host(
            source,
            settings: ViewerSettings(
              showDirectoryPanel: pinned,
              pinDirectoryPanel: pinned,
              directoryPanelWidth: 420,
              folderContinuousReading: !pinned,
            ),
            themeOverride: pinned ? AppTheme.dark() : AppTheme.light(),
          ),
        );
        await _waitForSelectedImage(tester);
        final controller = _bar(tester)!.controller;
        controller.select(2);
        await _waitForSelectedImage(tester);
        final selected = controller.currentEntry!.id;
        expect(controller.containers, isNotEmpty);
        expect(
          find.byKey(const ValueKey('navigation.directory')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('directory.panel')),
          pinned ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(ValueKey('directory.item:${chapter.path}')),
          findsNothing,
        );

        Future<void> toggleRecursion(bool enabled) async {
          await tester.tapAt(
            Offset(tester.view.physicalSize.width / 2, 250),
            buttons: kSecondaryMouseButton,
          );
          await _waitFor(tester, () => find.text('设置').evaluate().isNotEmpty);
          await _tapNavigation(tester, find.text('设置'));
          await _waitFor(
            tester,
            () => find
                .byKey(const ValueKey('settings.nav.browsing'))
                .evaluate()
                .isNotEmpty,
          );
          await _tapNavigation(
            tester,
            find.byKey(const ValueKey('settings.nav.browsing')),
          );
          await _tapNavigation(tester, find.text('递归浏览子文件夹'));
          await _waitFor(
            tester,
            () =>
                controller.browseMode.isRecursive == enabled &&
                !controller.isIndexing,
          );
          await _tapNavigation(tester, find.byTooltip('返回'));
          // The viewer underneath is already painted while the settings route
          // is still animating out. Wait for removal before opening it again.
          await _waitFor(
            tester,
            () => find
                .byKey(const ValueKey('settings.nav.browsing'))
                .evaluate()
                .isEmpty,
          );
          await _waitForSelectedImage(tester);
          expect(controller.currentEntry!.id, selected);
        }

        await toggleRecursion(true);
        expect(controller.hasFolderNavigation, isTrue);
        if (!pinned) await _openDirectory(tester);
        expect(find.byKey(const ValueKey('directory.panel')), findsOneWidget);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('directory.sizedPanel')))
              .width,
          420,
        );
        await _pixels(tester, 'recursion-on-$pinned');
        if (!pinned) {
          await _tapNavigation(
            tester,
            find.byKey(const ValueKey('directory.close')),
          );
        }
        await toggleRecursion(false);
        expect(controller.hasFolderNavigation, isFalse);
        expect(controller.entries.length, 6);
        expect(controller.containers, isNotEmpty);
        expect(
          find.byKey(const ValueKey('navigation.directory')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('navigation.chapter')), findsNothing);
        expect(
          find.byKey(const ValueKey('directory.panel')),
          pinned ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(ValueKey('directory.item:${chapter.path}')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('directory.barrier')), findsNothing);
        await _pixels(tester, 'recursion-off-$pinned');
        await toggleRecursion(true);
        if (!pinned) await _openDirectory(tester);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('directory.sizedPanel')))
              .width,
          420,
        );
        expect(tester.takeException(), isNull);
        await _finishViewer(tester, source);
      },
    );
  }
  for (final dark in [true, false]) {
    testWidgets(
      'directory width shares, adapts and restores after restart in dark=$dark',
      (tester) async {
        _mockHost(tester);
        await _loadCaptureFonts(tester);
        final directory = Directory.systemTemp.createTempSync(
          'directory-width-ui-',
        );
        addTearDown(() => _deleteFixture(directory));
        final source = _navigationArchive(directory);
        final theme = dark ? AppTheme.dark() : AppTheme.light();
        const panel = ValueKey('directory.sizedPanel');
        const resize = ValueKey('directory.resize');
        double width() => tester.getSize(find.byKey(panel)).width;
        await _pumpArchiveHost(
          tester,
          _host(
            source,
            settings: ViewerSettings(
              pinDirectoryPanel: true,
              toolbarMode: dark ? ToolbarMode.normal : ToolbarMode.floating,
            ),
            themeOverride: theme,
          ),
        );
        await _waitForSelectedImage(tester);
        final selected = _bar(tester)!.controller.currentEntry!.id;
        expect(width(), 360);
        await _pixels(tester, 'directory-resize-$dark-idle');
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(1000, 100));
        await mouse.moveTo(const Offset(350, 180));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 140));
        await _pixels(tester, 'directory-resize-$dark-near');
        await mouse.moveTo(const Offset(360, 180));
        await tester.pump(const Duration(milliseconds: 310));
        await tester.pump(const Duration(milliseconds: 140));
        await tester.pump(const Duration(milliseconds: 650));
        await tester.pump(const Duration(milliseconds: 200));
        await _pixels(tester, 'directory-resize-$dark-hover');
        await mouse.down(const Offset(360, 180));
        await tester.pump();
        await _pixels(tester, 'directory-resize-$dark-pressed');
        await mouse.moveBy(const Offset(120, 0));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('directory.resizeShield')),
          findsOneWidget,
        );
        await _pixels(tester, 'directory-resize-$dark-dragging');
        await mouse.up();
        await _drain(tester);
        expect(width(), 480);
        expect(_bar(tester)!.controller.currentEntry!.id, selected);
        await _pixels(tester, 'directory-resize-$dark-released');
        await mouse.moveTo(const Offset(1000, 100));
        await tester.pump(const Duration(milliseconds: 2100));
        await _drain(tester);
        await _pixels(tester, 'directory-resize-$dark-rest');
        await mouse.removePointer();
        await _pixels(tester, 'directory-width-$dark-docked');
        final search = find.descendant(
          of: find.byKey(const ValueKey('directory.search')),
          matching: find.byType(EditableText),
        );
        await tester.enterText(search, '第1卷');
        await _drain(tester);
        // Window width must never change a pinned panel into an overlay.
        // Shrinking only constrains its width, preserving search and selection.
        for (final windowWidth in [1000.0, 999.0, 440.0, 1280.0]) {
          tester.view.physicalSize = Size(windowWidth, 800);
          await _drain(tester);
          expect(find.byKey(panel), findsOneWidget);
          expect(
            width(),
            windowWidth == 440 ? inInclusiveRange(200, 240) : 480,
          );
          expect(
            find.byKey(const ValueKey('directory.docked')),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('directory.barrier')), findsNothing);
          expect(tester.widget<EditableText>(search).controller.text, '第1卷');
          expect(_bar(tester)!.controller.currentEntry!.id, selected);
          await _pixels(
            tester,
            'directory-pinned-$dark-${windowWidth.toInt()}',
          );
          if (windowWidth == 440) {
            await tester.tap(find.byTooltip('显示信息 · I'));
            await _drain(tester);
            expect(
              find.byKey(const ValueKey('viewer.infoOverlay')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('directory.docked')),
              findsOneWidget,
            );
            await _pixels(tester, 'directory-pinned-$dark-narrow-info');
            await tester.tap(find.byTooltip('隐藏信息 · I'));
            await _drain(tester);
          }
        }
        await tester.enterText(search, '');
        await _drain(tester);
        // Explicit dismissal stays dismissed when resizing in either direction.
        tester.view.physicalSize = const Size(440, 800);
        await tester.pump();
        await _tapNavigation(
          tester,
          find.byKey(const ValueKey('directory.close')),
        );
        for (final windowWidth in [1280.0, 440.0, 1280.0]) {
          tester.view.physicalSize = Size(windowWidth, 800);
          await tester.pump();
          expect(find.byKey(panel), findsNothing);
        }
        await _openDirectory(tester);
        expect(width(), 480);
        await _tapNavigation(
          tester,
          find.byKey(const ValueKey('directory.pin')),
        );
        await _drain(tester);
        expect(find.byKey(const ValueKey('directory.barrier')), findsOneWidget);
        expect(width(), 480);
        await _pixels(tester, 'directory-width-$dark-floating');
        await tester.drag(find.byKey(resize), const Offset(400, 0));
        await _drain(tester);
        expect(width(), 600);
        tester.view.physicalSize = const Size(1000, 800);
        await tester.pump();
        expect(width(), 600);
        tester.view.physicalSize = const Size(440, 800);
        await _drain(tester);
        expect(width(), inInclusiveRange(200, 240));
        await _pixels(tester, 'directory-width-$dark-narrow');
        tester.view.physicalSize = const Size(1280, 800);
        await tester.pump();
        expect(width(), 600);
        await _tapNavigation(
          tester,
          find.byKey(const ValueKey('directory.pin')),
        );
        await _drain(tester);
        expect(width(), 600);
        final store = AppConfigStore(filePath: '${directory.path}/config.json');
        await _waitForSavedDirectoryPin(tester, store, true);
        await _finishViewer(tester, source);
        final saved = await tester.runAsync(
          () => ViewerSettings.load(store: store),
        );
        expect(saved!.directoryPanelWidth, 600);
        await _pumpArchiveHost(
          tester,
          _host(source, settings: null, themeOverride: theme),
        );
        await _waitForSelectedImage(tester);
        expect(find.byKey(const ValueKey('directory.docked')), findsOneWidget);
        expect(width(), 600);
        expect(tester.takeException(), isNull);
        await _finishViewer(tester, source);
      },
    );
  }

  for (final archiveView in [false, true]) {
    testWidgets(
      'spread keys, touch and mode progress in archive=$archiveView',
      (tester) async {
        _mockHost(tester);
        final directory = Directory.systemTemp.createTempSync('spread-input-');
        addTearDown(() => _deleteFixture(directory));
        final source = _scrollFixture(directory, archiveView);
        await _pumpArchiveHost(
          tester,
          _host(
            source,
            settings: ViewerSettings(
              showDirectoryPanel: false,
              readingDirection: archiveView
                  ? ReadingDirection.leftToRight
                  : ReadingDirection.rightToLeft,
              interaction: const ViewerInteractionSettings(
                transition: ImageTransition.none,
              ),
            ),
          ),
        );
        await _waitForSelectedImage(tester);
        await _chooseMode(tester, '双页');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.runAsync(
          () => tester.sendKeyEvent(LogicalKeyboardKey.arrowRight),
        );
        await _waitFor(
          tester,
          () => _bar(tester)!.controller.currentIndex == 1,
        );
        await tester.runAsync(
          () => tester.sendKeyEvent(LogicalKeyboardKey.arrowRight),
        );
        await _waitFor(
          tester,
          () => _bar(tester)!.controller.currentIndex == 2,
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await _waitForSelectedImage(tester, minimum: 2);
        final controller = _bar(tester)!.controller;
        expect(
          tester
              .widgetList<ResourceImage>(
                find.descendant(
                  of: find.byType(ZoomableViewport),
                  matching: find.byType(ResourceImage),
                ),
              )
              .map((image) => image.entry.name),
          unorderedEquals([
            controller.entries[2].name,
            controller.entries[3].name,
          ]),
          reason: 'Shift must advance the visible spread by one source image.',
        );
        await tester.runAsync(
          () => tester.sendKeyEvent(LogicalKeyboardKey.arrowRight),
        );
        await _waitFor(
          tester,
          () => _bar(tester)!.controller.currentIndex == 4,
        );
        await tester.runAsync(
          () => tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft),
        );
        await _waitFor(
          tester,
          () => _bar(tester)!.controller.currentIndex == 2,
        );
        await _waitForSelectedImage(tester, minimum: 2);
        await tester.runAsync(
          () => tester.drag(
            find.byType(ZoomableViewport),
            Offset(archiveView ? -180 : 180, 0),
            kind: PointerDeviceKind.touch,
          ),
        );
        await _waitFor(
          tester,
          () => _bar(tester)!.controller.currentIndex == 4,
        );
        await tester.runAsync(
          () => tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft),
        );
        await _waitFor(
          tester,
          () => _bar(tester)!.controller.currentIndex == 2,
        );
        await _chooseMode(tester, '连续阅读');
        await _waitForSelectedImage(tester);
        var comic = tester.widget<ComicStripViewport>(
          find.byType(ComicStripViewport),
        );
        comic.commands.moveVertically(-180);
        await _drain(tester);
        final position = comic.positionController!.capture()!;
        final selected = _bar(tester)!.controller.currentEntry!.id;
        await _chooseMode(tester, '双页');
        expect(_bar(tester)!.controller.currentEntry!.id, selected);
        await _chooseMode(tester, '连续阅读');
        await _drain(tester);
        comic = tester.widget<ComicStripViewport>(
          find.byType(ComicStripViewport),
        );
        final restored = comic.positionController!.capture()!;
        expect(restored.path, position.path);
        expect(restored.pageFraction, closeTo(position.pageFraction, 0.002));
        expect(_bar(tester)!.controller.currentEntry!.id, selected);
        expect(tester.takeException(), isNull);
        await _finishViewer(tester, source);
      },
    );
  }

  testWidgets('wide scan splitting, cover exception and animation fallback', (
    tester,
  ) async {
    _mockHost(tester);
    await _loadCaptureFonts(tester);
    final directory = Directory.systemTemp.createTempSync('wide-scan-');
    addTearDown(() => _deleteFixture(directory));
    final pages = Directory('${directory.path}/pages')..createSync();
    final wide = bitmap.Image(width: 1001, height: 800);
    bitmap.fill(wide, color: bitmap.ColorRgb8(210, 70, 55));
    bitmap.fillRect(
      wide,
      x1: 501,
      y1: 0,
      x2: 1000,
      y2: 799,
      color: bitmap.ColorRgb8(65, 105, 205),
    );
    File('${pages.path}/001.png').writeAsBytesSync(bitmap.encodePng(wide));
    File('${pages.path}/002.png').writeAsBytesSync(bitmap.encodePng(wide));
    File('${pages.path}/003.gif').writeAsBytesSync(bitmap.encodeGif(wide));
    await _pumpArchiveHost(
      tester,
      _host(
        File('${pages.path}/001.png'),
        settings: const ViewerSettings(
          showDirectoryPanel: false,
          doublePageWideAlone: false,
          doublePageSplitWide: true,
        ),
      ),
    );
    await _waitForSelectedImage(tester);
    await _chooseMode(tester, '双页');
    expect(find.byType(SplitWideImage), findsNothing);
    await tester.runAsync(
      () => tester.sendKeyEvent(LogicalKeyboardKey.arrowRight),
    );
    await _waitFor(tester, () => _bar(tester)!.controller.currentIndex == 1);
    await _waitFor(
      tester,
      () => find.byType(SplitWideImage).evaluate().isNotEmpty,
    );
    await _waitForSelectedImage(tester, minimum: 2);
    expect(find.byType(SplitWideImage), findsOneWidget);
    await _waitFor(
      tester,
      () =>
          tester
              .widgetList<RawImage>(
                find.descendant(
                  of: find.byType(SplitWideImage),
                  matching: find.byType(RawImage),
                ),
              )
              .where((image) => image.image != null)
              .length ==
          2,
    );
    await _drain(tester);
    await _pixels(tester, 'wide-scan-split');
    await tester.runAsync(
      () => tester.sendKeyEvent(LogicalKeyboardKey.arrowRight),
    );
    await _waitFor(tester, () => _bar(tester)!.controller.currentIndex == 2);
    await _drain(tester);
    expect(find.byType(SplitWideImage), findsNothing);
    expect(tester.takeException(), isNull);
    await _finishViewer(tester, File('${pages.path}/001.png'));
  });

  for (final width in [1280.0, 560.0]) {
    testWidgets(
      'folder archive navigation keeps directory and peer switching at width=$width',
      (tester) async {
        _mockHost(tester);
        await _loadCaptureFonts(tester);
        tester.view.physicalSize = Size(width, 900);
        final directory = Directory.systemTemp.createTempSync(
          'viewer-peer-nav-',
        );
        addTearDown(() => _deleteFixture(directory));
        final library = Directory(paths.join(directory.path, '同级压缩包'))
          ..createSync();
        for (final file in Directory(
          'testdata/navigation/同级压缩包',
        ).listSync().whereType<File>()) {
          file.copySync(paths.join(library.path, paths.basename(file.path)));
        }
        await _pumpArchiveHost(
          tester,
          _host(
            File(library.path),
            settings: ViewerSettings(
              browseMode: width >= 1000
                  ? FolderBrowseMode.recursiveFolders
                  : FolderBrowseMode.currentFolder,
              sortOrder: SortOrder.nameAscending,
              pinDirectoryPanel: true,
              archiveAutoAdvance: false,
            ),
          ),
        );
        await _waitForSelectedImage(tester);
        final controller = _bar(tester)!.controller;
        final books = [
          for (var volume = 1; volume <= 3; volume++)
            paths.join(library.path, '第0$volume卷.cbz'),
        ];
        void expectChoices(String selected) {
          final select = tester.widget<AppSelect<String>>(
            find.byKey(const ValueKey('navigation.chapter')),
          );
          expect(select.options.map((option) => option.value), [
            library.path,
            ...books,
          ]);
          expect(select.value, selected);
          expect(controller.directoryRoot!.path, library.path);
        }

        Future<void> waitForBook(int volume) async {
          await _waitFor(
            tester,
            () =>
                controller.archiveContext?.archiveFile.path ==
                    books[volume - 1] &&
                !controller.isOpeningArchive,
          );
          await _waitForSelectedImage(tester);
          expectChoices(books[volume - 1]);
          expect(
            (await _pixels(
              tester,
              'peer-nav-$width-volume-$volume',
            ))[(volume - 1) * 2],
            greaterThan(5000),
          );
        }

        if (controller.browseMode.isRecursive) {
          expectChoices(library.path);
          if (find
              .byKey(const ValueKey('directory.panel'))
              .evaluate()
              .isEmpty) {
            await _openDirectory(tester);
          }
          expect(find.text('浏览目录'), findsOneWidget);
          await _tapNavigation(
            tester,
            find.byKey(ValueKey('directory.item:${books.first}')),
          );
        } else {
          expect(
            find.byKey(const ValueKey('navigation.directory')),
            findsOneWidget,
          );
          await tester.runAsync(() async {
            unawaited(controller.openArchiveEntry(controller.containers.first));
          });
        }
        await waitForBook(1);
        if (width >= 1000) {
          await tester.tap(find.text('查看顺序'));
          await tester.pump();
          expect(find.text('文件夹顺序'), findsNothing);
          expect(find.text('文件名升序'), findsOneWidget);
          await _pixels(tester, 'archive-sort-menu');
          await tester.tapAt(const Offset(4, 400));
          await tester.pump();
          await tester.tapAt(
            tester.getCenter(find.byType(ZoomableViewport)),
            buttons: kSecondaryMouseButton,
          );
          await _drain(tester);
          final contextSort = find.ancestor(
            of: find.text('查看顺序'),
            matching: find.byType(MenuItemButton),
          );
          expect(contextSort, findsOneWidget);
          await tester.tap(contextSort);
          await _drain(tester);
          expect(find.text('文件夹顺序'), findsNothing);
          expect(find.text('文件名升序'), findsOneWidget);
          await _pixels(tester, 'archive-context-sort-menu');
          await tester.tapAt(const Offset(4, 400));
          await tester.pump();
          expect(
            find.byKey(const ValueKey('directory.docked')),
            findsOneWidget,
          );
        }
        if (find.byKey(const ValueKey('directory.panel')).evaluate().isEmpty) {
          await _openDirectory(tester);
        }
        for (final book in books) {
          expect(find.byKey(ValueKey('directory.item:$book')), findsOneWidget);
        }
        await _pixels(tester, 'peer-nav-$width-directory');
        if (width < 1000) {
          await _tapNavigation(
            tester,
            find.byKey(const ValueKey('directory.close')),
          );
        }
        await _tapNavigation(
          tester,
          find.byKey(const ValueKey('navigation.nextChapter')),
        );
        await waitForBook(2);
        await _tapNavigation(
          tester,
          find.byKey(const ValueKey('navigation.chapter')),
        );
        await _tapNavigation(
          tester,
          find.widgetWithText(MenuItemButton, '第03卷.cbz'),
        );
        await waitForBook(3);
        final chapterSurface = find.descendant(
          of: find.byKey(const ValueKey('navigation.chapter')),
          matching: find.byType(FieldSurface),
        );
        final viewport = find.byType(ZoomableViewport);
        final transform = tester.widget<ZoomableViewport>(viewport).controller;
        final originalScale = transform.value.getMaxScaleOnAxis();
        final selectedId = controller.currentEntry!.id;
        await tester.tapAt(tester.getTopLeft(viewport) + const Offset(8, 8));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(viewport),
            scrollDelta: const Offset(0, -40),
          ),
        );
        await tester.pump();
        expect(transform.value.getMaxScaleOnAxis(), greaterThan(originalScale));
        expect(tester.widget<FieldSurface>(chapterSurface).focused, isFalse);
        expect(controller.currentEntry!.id, selectedId);
        await _pixels(tester, 'peer-nav-$width-zoom-no-select-focus');
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        tester.widget<ZoomableViewport>(viewport).commands!.resetView();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await _waitFor(tester, () => controller.currentIndex == 1);
        await _waitForSelectedImage(tester);
        expect(find.byType(MenuItemButton), findsNothing);
        expect(tester.widget<FieldSurface>(chapterSurface).focused, isFalse);
        await _tapNavigation(
          tester,
          find.byKey(const ValueKey('navigation.previousChapter')),
        );
        await waitForBook(2);
        await _tapNavigation(
          tester,
          find.byKey(const ValueKey('navigation.chapter')),
        );
        await _tapNavigation(
          tester,
          find.widgetWithText(MenuItemButton, '本目录图片'),
        );
        await _waitFor(
          tester,
          () => !controller.isArchiveView && !controller.isIndexing,
        );
        await _waitForSelectedImage(tester);
        if (controller.browseMode.isRecursive) {
          expectChoices(library.path);
        } else {
          expect(
            find.byKey(const ValueKey('navigation.chapter')),
            findsNothing,
          );
          expect(find.byKey(const ValueKey('directory.panel')), findsNothing);
        }
        expect(controller.currentEntry!.name, '封面.png');
        expect(tester.takeException(), isNull);
        await _finishViewer(tester, File(library.path));
      },
    );
  }
  for (final scenario in [
    (origin: 'folder', enabled: true),
    (origin: 'folder', enabled: false),
    (origin: 'direct', enabled: true),
    (origin: 'nested', enabled: true),
  ]) {
    testWidgets(
      'archive auto advance follows page input (${scenario.origin}, enabled=${scenario.enabled})',
      (tester) async {
        _mockHost(tester);
        final directory = Directory.systemTemp.createTempSync(
          'viewer-auto-advance-',
        );
        addTearDown(() => _deleteFixture(directory));
        // Keep the host's config/cache inside this fixture, not the shared temp root.
        final library = Directory(paths.join(directory.path, '连续阅读'))
          ..createSync();
        final pages = ZipDecoder()
            .decodeBytes(_archive(directory, 'pages.cbz').readAsBytesSync())
            .files;
        File writeBook(String name, Map<String, List<int>> entries) {
          final archive = Archive();
          for (final entry in entries.entries) {
            archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
          }
          return File(paths.join(library.path, name))
            ..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
        }

        final books = [
          for (var volume = 0; volume < 3; volume++)
            writeBook('第0${volume + 1}卷.cbz', {
              '001.png': pages[volume * 2].content,
              '002.png': pages[volume * 2 + 1].content,
            }),
        ];
        File(paths.join(library.path, 'cover.png'))
            .writeAsBytesSync(pages.first.content);
        if (scenario.origin == 'nested') {
          writeBook('第01卷.cbz', {
            'cover.png': pages.first.content,
            '内嵌.cbz': books.first.readAsBytesSync(),
          });
        }
        final source = scenario.origin == 'direct'
            ? books.first
            : File(library.path);
        await _pumpArchiveHost(
          tester,
          _host(
            source,
            settings: ViewerSettings(
              showDirectoryPanel: false,
              browseMode: FolderBrowseMode.recursiveFolders,
              sortOrder: SortOrder.nameAscending,
              archiveAutoAdvance: scenario.enabled,
            ),
          ),
        );
        await _waitForSelectedImage(tester);
        final controller = _bar(tester)!.controller;
        if (scenario.origin != 'direct') {
          await _openDirectory(tester);
          await _tapNavigation(
            tester,
            find.byKey(
              ValueKey('directory.item:${controller.containers.first.id}'),
            ),
          );
          await _waitFor(
            tester,
            () =>
                controller.archiveContext?.archiveFile.path ==
                    books.first.path &&
                !controller.isOpeningArchive,
          );
          await _waitForSelectedImage(tester);
          if (scenario.origin == 'nested') {
            final inner = controller.navigationContainers.single;
            await _openDirectory(tester);
            await _tapNavigation(
              tester,
              find.byKey(ValueKey('directory.item:${inner.id}')),
            );
            await _waitFor(
              tester,
              () =>
                  controller.archiveContext?.parent != null &&
                  !controller.isOpeningArchive,
            );
            await _waitForSelectedImage(tester);
          }
        }
        final crosses = scenario.origin == 'folder' && scenario.enabled;
        AppRepeatIconButton edge(String label) => tester
            .widgetList<AppRepeatIconButton>(find.byType(AppRepeatIconButton))
            .singleWhere((button) => button.tooltip == label);
        Future<void> selectPage(int index) async {
          await _tapNavigation(
            tester,
            find.byKey(ValueKey(controller.entries[index].id)),
          );
          await _waitFor(tester, () => controller.currentIndex == index);
          await _waitForSelectedImage(tester);
        }

        for (var volume = 0; volume < (crosses ? 3 : 1); volume++) {
          await selectPage(1);
          expect(
            (await _pixels(
              tester,
              'auto-advance-${scenario.origin}-${scenario.enabled}-$volume-tail',
            ))[volume * 2 + 1],
            greaterThan(5000),
          );
          final previousContext = controller.archiveContext;
          final previousImage = controller.currentEntry!.id;
          if (crosses && volume < 2) {
            expect(edge('下一个').onPressed, isNotNull);
          } else {
            expect(edge('下一个').onPressed, isNull);
          }
          if (volume == 1) {
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            final viewport = tester.getRect(find.byType(ZoomableViewport));
            await mouse.addPointer(location: viewport.center);
            await mouse.moveTo(
              Offset(tester.view.physicalSize.width - 24, viewport.center.dy),
            );
            await tester.pump(const Duration(milliseconds: 150));
            await tester.runAsync(() async {
              await mouse.down(tester.getCenter(find.byTooltip('下一个')));
              await mouse.up();
            });
            await mouse.removePointer();
          } else {
            await tester.runAsync(
              () => tester.sendKeyEvent(LogicalKeyboardKey.arrowRight),
            );
          }
          if (crosses && volume < 2) {
            await _waitFor(
              tester,
              () =>
                  controller.archiveContext?.archiveFile.path ==
                      books[volume + 1].path &&
                  !controller.isOpeningArchive,
            );
            await _waitForSelectedImage(tester);
            expect(controller.currentIndex, 0);
            expect(
              (await _pixels(
                tester,
                'auto-advance-volume-${volume + 2}-head',
              ))[(volume + 1) * 2],
              greaterThan(5000),
            );
          } else {
            await _drain(tester);
            expect(controller.isOpeningArchive, isFalse);
            expect(controller.archiveContext, same(previousContext));
            expect(controller.currentEntry!.id, previousImage);
          }
        }
        if (crosses) {
          for (var volume = 1; volume >= 0; volume--) {
            await selectPage(0);
            await tester.runAsync(
              () => tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft),
            );
            await _waitFor(
              tester,
              () =>
                  controller.archiveContext?.archiveFile.path ==
                      books[volume].path &&
                  !controller.isOpeningArchive,
            );
            await _waitForSelectedImage(tester);
          }
        }
        await selectPage(0);
        final firstPage = controller.currentEntry!.id;
        final firstContext = controller.archiveContext;
        expect(edge('上一个').onPressed, isNull);
        await tester.runAsync(
          () => tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft),
        );
        await _drain(tester);
        expect(controller.isOpeningArchive, isFalse);
        expect(controller.currentEntry!.id, firstPage);
        expect(controller.archiveContext, same(firstContext));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await _drain(tester);
        // Complete the shared config write queue before leaving FakeAsync, so
        // the following viewer test can save or restore its own configuration.
        final store = AppConfigStore(
          filePath: '${source.parent.path}/config.json',
        );
        var flushed = false;
        await tester.runAsync(() async {
          unawaited(
            store.update((config) => config).then((_) => flushed = true),
          );
        });
        await _waitFor(tester, () => flushed);
      },
    );
  }

  testWidgets('directory visibility saves, syncs with settings and restarts', (
    tester,
  ) async {
    _mockHost(tester);
    final directory = Directory.systemTemp.createTempSync(
      'directory-visibility-',
    );
    addTearDown(() => _deleteFixture(directory));
    final source = _archive(directory, 'flat.cbz');
    final store = AppConfigStore(filePath: '${directory.path}/config.json');
    Future<void> expectSaved(bool visible, bool pinned) async {
      for (var attempt = 0; attempt < 100; attempt++) {
        final saved = await tester.runAsync(
          () => ViewerSettings.load(store: store),
        );
        if (saved!.showDirectoryPanel == visible &&
            saved.pinDirectoryPanel == pinned) {
          return;
        }
        await _drain(tester);
      }
      fail('Directory visibility and pin preference did not save');
    }

    await _pumpArchiveHost(
      tester,
      _host(source, settings: const ViewerSettings()),
    );
    await _waitForSelectedImage(tester);
    expect(find.byKey(const ValueKey('directory.panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('directory.docked')), findsNothing);
    expect(find.byKey(const ValueKey('directory.barrier')), findsOneWidget);
    await _tapNavigation(tester, find.byKey(const ValueKey('directory.close')));
    await expectSaved(false, false);
    expect(find.byKey(const ValueKey('directory.panel')), findsNothing);
    await _finishViewer(tester, source);
    await _pumpArchiveHost(tester, _host(source, settings: null));
    await _waitForSelectedImage(tester);
    expect(find.byKey(const ValueKey('directory.panel')), findsNothing);
    await _openDirectory(tester);
    await expectSaved(true, false);
    await _tapNavigation(tester, find.byKey(const ValueKey('directory.pin')));
    await expectSaved(true, true);
    await tester.tapAt(const Offset(640, 250), buttons: kSecondaryMouseButton);
    await _waitFor(tester, () => find.text('设置').evaluate().isNotEmpty);
    await _tapNavigation(tester, find.text('设置'));
    await _waitFor(
      tester,
      () => find
          .byKey(const ValueKey('settings.nav.appearance'))
          .evaluate()
          .isNotEmpty,
    );
    await _tapNavigation(
      tester,
      find.byKey(const ValueKey('settings.nav.appearance')),
    );
    await _tapNavigation(tester, find.text('显示目录导航'));
    await expectSaved(false, true);
    await _tapNavigation(tester, find.byTooltip('返回'));
    await _waitFor(
      tester,
      () => find
          .byKey(const ValueKey('settings.nav.appearance'))
          .evaluate()
          .isEmpty,
    );
    expect(find.byKey(const ValueKey('directory.panel')), findsNothing);
    await _finishViewer(tester, source);
    await _pumpArchiveHost(tester, _host(source, settings: null));
    await _waitForSelectedImage(tester);
    expect(find.byKey(const ValueKey('directory.panel')), findsNothing);
    await _openDirectory(tester);
    expect(find.byKey(const ValueKey('directory.docked')), findsOneWidget);
    await expectSaved(true, true);
    expect(tester.takeException(), isNull);
    await _finishViewer(tester, source);
  });

  testWidgets(
    'saved directory pin survives flat archives and reopening the viewer',
    (tester) async {
      _mockHost(tester);
      final directory = Directory.systemTemp.createTempSync(
        'viewer-saved-directory-',
      );
      addTearDown(() => _deleteFixture(directory));
      final flat = _archive(directory, 'flat.cbz');
      final chapters = _navigationArchive(directory);
      final store = AppConfigStore(filePath: '${directory.path}/config.json');
      await tester.runAsync(
        () => const ViewerSettings(pinDirectoryPanel: true).save(store: store),
      );
      await _pumpArchiveHost(tester, _host(flat, settings: null));
      await _waitForSelectedImage(tester);
      expect(find.byKey(const ValueKey('directory.panel')), findsOneWidget);
      final canvasLeft = tester
          .getRect(find.byKey(const ValueKey('viewer.content')))
          .left;
      final panelWidth = tester
          .getSize(find.byKey(const ValueKey('directory.sizedPanel')))
          .width;
      await _pixels(tester, 'directory-flat-stable');
      expect(find.byKey(const ValueKey('navigation.compact')), findsNothing);
      final controller = _bar(tester)!.controller;
      await tester.runAsync(() async {
        unawaited(controller.openArchive(chapters));
      });
      await _waitFor(
        tester,
        () =>
            controller.archiveContext?.archiveFile.path == chapters.path &&
            !controller.isOpeningArchive,
      );
      await _waitForSelectedImage(tester);
      expect(find.byKey(const ValueKey('directory.docked')), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('viewer.content'))).left,
        canvasLeft,
      );
      await _tapNavigation(tester, find.byKey(const ValueKey('directory.pin')));
      await _waitForSavedDirectoryPin(tester, store, false);
      expect(find.byKey(const ValueKey('directory.docked')), findsNothing);
      expect(find.byKey(const ValueKey('directory.barrier')), findsOneWidget);
      await _tapNavigation(tester, find.byKey(const ValueKey('directory.pin')));
      await _waitForSavedDirectoryPin(tester, store, true);
      expect(find.byKey(const ValueKey('directory.docked')), findsOneWidget);
      await tester.runAsync(() async {
        unawaited(controller.openArchive(flat));
      });
      await _waitFor(
        tester,
        () =>
            controller.archiveContext?.archiveFile.path == flat.path &&
            !controller.isOpeningArchive,
      );
      await _waitForSelectedImage(tester);
      expect(find.byKey(const ValueKey('directory.panel')), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('viewer.content'))).left,
        canvasLeft,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('directory.sizedPanel')))
            .width,
        panelWidth,
      );
      expect(
        (await tester.runAsync(() => ViewerSettings.load(store: store)))!
            .pinDirectoryPanel,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await _drain(tester);
      await _pumpArchiveHost(tester, _host(chapters, settings: null));
      await _waitForSelectedImage(tester);
      expect(find.byKey(const ValueKey('directory.docked')), findsOneWidget);
      expect(find.byKey(const ValueKey('directory.pin')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _drain(tester);
      // Finish the final history write before this test's FakeAsync zone ends.
      var flushed = false;
      await tester.runAsync(() async {
        unawaited(store.update((config) => config).then((_) => flushed = true));
      });
      await _waitFor(tester, () => flushed);
    },
  );

  for (final continuous in [false, true]) {
    testWidgets(
      'recursive folder directory switches siblings with continuous=$continuous',
      (tester) async {
        _mockHost(tester);
        await _loadCaptureFonts(tester);
        final directory = Directory.systemTemp.createTempSync(
          'viewer-folder-directory-',
        );
        addTearDown(() => _deleteFixture(directory));
        final archive = ZipDecoder().decodeBytes(
          _navigationArchive(directory).readAsBytesSync(),
        );
        final folder = Directory(paths.join(directory.path, '我的漫画'))
          ..createSync();
        for (final entry in archive.files.where((entry) => entry.isFile)) {
          final file = File(paths.join(folder.path, entry.name));
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(entry.content);
        }
        await _pumpArchiveHost(
          tester,
          _host(
            File(folder.path),
            settings: ViewerSettings(
              showDirectoryPanel: false,
              browseMode: continuous
                  ? FolderBrowseMode.recursiveFlat
                  : FolderBrowseMode.recursiveFolders,
              sortOrder: SortOrder.nameAscending,
            ),
          ),
        );
        await _waitForSelectedImage(tester);
        final controller = _bar(tester)!.controller;
        expect(controller.entries.length, continuous ? 4 : 1);
        final volume = paths.join(folder.path, '第1卷');
        final chapter = paths.join(volume, '第02章');
        await _openDirectory(tester);
        await _tapNavigation(
          tester,
          find.byKey(ValueKey('directory.expand:$volume')),
        );
        await _waitFor(
          tester,
          () => find
              .byKey(ValueKey('directory.item:$chapter'))
              .evaluate()
              .isNotEmpty,
        );
        await _tapNavigation(
          tester,
          find.byKey(ValueKey('directory.item:$chapter')),
        );
        await _waitForSelectedImage(tester);
        _expectSelectedChapter(tester, chapter);
        expect(controller.entries.length, continuous ? 4 : 1);
        expect(
          (await _pixels(tester, 'folder-chapter-$continuous'))[2],
          greaterThan(5000),
        );
        await _openDirectory(tester);
        final selected = find
            .ancestor(
              of: find.byKey(ValueKey('directory.item:$chapter')),
              matching: find.byType(Semantics),
            )
            .first;
        expect(tester.widget<Semantics>(selected).properties.selected, isTrue);
        await _pixels(tester, 'folder-directory-$continuous');
        await _tapNavigation(
          tester,
          find.byKey(const ValueKey('directory.close')),
        );
        final selectedId = controller.currentEntry!.id;
        for (final mode in [
          FolderBrowseMode.recursiveFlat,
          FolderBrowseMode.recursiveFolders,
        ]) {
          var completed = false;
          await tester.runAsync(() async {
            unawaited(
              controller
                  .setOptions(browseMode: mode)
                  .then((_) => completed = true),
            );
          });
          await _waitFor(
            tester,
            () =>
                completed &&
                !controller.isIndexing &&
                controller.entries.length == (mode.isFlat ? 4 : 1),
          );
          await _waitForSelectedImage(tester);
          _expectSelectedChapter(tester, chapter);
          expect(controller.currentEntry!.id, selectedId);
          expect(controller.entries.length, mode.isFlat ? 4 : 1);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await _drain(tester);
      },
    );
  }

  testWidgets(
    'neighbor prefetch survives deactivation and resumes after reattachment',
    (tester) async {
      _mockHost(tester);
      final directory = Directory.systemTemp.createTempSync(
        'viewer-prefetch-lifecycle-',
      );
      addTearDown(() => _deleteFixture(directory));
      final viewerKey = GlobalKey();
      const slotKey = ValueKey('viewer-lifecycle-slot');
      final page = ViewerPage(
        key: viewerKey,
        initialPath: _archive(directory, 'lifecycle.cbz').path,
        initialSettings: const ViewerSettings(showDirectoryPanel: false),
        configStore: AppConfigStore(filePath: '${directory.path}/config.json'),
        archiveService: ArchiveService(
          cachePolicy: ArchiveCachePolicy(
            directory: Directory('${directory.path}/cache'),
          ),
        ),
      );
      await _pumpArchiveHost(
        tester,
        RepaintBoundary(
          key: _captureKey,
          child: MaterialApp(
            theme: AppTheme.dark(),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SizedBox(key: slotKey, child: page),
          ),
        ),
      );
      await _waitForSelectedImage(tester);
      final controller = _bar(tester)!.controller;
      final state = viewerKey.currentState!;
      final slot =
          tester.element(find.byKey(slotKey)) as SingleChildRenderObjectElement;
      await tester.runAsync(() async {
        controller.select(1);
        // Keep the page inactive across the 80 ms timer, before the next
        // frame either disposes it or reattaches its GlobalKey. mounted is
        // still true here, but ancestor lookups are already unsafe.
        slot.update(const SizedBox(key: slotKey));
        expect(state.mounted, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        slot.owner!.buildScope(
          slot,
          () => slot.update(SizedBox(key: slotKey, child: page)),
        );
      });
      await _waitForSelectedImage(tester);
      expect(viewerKey.currentState, same(state));
      expect(controller.currentIndex, 1);
      expect(
        (await _pixels(tester, 'prefetch-reattached'))[1],
        greaterThan(5000),
      );
      // A permanently removed page must also ignore late decode completions.
      await tester.runAsync(() async {
        controller.select(2);
        slot.update(const SizedBox(key: slotKey));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpWidget(const SizedBox());
      await _drain(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('navigation hides the entire row for a flat archive root', (
    tester,
  ) async {
    _mockHost(tester);
    await _loadCaptureFonts(tester);
    final directory = Directory.systemTemp.createTempSync(
      'viewer-flat-navigation-',
    );
    addTearDown(() => _deleteFixture(directory));
    await _pumpArchiveHost(tester, _host(_archive(directory, 'flat.cbz')));
    await _waitForSelectedImage(tester);
    expect(find.byKey(const ValueKey('navigation.compact')), findsNothing);
    expect(find.byKey(const ValueKey('archive.previous')), findsNothing);
    expect(find.byKey(const ValueKey('archive.next')), findsNothing);
    expect(tester.getSize(find.byType(ViewerBottomBar)).height, 88);
    expect((await _pixels(tester, 'navigation-flat'))[0], greaterThan(5000));
    await tester.pumpWidget(const SizedBox());
    await _drain(tester);
  });

  for (final continuous in [false, true]) {
    testWidgets(
      'compact navigation switches sibling chapters at narrow widths (continuous=$continuous)',
      (tester) async {
        _mockHost(tester);
        await _loadCaptureFonts(tester);
        final directory = Directory.systemTemp.createTempSync(
          'viewer-chapter-navigation-',
        );
        addTearDown(() => _deleteFixture(directory));
        final settings = ViewerSettings(
          showDirectoryPanel: false,
          archiveContinuousReading: continuous,
        );
        await _pumpArchiveHost(
          tester,
          _host(
            _navigationArchive(directory),
            settings: settings,
            themeOverride: continuous ? null : AppTheme.light(),
          ),
        );
        await _waitForSelectedImage(tester);
        final controller = _bar(tester)!.controller;
        final root = controller.archiveContext!.extractionRoot;
        final volume = paths.join(root, '第1卷');
        final first = paths.join(volume, '第01章');
        final second = paths.join(volume, '第02章');
        await _openDirectory(tester);
        await _tapNavigation(
          tester,
          find.byKey(ValueKey('directory.expand:$volume')),
        );
        await _waitFor(
          tester,
          () => find
              .byKey(ValueKey('directory.item:$first'))
              .evaluate()
              .isNotEmpty,
        );
        await _tapNavigation(
          tester,
          find.byKey(ValueKey('directory.item:$first')),
        );
        await _waitFor(
          tester,
          () => controller.currentEntry?.relativePath == '第1卷/第01章/001.png',
        );
        await _waitForSelectedImage(tester);
        expect(controller.entries.length, continuous ? 4 : 1);
        _expectSelectedChapter(tester, first);
        expect(find.byKey(const ValueKey('directory.panel')), findsNothing);
        await _tapNavigation(
          tester,
          find.byKey(const ValueKey('navigation.nextChapter')),
        );
        await _waitFor(
          tester,
          () => controller.currentEntry?.relativePath == '第1卷/第02章/001.png',
        );
        await _waitForSelectedImage(tester);
        _expectSelectedChapter(tester, second);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('navigation.chapter')))
              .width,
          lessThan(180),
        );
        tester.view.physicalSize = const Size(440, 800);
        await _waitForSelectedImage(tester);
        expect(find.text('第02章'), findsOneWidget);
        expect(
          tester
              .getRect(find.byKey(const ValueKey('navigation.chapter')))
              .right,
          lessThan(410),
        );
        expect(
          (await _pixels(tester, 'navigation-narrow-$continuous'))[2],
          greaterThan(5000),
        );
        final selected = controller.currentEntry!.id;
        controller.configureArchive(
          settings.copyWith(archiveContinuousReading: !continuous),
        );
        await _waitForSelectedImage(tester);
        expect(controller.currentEntry!.id, selected);
        expect(controller.entries.length, continuous ? 1 : 4);
        _expectSelectedChapter(tester, second);
        final select = tester.widget<AppSelect<String>>(
          find.byKey(const ValueKey('navigation.chapter')),
        );
        expect(select.options.map((option) => option.label), [
          '第01章',
          '第02章',
          '单行本.cbz',
        ]);
        await _openDirectory(tester);
        await _waitFor(
          tester,
          () => find
              .byKey(ValueKey('directory.item:$second'))
              .evaluate()
              .isNotEmpty,
        );
        final selectedSemantics = tester.widgetList<Semantics>(
          find.ancestor(
            of: find.byKey(ValueKey('directory.item:$second')),
            matching: find.byType(Semantics),
          ),
        );
        expect(
          selectedSemantics.any(
            (semantics) => semantics.properties.selected == true,
          ),
          isTrue,
        );
        await _pixels(tester, 'directory-narrow-$continuous');
        await _tapNavigation(
          tester,
          find.byKey(const ValueKey('directory.close')),
        );
        await _tapNavigation(
          tester,
          find.byKey(const ValueKey('navigation.chapter')),
        );
        await _tapNavigation(
          tester,
          find.widgetWithText(MenuItemButton, '第01章'),
        );
        await _waitFor(
          tester,
          () => controller.currentEntry?.relativePath == '第1卷/第01章/001.png',
        );
        await _waitForSelectedImage(tester);
        expect(
          (await _pixels(tester, 'navigation-dropdown-$continuous'))[1],
          greaterThan(5000),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await _drain(tester);
      },
    );
  }

  testWidgets(
    'directory navigation pins, adapts to narrow windows and searches deep chapters',
    (tester) async {
      _mockHost(tester);
      await _loadCaptureFonts(tester);
      final directory = Directory.systemTemp.createTempSync(
        'viewer-directory-panel-',
      );
      addTearDown(() => _deleteFixture(directory));
      await _pumpArchiveHost(
        tester,
        _host(
          _navigationArchive(directory),
          settings: const ViewerSettings(pinDirectoryPanel: true),
        ),
      );
      await _waitForSelectedImage(tester);
      final controller = _bar(tester)!.controller;
      final root = controller.archiveContext!.extractionRoot;
      final selected = controller.currentEntry!.id;
      await _waitFor(
        tester,
        () => find
            .byKey(const ValueKey('directory.docked'))
            .evaluate()
            .isNotEmpty,
      );
      expect(find.byKey(const ValueKey('directory.barrier')), findsNothing);
      await _waitForSelectedImage(tester);
      expect(controller.currentEntry!.id, selected);
      expect((await _pixels(tester, 'directory-pinned'))[0], greaterThan(5000));
      await _tapNavigation(tester, find.byKey(const ValueKey('directory.pin')));
      await _waitFor(
        tester,
        () => find
            .byKey(const ValueKey('directory.barrier'))
            .evaluate()
            .isNotEmpty,
      );
      expect(find.byKey(const ValueKey('directory.docked')), findsNothing);
      expect(controller.currentEntry!.id, selected);
      await _tapNavigation(tester, find.byKey(const ValueKey('directory.pin')));
      await _waitFor(
        tester,
        () => find
            .byKey(const ValueKey('directory.docked'))
            .evaluate()
            .isNotEmpty,
      );
      tester.view.physicalSize = const Size(440, 800);
      await tester.pump();
      expect(find.byKey(const ValueKey('directory.docked')), findsOneWidget);
      expect(find.byKey(const ValueKey('directory.barrier')), findsNothing);
      expect(find.byKey(const ValueKey('directory.pin')), findsOneWidget);
      expect(controller.currentEntry!.id, selected);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('directory.search')),
          matching: find.byType(TextField),
        ),
        '上篇',
      );
      final chapter = paths.join(root, '第2卷', '上篇', '第01章');
      await _waitFor(
        tester,
        () => find
            .byKey(ValueKey('directory.item:$chapter'))
            .evaluate()
            .isNotEmpty,
      );
      await _pixels(tester, 'directory-search');
      await _tapNavigation(
        tester,
        find.byKey(ValueKey('directory.item:$chapter')),
      );
      await _waitFor(
        tester,
        () => controller.currentEntry?.relativePath == '第2卷/上篇/第01章/001.png',
      );
      await _waitForSelectedImage(tester);
      expect(find.byKey(const ValueKey('directory.panel')), findsOneWidget);
      expect(
        (await _pixels(tester, 'directory-search-selected'))[3],
        greaterThan(5000),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(const ValueKey('directory.panel')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _drain(tester);
    },
  );

  testWidgets(
    'directory navigation enters nested archives and restores the outer image on return',
    (tester) async {
      _mockHost(tester);
      await _loadCaptureFonts(tester);
      final directory = Directory.systemTemp.createTempSync(
        'viewer-nested-navigation-',
      );
      addTearDown(() => _deleteFixture(directory));
      await _pumpArchiveHost(tester, _host(_navigationArchive(directory)));
      await _waitForSelectedImage(tester);
      final controller = _bar(tester)!.controller;
      final outer = controller.archiveContext!;
      final volume = paths.join(outer.extractionRoot, '第1卷');
      final chapter = paths.join(volume, '第02章');
      await _openDirectory(tester);
      await _tapNavigation(
        tester,
        find.byKey(ValueKey('directory.expand:$volume')),
      );
      await _waitFor(
        tester,
        () => find
            .byKey(ValueKey('directory.item:$chapter'))
            .evaluate()
            .isNotEmpty,
      );
      await _tapNavigation(
        tester,
        find.byKey(ValueKey('directory.item:$chapter')),
      );
      await _waitForSelectedImage(tester);
      final selectedId = controller.currentEntry!.id;
      final nested = controller.navigationContainers.single;
      await _openDirectory(tester);
      await _waitFor(
        tester,
        () => find
            .byKey(ValueKey('directory.item:${nested.id}'))
            .evaluate()
            .isNotEmpty,
      );
      await _tapNavigation(
        tester,
        find.byKey(ValueKey('directory.item:${nested.id}')),
      );
      // Nested acquisition also drains parent archive/cache writes. Give real
      // Windows filesystem IO its own budget when the full suite is running.
      await _waitFor(
        tester,
        () => controller.archiveContext?.parent == outer,
        attempts: 600,
      );
      await _waitForSelectedImage(tester);
      expect(
        (await _pixels(tester, 'navigation-inner-archive'))[4],
        greaterThan(5000),
      );
      final inner = controller.archiveContext!;
      final appendix = controller.navigationContainers.single;
      await _openDirectory(tester);
      await _waitFor(
        tester,
        () => find
            .byKey(ValueKey('directory.item:${appendix.id}'))
            .evaluate()
            .isNotEmpty,
      );
      await _tapNavigation(
        tester,
        find.byKey(ValueKey('directory.item:${appendix.id}')),
      );
      await _waitFor(
        tester,
        () => controller.archiveContext?.parent == inner,
        attempts: 600,
      );
      await _waitForSelectedImage(tester);
      expect(
        (await _pixels(tester, 'navigation-deep-archive'))[5],
        greaterThan(5000),
      );
      for (final expected in [inner, outer]) {
        await _openDirectory(tester);
        expect(find.byKey(const ValueKey('directory.parent')), findsNothing);
        final target = expected == inner ? nested.id : chapter;
        await _waitFor(
          tester,
          () => find
              .byKey(ValueKey('directory.item:$target'))
              .evaluate()
              .isNotEmpty,
        );
        await _tapNavigation(
          tester,
          find.byKey(ValueKey('directory.item:$target')),
        );
        await _waitFor(tester, () => controller.archiveContext == expected);
        await _waitForSelectedImage(tester);
      }
      expect(controller.currentEntry!.id, selectedId);
      _expectSelectedChapter(tester, chapter);
      expect(
        (await _pixels(tester, 'navigation-nested-return'))[2],
        greaterThan(5000),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _drain(tester);
    },
  );

  for (final allPagesInvalid in [false, true]) {
    testWidgets(
      'invalid first PNG keeps Chinese chapters navigable (all invalid: $allPagesInvalid)',
      (tester) async {
        _mockHost(tester);
        await _loadCaptureFonts(tester);
        final directory = Directory.systemTemp.createTempSync(
          'viewer-bad-png-',
        );
        addTearDown(() => _deleteFixture(directory));
        // A readable ZIP containing the same malformed 1x1 PNG as the reported
        // chapter archive: its IDAT CRC is invalid, so the image codec rejects it.
        final malformed = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
        );
        final valid = ZipDecoder()
            .decodeBytes(_archive(directory, 'valid.cbz').readAsBytesSync())
            .files
            .first
            .content;
        final archive = Archive();
        for (var chapter = 1; chapter <= 3; chapter++) {
          for (var page = 1; page <= 3; page++) {
            final name =
                '第${chapter.toString().padLeft(2, '0')}章/${page.toString().padLeft(3, '0')}.png';
            archive.addFile(
              ArchiveFile.bytes(
                name,
                !allPagesInvalid && chapter == 1 && page == 2
                    ? valid
                    : malformed,
              ),
            );
          }
        }
        final source = File('${directory.path}/我的漫画_分章节.zip')
          ..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
        await _pumpArchiveHost(tester, _host(source));
        await _waitFor(
          tester,
          () => _bar(tester)?.controller.archiveContext != null,
        );
        final controller = _bar(tester)!.controller;
        expect(controller.lastArchiveFailure, isNull);
        expect(controller.entries.length, 9);
        expect(controller.childFolders.map((folder) => folder.name), [
          '第01章',
          '第02章',
          '第03章',
        ]);
        await _waitFor(
          tester,
          () => find.text('无法解析 001.png').evaluate().isNotEmpty,
        );
        await _pixels(tester, 'invalid-png-first-$allPagesInvalid');

        if (allPagesInvalid) {
          await tester.runAsync(
            () => controller.navigateToFolder(
              controller.childFolders[1].directory.path,
            ),
          );
          await _drain(tester);
          expect(controller.currentEntry!.relativePath, '第02章/001.png');
          expect(controller.lastArchiveFailure, isNull);
        } else {
          await tester.runAsync(
            () => tester.tap(find.byKey(ValueKey(controller.entries[1].id))),
          );
          await _waitFor(tester, () => controller.currentIndex == 1);
          await _waitForSelectedImage(tester);
          expect(
            (await _pixels(tester, 'valid-png-after-bad-first'))[0],
            greaterThan(5000),
          );
          expect(find.text('无法解析 001.png'), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await _drain(tester);
      },
    );
  }

  for (final archiveView in [false, true]) {
    final label = 'audit-${archiveView ? 'archive' : 'folder'}';
    testWidgets('$label preserves image state through scale and idle input', (
      tester,
    ) async {
      _mockHost(tester);
      await _loadCaptureFonts(tester);
      final directory = Directory.systemTemp.createTempSync('viewer-audit-');
      addTearDown(() => _deleteFixture(directory));
      await _pumpArchiveHost(
        tester,
        _host(
          _scrollFixture(directory, archiveView),
          settings: const ViewerSettings(
            showDirectoryPanel: false,
            doublePageFirstAlone: false,
          ),
        ),
      );
      await _waitForSelectedImage(tester);
      await _chooseMode(tester, '双页');
      await _waitForSelectedImage(tester, minimum: 2);
      final viewport = find.byType(ZoomableViewport);
      final images = find.descendant(
        of: viewport,
        matching: find.byType(RawImage),
      );
      final originalElements = images.evaluate().toList();
      expect(originalElements, hasLength(2));
      for (final button in ['实际大小 · 0', '适应窗口 · F', '实际大小 · 0', '适应窗口 · F']) {
        await tester.tap(find.byTooltip(button));
        await tester.pump();
        expect(images.evaluate().toList(), originalElements);
        expect(
          tester
              .widgetList<RawImage>(images)
              .every((image) => image.image != null),
          isTrue,
          reason: 'Keep the displayed frames while the new decode is pending.',
        );
        final painted = tester.renderObject<RenderTransform>(
          find.descendant(of: viewport, matching: find.byType(Transform)).first,
        );
        expect(
          painted.child!.getTransformTo(painted),
          tester.widget<ZoomableViewport>(viewport).controller.value,
        );
        await _pixels(tester, '$label-$button-first-frame');
        await _waitForSelectedImage(tester, minimum: 2);
      }
      await tester.tap(find.byTooltip('实际大小 · 0'));
      await _waitForSelectedImage(tester, minimum: 2);
      final beforeFlip = tester
          .widget<ZoomableViewport>(viewport)
          .controller
          .value
          .clone();
      for (var flip = 0; flip < 2; flip++) {
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip && widget.message?.startsWith('水平翻转') == true,
          ),
        );
        await tester.pump();
        final painted = tester.renderObject<RenderTransform>(
          find.descendant(of: viewport, matching: find.byType(Transform)).first,
        );
        expect(painted.child!.getTransformTo(painted), beforeFlip);
        expect(images.evaluate().toList(), originalElements);
        await _pixels(tester, '$label-flip-first-frame-$flip');
      }
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(viewport));
      await tester.pump();
      final beforeHover = tester.widget<ZoomableViewport>(viewport);
      await mouse.moveTo(const Offset(640, 20));
      await tester.pump();
      expect(tester.widget<ZoomableViewport>(viewport), same(beforeHover));
      expect(
        tester.widget<HdrOverlayScope>(find.byType(HdrOverlayScope)).suspended,
        isTrue,
      );
      await mouse.moveTo(tester.getCenter(viewport));
      await tester.pump();
      expect(tester.widget<ZoomableViewport>(viewport), same(beforeHover));
      expect(
        tester.widget<HdrOverlayScope>(find.byType(HdrOverlayScope)).suspended,
        isFalse,
      );
      // End a real pan without crossing the zoomed/unzoomed state boundary.
      beforeHover.commands!.setScale(2);
      await _drain(tester);
      final beforeDrag = tester.widget<ZoomableViewport>(viewport);
      await tester.drag(viewport, const Offset(-40, -35));
      await tester.pump();
      expect(tester.widget<ZoomableViewport>(viewport), same(beforeDrag));
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _drain(tester);
    });
  }

  for (final archiveView in [false, true]) {
    for (final doublePage in [false, true]) {
      final label =
          'repeat-${archiveView ? 'archive' : 'folder'}-${doublePage ? 'double' : 'single'}';
      testWidgets('$label keeps repeated scale and thumbnail clicks stable', (
        tester,
      ) async {
        _mockHost(tester);
        await _loadCaptureFonts(tester);
        final directory = Directory.systemTemp.createTempSync(
          'viewer-repeat-selection-',
        );
        addTearDown(() => _deleteFixture(directory));
        await _pumpArchiveHost(
          tester,
          _host(
            _scrollFixture(directory, archiveView),
            settings: const ViewerSettings(
              showDirectoryPanel: false,
              doublePageFirstAlone: false,
            ),
          ),
        );
        await _waitForSelectedImage(tester);
        if (doublePage) await _chooseMode(tester, '双页');
        await _waitForSelectedImage(tester, minimum: doublePage ? 2 : 1);
        final controller = _bar(tester)!.controller;
        for (final button in ['实际大小 · 0', '适应窗口 · F']) {
          await tester.tap(find.byTooltip(button));
          await _waitForSelectedImage(tester, minimum: doublePage ? 2 : 1);
          final transform = tester
              .widget<ZoomableViewport>(find.byType(ZoomableViewport))
              .controller;
          final before = transform.value.clone();
          final pixels = await _pixels(tester, '$label-$button-before');
          expect(pixels.first, greaterThan(5000));
          var changes = 0;
          void changed() => changes++;
          transform.addListener(changed);
          try {
            for (var click = 0; click < 3; click++) {
              await tester.tap(find.byTooltip(button));
              await tester.pump();
              expect(transform.value, before);
              expect(changes, 0);
              expect(
                await _pixels(tester, '$label-$button-frame-$click'),
                pixels,
              );
            }
            // A selected thumbnail must preserve manual zoom and pan too.
            transform.value = Matrix4.identity()
              ..scaleByDouble(3, 3, 3, 1)
              ..setTranslationRaw(-90, -160, 0);
            await _drain(tester);
            final zoomed = transform.value.clone();
            final zoomedPixels = await _pixels(tester, '$label-$button-zoomed');
            changes = 0;
            await _chooseMode(tester, doublePage ? '双页' : '单页');
            expect(transform.value, zoomed);
            expect(
              changes,
              0,
              reason: 'Selecting the active mode must not reset the view.',
            );
            for (var click = 0; click < 3; click++) {
              await tester.tap(
                find.byKey(ValueKey(controller.currentEntry!.id)),
              );
              await tester.pump();
              expect(transform.value, zoomed);
              expect(changes, 0);
              expect(
                await _pixels(tester, '$label-$button-thumbnail-$click'),
                zoomedPixels,
              );
            }
            // The same scale button still restores a manually changed view,
            // with one final matrix rather than an identity/center sequence.
            await tester.tap(find.byTooltip(button));
            expect(transform.value, before);
            expect(changes, 1);
            await tester.pump();
            expect(transform.value, before);
            expect(changes, 1);
          } finally {
            transform.removeListener(changed);
          }
        }
        if (archiveView) {
          final before = tester
              .widget<ZoomableViewport>(find.byType(ZoomableViewport))
              .controller
              .value
              .clone();
          // Duplicate requests do not restart a pending page. Clicking the
          // visible thumbnail instead cancels that pending navigation.
          _bar(tester)!.onSelect(2);
          _bar(tester)!.onSelect(2);
          _bar(tester)!.onSelect(controller.currentIndex);
          await _drain(tester);
          expect(controller.currentIndex, 0);
          expect(
            tester
                .widget<ZoomableViewport>(find.byType(ZoomableViewport))
                .controller
                .value,
            before,
          );
          _bar(tester)!.onSelect(2);
          _bar(tester)!.onSelect(2);
          await _waitFor(tester, () => controller.currentIndex == 2);
          await _waitForSelectedImage(tester, minimum: doublePage ? 2 : 1);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await _drain(tester);
      });
    }
  }

  for (final archiveView in [false, true]) {
    for (final doublePage in [false, true]) {
      final label =
          'scroll-${archiveView ? 'archive' : 'folder'}-${doublePage ? 'double' : 'single'}';
      testWidgets('$label limits continuous trackpad page rate', (
        tester,
      ) async {
        _mockHost(tester);
        await _loadCaptureFonts(tester);
        final directory = Directory.systemTemp.createTempSync(
          'viewer-scroll-regression-',
        );
        addTearDown(() => _deleteFixture(directory));
        await _pumpArchiveHost(
          tester,
          _host(
            _scrollFixture(directory, archiveView),
            settings: const ViewerSettings(
              showDirectoryPanel: false,
              doublePageFirstAlone: false,
            ),
          ),
        );
        await _waitForSelectedImage(tester);
        if (doublePage) await _chooseMode(tester, '双页');
        final controller = _bar(tester)!.controller;
        var elapsed = 0;
        Future<void> scroll(
          Offset delta, {
          int pause = 8,
          bool thumbnails = false,
        }) {
          elapsed += pause;
          return tester.sendEventToBinding(
            PointerScrollEvent(
              kind: PointerDeviceKind.mouse,
              position: tester.getCenter(
                find.byType(thumbnails ? ViewerBottomBar : ZoomableViewport),
              ),
              timeStamp: Duration(milliseconds: elapsed),
              scrollDelta: delta,
            ),
          );
        }

        await scroll(const Offset(80, 0));
        await scroll(const Offset(0, 40));
        expect(controller.currentIndex, 0);
        for (var i = 0; i < 40; i++) {
          await scroll(const Offset(0, 0.1), pause: i == 0 ? 300 : 8);
        }
        expect(controller.currentIndex, 0, reason: '4px must not turn a page.');
        await scroll(const Offset(0, 16));
        final step = doublePage ? 2 : 1;
        await _waitFor(tester, () => controller.currentIndex == step);
        await _waitForSelectedImage(tester, minimum: step);
        final transform = tester
            .widget<ZoomableViewport>(find.byType(ZoomableViewport))
            .controller;
        final before = transform.value.clone();
        final pixels = await _pixels(tester, '$label-before-inertia');
        expect(pixels.reduce((a, b) => a + b), greaterThan(5000));
        var changes = 0;
        void onTransform() => changes++;
        transform.addListener(onTransform);
        try {
          for (var i = 0; i < 22; i++) {
            await scroll(const Offset(0, 20));
          }
          expect(controller.currentIndex, step);
          expect(transform.value, before);
          expect(changes, 0);
          await tester.pump();
          expect(await _pixels(tester, '$label-after-inertia'), pixels);
        } finally {
          transform.removeListener(onTransform);
        }
        // The same uninterrupted gesture turns again when the interval elapses.
        await scroll(const Offset(0, 20), pause: 4);
        await _waitFor(tester, () => controller.currentIndex == step * 2);
        await _waitForSelectedImage(tester, minimum: step);
        await tester.sendEventToBinding(
          PointerScrollInertiaCancelEvent(
            position: tester.getCenter(find.byType(ZoomableViewport)),
          ),
        );
        await scroll(const Offset(0, -20));
        expect(controller.currentIndex, step * 2);
        await scroll(const Offset(0, -20), pause: 180);
        await _waitFor(tester, () => controller.currentIndex == step);
        await _waitForSelectedImage(tester, minimum: step);
        // Thumbnail wheel navigation uses the same spread boundaries and the
        // pending archive selection, even before extraction has completed.
        await scroll(const Offset(0, 20), pause: 300, thumbnails: true);
        await scroll(const Offset(0, 20), pause: 180, thumbnails: true);
        final thumbnailTarget = doublePage ? 4 : 3;
        await _waitFor(
          tester,
          () => controller.currentIndex == thumbnailTarget,
        );
        await _waitForSelectedImage(tester, minimum: step);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await _drain(tester);
      });
    }
  }

  for (final archiveView in [false, true]) {
    for (final doublePage in [false, true]) {
      testWidgets(
        'held arrows repeat and stop in archive=$archiveView double=$doublePage',
        (tester) async {
          _mockHost(tester);
          final directory = Directory.systemTemp.createTempSync(
            'viewer-held-navigation-',
          );
          addTearDown(() => _deleteFixture(directory));
          await _pumpArchiveHost(
            tester,
            _host(
              _scrollFixture(directory, archiveView),
              settings: const ViewerSettings(
                showDirectoryPanel: false,
                doublePageFirstAlone: false,
                interaction: ViewerInteractionSettings(
                  holdDelayMs: 200,
                  holdIntervalMs: 120,
                ),
              ),
            ),
          );
          await _waitForSelectedImage(tester);
          if (doublePage) await _chooseMode(tester, '双页');
          final controller = _bar(tester)!.controller;
          final step = doublePage ? 2 : 1;
          Future<void> selected(int index) async {
            for (
              var attempt = 0;
              attempt < 200 && controller.currentIndex != index;
              attempt++
            ) {
              await tester.pump();
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 20)),
              );
            }
            expect(controller.currentIndex, index);
          }

          await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
          await selected(step);
          await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
          expect(
            controller.currentIndex,
            step,
            reason: 'OS repeat must not bypass the configured delay.',
          );
          await tester.pump(const Duration(milliseconds: 199));
          expect(controller.currentIndex, step);
          await tester.pump(const Duration(milliseconds: 1));
          await selected(step * 2);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump(const Duration(seconds: 1));
          expect(controller.currentIndex, step * 2);

          await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
          await selected(step);
          final listener =
              tester.state(find.byType(ViewerPage)) as WindowListener;
          listener.onWindowBlur();
          await tester.pump(const Duration(milliseconds: 600));
          expect(controller.currentIndex, step);
          listener.onWindowFocus();
          await tester.pump(const Duration(milliseconds: 600));
          expect(
            controller.currentIndex,
            step,
            reason: 'Regaining focus must not resume a held key.',
          );
          await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
          await selected(0);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
          await _waitForSelectedImage(tester, minimum: step);
          final transform = tester
              .widget<ZoomableViewport>(find.byType(ZoomableViewport))
              .controller;
          final before = transform.value.clone();
          var changes = 0;
          void changed() => changes++;
          transform.addListener(changed);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pump(const Duration(milliseconds: 800));
          await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
          expect(controller.currentIndex, 0);
          expect(transform.value, before);
          expect(changes, 0);
          transform.removeListener(changed);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await _drain(tester);
        },
      );
    }
  }

  testWidgets('edge navigation repeats only while pressed inside its button', (
    tester,
  ) async {
    _mockHost(tester);
    final directory = Directory.systemTemp.createTempSync('viewer-edge-hold-');
    addTearDown(() => _deleteFixture(directory));
    await _pumpArchiveHost(
      tester,
      _host(
        _scrollFixture(directory, false),
        settings: const ViewerSettings(
          showDirectoryPanel: false,
          interaction: ViewerInteractionSettings(
            holdDelayMs: 200,
            holdIntervalMs: 120,
          ),
        ),
      ),
    );
    await _waitForSelectedImage(tester);
    final controller = _bar(tester)!.controller;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(find.byType(ZoomableViewport)),
    );
    final viewport = tester.getRect(find.byType(ZoomableViewport));
    await mouse.moveTo(
      Offset(tester.view.physicalSize.width - 24, viewport.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 150));
    final next = tester.getCenter(find.byTooltip('下一个'));
    await mouse.down(next);
    expect(controller.currentIndex, 1);
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.currentIndex, 2);
    await mouse.up();
    expect(
      controller.currentIndex,
      2,
      reason: 'Releasing must not add a second tap.',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.currentIndex, 2);
    await mouse.down(next);
    expect(controller.currentIndex, 3);
    await mouse.moveTo(viewport.center);
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      controller.currentIndex,
      3,
      reason: 'Leaving the button must cancel repetition.',
    );
    await mouse.up();
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await _drain(tester);
  });

  testWidgets(
    'wheel zoom preference preserves Ctrl zoom and continuous view modes',
    (tester) async {
      _mockHost(tester);
      final directory = Directory.systemTemp.createTempSync(
        'viewer-scroll-modes-',
      );
      addTearDown(() => _deleteFixture(directory));
      await _pumpArchiveHost(
        tester,
        _host(
          _scrollFixture(directory, false),
          settings: const ViewerSettings(
            showDirectoryPanel: false,
            interaction: ViewerInteractionSettings(
              wheelAction: WheelAction.zoom,
            ),
          ),
        ),
      );
      await _waitForSelectedImage(tester);
      final controller = _bar(tester)!.controller;
      var elapsed = 0;
      Future<void> scroll(double dy) {
        elapsed += 16;
        return tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(find.byType(ZoomableViewport)),
            timeStamp: Duration(milliseconds: elapsed),
            scrollDelta: Offset(0, dy),
          ),
        );
      }

      final transform = tester
          .widget<ZoomableViewport>(find.byType(ZoomableViewport))
          .controller;
      final oldScale = transform.value.getMaxScaleOnAxis();
      await scroll(-40);
      expect(transform.value.getMaxScaleOnAxis(), greaterThan(oldScale));
      expect(controller.currentIndex, 0);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await scroll(-40);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(transform.value.getMaxScaleOnAxis(), greaterThan(oldScale));
      await scroll(40);
      expect(controller.currentIndex, 0);
      tester
          .widget<ZoomableViewport>(find.byType(ZoomableViewport))
          .commands!
          .setScale(3);
      await _drain(tester);
      final trackpad = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      final focal = tester.getCenter(find.byType(ZoomableViewport));
      final beforePan = transform.value.getTranslation().y;
      await trackpad.panZoomStart(focal);
      await trackpad.panZoomUpdate(focal, pan: const Offset(0, -20));
      await trackpad.panZoomUpdate(
        focal,
        pan: const Offset(0, -60),
        scale: 1.2,
      );
      await trackpad.panZoomEnd();
      expect(transform.value.getMaxScaleOnAxis(), greaterThan(3));
      expect(transform.value.getTranslation().y, lessThan(beforePan));
      expect(controller.currentIndex, 0);
      for (final mode in ['长图', '连续阅读']) {
        await _chooseMode(tester, mode);
        await _waitForSelectedImage(tester);
        final beforeY = transform.value.getTranslation().y;
        await scroll(80);
        expect(transform.value.getTranslation().y, lessThan(beforeY));
        expect(controller.currentIndex, 0);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _drain(tester);
    },
  );

  for (final archiveView in [false, true]) {
    for (final firstAlone in <bool?>[null, true, false]) {
      final sourceName = archiveView ? 'archive' : 'folder';
      final modeName = firstAlone == null
          ? 'single'
          : 'double cover=$firstAlone';
      testWidgets(
        'boundary navigation preserves every frame in $sourceName $modeName',
        (tester) async {
          _mockHost(tester);
          await _loadCaptureFonts(tester);
          final directory = Directory.systemTemp.createTempSync(
            'viewer-boundary-regression-',
          );
          addTearDown(() => _deleteFixture(directory));
          final archive = _archive(directory, 'boundary.cbz');
          File source = archive;
          if (!archiveView) {
            final folder = Directory('${directory.path}/pages')..createSync();
            for (final file
                in ZipDecoder().decodeBytes(archive.readAsBytesSync()).files) {
              File('${folder.path}/${file.name}')
                  .writeAsBytesSync(file.content);
            }
            source = File('${folder.path}/001.png');
          }
          await _pumpArchiveHost(
            tester,
            _host(
              source,
              settings: ViewerSettings(
                showDirectoryPanel: false,
                doublePageFirstAlone: firstAlone ?? true,
              ),
            ),
          );
          await _waitForImage(tester);
          if (firstAlone != null) await _chooseMode(tester, '双页');
          final controller = _bar(tester)!.controller;
          expect(controller.isArchiveView, archiveView);
          final boundaries = [
            (0, LogicalKeyboardKey.arrowLeft),
            if (firstAlone == false) (1, LogicalKeyboardKey.arrowLeft),
            if (firstAlone == false) (4, LogicalKeyboardKey.arrowRight),
            (5, LogicalKeyboardKey.arrowRight),
          ];
          for (final (index, key) in boundaries) {
            if (controller.currentIndex != index) {
              await tester.runAsync(
                () => tester.tap(
                  find.byKey(ValueKey(controller.entries[index].id)),
                ),
              );
              await _waitFor(tester, () => controller.currentIndex == index);
            }
            await _waitForSelectedImage(
              tester,
              minimum: firstAlone == false ? 2 : 1,
            );
            for (final zoomed in [false, true]) {
              final viewport = tester.widget<ZoomableViewport>(
                find.byType(ZoomableViewport),
              );
              viewport.commands!.setScale(zoomed ? 3 : 1);
              if (zoomed) {
                viewport.commands!.moveHorizontally(-73);
                viewport.commands!.moveVertically(-91);
              }
              await _drain(tester);
              final transform = viewport.controller;
              final before = transform.value.clone();
              final label =
                  'boundary-$sourceName-$modeName-$index-zoom=$zoomed';
              final pixels = await _pixels(tester, '$label-before');
              expect(pixels.reduce((a, b) => a + b), greaterThan(5000));
              var changes = 0;
              void onTransform() => changes++;
              transform.addListener(onTransform);
              try {
                for (var press = 0; press < 3; press++) {
                  await tester.runAsync(() => tester.sendKeyEvent(key));
                  expect(controller.currentIndex, index);
                  expect(transform.value, before);
                  expect(changes, 0, reason: 'Even a temporary reset flashes.');
                  await tester.pump();
                  expect(await _pixels(tester, '$label-frame-$press'), pixels);
                }
                await _drain(tester);
                expect(controller.currentIndex, index);
                expect(transform.value, before);
                expect(changes, 0);
              } finally {
                transform.removeListener(onTransform);
              }
            }
          }
          // A valid move immediately after hitting the end still works.
          await tester.runAsync(
            () => tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft),
          );
          await _waitFor(tester, () => controller.currentIndex < 5);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await _drain(tester);
        },
      );
    }
  }

  testWidgets(
    'focus changes preserve every visible thumbnail with prefetch off in archives and folders',
    (tester) async {
      _mockHost(tester);
      await _loadCaptureFonts(tester);
      tester.view.physicalSize = const Size(1280, 800);
      final directory = Directory.systemTemp.createTempSync(
        'viewer-focus-regression-',
      );
      addTearDown(() => _deleteFixture(directory));
      final archive = _archive(directory, 'focus.cbz');
      final extracted = ZipDecoder().decodeBytes(archive.readAsBytesSync());
      final folder = Directory('${directory.path}/folder')..createSync();
      for (final file in extracted.files) {
        File('${folder.path}/${file.name}').writeAsBytesSync(file.content);
      }
      for (final source in [archive, File('${folder.path}/001.png')]) {
        // Keep the whole serial thumbnail extraction chain on real IO, rather
        // than requiring a FakeAsync pump for every individual filesystem stat.
        await tester.runAsync(() async {
          await tester.pumpWidget(
            _host(
              source,
              key: ValueKey(source.path),
              settings: const ViewerSettings(
                showDirectoryPanel: false,
                archivePrefetchMode: ArchivePrefetchMode.off,
                archiveMemoryBudgetMiB: 16,
              ),
            ),
          );
          for (var attempt = 0; attempt < 200; attempt++) {
            await tester.pump();
            final loaded = tester
                .widgetList<RawImage>(
                  find.descendant(
                    of: find.byType(ViewerBottomBar),
                    matching: find.byType(RawImage),
                  ),
                )
                .where((image) => image.image != null)
                .length;
            if (loaded == 6) break;
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
        });
        await _waitForImage(tester);
        final thumbs = find.descendant(
          of: find.byType(ViewerBottomBar),
          matching: find.byType(RawImage),
        );
        await _drain(tester);
        await _waitFor(
          tester,
          () =>
              tester
                  .widgetList<RawImage>(thumbs)
                  .where((image) => image.image != null)
                  .length ==
              6,
        );
        final images = tester
            .widgetList<RawImage>(thumbs)
            .map((image) => image.image!)
            .toList();
        final resources = _bar(tester)!.resources;
        final archiveView = _bar(tester)!.controller.isArchiveView;
        expect(
          resources.policy.maxLevel,
          archiveView ? PrefetchLevel.onDemand : PrefetchLevel.normal,
        );
        if (!archiveView) {
          expect(resources.memoryBudgetBytes, greaterThan(16 * 1024 * 1024));
        }
        final budget = resources.memoryBudgetBytes;
        final listener =
            tester.state(find.byType(ViewerPage)) as WindowListener;
        listener.onWindowBlur();
        await _drain(tester);
        expect(resources.memoryBudgetBytes, budget);
        final blurred = tester
            .widgetList<RawImage>(thumbs)
            .map((image) => image.image!)
            .toList();
        expect(blurred.length, images.length);
        for (var index = 0; index < images.length; index++) {
          expect(blurred[index].isCloneOf(images[index]), isTrue);
        }
        await _pixels(
          tester,
          archiveView
              ? 'archive-blurred-thumbnails'
              : 'folder-blurred-thumbnails',
        );
        listener.onWindowFocus();
        await _drain(tester);
        expect(
          tester
              .widgetList<RawImage>(thumbs)
              .where((image) => image.image != null)
              .length,
          6,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await _drain(tester);
      }
    },
  );

  testWidgets(
    'source view releases replaced, late and disposed archive leases',
    (tester) async {
      final first = _ControlledSource('first');
      final second = _ControlledSource('second');
      final third = _ControlledSource('third');
      await tester.pumpWidget(_sourceHost(first));
      expect(first.requests.single.cancelled, isFalse);
      await tester.pumpWidget(_sourceHost(second));
      expect(first.requests.single.cancelled, isTrue);
      first.complete();
      second.complete();
      await tester.pump();
      await tester.pump();
      expect(first.released, 1);
      expect(second.released, 0);
      expect(find.text('loaded second'), findsOneWidget);
      await tester.pumpWidget(_sourceHost(third));
      expect(second.released, 1);
      third.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('loaded third'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(third.released, 1);
    },
  );

  testWidgets(
    'source view retries failed materialization with a fresh request',
    (tester) async {
      final source = _ControlledSource('retry');
      await tester.pumpWidget(_sourceHost(source));
      source.pending.single.completeError(StateError('temporary read error'));
      await tester.pump();
      expect(find.text('source failed'), findsOneWidget);
      await tester.tap(find.text('重试此页'));
      await tester.pump();
      expect(source.requests, hasLength(2));
      expect(source.requests.first.cancelled, isTrue);
      source.complete(index: 1);
      await tester.pump();
      await tester.pump();
      expect(find.text('loaded retry'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(source.released, 1);
    },
  );

  testWidgets(
    'real CBZ displays first image, complete spread and comic pages in wide and narrow windows',
    (tester) async {
      _mockHost(tester);
      await _loadCaptureFonts(tester);
      final directory = Directory.systemTemp.createTempSync(
        'viewer-archive-integration-',
      );
      addTearDown(() => _deleteFixture(directory));
      for (final width in [1280.0, 440.0]) {
        final viewportDirectory = Directory('${directory.path}/$width')
          ..createSync();
        final source = _archive(
          viewportDirectory,
          '漫画阅读样本-${width.toInt()}.cbz',
        );
        tester.view.physicalSize = Size(width, 800);
        await _pumpArchiveHost(
          tester,
          _host(source, key: ValueKey('viewer-$width')),
        );
        await _waitFor(
          tester,
          () => _bar(tester)?.controller.archiveContext != null,
        );
        await _waitForImage(tester);
        final bar = _bar(tester)!;
        expect(bar.controller.entries.length, 6);
        expect(bar.controller.currentEntry!.name, '001.png');
        expect(
          bar.controller.entries.every((entry) => !entry.isMaterialized),
          isTrue,
        );
        final single = await _pixels(tester, 'dark-${width.toInt()}-single');
        expect(
          single[0],
          greaterThan(5000),
          reason: 'The first page must actually paint in the main canvas.',
        );

        await _chooseMode(tester, '双页');
        expect(_bar(tester)!.mode, ViewerMode.doublePage);
        final secondPage = _bar(tester)!.controller.entries[1];
        await tester.runAsync(
          () => tester.tap(find.byKey(ValueKey(secondPage.id))),
        );
        await _waitFor(
          tester,
          () => _bar(tester)!.controller.currentIndex == 1,
        );
        await _waitForImage(tester, minimum: 2);
        final spread = await _pixels(tester, 'dark-${width.toInt()}-double');
        expect(
          spread[1],
          greaterThan(4000),
          reason: 'The first half of the spread must paint.',
        );
        expect(
          spread[2],
          greaterThan(4000),
          reason: 'The second half must paint in the same spread.',
        );
        if (width == 1280) {
          await _chooseMode(tester, '双页');
          await tester.runAsync(
            () => tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft),
          );
          await _waitFor(
            tester,
            () => _bar(tester)!.controller.currentIndex == 0,
          );
        }

        await _chooseMode(tester, '连续阅读');
        expect(_bar(tester)!.mode, ViewerMode.comic);
        expect(find.byType(ComicStripViewport), findsOneWidget);
        await _waitForImage(tester);
        await tester.runAsync(
          () => tester.drag(
            find.byType(ComicStripViewport),
            const Offset(0, -350),
          ),
        );
        await _drain(tester);
        final comic = await _pixels(tester, 'dark-${width.toInt()}-comic');
        expect(comic.reduce((a, b) => a + b), greaterThan(10000));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await _drain(tester);
      }
    },
  );

  testWidgets(
    'on-demand comic still paints the visible range after reversing scroll',
    (tester) async {
      _mockHost(tester);
      await _loadCaptureFonts(tester);
      tester.view.physicalSize = const Size(440, 800);
      final directory = Directory.systemTemp.createTempSync(
        'viewer-archive-on-demand-',
      );
      addTearDown(() => _deleteFixture(directory));
      final source = _archive(directory, '按需阅读.cbz');
      await _pumpArchiveHost(
        tester,
        _host(
          source,
          settings: const ViewerSettings(
            showDirectoryPanel: false,
            archivePrefetchMode: ArchivePrefetchMode.off,
          ),
        ),
      );
      await _waitFor(
        tester,
        () => _bar(tester)?.controller.archiveContext != null,
      );
      await _waitForImage(tester);
      await _chooseMode(tester, '连续阅读');
      await _waitForImage(tester);
      await tester.runAsync(
        () =>
            tester.drag(find.byType(ComicStripViewport), const Offset(0, -500)),
      );
      await _waitForImage(tester, minimum: 2);
      await tester.runAsync(
        () =>
            tester.drag(find.byType(ComicStripViewport), const Offset(0, 300)),
      );
      await _waitForImage(tester, minimum: 2);
      final pixels = await _pixels(tester, 'dark-440-on-demand-comic-reverse');
      expect(pixels.reduce((a, b) => a + b), greaterThan(10000));
      expect(pixels[1], greaterThan(500));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _drain(tester);
    },
  );

  testWidgets(
    'password retry opens the real archive and cancel leaves navigation usable',
    (tester) async {
      _mockHost(tester);
      final directory = Directory.systemTemp.createTempSync(
        'viewer-archive-password-',
      );
      addTearDown(() => _deleteFixture(directory));
      final source = _archive(
        directory,
        '加密漫画.cbz',
        password: 'correct-password',
      );
      await _pumpArchiveHost(tester, _host(source));
      await _waitFor(
        tester,
        () => find.byType(ArchivePasswordDialog).evaluate().isNotEmpty,
      );
      await tester.enterText(find.byType(TextField), 'wrong-password');
      await tester.pump();
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('archive.passwordSubmit'))),
      );
      await _waitFor(
        tester,
        () => find.text('密码不正确，请重新输入。').evaluate().isNotEmpty,
      );
      await tester.enterText(find.byType(TextField), 'correct-password');
      await tester.pump();
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('archive.passwordSubmit'))),
      );
      await _waitFor(
        tester,
        () => _bar(tester)?.controller.archiveContext != null,
      );
      await _waitForImage(tester);
      expect(find.byType(ArchivePasswordDialog), findsNothing);
      expect((await _pixels(tester, 'password-opened'))[0], greaterThan(5000));
      await tester.pumpWidget(const SizedBox());
      await _drain(tester);
      await _pumpArchiveHost(
        tester,
        _host(source, key: const ValueKey('cancel-password')),
      );
      await _waitFor(
        tester,
        () => find.byType(ArchivePasswordDialog).evaluate().isNotEmpty,
      );
      await tester.tap(find.text('取消'));
      await _drain(tester);
      expect(find.byType(ArchivePasswordDialog), findsNothing);
      expect(_bar(tester)?.controller.archiveContext, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _drain(tester);
    },
  );
}

void _mockHost(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const window = MethodChannel('window_manager');
  const resources = MethodChannel('shenview/system_resources');
  messenger.setMockMethodCallHandler(
    window,
    (call) async =>
        ['isFullScreen', 'isMaximized', 'isAlwaysOnTop'].contains(call.method)
        ? false
        : null,
  );
  messenger.setMockMethodCallHandler(
    resources,
    (_) async => {
      'physicalMemoryBytes': 16 * 1024 * 1024 * 1024,
      'availableMemoryBytes': 8 * 1024 * 1024 * 1024,
      'availableDiskBytes': 100 * 1024 * 1024 * 1024,
      'diskCapacityBytes': 512 * 1024 * 1024 * 1024,
    },
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await _drain(tester);
    messenger.setMockMethodCallHandler(window, null);
    messenger.setMockMethodCallHandler(resources, null);
  });
}

Widget _host(
  File source, {
  Key? key,
  ViewerSettings? settings = const ViewerSettings(showDirectoryPanel: false),
  ThemeData? themeOverride,
  AppConfigStore? configStore,
}) {
  final capture = Platform.environment['ARCHIVE_VIEWER_CAPTURE_DIR'] != null;
  final platform = capture ? TargetPlatform.windows : null;
  final theme = themeOverride ?? AppTheme.dark(platform: platform);
  return RepaintBoundary(
    key: _captureKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: capture
          ? theme.copyWith(
              platform: platform,
              textTheme:
                  (theme.brightness == Brightness.dark
                          ? AppTheme.dark(platform: platform)
                          : AppTheme.light(platform: platform))
                      .textTheme,
            )
          : theme,
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ViewerPage(
        key: key,
        initialPath: source.path,
        initialSettings: settings,
        archiveService: ArchiveService(
          cachePolicy: ArchiveCachePolicy(
            directory: Directory('${source.parent.path}/cache'),
          ),
        ),
        configStore:
            configStore ??
            AppConfigStore(filePath: '${source.parent.path}/config.json'),
      ),
    ),
  );
}

ViewerBottomBar? _bar(WidgetTester tester) =>
    find.byType(ViewerBottomBar).evaluate().isEmpty
    ? null
    : tester.widget<ViewerBottomBar>(find.byType(ViewerBottomBar));

Future<void> _pumpArchiveHost(WidgetTester tester, Widget host) async {
  // Archive startup scans cache entries using real filesystem IO. Start the
  // post-frame initializer outside FakeAsync so each stat does not need a pump.
  await tester.runAsync(() => tester.pumpWidget(host));
}

Future<void> _finishViewer(WidgetTester tester, File source) async {
  final controller = _bar(tester)?.controller;
  // Opening now also queues bounded recent-item updates. Drain the controller's
  // chain before the fixture is removed, and keep disposal IO outside FakeAsync.
  var historyFlushed = controller == null;
  await tester.runAsync(() async {
    unawaited(
      controller?.flushPersistence().then((_) => historyFlushed = true),
    );
  });
  await _waitFor(tester, () => historyFlushed);
  await tester.runAsync(() => tester.pumpWidget(const SizedBox()));
  await _drain(tester);
  final store = AppConfigStore(filePath: '${source.parent.path}/config.json');
  var flushed = false;
  await tester.runAsync(() async {
    unawaited(store.update((config) => config).then((_) => flushed = true));
  });
  await _waitFor(tester, () => flushed);
}

File _scrollFixture(Directory directory, bool archiveView) {
  final archive = _archive(directory, 'scroll.cbz');
  if (archiveView) return archive;
  final folder = Directory('${directory.path}/pages')..createSync();
  for (final file
      in ZipDecoder().decodeBytes(archive.readAsBytesSync()).files) {
    File('${folder.path}/${file.name}').writeAsBytesSync(file.content);
  }
  return File('${folder.path}/001.png');
}

Future<void> _waitForSelectedImage(
  WidgetTester tester, {
  int minimum = 1,
}) async {
  await _waitForImage(tester);
  // The old transition has ended by now; require the current spread to paint.
  await _waitFor(
    tester,
    () =>
        tester
            .widgetList<RawImage>(
              find.descendant(
                of: find.byType(ZoomableViewport),
                matching: find.byType(RawImage),
              ),
            )
            .where((image) => image.image != null)
            .length >=
        minimum,
  );
  final controller = _bar(tester)!.controller;
  if (!controller.isArchiveView) return;
  await _waitFor(
    tester,
    () => tester
        .widgetList<RawImage>(
          find.descendant(
            of: find.byKey(ValueKey('source:${controller.currentEntry!.id}')),
            matching: find.byType(RawImage),
          ),
        )
        .any((image) => image.image != null),
  );
  await _drain(tester);
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() ready, {
  int attempts = 200,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
  }
  final controller = _bar(tester)?.controller;
  expect(
    ready(),
    isTrue,
    reason:
        'Archive opening or image rendering did not complete. opening=${controller?.isOpeningArchive}, failure=${controller?.lastArchiveFailure}, entries=${controller?.entries.length}, index=${controller?.currentIndex}, error=${controller?.errorMessage}',
  );
}

Future<void> _waitForImage(WidgetTester tester, {int minimum = 1}) async {
  await _waitFor(tester, () {
    final bottom = tester.getTopLeft(find.byType(ViewerBottomBar)).dy;
    final canvas = Rect.fromLTRB(0, 44, tester.view.physicalSize.width, bottom);
    return find.byType(RawImage).evaluate().where((element) {
          if ((element.widget as RawImage).image == null) return false;
          return tester.getRect(find.byWidget(element.widget)).overlaps(canvas);
        }).length >=
        minimum;
  });
  await _drain(tester);
}

Future<void> _drain(WidgetTester tester) async {
  for (var index = 0; index < 8; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<void> _chooseMode(WidgetTester tester, String label) async {
  await tester.tapAt(
    Offset(tester.view.physicalSize.width / 2, 250),
    buttons: kSecondaryMouseButton,
  );
  await tester.pump();
  final l10n = AppLocalizations.of(tester.element(find.byType(ViewerPage)))!;
  await _waitFor(tester, () => find.text(l10n.viewMode).evaluate().isNotEmpty);
  await tester.tap(find.text(l10n.viewMode));
  await tester.pump(const Duration(milliseconds: 220));
  await _waitFor(tester, () => find.text(label).evaluate().isNotEmpty);
  await tester.runAsync(() => tester.tap(find.text(label).last));
  await _drain(tester);
}

Future<void> _chooseSizing(WidgetTester tester, String label) async {
  final trigger = find.byKey(const ValueKey('viewer.zoomMenu'));
  await _tapNavigation(
    tester,
    trigger.evaluate().isNotEmpty ? trigger : find.byTooltip('更多缩放操作'),
  );
  await _drain(tester);
  await _tapNavigation(tester, find.text(label).last);
  await _drain(tester);
}

File _archive(Directory directory, String name, {String? password}) {
  final archive = Archive();
  for (var index = 0; index < _colors.length; index++) {
    final color = _colors[index];
    final image = bitmap.Image(width: 480, height: 720);
    bitmap.fill(image, color: bitmap.ColorRgb8(color.$1, color.$2, color.$3));
    bitmap.fillRect(
      image,
      x1: 28,
      y1: 210,
      x2: 450,
      y2: 220,
      color: bitmap.ColorRgb8(245, 235, 220),
    );
    bitmap.drawString(
      image,
      'PAGE ${index + 1}',
      font: bitmap.arial48,
      x: 30,
      y: 110,
      color: bitmap.ColorRgb8(255, 255, 255),
    );
    final bytes = bitmap.encodePng(image);
    archive.addFile(
      ArchiveFile.bytes('${(index + 1).toString().padLeft(3, "0")}.png', bytes),
    );
  }
  return File('${directory.path}/$name')
    ..writeAsBytesSync(ZipEncoder(password: password).encodeBytes(archive));
}

Future<void> _tapNavigation(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  // Routes and directory controls can exist before their slide transition
  // accepts input. Wait for the actual hit target rather than tapping midway.
  await _waitFor(tester, () => finder.hitTestable().evaluate().isNotEmpty);
  await tester.runAsync(() => tester.tap(finder));
  await tester.pump();
}

Future<void> _waitForSavedDirectoryPin(
  WidgetTester tester,
  AppConfigStore store,
  bool pinned,
) async {
  for (var i = 0; i < 100; i++) {
    final config = await tester.runAsync(store.read);
    final settings = config!['settings'] as Map<String, dynamic>?;
    if (settings?['pinDirectoryPanel'] == pinned) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  fail('Directory pin preference was not saved');
}

Future<void> _openDirectory(WidgetTester tester) async {
  await _tapNavigation(
    tester,
    find.byKey(const ValueKey('navigation.directory')),
  );
  await _waitFor(
    tester,
    () => find.byKey(const ValueKey('directory.panel')).evaluate().isNotEmpty,
  );
  await _drain(tester);
}

void _expectSelectedChapter(WidgetTester tester, String path) {
  final select = tester.widget<AppSelect<String>>(
    find.byKey(const ValueKey('navigation.chapter')),
  );
  expect(select.value, path);
}

File _navigationArchive(Directory directory) {
  final pages = ZipDecoder()
      .decodeBytes(_archive(directory, 'pages.cbz').readAsBytesSync())
      .files;
  List<int> zip(Map<String, List<int>> entries) {
    final archive = Archive();
    for (final entry in entries.entries) {
      archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
    }
    return ZipEncoder().encodeBytes(archive);
  }

  final appendix = zip({'001.png': pages[5].content});
  final inner = zip({'001.png': pages[4].content, '附录.cbz': appendix});
  return File('${directory.path}/多级目录与嵌套包.zip')..writeAsBytesSync(
    zip({
      'cover.png': pages[0].content,
      '第1卷/第01章/001.png': pages[1].content,
      '第1卷/第02章/001.png': pages[2].content,
      '第2卷/上篇/第01章/001.png': pages[3].content,
      '第1卷/单行本.cbz': inner,
    }),
  );
}

Future<List<int>> _pixels(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final bottom = tester.getTopLeft(find.byType(ViewerBottomBar)).dy.toInt();
  final counts = List.filled(_colors.length, 0);
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      for (var y = 70; y < bottom; y++) {
        for (var x = 12; x < image.width - 12; x++) {
          final offset = (y * image.width + x) * 4;
          for (var c = 0; c < _colors.length; c++) {
            final color = _colors[c];
            if ((bytes!.getUint8(offset) - color.$1).abs() < 3 &&
                (bytes.getUint8(offset + 1) - color.$2).abs() < 3 &&
                (bytes.getUint8(offset + 2) - color.$3).abs() < 3) {
              counts[c]++;
            }
          }
        }
      }
      final directory = Platform.environment['ARCHIVE_VIEWER_CAPTURE_DIR'];
      if (directory != null) {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$directory/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(png!.buffer.asUint8List());
      }
    } finally {
      image.dispose();
    }
  });
  return counts;
}

Future<void> _loadCaptureFonts(WidgetTester tester) async {
  if (Platform.environment['ARCHIVE_VIEWER_CAPTURE_DIR'] == null) return;
  await loadStyleReviewFonts(tester);
}

Future<void> _deleteFixture(Directory directory) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }
}

Widget _sourceHost(_ControlledSource source) => MaterialApp(
  theme: AppTheme.dark(),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SourceImageView(
      entry: ImageEntry.fromSource(
        source: source,
        format: ImageFormat.svg,
        byteLength: 10,
        modifiedAt: DateTime(2026),
      ),
      builder: (entry) {
        expect(entry.isMaterialized, isTrue);
        expect(entry.id, source.id);
        return Text('loaded ${source.id}');
      },
      errorBuilder: (_) => const Text('source failed'),
    ),
  ),
);

class _ControlledSource implements ImageSource {
  _ControlledSource(this.id);
  @override
  final String id;
  final requests = <DecodeRequest>[];
  final pending = <Completer<SourceFileLease>>[];
  var released = 0;
  @override
  String get name => '$id.svg';
  @override
  String get relativePath => name;
  @override
  bool get sensitive => false;
  @override
  Future<SourceFileLease> acquireFile({DecodeRequest? request}) {
    requests.add(request!);
    final completer = Completer<SourceFileLease>();
    pending.add(completer);
    return completer.future;
  }

  void complete({int index = 0}) => pending[index].complete(
    SourceFileLease(
      File('$id.svg'),
      onRelease: () async {
        released++;
      },
    ),
  );
}
