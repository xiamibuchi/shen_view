import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:shen_view/src/presentation/theme/app_control_styles.dart';
import 'package:shen_view/src/presentation/components/form_components.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/components/field_frame.dart';

void main() {
  testWidgets(
    'button focus uses its active fill and preserves keyboard activation',
    (tester) async {
      final first = FocusNode();
      final second = FocusNode();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      var activations = 0;
      await tester.pumpWidget(
        _host(
          Row(
            children: [
              AppButton(
                label: '取消',
                focusNode: first,
                variant: AppButtonVariant.neutral,
                onPressed: () => activations++,
              ),
              AppButton(label: '确认', focusNode: second, onPressed: () {}),
            ],
          ),
        ),
      );
      Material surface() => tester.widget<Material>(
        find
            .descendant(
              of: find.byType(AppButton).first,
              matching: find.byType(Material),
            )
            .first,
      );
      final tokens = ViewerThemeTokens.of(
        tester.element(find.byType(AppButton).first),
      );
      expect(surface().color, tokens.controlFill);
      final initialShape = surface().shape;
      final bounds = tester.getRect(find.byType(AppButton).first);
      first.requestFocus();
      await tester.pumpAndSettle();
      expect(surface().color, AppControlStyles.focusFill(tokens));
      expect(surface().shape, initialShape);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(activations, 1);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(surface().color, AppControlStyles.focusFill(tokens));
      expect(activations, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(second.hasFocus, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(first.hasFocus, isTrue);
      expect(surface().color, AppControlStyles.focusFill(tokens));
      expect(surface().shape, initialShape);
      expect(tester.getRect(find.byType(AppButton).first), bounds);
    },
  );

  testWidgets('field focus and errors recolor the full one-pixel frame', (
    tester,
  ) async {
    for (final (focused, error, enabled) in [
      (false, false, true),
      (true, false, true),
      (false, true, true),
      (true, true, false),
    ]) {
      await tester.pumpWidget(
        _host(
          FieldSurface(
            focused: focused,
            hasError: error,
            enabled: enabled,
            child: const Text('输入内容'),
          ),
        ),
      );
      final frame = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(FieldSurface),
          matching: find.byType(DecoratedBox),
        ),
      );
      final border = (frame.decoration as BoxDecoration).border! as Border;
      expect(border.top.width, 1);
      expect(border.top.color, border.bottom.color);
      final tokens = ViewerThemeTokens.of(
        tester.element(find.byType(FieldSurface)),
      );
      expect(
        border.top.color,
        !enabled
            ? tokens.border
            : error
            ? tokens.danger
            : focused
            ? tokens.accentStrong
            : tokens.border,
      );
      expect(border.left, border.top);
      expect(border.right, border.top);
      expect(frame.child, isA<Padding>());
    }
  });

  testWidgets(
    'input icons and padding focus the editor without changing its value',
    (tester) async {
      final focus = FocusNode();
      final controller = TextEditingController(text: '目录');
      addTearDown(focus.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          AppInput(
            controller: controller,
            focusNode: focus,
            label: '搜索目录',
            leadingIcon: FluentIcons.search_20_regular,
            clearable: true,
          ),
        ),
      );
      final surface = tester.getRect(find.byType(FieldSurface));
      for (final point in [
        surface.centerLeft + const Offset(3, 0),
        tester.getCenter(find.byIcon(FluentIcons.search_20_regular)),
        surface.centerRight - const Offset(3, 0),
      ]) {
        focus.unfocus();
        await tester.pump();
        await tester.tapAt(point);
        await tester.pump();
        expect(focus.hasFocus, isTrue);
        expect(controller.text, '目录');
      }
      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byType(EditableText)).label,
        contains('搜索目录'),
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'enlarged input and select share their height and retain text insets',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: AppInput(label: '输入', hint: '搜索目录'),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: AppSelect<int>(
                        label: '选择',
                        value: 1,
                        options: const [AppSelectOption(value: 1, label: 'A4')],
                        onChanged: (_) {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final surfaces = find.byType(FieldSurface);
      expect(
        tester.getSize(surfaces.at(0)).height,
        tester.getSize(surfaces.at(1)).height,
      );
      expect(tester.getSize(surfaces.at(0)).height, greaterThan(36));
      for (final (index, label) in [(0, '搜索目录'), (1, 'A4')]) {
        final bounds = tester.getRect(find.text(label));
        final surface = tester.getRect(surfaces.at(index));
        expect(bounds.height, lessThan(surface.height - 8));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keyboard select opens on the current value and skips disabled choices',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      int? chosen;
      await tester.pumpWidget(
        _host(
          AppSelect<int>(
            focusNode: focus,
            value: 3,
            options: const [
              AppSelectOption(value: 1, label: '第一项'),
              AppSelectOption(value: 2, label: '不可选', enabled: false),
              AppSelectOption(value: 3, label: '当前项'),
            ],
            onChanged: (value) => chosen = value,
          ),
        ),
      );
      final before = tester.getRect(find.byType(FieldSurface));
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final selected = tester.widget<MenuItemButton>(
        find.widgetWithText(MenuItemButton, '当前项'),
      );
      expect(selected.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(chosen, 1);
      expect(tester.getRect(find.byType(FieldSurface)), before);
      expect(focus.hasFocus, isTrue);
    },
  );

  testWidgets(
    'clear keeps editor focus, geometry and notifies once without a controller',
    (tester) async {
      final changes = <String>[];
      await tester.pumpWidget(
        _host(
          AppInput(
            hint: '搜索',
            clearable: true,
            clearTooltip: '清空搜索',
            onChanged: changes.add,
          ),
        ),
      );
      final editor = find.byType(EditableText);
      final before = tester.getRect(editor);
      expect(find.byTooltip('清空搜索'), findsNothing);
      await tester.enterText(editor, '图片');
      await tester.pumpAndSettle();
      expect(tester.getRect(editor), before);
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pumpAndSettle();
      expect(changes, ['图片', '']);
      expect(tester.widget<EditableText>(editor).controller.text, isEmpty);
      expect(tester.widget<EditableText>(editor).focusNode.hasFocus, isTrue);
      expect(tester.getRect(editor), before);
      expect(find.byTooltip('清空搜索'), findsNothing);
    },
  );

  testWidgets('a read-only input cannot be cleared', (tester) async {
    final controller = TextEditingController(text: '只读');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(AppInput(controller: controller, readOnly: true, clearable: true)),
    );
    expect(find.byKey(const ValueKey('appInput.clearButton')), findsNothing);
    expect(controller.text, '只读');
  });

  testWidgets('select clears pointer focus but preserves keyboard navigation', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _host(
        AppSelect<int>(
          value: 1,
          focusNode: focus,
          borderless: true,
          options: const [
            AppSelectOption(value: 1, label: '第01章'),
            AppSelectOption(value: 2, label: '第02章'),
          ],
          onChanged: (_) {},
        ),
      ),
    );
    bool highlighted() =>
        tester.widget<FieldSurface>(find.byType(FieldSurface)).focused;
    await tester.tap(find.byType(AppSelect<int>));
    await tester.pumpAndSettle();
    expect(highlighted(), isTrue);
    await tester.tap(find.text('第02章'));
    await tester.pumpAndSettle();
    expect(highlighted(), isFalse);
    await tester.tapAt(const Offset(700, 450));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      highlighted(),
      isFalse,
      reason: 'Ctrl used for image zoom must not restore select focus',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(focus.hasFocus, isFalse);
    await tester.tap(find.byType(AppSelect<int>));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(700, 450));
    await tester.pumpAndSettle();
    expect(highlighted(), isFalse);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNWidgets(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(highlighted(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('第02章'));
    await tester.pumpAndSettle();
    expect(highlighted(), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('input and select share 36px surfaces and text alignment', (
    tester,
  ) async {
    final controller = TextEditingController(text: '20');
    addTearDown(controller.dispose);
    for (final dark in [true, false]) {
      await tester.pumpWidget(
        _host(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppInput(
                  label: '页边距',
                  controller: controller,
                  suffixText: 'mm',
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: AppSelect<String>(
                  label: '纸张',
                  value: 'a4',
                  options: const [AppSelectOption(value: 'a4', label: 'A4')],
                  onChanged: (_) {},
                ),
              ),
            ],
          ),
          dark: dark,
        ),
      );
      await tester.pumpAndSettle();
      final surfaces = find.byType(FieldSurface);
      expect(tester.getSize(surfaces.at(0)).height, 36);
      expect(tester.getSize(surfaces.at(1)).height, 36);
      expect(
        tester.getTopLeft(surfaces.at(0)).dy,
        tester.getTopLeft(surfaces.at(1)).dy,
      );
      expect(
        tester.getCenter(find.byType(EditableText)).dy,
        closeTo(tester.getCenter(find.text('A4')).dy, 1),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('buttons fit a dialog row and expose actual hand cursors', (
    tester,
  ) async {
    var cancelled = false;
    await tester.pumpWidget(
      _host(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton(
              label: '取消',
              variant: AppButtonVariant.neutral,
              onPressed: () => cancelled = true,
            ),
            const SizedBox(width: 8),
            AppButton(
              label: '删除',
              variant: AppButtonVariant.danger,
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 1,
    );
    await mouse.addPointer(location: Offset.zero);
    for (final text in ['取消', '删除']) {
      await mouse.moveTo(tester.getCenter(find.text(text)));
      await tester.pump();
      expect(
        tester.binding.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );
    }
    await tester.tap(find.text('取消'));
    expect(cancelled, isTrue);
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
  });

  testWidgets(
    'select anchors its menu and supports keyboard selection and Escape',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      String? changed;
      await tester.pumpWidget(
        _host(
          AppSelect<String>(
            label: '纸张大小',
            helperText: '下方说明不参与菜单定位',
            focusNode: focus,
            value: 'a4',
            options: const [
              AppSelectOption(value: 'a4', label: 'A4'),
              AppSelectOption(value: 'disabled', label: '禁用项', enabled: false),
              AppSelectOption(value: 'a3', label: 'A3'),
            ],
            onChanged: (value) => changed = value,
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final control = tester.getRect(find.byType(FieldSurface));
      final item = tester.getRect(find.byType(MenuItemButton).first);
      expect(
        item.top,
        inInclusiveRange(control.bottom + 6, control.bottom + 14),
      );
      expect(item.left, inInclusiveRange(control.left, control.left + 8));
      expect(item.width, closeTo(control.width - 8, 2));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(changed, 'a3');
      expect(find.byType(MenuItemButton), findsNothing);
      await tester.tap(find.byType(FieldSurface));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('select menu only widens when an option label does not fit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> show(String label) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: 180,
                child: AppSelect<String>(
                  value: 'only',
                  options: [AppSelectOption(value: 'only', label: label)],
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await show('短');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppSelect<String>));
    await tester.pumpAndSettle();
    var control = tester.getRect(find.byType(FieldSurface));
    var item = tester.getRect(find.byType(MenuItemButton).last);
    expect(item.width, closeTo(control.width - 8, 2));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await show('这是一个明显超过控件宽度的很长选项标签');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppSelect<String>));
    await tester.pumpAndSettle();
    control = tester.getRect(find.byType(FieldSurface));
    item = tester.getRect(find.byType(MenuItemButton).last);
    expect(item.width, greaterThan(control.width + 80));
    expect(item.width, lessThanOrEqualTo(360));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disabled controls ignore clicks and use an arrow cursor', (
    tester,
  ) async {
    var changes = 0;
    await tester.pumpWidget(
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppButton(label: '不可用'),
            AppSelect<int>(
              enabled: false,
              value: 1,
              options: const [AppSelectOption(value: 1, label: '一')],
              onChanged: (_) => changes++,
            ),
            AppSwitch(
              value: false,
              enabled: false,
              onChanged: (_) => changes++,
            ),
            AppTabSwitch<int>(
              value: 1,
              enabled: false,
              options: const [
                AppTabOption(value: 1, label: '一页'),
                AppTabOption(value: 2, label: '两页'),
              ],
              onChanged: (_) => changes++,
            ),
            const AppInput(enabled: false, hint: '禁用输入'),
          ],
        ),
      ),
    );
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 1,
    );
    await mouse.addPointer(location: Offset.zero);
    for (final finder in [
      find.text('不可用'),
      find.text('一'),
      find.byType(Switch),
      find.text('两页'),
    ]) {
      await mouse.moveTo(tester.getCenter(finder));
      await tester.pump();
      expect(
        tester.binding.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.basic,
      );
      await tester.tap(finder);
    }
    expect(changes, 0);
    expect(find.byType(MenuItemButton), findsNothing);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('form components expose their states and callbacks', (
    tester,
  ) async {
    final inputController = TextEditingController();
    addTearDown(inputController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: _FormHarness(inputController: inputController)),
      ),
    );

    expect(tester.getSize(find.byType(AppButton)).height, 36);
    expect(
      tester.getSize(find.byType(TextField)).height,
      lessThanOrEqualTo(36),
    );

    await tester.tap(find.byType(AppButton));
    await tester.pump();
    expect(find.text('button:1'), findsOneWidget);

    await tester.tap(find.byType(AppSelect<String>));
    await tester.pumpAndSettle();
    expect(find.text('第二项'), findsOneWidget);
    await tester.tap(find.text('第二项'));
    await tester.pumpAndSettle();
    expect(find.text('selected:two'), findsOneWidget);

    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(find.text('switch:on'), findsOneWidget);

    await tester.tap(find.text('标签二'));
    await tester.pump();
    expect(find.text('tab:two'), findsOneWidget);

    await tester.tap(find.byType(AppInput));
    await tester.enterText(find.byType(AppInput), 'sample');
    await tester.pump();
    expect(inputController.text, 'sample');
  });
}

Widget _host(Widget child, {bool dark = true}) => MaterialApp(
  theme: dark ? AppTheme.dark() : AppTheme.light(),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox(width: 420, child: child),
      ),
    ),
  ),
);

