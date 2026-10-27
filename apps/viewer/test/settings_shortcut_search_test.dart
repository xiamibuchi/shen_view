import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/decoder_registry.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/settings_page.dart';
import 'package:shen_view/src/presentation/components/app_button.dart';
import 'package:shen_view/src/presentation/components/app_shortcut_keycap.dart';
import 'package:shen_view/src/presentation/shortcut_editor_dialog.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_shortcuts.dart';

import 'support/style_review_fonts.dart';

const _capture = ValueKey('shortcut-search.capture');

Widget _host({
  required TargetPlatform platform,
  required Locale locale,
  required bool dark,
  required VoidCallback onChanged,
  ViewerShortcutBindings shortcuts = ViewerShortcutBindings.defaults,
  ViewerSettings settings = const ViewerSettings(),
  ValueChanged<ViewerSettings>? onSettingsChanged,
}) {
  final fontPlatform = Platform.isWindows ? TargetPlatform.windows : platform;
  final theme = dark
      ? AppTheme.dark(platform: fontPlatform)
      : AppTheme.light(platform: fontPlatform);
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: locale,
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
    builder: (context, child) => RepaintBoundary(key: _capture, child: child!),
    home: SettingsPage(
      settings: settings,
      onChanged: (value) {
        onChanged();
        onSettingsChanged?.call(value);
      },
      decoderRegistry: DecoderRegistry(),
      shortcuts: shortcuts,
    ),
  );
}

Finder get _search => find.descendant(
  of: find.byKey(const ValueKey('settings.search')),
  matching: find.byType(TextField),
);

