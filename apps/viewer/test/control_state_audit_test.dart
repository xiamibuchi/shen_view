import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/presentation/components/app_button.dart';
import 'package:shen_view/src/presentation/components/app_input.dart';
import 'package:shen_view/src/presentation/components/app_select.dart';
import 'package:shen_view/src/presentation/components/field_frame.dart';
import 'package:shen_view/src/presentation/theme/app_control_styles.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

import 'support/style_review_fonts.dart';

const _tile = ValueKey('state-audit.tile');

void main() {
  if (Platform.environment['STATE_AUDIT_CAPTURE_DIR'] != null) {
    StyleReviewBinding();
  }
  for (final dark in [true, false]) {
    testWidgets('button state fills and disabled precedence dark=$dark', (
      tester,
    ) async {
      await _fonts(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      for (final variant in AppButtonVariant.values) {
        var activations = 0;
        Future<void> show({bool enabled = true, bool busy = false}) async {
          await tester.pumpWidget(
            _host(
              AppButton(
                label: '保存图片',
                variant: variant,
                focusNode: focus,
                busy: busy,
                onPressed: enabled ? () => activations++ : null,
              ),
              dark: dark,
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
        }

        final prefix = '${dark ? 'dark' : 'light'}-button-${variant.name}';
        await mouse.moveTo(Offset.zero);
        focus.unfocus();
        await show();
        final control = find.byType(AppButton);
        final rect = tester.getRect(control);
        final normal = _buttonSurface(tester, control).color;
        await _capture(tester, '$prefix-default');
        await mouse.moveTo(rect.center);
        await tester.pumpAndSettle();
        final hover = _buttonSurface(tester, control).color;
        expect(hover, isNot(normal));
        await _capture(tester, '$prefix-hover');
        await mouse.down(rect.center);
        await tester.pumpAndSettle();
        final pressed = _buttonSurface(tester, control).color;
        expect(pressed, isNot(hover));
        await _capture(tester, '$prefix-pressed');
        await mouse.up();
        await mouse.moveTo(Offset.zero);
        focus.requestFocus();
        await tester.pumpAndSettle();
        final focused = _buttonSurface(tester, control).color;
        expect(focused, isNot(normal));
        expect(focused, isNot(hover));
        await _capture(tester, '$prefix-focused');
        await mouse.moveTo(rect.center);
        await tester.pumpAndSettle();
        expect(_buttonSurface(tester, control).color, focused);
        await _capture(tester, '$prefix-focused-hover');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(activations, 2);
        expect(tester.getRect(control), rect);
        await show(enabled: false);
        final disabled = _buttonSurface(tester, control).color;
        await mouse.down(rect.center);
        await tester.pumpAndSettle();
        expect(_buttonSurface(tester, control).color, disabled);
        await _capture(tester, '$prefix-disabled');
        await mouse.up();
        expect(activations, 2);
        expect(focus.hasFocus, isFalse);
        await show(busy: true);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await _capture(tester, '$prefix-busy');
        await tester.tap(control);
        await tester.pump();
        expect(activations, 2);
      }
      await mouse.removePointer();
    });

    testWidgets('toggle foreground and transient command fills dark=$dark', (
      tester,
    ) async {
      await _fonts(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      for (final name in [
        'sort-wide',
        'sort-compact',
        'pin',
        'toolbar',
        'bottom',
        'menu-action',
        'menu-row',
      ]) {
        List<Color?>? normalBackgrounds;
        for (final selected in [false, true]) {
          Future<void> show({bool enabled = true}) async {
            await tester.pumpWidget(
              _host(
                Builder(
                  builder: (context) {
                    final tokens = ViewerThemeTokens.of(context);
                    final style = switch (name) {
                      'sort-wide' => AppControlStyles.sortTrigger(
                        tokens,
                        size: 32,
                      ),
                      'sort-compact' => AppControlStyles.windowIcon(
                        tokens,
                        size: 32,
                        chromeColor: tokens.textPrimary,
                      ),
                      'pin' => AppControlStyles.windowIcon(
                        tokens,
                        size: 32,
                        chromeColor: tokens.textPrimary,
                        selected: selected,
                      ),
                      'toolbar' => AppControlStyles.toolbarIcon(
                        tokens,
                        size: 32,
                        selected: selected,
                      ),
                      'bottom' => AppControlStyles.bottomIcon(
                        tokens,
                        size: 32,
                        selected: selected,
                      ),
                      'menu-action' => AppControlStyles.menuAction(
                        tokens,
                        selected: selected,
                      ),
                      _ =>
                        AppControlStyles.menuItem(
                          context,
                          selected: selected,
                        ).copyWith(
                          minimumSize: const WidgetStatePropertyAll(
                            Size(140, 36),
                          ),
                        ),
                    };
                    return TextButton(
                      focusNode: focus,
                      style: style,
                      onPressed: enabled ? () {} : null,
                      child: name == 'sort-wide' || name == 'menu-row'
                          ? const Text('查看顺序')
                          : const Icon(
                              FluentIcons.arrow_sort_20_regular,
                              size: 18,
                            ),
                    );
                  },
                ),
                dark: dark,
              ),
            );
            await tester.pumpAndSettle();
          }

          await mouse.moveTo(Offset.zero);
          focus.unfocus();
          await show();
          final control = find.byType(TextButton);
          final rect = tester.getRect(control);
          final prefix =
              '${dark ? 'dark' : 'light'}-$name-${selected ? 'selected' : 'normal'}';
          final backgrounds = <Color?>[];
          backgrounds.add(_buttonSurface(tester, control).color);
          await _capture(tester, '$prefix-default');
          await mouse.moveTo(rect.center);
          await tester.pumpAndSettle();
          backgrounds.add(_buttonSurface(tester, control).color);
          await _capture(tester, '$prefix-hover');
          await mouse.down(rect.center);
          await tester.pumpAndSettle();
          backgrounds.add(_buttonSurface(tester, control).color);
          await _capture(tester, '$prefix-pressed');
          await mouse.up();
          await mouse.moveTo(Offset.zero);
          focus.requestFocus();
          await tester.pumpAndSettle();
          backgrounds.add(_buttonSurface(tester, control).color);
          await _capture(tester, '$prefix-focused');
          if (selected && name == 'menu-row') {
            for (final fill in backgrounds) {
              expect(
                fill!.b,
                greaterThan(fill.r),
                reason: '$name retains accent',
              );
            }
            expect(backgrounds[0], isNot(backgrounds[1]));
            expect(backgrounds[1], isNot(backgrounds[2]));
          } else if (selected) {
            expect(
              backgrounds,
              normalBackgrounds,
              reason: '$name toggles must not change the trigger background',
            );
          } else {
            normalBackgrounds = List.of(backgrounds);
          }
          final buttonStyle = tester.widget<TextButton>(control).style!;
          final tokens = ViewerThemeTokens.of(tester.element(control));
          expect(
            buttonStyle.foregroundColor!.resolve({}),
            selected && !name.startsWith('sort-') && name != 'menu-action'
                ? tokens.accentStrong
                : tokens.textPrimary,
          );
          expect(tester.getRect(control), rect);
          expect(
            (_buttonSurface(tester, control).shape! as RoundedRectangleBorder)
                .side,
            BorderSide.none,
          );
          await show(enabled: false);
          final disabled = _buttonSurface(tester, control).color;
          await mouse.moveTo(rect.center);
          await mouse.down(rect.center);
          await tester.pumpAndSettle();
          expect(_buttonSurface(tester, control).color, disabled);
          await _capture(tester, '$prefix-disabled');
          await mouse.up();
        }
      }
      await mouse.removePointer();
    });

    testWidgets('field states and single Tab stops dark=$dark', (tester) async {
      await _fonts(tester);
      final first = FocusNode();
      final input = FocusNode();
      final select = FocusNode();
      final last = FocusNode();
      for (final node in [first, input, select, last]) {
        addTearDown(node.dispose);
      }
      await tester.pumpWidget(
        _host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton(label: '前一项', focusNode: first, onPressed: () {}),
              AppInput(focusNode: input, hint: '搜索图片'),
              AppSelect<int>(
                value: 1,
                focusNode: select,
                onChanged: (_) {},
                options: const [AppSelectOption(value: 1, label: '名称升序')],
              ),
              AppButton(label: '后一项', focusNode: last, onPressed: () {}),
            ],
          ),
          dark: dark,
          tileHeight: 200,
        ),
      );
      first.requestFocus();
      await tester.pump();
      for (final node in [input, select, last]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(node.hasFocus, isTrue);
      }
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      for (final name in ['input', 'select', 'select-borderless']) {
        final node = name == 'input' ? input : select;
        Future<void> show({
          bool enabled = true,
          bool error = false,
          bool readOnly = false,
        }) async {
          await tester.pumpWidget(
            _host(
              name == 'input'
                  ? AppInput(
                      focusNode: node,
                      hint: '搜索图片',
                      clearable: true,
                      enabled: enabled,
                      readOnly: readOnly,
                      errorText: error ? '请输入有效值' : null,
                    )
                  : AppSelect<int>(
                      value: 1,
                      focusNode: node,
                      enabled: enabled,
                      borderless: name == 'select-borderless',
                      errorText: error ? '请选择有效值' : null,
                      onChanged: (_) {},
                      options: const [
                        AppSelectOption(value: 1, label: '名称升序'),
                        AppSelectOption(value: 2, label: '名称降序'),
                        AppSelectOption(
                          value: 3,
                          label: '不可用选项',
                          enabled: false,
                        ),
                      ],
                    ),
              dark: dark,
            ),
          );
          await tester.pumpAndSettle();
        }

        await mouse.moveTo(Offset.zero);
        node.unfocus();
        await show();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(node.hasFocus, isFalse);
        final surface = find.byType(FieldSurface);
        final size = tester.getSize(surface);
        final point = tester.getCenter(surface);
        final prefix = '${dark ? 'dark' : 'light'}-field-$name';
        await _capture(tester, '$prefix-default');
        await mouse.moveTo(point);
        await tester.pumpAndSettle();
        await _capture(tester, '$prefix-hover');
        await mouse.down(point);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        await _capture(tester, '$prefix-pressed');
        await mouse.up();
        await tester.pumpAndSettle();
        if (name != 'input') {
          expect(find.text('名称降序'), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        }
        await mouse.moveTo(Offset.zero);
        node.requestFocus();
        await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        BoxDecoration decoration() =>
            tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: surface,
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        final border = decoration().border! as Border;
        expect(border.top.width, 1);
        expect(border.left, border.top);
        expect(
          border.top.color,
          ViewerThemeTokens.of(tester.element(surface)).accentStrong,
        );
        await _capture(tester, '$prefix-focused');
        await show(error: true);
        await _capture(tester, '$prefix-error');
        expect(
          (decoration().border! as Border).top.color,
          ViewerThemeTokens.of(tester.element(surface)).danger,
        );
        await show(enabled: false);
        final disabled = decoration();
        await mouse.moveTo(tester.getCenter(surface));
        await mouse.down(tester.getCenter(surface));
        await tester.pumpAndSettle();
        expect(decoration(), disabled);
        await _capture(tester, '$prefix-disabled');
        await mouse.up();
        expect(tester.getSize(surface), size);
        if (name == 'input') {
          await show(readOnly: true);
          await tester.tap(find.byType(AppInput));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(find.byType(TextField)).readOnly,
            isTrue,
          );
          expect(
            find.byKey(const ValueKey('appInput.clearButton')),
            findsNothing,
          );
          await _capture(tester, '$prefix-readonly');
        }
        node.unfocus();
      }
      await mouse.removePointer();
    });

    testWidgets('disabled fields skip Tab and mute empty hints dark=$dark', (
      tester,
    ) async {
      final first = FocusNode();
      final last = FocusNode();
      addTearDown(first.dispose);
      addTearDown(last.dispose);
      await tester.pumpWidget(
        _host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton(label: '前一项', focusNode: first, onPressed: () {}),
              const AppInput(enabled: false, hint: '搜索图片'),
              AppSelect<int>(
                value: 1,
                enabled: false,
                onChanged: (_) {},
                options: const [AppSelectOption(value: 1, label: '名称升序')],
              ),
              AppButton(label: '后一项', focusNode: last, onPressed: () {}),
            ],
          ),
          dark: dark,
          tileHeight: 200,
        ),
      );
      final tokens = ViewerThemeTokens.of(
        tester.element(find.byType(AppInput)),
      );
      expect(
        tester.widget<Text>(find.text('搜索图片')).style!.color,
        tokens.textDisabled,
      );
      first.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(last.hasFocus, isTrue);
      expect(find.byType(MenuItemButton), findsNothing);
      final before = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(FieldSurface),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((w) => w.decoration)
          .toList();
      await tester.tap(find.byType(AppSelect<int>));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      final after = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(FieldSurface),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((w) => w.decoration)
          .toList();
      expect(after, before);
    });
  }
}

Material _buttonSurface(WidgetTester tester, Finder control) =>
    tester.widget<Material>(
      find.descendant(of: control, matching: find.byType(Material)).first,
    );

Widget _host(Widget child, {required bool dark, double tileHeight = 80}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark
          ? AppTheme.dark(platform: TargetPlatform.windows)
          : AppTheme.light(platform: TargetPlatform.windows),
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: _tile,
            child: Builder(
              builder: (context) => Container(
                width: 200,
                height: tileHeight,
                color: ViewerThemeTokens.of(context).surfaceElevated,
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _fonts(WidgetTester tester) async {
  if (Platform.environment['STATE_AUDIT_CAPTURE_DIR'] != null) {
    await loadStyleReviewFonts(tester);
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['STATE_AUDIT_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_tile),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
