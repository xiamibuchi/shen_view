import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/presentation/components/app_button.dart';
import 'package:shen_view/src/presentation/components/app_dialog.dart';
import 'package:shen_view/src/presentation/components/app_select.dart';
import 'package:shen_view/src/presentation/components/app_switch.dart';
import 'package:shen_view/src/presentation/components/field_frame.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/theme/app_control_styles.dart';

import 'support/style_review_fonts.dart';

void main() {
  for (final dark in [true, false]) {
    testWidgets(
      'action strip uses focus backgrounds without outlines dark=$dark',
      (tester) async {
        final nodes = List.generate(4, (_) => FocusNode());
        for (final node in nodes) {
          addTearDown(node.dispose);
        }
        var activations = 0;
        await tester.pumpWidget(
          _host(
            Builder(
              builder: (context) {
                final tokens = ViewerThemeTokens.of(context);
                return Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 4; i++)
                        TextButton(
                          focusNode: nodes[i],
                          style: AppControlStyles.menuAction(tokens),
                          onPressed: () => activations++,
                          child: Text(['复制', '删除', '打印', '置顶'][i]),
                        ),
                    ],
                  ),
                );
              },
            ),
            dark: dark,
          ),
        );
        final buttons = find.byType(TextButton);
        final before = List.generate(4, (i) => tester.getRect(buttons.at(i)));
        nodes.first.requestFocus();
        await tester.pumpAndSettle();
        for (var i = 0; i < 4; i++) {
          expect(nodes[i].hasFocus, isTrue);
          final surface = tester.widget<Material>(
            find
                .descendant(of: buttons.at(i), matching: find.byType(Material))
                .first,
          );
          final tokens = ViewerThemeTokens.of(tester.element(buttons.at(i)));
          expect(surface.color, AppControlStyles.focusFill(tokens));
          expect(
            (surface.shape! as RoundedRectangleBorder).side,
            BorderSide.none,
          );
          expect(tester.getRect(buttons.at(i)), before[i]);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(activations, i + 1);
          if (i < 3) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpAndSettle();
          }
        }
      },
    );
  }

  testWidgets(
    'dialog actions have equal sizes and align in every theme and locale',
    (tester) async {
      await _fonts(tester);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final dark in [true, false]) {
        for (final english in [false, true]) {
          for (final width in [440.0, 260.0]) {
            tester.view.physicalSize = Size(width, 560);
            await tester.pumpWidget(
              _host(
                AppConfirmDialog(
                  title: english ? 'Delete image' : '删除图片',
                  content: Text(
                    english
                        ? 'Move “1.png” to the Recycle Bin?'
                        : '你确定要删除“1.png”吗？文件将被移入回收站。',
                  ),
                  cancelLabel: english ? 'Cancel' : '取消',
                  confirmLabel: english ? 'Move to Recycle Bin' : '移入回收站',
                  danger: true,
                ),
                dark: dark,
              ),
            );
            await tester.pumpAndSettle();
            final buttons = find.byType(AppButton);
            final cancel = tester.getRect(buttons.first);
            final confirm = tester.getRect(buttons.last);
            expect(cancel.size, confirm.size);
            expect(cancel.height, 36);
            if (width == 440) {
              expect(cancel.top, confirm.top);
              expect(confirm.left - cancel.right, 8);
            } else {
              expect(cancel.left, confirm.left);
              expect(confirm.top - cancel.bottom, 8);
            }
            expect(tester.takeException(), isNull);
            if (width == 440 && !english) {
              await _capture(tester, 'confirm-${dark ? 'dark' : 'light'}');
            }
          }
        }
      }
    },
  );

  testWidgets(
    'switch keeps checked fill through real hover, press, focus and disable',
    (tester) async {
      await _fonts(tester);
      tester.view.physicalSize = const Size(600, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        pointer: 1,
      );
      await mouse.addPointer();
      var changes = 0;
      for (final dark in [true, false]) {
        for (final value in [false, true]) {
          Future<void> show({bool enabled = true}) async {
            await tester.pumpWidget(
              _host(
                Center(
                  child: AppSwitch(
                    value: value,
                    enabled: enabled,
                    focusNode: focus,
                    onChanged: (_) => changes++,
                  ),
                ),
                dark: dark,
              ),
            );
            await tester.pumpAndSettle();
          }

          await mouse.moveTo(Offset.zero);
          await show();
          final control = find.byType(AppSwitch);
          final rect = tester.getRect(control);
          expect(rect.size, const Size(40, 36));
          final sample = Offset(rect.left + 8, rect.center.dy);
          final prefix =
              'switch-${dark ? 'dark' : 'light'}-${value ? 'on' : 'off'}';
          final normal = await _sample(tester, sample);
          await _capture(tester, '$prefix-normal');
          await mouse.moveTo(rect.center);
          await tester.pumpAndSettle();
          final hovered = await _sample(tester, sample);
          await _capture(tester, '$prefix-hover');
          await mouse.down(rect.center);
          await tester.pumpAndSettle();
          final pressed = await _sample(tester, sample);
          await _capture(tester, '$prefix-pressed');
          if (value) {
            for (final color in [normal, hovered, pressed]) {
              expect(
                color.b - color.r,
                greaterThan(0.25),
                reason: '$prefix stays blue',
              );
            }
          }
          await mouse.up();
          await mouse.moveTo(Offset.zero);
          focus.requestFocus();
          await tester.pumpAndSettle();
          await _capture(tester, '$prefix-focused');
          final beforeKeyboard = changes;
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(changes, beforeKeyboard + 1);
          await show(enabled: false);
          await mouse.moveTo(rect.center);
          await tester.pumpAndSettle();
          final disabled = await _sample(tester, sample);
          if (value) {
            expect(disabled.b - disabled.r, lessThan(normal.b - normal.r));
            expect(disabled.b - disabled.r, greaterThan(0.05));
          }
          final beforeDisabled = changes;
          await tester.tap(control);
          await tester.pumpAndSettle();
          expect(changes, beforeDisabled);
          expect(
            tester.binding.mouseTracker.debugDeviceActiveCursor(1),
            SystemMouseCursors.basic,
          );
          await _capture(tester, '$prefix-disabled-hover');
          focus.unfocus();
        }
      }
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact switch retains drag and checked semantics', (
    tester,
  ) async {
    var value = false;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => Center(
            child: AppSwitch(
              value: value,
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(Switch), const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(value, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.drag(find.byType(Switch), const Offset(-30, 0));
    await tester.pumpAndSettle();
    expect(value, isFalse);
  });

  testWidgets(
    'select uses regular type and background highlights without item borders',
    (tester) async {
      await _fonts(tester);
      tester.view.physicalSize = const Size(600, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      var changes = 0;
      for (final dark in [true, false]) {
        await tester.pumpWidget(
          _host(
            Center(
              child: SizedBox(
                width: 240,
                child: AppSelect<int>(
                  value: 2,
                  focusNode: focus,
                  options: const [
                    AppSelectOption(value: 1, label: '纵向连续'),
                    AppSelectOption(value: 2, label: '横向：从左到右'),
                    AppSelectOption(
                      value: 3,
                      label: '从右到左（日漫）',
                      enabled: false,
                    ),
                  ],
                  onChanged: (_) => changes++,
                ),
              ),
            ),
            dark: dark,
          ),
        );
        await tester.pumpAndSettle();
        expect(_weight(tester, find.text('横向：从左到右')), FontWeight.w400);
        await tester.tap(find.byType(FieldSurface));
        await tester.pumpAndSettle();
        for (final label in ['纵向连续', '横向：从左到右', '从右到左（日漫）']) {
          expect(_weight(tester, find.text(label).last), FontWeight.w400);
          final item = find.widgetWithText(MenuItemButton, label);
          await mouse.moveTo(tester.getCenter(item));
          await tester.pumpAndSettle();
          final button = tester.widget<MenuItemButton>(item);
          for (final states in [
            <WidgetState>{WidgetState.hovered},
            <WidgetState>{WidgetState.focused, WidgetState.hovered},
            <WidgetState>{WidgetState.disabled, WidgetState.focused},
          ]) {
            expect(button.style!.side!.resolve(states), BorderSide.none);
          }
          await _capture(
            tester,
            'select-${dark ? 'dark' : 'light'}-${label == '纵向连续'
                ? 'hover'
                : label == '横向：从左到右'
                ? 'selected'
                : 'disabled'}',
          );
        }
        await tester.tap(find.text('从右到左（日漫）'));
        expect(changes, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        focus.requestFocus();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        await _capture(tester, 'select-${dark ? 'dark' : 'light'}-keyboard');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(changes, 1);
        changes = 0;
        expect(tester.takeException(), isNull);
        await mouse.moveTo(Offset.zero);
      }
      await mouse.removePointer();
    },
  );
}

FontWeight? _weight(WidgetTester tester, Finder finder) =>
    tester.renderObject<RenderParagraph>(finder).text.style?.fontWeight;

Widget _host(Widget child, {bool dark = true}) => RepaintBoundary(
  key: const ValueKey('states.capture'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: child),
  ),
);

Future<void> _fonts(WidgetTester tester) async {
  if (Platform.environment['CONTROL_STATES_CAPTURE_DIR'] == null) return;
  await tester.runAsync(() async {
    final loader = FontLoader('Roboto')
      ..addFont(
        File(windowsFontPath('msyh.ttc'))
            .readAsBytes()
            .then(ByteData.sublistView),
      );
    await loader.load();
    final icons =
        FontLoader('packages/fluentui_system_icons/FluentSystemIcons-Regular')
          ..addFont(
            rootBundle.load(
              'packages/fluentui_system_icons/fonts/FluentSystemIcons-Regular.ttf',
            ),
          );
    await icons.load();
  });
}

RenderRepaintBoundary _boundary(WidgetTester tester) =>
    tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('states.capture')),
    );

Future<Color> _sample(WidgetTester tester, Offset point) => tester
    .runAsync(() async {
      final image = await _boundary(tester).toImage();
      try {
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final offset = (point.dy.round() * image.width + point.dx.round()) * 4;
        return Color.fromARGB(
          bytes.getUint8(offset + 3),
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
      } finally {
        image.dispose();
      }
    })
    .then((color) => color!);

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['CONTROL_STATES_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final image = await _boundary(tester).toImage();
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