void main() {
  testWidgets(
    'all command bindings are editable and page reset preserves other platforms',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var settings = const ViewerSettings(
        autoHdr: false,
        instanceMode: InstanceMode.multiProcess,
        shortcutOverrides: {
          'windows.rotate': ViewerShortcutBinding(
            key: LogicalKeyboardKey.keyB,
            control: true,
            shift: true,
          ),
          'macOS.rotate': ViewerShortcutBinding(
            key: LogicalKeyboardKey.keyB,
            control: true,
            shift: true,
          ),
        },
      );
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.windows,
          locale: const Locale('zh'),
          dark: false,
          settings: settings,
          onChanged: () {},
          onSettingsChanged: (value) => settings = value,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings.nav.shortcuts')));
      await tester.pumpAndSettle();
      for (final command in ViewerCommand.values) {
        expect(
          find.byKey(ValueKey('shortcuts.edit.${command.name}')),
          findsWidgets,
          reason: command.name,
        );
      }
      await tester.tap(find.byKey(const ValueKey('settings.resetSection')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复默认'));
      await tester.pumpAndSettle();
      expect(settings.shortcutOverrides.keys, ['macOS.rotate']);
      expect(settings.autoHdr, isFalse);
      await tester.tap(find.byKey(const ValueKey('settings.resetAll')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复所有设置').last);
      await tester.pumpAndSettle();
      expect(settings, const ViewerSettings());
    },
  );

  for (final width in [1280.0, 440.0]) {
    for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
      testWidgets('independent shortcut search and editing $width $platform', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
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
        var settings = const ViewerSettings(autoHdr: false);
        final mac = platform == TargetPlatform.macOS;
        final zh = width == 440;
        await tester.pumpWidget(
          _host(
            platform: platform,
            locale: Locale(zh ? 'zh' : 'en'),
            dark: mac,
            settings: settings,
            onChanged: () {},
            onSettingsChanged: (value) => settings = value,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('settings.nav.shortcuts')));
        await tester.pumpAndSettle();
        final search = find.descendant(
          of: find.byKey(const ValueKey('settings.shortcuts.search')),
          matching: find.byType(TextField),
        );
        await tester.enterText(search, 'rotate');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('settings.nav.general')),
          findsOneWidget,
        );
        expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
        expect(
          find.byKey(const ValueKey('shortcuts.edit.rename')),
          findsNothing,
        );
        final edit = find.byKey(const ValueKey('shortcuts.edit.rotate'));
        expect(edit.hitTestable(), findsOneWidget);
        await _save(tester, 'edit-${platform.name}-$width-search');
        final primary = mac
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        Future<void> record(
          LogicalKeyboardKey key, {
          bool shift = false,
        }) async {
          await tester.tap(find.byKey(const ValueKey('shortcuts.recorder')));
          await tester.sendKeyDownEvent(primary);
          if (shift) {
            await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          }
          await tester.sendKeyEvent(key);
          if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyUpEvent(primary);
          await tester.pumpAndSettle();
        }

        await tester.tap(edit);
        await tester.pumpAndSettle();
        final recorder = find.byKey(const ValueKey('shortcuts.recorder'));
        final defaultLabel = ViewerShortcutBindings.defaults.label(
          ViewerCommand.rotate,
          platform: platform,
        );
        Finder recordedLabel(String label) =>
            find.descendant(of: recorder, matching: find.text(label));
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.pumpAndSettle();
        expect(recordedLabel(defaultLabel), findsOneWidget);
        final recorderFocus = tester
            .widget<Focus>(
              find.ancestor(of: recorder, matching: find.byType(Focus)).first,
            )
            .focusNode!;
        for (var i = 0; i < 8 && !recorderFocus.hasFocus; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
        }
        expect(recorderFocus.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.pumpAndSettle();
        expect(recordedLabel(defaultLabel), findsOneWidget);
        final restoreText = find.descendant(
          of: find.byKey(const ValueKey('shortcuts.restoreOne')),
          matching: find.byType(Text),
        );
        final clearText = find.descendant(
          of: find.byKey(const ValueKey('shortcuts.clearOne')),
          matching: find.byType(Text),
        );
        final restoreRect = tester.getRect(restoreText);
        final clearRect = tester.getRect(clearText);
        expect(restoreRect.left, closeTo(tester.getRect(recorder).left, 0.1));
        expect(restoreRect.top, closeTo(clearRect.top, 0.1));
        expect(clearRect.left - restoreRect.right, greaterThanOrEqualTo(20));
        await _save(tester, 'edit-${platform.name}-$width-idle');
        await tester.tap(recorder);
        await tester.pumpAndSettle();
        expect(
          recordedLabel(zh ? '等待按键…' : 'Waiting for a key…'),
          findsOneWidget,
        );
        await _save(tester, 'edit-${platform.name}-$width-recording');
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.pumpAndSettle();
        expect(recordedLabel(defaultLabel), findsOneWidget);
        await record(LogicalKeyboardKey.keyP);
        expect(
          tester
              .widget<AppButton>(find.byKey(const ValueKey('shortcuts.save')))
              .onPressed,
          isNull,
        );
        await _save(tester, 'edit-${platform.name}-$width-conflict');
        await record(LogicalKeyboardKey.keyB, shift: true);
        final newLabel = recordedLabel(
          const ViewerShortcutBinding(
            key: LogicalKeyboardKey.keyB,
            control: true,
            shift: true,
          ).displayLabel(platform: platform),
        );
        // A completed recording must not absorb later typing.
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.pumpAndSettle();
        expect(newLabel, findsOneWidget);
        expect(
          tester
              .widget<AppButton>(find.byKey(const ValueKey('shortcuts.save')))
              .onPressed,
          isNotNull,
        );
        await _save(tester, 'edit-${platform.name}-$width-ready');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(ShortcutEditorDialog), findsNothing);
        expect(settings.shortcutOverrides, isEmpty);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        await tester.tap(recorder);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(ShortcutEditorDialog), findsNothing);
        expect(settings.shortcutOverrides, isEmpty);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        await record(LogicalKeyboardKey.keyB, shift: true);
        await tester.tap(find.byKey(const ValueKey('shortcuts.save')));
        await tester.pumpAndSettle();
        expect(
          settings
              .shortcutOverrides[ViewerShortcutBindings.overrideKey(
                platform,
                ViewerCommand.rotate,
              )]
              ?.key,
          LogicalKeyboardKey.keyB,
        );
        expect(settings.autoHdr, isFalse);
        await tester.enterText(
          search,
          mac ? 'Command+Shift+B' : 'Ctrl+Shift+B',
        );
        await tester.pumpAndSettle();
        expect(edit.hitTestable(), findsOneWidget);
        await _save(tester, 'edit-${platform.name}-$width-saved');
        await tester.tap(edit);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('shortcuts.clearOne')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('shortcuts.save')));
        await tester.pumpAndSettle();
        expect(settings.shortcutOverrides.values.single.isAssigned, isFalse);
        expect(
          find.text(
            zh
                ? '没有匹配的快捷键，试试功能名或按键。'
                : 'No matching shortcuts. Try an action or key.',
          ),
          findsOneWidget,
        );
        await _save(tester, 'edit-${platform.name}-$width-empty');
        await tester.tap(find.byKey(const ValueKey('shortcuts.clearSearch')));
        await tester.pumpAndSettle();
        await tester.enterText(search, 'rotate');
        await tester.pumpAndSettle();
        await tester.tap(edit);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('shortcuts.restoreOne')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('shortcuts.save')));
        await tester.pumpAndSettle();
        expect(settings.shortcutOverrides, isEmpty);
        expect(settings.autoHdr, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final width in [1280.0, 440.0]) {
    for (final language in ['zh', 'en']) {
      for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
        testWidgets('shortcut search $width $language $platform', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
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
          var changes = 0;
          final zh = language == 'zh';
          final mac = platform == TargetPlatform.macOS;
          await tester.pumpWidget(
            _host(
              platform: platform,
              locale: Locale(language),
              dark: mac,
              onChanged: () => changes++,
            ),
          );
          await tester.pumpAndSettle();
          // A key query must discover the category from another settings page.
          await tester.enterText(_search, 'F2');
          await tester.pumpAndSettle();
          expect(
            find.text(zh ? '重命名' : 'Rename', findRichText: true).hitTestable(),
            findsOneWidget,
          );
          expect(
            find.text(zh ? '自动适应' : 'Auto fit', findRichText: true),
            findsNothing,
          );
          final queries = {
            'rotate': zh ? '顺时针旋转' : 'Rotate clockwise',
            'F6': zh ? '开始或暂停自动播放' : 'Start or pause auto play',
            mac ? 'Command + Shift + S' : 'Ctrl + Shift + S': zh
                ? '保存原图副本'
                : 'Save original copy',
            '复制路径': zh ? '复制图片路径' : 'Copy image path',
            '空格': zh ? '播放或暂停动图' : 'Play or pause animation',
            mac ? '⌃+⌘+F' : 'F11': zh ? '切换全屏' : 'Toggle fullscreen',
          };
          for (final entry in queries.entries) {
            await tester.enterText(_search, entry.key);
            await tester.pumpAndSettle();
            expect(
              find.text(entry.value, findRichText: true).hitTestable(),
              findsOneWidget,
              reason: entry.key,
            );
            expect(
              find.text(zh ? '重命名' : 'Rename', findRichText: true),
              findsNothing,
            );
          }
          await tester.enterText(
            _search,
            mac ? 'Command + Shift + S' : 'Ctrl + Shift + S',
          );
          await tester.pumpAndSettle();
          final action = tester.getRect(
            find.text(zh ? '保存原图副本' : 'Save original copy', findRichText: true),
          );
          final binding = tester.getRect(
            find.text(mac ? '⌘+Shift+S' : 'Ctrl+Shift+S', findRichText: true),
          );
          if (width >= 600) {
            expect(binding.left - action.right, greaterThanOrEqualTo(12));
          } else {
            expect(binding.top - action.bottom, greaterThanOrEqualTo(6));
          }
          await _save(
            tester,
            '$language-${platform.name}-${width.toInt()}-result',
          );
          final controller = tester.widget<TextField>(_search).controller!;
          controller.value = const TextEditingValue(
            text: 'quan',
            composing: TextRange(start: 0, end: 4),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(zh ? '保存原图副本' : 'Save original copy', findRichText: true),
            findsOneWidget,
          );
          await tester.enterText(_search, 'unmatched-keybinding-query');
          await tester.pumpAndSettle();
          expect(
            find.text(zh ? '没有匹配的设置' : 'No matching settings'),
            findsOneWidget,
          );
          await _save(
            tester,
            '$language-${platform.name}-${width.toInt()}-empty',
          );
          await tester.tap(find.byKey(const ValueKey('appInput.clearButton')));
          await tester.pumpAndSettle();
          expect(
            find.text(zh ? '重命名' : 'Rename', findRichText: true),
            findsOneWidget,
          );
          expect(
            find.text(zh ? '自动适应' : 'Auto fit', findRichText: true),
            findsOneWidget,
          );
          await tester.enterText(
            find.descendant(
              of: find.byKey(const ValueKey('settings.shortcuts.search')),
              matching: find.byType(TextField),
            ),
            zh ? '浏览' : 'Browsing',
          );
          await tester.pumpAndSettle();
          final editable = find.byKey(
            const ValueKey('shortcuts.edit.previousImage'),
          );
          final fixed = find.byWidgetPredicate(
            (widget) =>
                widget is AppShortcutKeycap &&
                widget.label == '↑' &&
                widget.onPressed == null,
          );
          await tester.ensureVisible(editable);
          await tester.pumpAndSettle();
          expect(tester.getSize(editable), tester.getSize(fixed));
          expect(tester.getSize(editable).height, greaterThanOrEqualTo(32));
          expect(
            find.text(
              zh
                  ? '按功能名或按键搜索，点击键位修改。'
                  : 'Search actions or keys, then click a binding to edit.',
              findRichText: true,
            ),
            findsOneWidget,
          );
          await _save(
            tester,
            '$language-${platform.name}-${width.toInt()}-keycaps',
          );
          expect(changes, 0);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('shortcut search indexes supplied bindings, not only defaults', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        platform: TargetPlatform.windows,
        locale: const Locale('zh'),
        dark: true,
        onChanged: () {},
        shortcuts: const ViewerShortcutBindings(
          print: ViewerShortcutBinding(
            key: LogicalKeyboardKey.keyB,
            control: true,
            shift: true,
          ),
        ),
      ),
    );
    await tester.enterText(_search, 'Ctrl+Shift+B');
    await tester.pumpAndSettle();
    expect(find.text('打印', findRichText: true).hitTestable(), findsOneWidget);
    await tester.enterText(_search, 'Ctrl+P');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的设置'), findsOneWidget);
  });
}

Future<void> _save(WidgetTester tester, String name) async {
  final directory = Platform.environment['SHORTCUT_SEARCH_CAPTURE'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
