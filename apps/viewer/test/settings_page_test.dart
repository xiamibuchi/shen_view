import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_info.dart';
import 'package:shen_view/src/application/decoder_registry.dart';
import 'package:shen_view/src/domain/animation_timeline.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/domain/viewer_mode.dart';
import 'package:shen_view/src/domain/view_scale_mode.dart';
import 'package:shen_view/src/domain/folder_browse_mode.dart';
import 'package:shen_view/src/presentation/components/app_button.dart';
import 'package:shen_view/src/presentation/components/app_switch.dart';
import 'package:shen_view/src/presentation/components/app_select.dart';
import 'package:shen_view/src/presentation/components/app_search_text.dart';
import 'package:shen_view/src/presentation/settings_page.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

import 'support/style_review_fonts.dart';

const _captureKey = ValueKey('settings-capture');
const _resetKey = ValueKey('settings.resetSection');

void main() {
  for (final width in [1280.0, 440.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'instance mode is selectable and renders at $width dark=$dark',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var theme = dark ? AppTheme.dark() : AppTheme.light();
          if (Platform.environment['INSTANCE_SETTINGS_REVIEW'] == '1') {
            await tester.runAsync(() async {
              for (final font in [
                ('InstanceReview', windowsFontPath('msyh.ttc')),
                (
                  'packages/fluentui_system_icons/FluentSystemIcons-Regular',
                  'packages/fluentui_system_icons/fonts/FluentSystemIcons-Regular.ttf',
                ),
                (
                  'packages/fluentui_system_icons/FluentSystemIcons-Filled',
                  'packages/fluentui_system_icons/fonts/FluentSystemIcons-Filled.ttf',
                ),
              ]) {
                await (FontLoader(
                  font.$1,
                )..addFont(loadReviewFontData(font.$2))).load();
              }
            });
            theme = theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'InstanceReview'),
            );
          }
          var settings = const ViewerSettings();
          await tester.pumpWidget(
            _host(theme: theme, onChanged: (value) => settings = value),
          );
          await tester.pumpAndSettle();
          final row = find.byKey(const ValueKey('settings.instanceMode'));
          await tester.ensureVisible(row);
          final control = find.descendant(
            of: row,
            matching: find.byType(AppSelect<InstanceMode>),
            matchRoot: true,
          );
          expect(
            tester.widget<AppSelect<InstanceMode>>(control).value,
            InstanceMode.singleProcess,
          );
          await tester.tap(control);
          await tester.pumpAndSettle();
          await tester.tap(find.text('多进程').last);
          await tester.pumpAndSettle();
          expect(settings.instanceMode, InstanceMode.multiProcess);
          await _capture(
            tester,
            'build/settings-instances-${dark ? "dark" : "light"}-${width.toInt()}.png',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final width in [1280.0, 440.0]) {
    testWidgets(
      'Chinese IME commits search without replacing its client at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(_host());
        await tester.pumpAndSettle();
        final search = find.descendant(
          of: find.byKey(const ValueKey('settings.search')),
          matching: find.byType(EditableText),
        );
        await tester.showKeyboard(search);
        final editor = tester.state<EditableTextState>(search);
        final clientCount = tester.testTextInput.log
            .where((call) => call.method == 'TextInput.setClient')
            .length;
        for (final text in ['h', 'huan', 'huancun', '缓存']) {
          tester.testTextInput.updateEditingValue(
            TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(offset: text.length),
              composing: TextRange(start: 0, end: text.length),
            ),
          );
          await tester.pumpAndSettle();
          // Pinyin and uncommitted candidates must not filter the page.
          expect(
            find.byKey(const ValueKey('settings.nav.general')),
            findsOneWidget,
          );
          expect(find.text('没有匹配的设置'), findsNothing);
          expect(_highlightedFragments(tester), isEmpty);
          expect(editor.widget.focusNode.hasFocus, isTrue);
          expect(
            editor.widget.controller.value.composing,
            TextRange(start: 0, end: text.length),
          );
        }
        await _capture(
          tester,
          'build/settings-ime-composing-${width.toInt()}.png',
        );
        // Committing can change only the composing range, without onChanged.
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: '缓存',
            selection: const TextSelection.collapsed(offset: 2),
            composing: width == 440
                ? const TextRange.collapsed(2)
                : TextRange.empty,
          ),
        );
        await tester.pumpAndSettle();
        expect(_highlightedFragments(tester), contains('缓存'));
        expect(
          find.byKey(const ValueKey('settings.nav.general')),
          findsNothing,
        );
        expect(tester.state<EditableTextState>(search), same(editor));
        expect(editor.widget.focusNode.hasFocus, isTrue);
        expect(tester.testTextInput.hasAnyClients, isTrue);
        expect(
          tester.testTextInput.log
              .where((call) => call.method == 'TextInput.setClient')
              .length,
          clientCount,
        );
        final results = find.byWidgetPredicate(
          (widget) => widget is AppSearchText && widget.data.contains('缓存'),
        );
        expect(results.hitTestable(), findsWidgets);
        await _capture(
          tester,
          'build/settings-ime-committed-${width.toInt()}.png',
        );
        // A cancelled second composition keeps the committed result intact.
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: '缓存z',
            selection: TextSelection.collapsed(offset: 3),
            composing: TextRange(start: 2, end: 3),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('没有匹配的设置'), findsNothing);
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: '缓存',
            selection: TextSelection.collapsed(offset: 2),
          ),
        );
        await tester.pumpAndSettle();
        expect(_highlightedFragments(tester), contains('缓存'));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [1280.0, 440.0]) {
    for (final dark in [false, true]) {
      testWidgets('search highlights and locates results at $width dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _host(theme: dark ? AppTheme.dark() : AppTheme.light()),
        );
        await tester.pumpAndSettle();
        final search = find.descendant(
          of: find.byKey(const ValueKey('settings.search')),
          matching: find.byType(EditableText),
        );
        await tester.enterText(search, '缓存');
        await tester.pumpAndSettle();
        final highlighted = _highlightedFragments(tester);
        expect(highlighted.length, greaterThan(1));
        expect(highlighted.every((text) => text == '缓存'), isTrue);
        final results = find.byWidgetPredicate(
          (widget) => widget is AppSearchText && widget.data.contains('缓存'),
        );
        expect(results.hitTestable(), findsWidgets);
        await _capture(
          tester,
          'build/settings-search-${dark ? 'dark' : 'light'}-${width.toInt()}.png',
        );
        await tester.enterText(search, '缓存 容量');
        await tester.pumpAndSettle();
        expect(_highlightedFragments(tester), containsAll(['缓存', '容量']));
        // Refining the query must not pull the same target back after the
        // user has deliberately scrolled away from it.
        final content = find
            .descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Scrollable),
            )
            .first;
        final position = tester.state<ScrollableState>(content).position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        final offset = position.pixels;
        await tester.enterText(search, '缓存 cache');
        await tester.pumpAndSettle();
        expect(position.pixels, offset);
        await tester.enterText(search, 'no-such-setting');
        await tester.pumpAndSettle();
        await tester.enterText(search, '缓存');
        await tester.pumpAndSettle();
        expect(results.hitTestable(), findsWidgets);
        await tester.enterText(search, '');
        await tester.pumpAndSettle();
        expect(_highlightedFragments(tester), isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'English aliases mark the relevant group without fake highlights',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      final search = find.descendant(
        of: find.byKey(const ValueKey('settings.search')),
        matching: find.byType(EditableText),
      );
      await tester.enterText(search, 'WhEeL');
      await tester.pumpAndSettle();
      expect(find.text('滚轮操作').hitTestable(), findsOneWidget);
      expect(_highlightedFragments(tester), isEmpty);
      final group = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('settings.searchGroup.0')),
      );
      final context = tester.element(find.byType(SettingsPage));
      expect(
        ((group.decoration as BoxDecoration).border! as Border).top.color,
        ViewerThemeTokens.of(context).accentStrong,
      );
      await _capture(tester, 'build/settings-search-alias.png');
      await tester.enterText(search, 'cache');
      await tester.pumpAndSettle();
      expect(find.text('磁盘缓存').hitTestable(), findsOneWidget);
      final cacheGroup = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('settings.searchGroup.2')),
      );
      expect(
        ((cacheGroup.decoration as BoxDecoration).border! as Border).top.color,
        ViewerThemeTokens.of(context).accentStrong,
      );
      await tester.enterText(search, 'hdr HDR');
      await tester.pumpAndSettle();
      expect(_highlightedFragments(tester), isNotEmpty);
      expect(
        _highlightedFragments(tester)
            .every((text) => text.toLowerCase() == 'hdr'),
        isTrue,
      );
      await tester.enterText(search, 'no-such-setting');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的设置'), findsOneWidget);
      expect(_highlightedFragments(tester), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [1280.0, 440.0]) {
    testWidgets('animation preferences are searchable and reset at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var settings = const ViewerSettings(showBottomBar: false);
      await tester.pumpWidget(
        _host(settings: settings, onChanged: (value) => settings = value),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('settings.search')),
          matching: find.byType(EditableText),
        ),
        '动图 倍速',
      );
      await tester.pumpAndSettle();
      expect(find.text('动图播放'), findsOneWidget);
      await tester.ensureVisible(find.text('打开动图时自动播放'));
      await tester.tap(find.text('打开动图时自动播放'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings.animationLoopMode')),
      );
      await tester.tap(
        find.byKey(const ValueKey('settings.animationLoopMode')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('播放一次').last);
      await tester.pumpAndSettle();
      final speed = find.byKey(const ValueKey('settings.animationSpeed'));
      await tester.ensureVisible(speed);
      await tester.tap(speed);
      await tester.pumpAndSettle();
      await tester.tap(find.text('0.5×').last);
      await tester.pumpAndSettle();
      final controls = find.byKey(
        const ValueKey('settings.animationControlsMode'),
      );
      await tester.ensureVisible(controls);
      await tester.tap(controls);
      await tester.pumpAndSettle();
      await tester.tap(find.text('隐藏').last);
      await tester.pumpAndSettle();
      expect(settings.animationAutoPlay, isFalse);
      expect(settings.animationLoopMode, AnimationLoopMode.once);
      expect(settings.animationSpeed, 0.5);
      expect(settings.animationControlsMode, AnimationControlsMode.hidden);
      await tester.ensureVisible(find.byKey(_resetKey));
      await tester.tap(find.byKey(_resetKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复默认').last);
      await tester.pumpAndSettle();
      expect(settings, const ViewerSettings(showBottomBar: false));
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [1280.0, 440.0]) {
    testWidgets(
      'archive sorting link locates the control through search at width=$width',
      (tester) async {
        tester.view.physicalSize = Size(width, 560);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const initial = ViewerSettings(
          sortOrder: SortOrder.modifiedOldest,
          archiveSortOrder: SortOrder.modifiedNewest,
        );
        var settings = initial;
        await tester.pumpWidget(
          _host(settings: settings, onChanged: (value) => settings = value),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('settings.nav.archives')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('settings.archiveClearCache')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('settings.nav.browsing')));
        await tester.pumpAndSettle();
        final search = find.descendant(
          of: find.byKey(const ValueKey('settings.search')),
          matching: find.byType(EditableText),
        );
        await tester.enterText(search, '文件夹');
        await tester.pumpAndSettle();
        final link = find.byKey(const ValueKey('settings.openArchiveSort'));
        await tester.ensureVisible(link);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: link, matching: find.text('压缩包')),
          findsOneWidget,
        );
        expect(find.text('压缩包排序设置'), findsNothing);
        expect(tester.getSize(link).height, lessThan(24));
        if (width == 440) {
          Focus.of(tester.element(link)).requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(link);
        }
        await tester.pumpAndSettle();
        final target = find.byKey(const ValueKey('settings.archiveSortOrder'));
        expect(target.hitTestable(), findsOneWidget);
        expect(find.text('包内排序').hitTestable(), findsOneWidget);
        final select = tester.widget<AppSelect<SortOrder>>(target);
        expect(select.focusNode!.hasFocus, isTrue);
        expect(tester.widget<EditableText>(search).controller.text, isEmpty);
        expect(settings, initial);
        await tester.tap(target);
        await tester.pumpAndSettle();
        await tester.tap(find.text('文件名升序').last);
        await tester.pumpAndSettle();
        expect(settings.archiveSortOrder, SortOrder.nameAscending);
        expect(settings.sortOrder, SortOrder.modifiedOldest);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'reading options use aligned labels and reset both wide preferences',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var settings = const ViewerSettings();
      await tester.pumpWidget(
        _host(settings: settings, onChanged: (value) => settings = value),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings.nav.reading')));
      await tester.pumpAndSettle();
      final direction = tester.widget<AppSelect<ReadingDirection>>(
        find.byKey(const ValueKey('settings.readingDirection')),
      );
      expect(direction.options.map((option) => option.label), ['从左到右', '从右到左']);
      await tester.tap(find.text('宽图独占一页'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自动拆分宽图'));
      await tester.pumpAndSettle();
      expect(settings.doublePageWideAlone, isFalse);
      expect(settings.doublePageSplitWide, isTrue);
      await tester.tap(find.byKey(_resetKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复默认').last);
      await tester.pumpAndSettle();
      expect(settings.doublePageWideAlone, isTrue);
      expect(settings.doublePageSplitWide, isFalse);
    },
  );

  testWidgets(
    'filename rule is shared and archive order excludes folder order',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var settings = const ViewerSettings(
        archiveSortOrder: SortOrder.modifiedNewest,
      );
      await tester.pumpWidget(
        _host(settings: settings, onChanged: (value) => settings = value),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings.nav.browsing')));
      await tester.pumpAndSettle();
      final rule = find.byKey(const ValueKey('settings.fileNameSortMode'));
      await tester.ensureVisible(rule);
      const naturalTip = '按数字大小比较主文件名，例如升序时 2 在 10 前。';
      const stringTip = '逐字符比较主文件名，例如升序时 10 在 2 前。';
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer();
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('自然排序')));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text(naturalTip), findsOneWidget);
      await tester.tap(rule);
      await tester.pumpAndSettle();
      expect(find.text('自然排序'), findsNWidgets(2));
      expect(find.text('普通字符串排序'), findsOneWidget);
      await mouse.moveTo(tester.getCenter(find.text('普通字符串排序')));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text(stringTip), findsOneWidget);
      await tester.tap(find.text('普通字符串排序'));
      await tester.pumpAndSettle();
      expect(settings.fileNameSortMode, FileNameSortMode.lexicographic);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      await mouse.moveTo(tester.getCenter(find.text('普通字符串排序')));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text(stringTip), findsOneWidget);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings.nav.archives')));
      await tester.pumpAndSettle();
      final archiveOrder = tester.widget<AppSelect<SortOrder>>(
        find.byKey(const ValueKey('settings.archiveSortOrder')),
      );
      expect(
        archiveOrder.options.map((o) => o.value),
        isNot(contains(SortOrder.fileSystem)),
      );
      await tester.tap(find.byKey(const ValueKey('settings.nav.browsing')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_resetKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复默认').last);
      await tester.pumpAndSettle();
      expect(settings.fileNameSortMode, FileNameSortMode.natural);
      expect(settings.archiveSortOrder, SortOrder.modifiedNewest);
    },
  );
  testWidgets(
    'folder recursion and continuous switches keep the disabled preference',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var settings = const ViewerSettings(
        browseMode: FolderBrowseMode.recursiveFlat,
        pinDirectoryPanel: true,
      );
      await tester.pumpWidget(
        _host(settings: settings, onChanged: (value) => settings = value),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings.nav.browsing')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings.browseMode')), findsNothing);
      await tester.tap(find.text('递归浏览子文件夹'));
      await tester.pumpAndSettle();
      expect(settings.browseMode, FolderBrowseMode.currentFolder);
      expect(settings.folderContinuousReading, isTrue);
      final continuous = tester.widget<AppSwitch>(
        find.byWidgetPredicate(
          (widget) => widget is AppSwitch && widget.label == '连续浏览子文件夹',
        ),
      );
      expect(continuous.enabled, isFalse);
      expect(continuous.value, isTrue);
      await tester.tap(find.text('递归浏览子文件夹'));
      await tester.pumpAndSettle();
      expect(settings.browseMode, FolderBrowseMode.recursiveFlat);
      await tester.tap(find.text('连续浏览子文件夹'));
      await tester.pumpAndSettle();
      expect(settings.browseMode, FolderBrowseMode.recursiveFolders);
      expect(settings.folderContinuousReading, isFalse);
      expect(settings.pinDirectoryPanel, isTrue);
    },
  );

  testWidgets('folder watching is a browsing preference with page reset', (
    tester,
  ) async {
    await loadStyleReviewFonts(tester);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var settings = const ViewerSettings(watchFolderChanges: false);
    await tester.pumpWidget(
      _host(
        theme: AppTheme.dark(platform: TargetPlatform.windows),
        settings: settings,
        onChanged: (value) => settings = value,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings.nav.browsing')));
    await tester.pumpAndSettle();
    final toggle = find.byWidgetPredicate(
      (widget) => widget is AppSwitch && widget.label == '自动刷新文件夹',
    );
    final descriptionText = AppLocalizations.of(tester.element(toggle))!
        .watchFolderChangesDescription;
    // Reserve a real gutter even when a long explanation wraps beside a switch.
    for (final width in [1280.0, 760.0, 440.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      await tester.ensureVisible(toggle);
      final description = find.descendant(
        of: toggle,
        matching: find.byWidgetPredicate(
          (widget) => widget is AppSearchText && widget.data == descriptionText,
        ),
      );
      final track = find.descendant(of: toggle, matching: find.byType(Switch));
      expect(
        tester.getRect(track).left - tester.getRect(description).right,
        greaterThanOrEqualTo(24),
      );
      await _capture(
        tester,
        '../../artifacts/style-followup/settings-gap-${width.toInt()}.png',
      );
      expect(tester.takeException(), isNull);
    }
    expect(tester.widget<AppSwitch>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(settings.watchFolderChanges, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(settings.watchFolderChanges, isFalse);
    await tester.ensureVisible(find.byKey(_resetKey));
    await tester.tap(find.byKey(_resetKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复默认').last);
    await tester.pumpAndSettle();
    expect(settings.watchFolderChanges, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('directory pin is a browsing preference with page-scoped reset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var settings = const ViewerSettings(archiveContinuousReading: false);
    await tester.pumpWidget(
      _host(settings: settings, onChanged: (value) => settings = value),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings.nav.browsing')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('固定目录栏'));
    await tester.pumpAndSettle();
    expect(settings.pinDirectoryPanel, isTrue);
    await tester.ensureVisible(find.byKey(_resetKey));
    await tester.tap(find.byKey(_resetKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复默认').last);
    await tester.pumpAndSettle();
    expect(settings.pinDirectoryPanel, isFalse);
    expect(settings.archiveContinuousReading, isFalse);
  });

  testWidgets(
    'interaction choices and reset stay scoped to input preferences',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var settings = const ViewerSettings(
        showBottomBar: false,
        interaction: ViewerInteractionSettings(wheelIntervalMs: 350),
      );
      await tester.pumpWidget(
        _host(settings: settings, onChanged: (next) => settings = next),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings.nav.interaction')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings.wheelIntervalMs')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('120 毫秒').last);
      await tester.pumpAndSettle();
      expect(settings.interaction.wheelIntervalMs, 120);
      final keepZoom = find.text('换图时保持缩放比例');
      await tester.ensureVisible(keepZoom);
      await tester.pumpAndSettle();
      await tester.tap(keepZoom);
      await tester.pumpAndSettle();
      expect(settings.interaction.keepZoom, isTrue);
      final keepPosition = find.text('同时保持查看位置');
      await tester.ensureVisible(keepPosition);
      await tester.pumpAndSettle();
      await tester.tap(keepPosition);
      await tester.pumpAndSettle();
      expect(settings.interaction.keepZoomPosition, isTrue);
      final zoomCenter = find.byKey(const ValueKey('settings.zoomCenter'));
      await tester.ensureVisible(zoomCenter);
      await tester.pumpAndSettle();
      await tester.tap(zoomCenter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('视口中心').last);
      await tester.pumpAndSettle();
      expect(settings.interaction.zoomCenter, ZoomCenter.viewport);
      final transition = find.byKey(const ValueKey('settings.transition'));
      await tester.ensureVisible(transition);
      await tester.pumpAndSettle();
      await tester.tap(transition);
      await tester.pumpAndSettle();
      await tester.tap(find.text('无动画').last);
      await tester.pumpAndSettle();
      expect(settings.interaction.transition, ImageTransition.none);
      expect(
        find.byKey(const ValueKey('settings.transitionDurationMs')),
        findsNothing,
      );
      await tester.ensureVisible(find.byKey(_resetKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_resetKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复默认').last);
      await tester.pumpAndSettle();
      expect(settings.interaction, const ViewerInteractionSettings());
      expect(settings.showBottomBar, isFalse);
    },
  );

  testWidgets('settings categories render in both themes and small windows', (
    tester,
  ) async {
    final captureDir = Platform.environment['SETTINGS_CAPTURE_DIR'];
    if (captureDir != null) {
      await loadStyleReviewFonts(tester);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    for (final dark in [true, false]) {
      for (final size in [
        const Size(1280, 800),
        const Size(800, 500),
        const Size(560, 640),
        const Size(440, 560),
      ]) {
        tester.view.physicalSize = size;
        final platform = captureDir != null ? TargetPlatform.windows : null;
        final theme = dark
            ? AppTheme.dark(platform: platform)
            : AppTheme.light(platform: platform);
        await tester.pumpWidget(
          _host(
            settings: captureDir == null
                ? const ViewerSettings()
                : const ViewerSettings(
                    interaction: ViewerInteractionSettings(
                      keepZoom: true,
                      keepZoomPosition: true,
                    ),
                  ),
            theme: theme,
          ),
        );
        await tester.pumpAndSettle();
        for (final section in [
          ('general', '通用'),
          ('appearance', '外观'),
          ('browsing', '浏览'),
          ('reading', '查看与阅读'),
          ('interaction', '操作'),
          ('playback', '播放'),
          ('archives', '压缩包'),
          ('image', '图像与 HDR'),
          ('shortcuts', '快捷键'),
          ('about', '关于'),
        ]) {
          final nav = find.byKey(ValueKey('settings.nav.${section.$1}'));
          await tester.ensureVisible(nav);
          await tester.pumpAndSettle();
          await tester.tap(nav);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: section.$1);
          expect(find.text(section.$2), findsWidgets, reason: section.$1);
          if (captureDir != null) {
            if (section.$1 == 'playback') {
              Scrollable.of(tester.element(find.text('动图播放'))).position
                  .jumpTo(0);
              await tester.pumpAndSettle();
            }
            await _capture(
              tester,
              '$captureDir/${dark ? 'dark' : 'light'}-${size.width.toInt()}-${section.$1}.png',
            );
            if (section.$1 == 'playback' && size.width < 800) {
              await tester.ensureVisible(
                find.byKey(const ValueKey('settings.animationControlsMode')),
              );
              await tester.pumpAndSettle();
              await _capture(
                tester,
                '$captureDir/${dark ? 'dark' : 'light'}-${size.width.toInt()}-animation-controls.png',
              );
            }
            if (section.$1 == 'browsing') {
              final link = find.byKey(
                const ValueKey('settings.openArchiveSort'),
              );
              await tester.ensureVisible(link);
              await tester.pumpAndSettle();
              await _capture(
                tester,
                '$captureDir/${dark ? 'dark' : 'light'}-${size.width.toInt()}-sorting-link.png',
              );
              await tester.tap(link);
              await tester.pumpAndSettle();
              expect(
                find
                    .byKey(const ValueKey('settings.archiveSortOrder'))
                    .hitTestable(),
                findsOneWidget,
              );
              await _capture(
                tester,
                '$captureDir/${dark ? 'dark' : 'light'}-${size.width.toInt()}-sorting-target.png',
              );
              await tester.tap(nav);
              await tester.pumpAndSettle();
            }
            if (section.$1 == 'browsing' && size.width == 1280) {
              await tester.tap(
                find.byKey(const ValueKey('settings.fileNameSortMode')),
              );
              await tester.pumpAndSettle();
              await _capture(
                tester,
                '$captureDir/${dark ? 'dark' : 'light'}-filename-rules.png',
              );
              final mouse = await tester.createGesture(
                kind: ui.PointerDeviceKind.mouse,
              );
              await mouse.addPointer();
              await mouse.moveTo(tester.getCenter(find.text('普通字符串排序').last));
              await tester.pump(const Duration(seconds: 1));
              await tester.pumpAndSettle();
              await _capture(
                tester,
                '$captureDir/${dark ? 'dark' : 'light'}-filename-rule-tooltip.png',
              );
              await mouse.removePointer();
              await tester.pumpAndSettle();
              await tester.tapAt(const Offset(1100, 50));
              await tester.pumpAndSettle();
            }
            if (section.$1 == 'interaction') {
              await tester.ensureVisible(
                find.byKey(const ValueKey('settings.zoomCenter')),
              );
              await tester.pumpAndSettle();
              await _capture(
                tester,
                '$captureDir/${dark ? 'dark' : 'light'}-${size.width.toInt()}-zoom-settings.png',
              );
              await tester.ensureVisible(
                find.byKey(const ValueKey('settings.transitionDurationMs')),
              );
              await tester.pumpAndSettle();
              await _capture(
                tester,
                '$captureDir/${dark ? 'dark' : 'light'}-${size.width.toInt()}-interaction-more.png',
              );
            }
          }
        }
      }
    }
  });

  testWidgets('search, page-scoped reset and read-only pages behave', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var settings = const ViewerSettings(
      localeCode: 'zh',
      toolbarMode: ToolbarMode.floating,
      defaultScaleModes: {ViewerMode.single: ViewScaleMode.originalSize},
    );
    await tester.pumpWidget(
      _host(settings: settings, onChanged: (value) => settings = value),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '解析');
    await tester.pumpAndSettle();
    expect(find.text('支持的图片格式'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('appInput.clearButton')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );

    await tester.tap(find.byKey(const ValueKey('settings.nav.general')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings.language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(settings.localeCode, 'en');

    await tester.tap(find.byKey(_resetKey));
    await tester.pumpAndSettle();
    expect(find.text('恢复本页默认？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('恢复本页默认？'), findsNothing);
    expect(settings.localeCode, 'en');

    await tester.tap(find.byKey(_resetKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    expect(settings.localeCode, const ViewerSettings().localeCode);
    expect(settings.toolbarMode, ToolbarMode.floating);
    expect(settings.defaultScaleModes, {
      ViewerMode.single: ViewScaleMode.originalSize,
    });
    expect(tester.widget<AppButton>(find.byKey(_resetKey)).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('settings.nav.appearance')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_resetKey));
    await tester.pumpAndSettle();
    expect(find.text('恢复本页默认？'), findsOneWidget);
    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    expect(settings.toolbarMode, ToolbarMode.normal);
    expect(settings.defaultScaleModes, {
      ViewerMode.single: ViewScaleMode.originalSize,
    });
    await tester.tap(find.byKey(const ValueKey('settings.nav.reading')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_resetKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    expect(settings.defaultScaleModes, isEmpty);
    expect(settings.localeCode, const ViewerSettings().localeCode);

    await tester.tap(find.byKey(const ValueKey('settings.nav.shortcuts')));
    await tester.pumpAndSettle();
    expect(find.byKey(_resetKey), findsOneWidget);
    expect(tester.widget<AppButton>(find.byKey(_resetKey)).onPressed, isNull);
    expect(find.text('快捷键'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('settings.nav.about')));
    await tester.pumpAndSettle();
    expect(find.byKey(_resetKey), findsNothing);
    expect(find.text('神羊看图'), findsOneWidget);
    expect(find.textContaining(AppInfo.version), findsOneWidget);
    expect(find.text('开源许可'), findsOneWidget);
    expect(find.text('第三方组件'), findsOneWidget);

    final licenseLink = find.byKey(const ValueKey('settings.openLicenses'));
    await tester.ensureVisible(licenseLink);
    await tester.tap(licenseLink);
    await tester.pumpAndSettle();
    expect(find.text('开源许可'), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('神羊看图'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches toggle from their whole row', (tester) async {
    tester.view.physicalSize = const Size(800, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var settings = const ViewerSettings();
    await tester.pumpWidget(
      _host(settings: settings, onChanged: (value) => settings = value),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings.nav.browsing')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('扫描未知扩展名文件'));
    await tester.tap(find.text('扫描未知扩展名文件'));
    await tester.pumpAndSettle();
    expect(settings.scanUnknownExtensions, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact layout keeps search available when nothing matches', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(560, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的设置'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.text('清除搜索'));
    await tester.pumpAndSettle();
    expect(find.text('通用'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'HDR type switches retain choices under global off and reset by page',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var settings = const ViewerSettings(toolbarMode: ToolbarMode.floating);
      await tester.pumpWidget(
        _host(settings: settings, onChanged: (value) => settings = value),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Gain Map');
      await tester.pumpAndSettle();
      expect(find.text('按图片类型使用 HDR'), findsOneWidget);
      Finder toggle(String label) =>
          find.byWidgetPredicate((w) => w is AppSwitch && w.label == label);
      Future<void> tapToggle(String label) async {
        await tester.ensureVisible(toggle(label));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: toggle(label), matching: find.text(label)),
        );
        await tester.pumpAndSettle();
      }

      for (final label in [
        '线性 HDR（HDR / EXR）',
        'PQ / HLG',
        'Gain Map',
        'RAW',
        'Dolby Vision',
      ]) {
        await tapToggle(label);
        expect(tester.widget<AppSwitch>(toggle(label)).value, isFalse);
      }
      expect(settings.hdrLinear, isFalse);
      expect(settings.hdrPqHlg, isFalse);
      expect(settings.hdrGainMap, isFalse);
      expect(settings.hdrRaw, isFalse);
      expect(settings.hdrDolbyVision, isFalse);
      await tapToggle('自动 HDR 显示');
      expect(settings.autoHdr, isFalse);
      expect(tester.widget<AppSwitch>(toggle('PQ / HLG')).enabled, isFalse);
      await tapToggle('PQ / HLG');
      expect(settings.hdrPqHlg, isFalse);
      await tapToggle('自动 HDR 显示');
      expect(settings.hdrGainMap, isFalse);
      expect(tester.widget<AppSwitch>(toggle('Gain Map')).enabled, isTrue);

      await tester.ensureVisible(find.byKey(_resetKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_resetKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复默认'));
      await tester.pumpAndSettle();
      expect(settings, const ViewerSettings(toolbarMode: ToolbarMode.floating));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('comic page gap uses presets and a bounded custom slider', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var settings = const ViewerSettings();
    await tester.pumpWidget(
      _host(settings: settings, onChanged: (value) => settings = value),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings.nav.reading')));
    await tester.pumpAndSettle();

    expect(find.text('双页'), findsWidgets);
    expect(find.text('连续阅读'), findsOneWidget);
    final gapSelect = find.byKey(const ValueKey('settings.comicPageGap'));
    await tester.ensureVisible(gapSelect);
    await tester.tap(gapSelect);
    await tester.pumpAndSettle();
    for (final label in ['无', '紧凑', '标准', '宽松', '自定义']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    await tester.tap(find.text('紧凑').last);
    await tester.pumpAndSettle();
    expect(settings.comicPageGap, 4);

    await tester.tap(gapSelect);
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义').last);
    await tester.pumpAndSettle();
    final slider = find.byKey(const ValueKey('settings.comicPageGapSlider'));
    expect(slider, findsOneWidget);
    expect(settings.comicPageGap, 4);
    await tester.drag(slider, const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(settings.comicPageGap, greaterThan(4));
    expect(
      settings.comicPageGap,
      lessThanOrEqualTo(ViewerSettings.maxComicPageGap),
    );

    await tester.tap(gapSelect);
    await tester.pumpAndSettle();
    await tester.tap(find.text('标准').last);
    await tester.pumpAndSettle();
    expect(settings.comicPageGap, ViewerSettings.defaultComicPageGap);
    expect(slider, findsNothing);

    await tester.tap(gapSelect);
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义').last);
    await tester.pumpAndSettle();
    expect(slider, findsOneWidget);
    await tester.drag(slider, const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(settings.comicPageGap, isNot(ViewerSettings.defaultComicPageGap));
    await tester.ensureVisible(find.byKey(_resetKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_resetKey));
    await tester.pumpAndSettle();
    expect(find.text('恢复默认'), findsOneWidget);
    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    expect(settings.comicPageGap, ViewerSettings.defaultComicPageGap);
    expect(slider, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'archive options enforce custom bounds and reset only this page',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var settings = const ViewerSettings(toolbarMode: ToolbarMode.floating);
      var clearCalls = 0;
      await tester.pumpWidget(
        _host(
          settings: settings,
          onChanged: (value) => settings = value,
          onClearArchiveCache: () async {
            clearCalls++;
          },
        ),
      );
      await tester.tap(find.byKey(const ValueKey('settings.nav.archives')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('settings.archiveMemoryMode')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('自定义').last);
      await tester.pumpAndSettle();
      final memory = find.descendant(
        of: find.byKey(const ValueKey('settings.archiveMemoryCustom')),
        matching: find.byType(TextField),
      );
      await tester.enterText(memory, '16');
      await tester.pumpAndSettle();
      expect(find.text('请输入 32 到 1024 之间的整数。'), findsOneWidget);
      expect(settings.archiveMemoryBudgetMiB, 256);
      await tester.enterText(memory, '160');
      await tester.pumpAndSettle();
      expect(settings.archiveMemoryBudgetMiB, 160);
      final clear = find.byKey(const ValueKey('settings.archiveClearCache'));
      await tester.ensureVisible(clear);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(clearCalls, 1);
      expect(find.text('已清理未使用的缓存，其余缓存会在使用结束后清理。'), findsOneWidget);
      await tester.ensureVisible(find.byKey(_resetKey));
      await tester.tap(find.byKey(_resetKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复默认'));
      await tester.pumpAndSettle();
      expect(settings.archiveMemoryBudgetMiB, 0);
      expect(settings.toolbarMode, ToolbarMode.floating);
      expect(
        find.byKey(const ValueKey('settings.archiveMemoryCustom')),
        findsNothing,
      );
    },
  );

  testWidgets('a pushed settings page exposes a back action', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: AppTheme.dark(),
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const Scaffold(body: Text('root')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsPage(
          settings: const ViewerSettings(),
          onChanged: (_) {},
          decoderRegistry: DecoderRegistry(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('root'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

List<String> _highlightedFragments(WidgetTester tester) {
  final fragments = <String>[];
  for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
    text.text.visitChildren((span) {
      if (span is TextSpan && span.style?.backgroundColor != null) {
        fragments.add(span.text!);
      }
      return true;
    });
  }
  return fragments;
}

Widget _host({
  ThemeData? theme,
  ViewerSettings settings = const ViewerSettings(),
  ValueChanged<ViewerSettings>? onChanged,
  Future<void> Function()? onClearArchiveCache,
}) => RepaintBoundary(
  key: _captureKey,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme ?? AppTheme.dark(),
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: SettingsPage(
      settings: settings,
      onChanged: onChanged ?? (_) {},
      decoderRegistry: DecoderRegistry(),
      onClearArchiveCache: onClearArchiveCache,
    ),
  ),
);

Future<void> _capture(WidgetTester tester, String filePath) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