class _FormHarness extends StatefulWidget {
  const _FormHarness({required this.inputController});

  final TextEditingController inputController;

  @override
  State<_FormHarness> createState() => _FormHarnessState();
}

class _FormHarnessState extends State<_FormHarness> {
  int buttonPresses = 0;
  String selected = 'one';
  bool switched = false;
  String tab = 'one';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 800,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          AppButton(
            label: '按钮',
            onPressed: () => setState(() => buttonPresses++),
          ),
          Text('button:$buttonPresses'),
          AppSelect<String>(
            label: '选择',
            value: selected,
            options: const [
              AppSelectOption(value: 'one', label: '第一项'),
              AppSelectOption(value: 'two', label: '第二项'),
            ],
            onChanged: (value) => setState(() => selected = value),
          ),
          Text('selected:$selected'),
          AppSwitch(
            label: '开关',
            value: switched,
            onChanged: (value) => setState(() => switched = value),
          ),
          Text(switched ? 'switch:on' : 'switch:off'),
          AppTabSwitch<String>(
            value: tab,
            options: const [
              AppTabOption(value: 'one', label: '标签一'),
              AppTabOption(value: 'two', label: '标签二'),
            ],
            onChanged: (value) => setState(() => tab = value),
          ),
          Text('tab:$tab'),
          AppInput(
            label: '输入',
            controller: widget.inputController,
            hint: '请输入',
          ),
        ],
      ),
    );
  }
}
