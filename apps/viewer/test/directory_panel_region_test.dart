import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/presentation/directory_panel_region.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

const _panel = ValueKey('directory.sizedPanel');
const _resize = ValueKey('directory.resize');

void main() {
  testWidgets(
    'mouse approach, press and release do not leave a blue focus line',
    (tester) async {
      final harness = await _mount(tester);
      final tokens = ViewerThemeTokens.of(tester.element(find.byKey(_panel)));
      Color? line() =>
          (tester
                      .widget<DecoratedBox>(
                        find
                            .descendant(
                              of: find.byKey(
                                const ValueKey('directory.resizeLine'),
                              ),
                              matching: find.byType(DecoratedBox),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration)
              .color;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1000, 100));
      expect(line(), tokens.navigationBorder);
      await mouse.moveTo(const Offset(350, 180));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(line(), tokens.borderStrong);
      await tester.pump(const Duration(milliseconds: 310));
      await tester.pump(const Duration(milliseconds: 140));
      expect(line(), tokens.accent);
      await mouse.moveTo(const Offset(360, 180));
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('directory.resizeRegion')),
          matching: find.byType(Tooltip),
        ),
        findsNothing,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('directory.resizeGrip'))),
        const Size(14, 36),
      );
      await mouse.down(const Offset(360, 180));
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const ValueKey('directory.resizeGrip'))),
        const Size(16, 32),
      );
      expect(line(), tokens.accent);
      expect(_width(tester), 360);
      await mouse.moveBy(const Offset(120, 0));
      await tester.pump();
      expect(_width(tester), 480);
      expect(
        find.byKey(const ValueKey('directory.resizeShield')),
        findsOneWidget,
      );
      expect(find.text('480 px'), findsNothing);
      expect(harness.saved, isEmpty);
      await mouse.up();
      await mouse.moveTo(const Offset(1000, 100));
      await tester.pumpAndSettle();
      expect(harness.saved, [480]);
      expect(
        find.byKey(const ValueKey('directory.resizeShield')),
        findsNothing,
      );
      expect(line(), tokens.navigationBorder);
      await mouse.removePointer();
    },
  );

  testWidgets(
    'limits stop precisely and reversing at a limit moves immediately',
    (tester) async {
      final harness = await _mount(tester);
      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(_resize)),
      );
      await drag.moveBy(const Offset(900, 0));
      await tester.pump();
      expect(_width(tester), 600);
      await drag.moveBy(const Offset(-20, 0));
      await tester.pump();
      expect(_width(tester), 580);
      await drag.moveBy(const Offset(-900, 0));
      await tester.pump();
      expect(_width(tester), 240);
      await drag.up();
      await tester.pumpAndSettle();
      expect(harness.saved, [240]);
    },
  );

  testWidgets(
    'Escape restores the pre-drag width and ignores remaining pointer motion',
    (tester) async {
      final harness = await _mount(tester, docked: false);
      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(_resize)),
      );
      await drag.moveBy(const Offset(90, 0));
      await tester.pump();
      expect(_width(tester), 450);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(_width(tester), 360);
      await drag.moveBy(const Offset(100, 0));
      await drag.up();
      await tester.pumpAndSettle();
      expect(harness.saved, isEmpty);
      expect(harness.closed, 0);
      expect(find.byKey(const ValueKey('directory.barrier')), findsOneWidget);
    },
  );

  for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
    testWidgets(
      'double-click reset and keyboard undo are reversible $platform',
      (tester) async {
        final harness = await _mount(
          tester,
          preferred: 480,
          platform: platform,
        );
        final mac = platform == TargetPlatform.macOS;
        final undo = mac
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        final resizeSemantics = tester.widget<Semantics>(
          find
              .ancestor(
                of: find.byKey(_resize),
                matching: find.byType(Semantics),
              )
              .first,
        );
        expect(
          resizeSemantics.properties.label,
          contains(mac ? '⌘+Z 撤销' : 'Ctrl+Z 撤销'),
        );
        await tester.tap(find.byKey(_resize));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.byKey(_resize));
        await tester.pumpAndSettle();
        expect(_width(tester), 360);
        await tester.sendKeyDownEvent(undo);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(undo);
        await tester.pumpAndSettle();
        expect(_width(tester), 480);
        await tester.tap(find.byKey(_resize));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(_width(tester), 470);
        await tester.sendKeyDownEvent(undo);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(undo);
        await tester.pump();
        expect(_width(tester), 480);
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pumpAndSettle();
        expect(_width(tester), 360);
        expect(harness.saved, [360, 480, 470, 480, 360]);
      },
    );
  }

  testWidgets(
    'window resize cancels an active drag without overwriting its remembered width',
    (tester) async {
      final harness = await _mount(tester, preferred: 600);
      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(_resize)),
      );
      await drag.moveBy(const Offset(-100, 0));
      await tester.pump();
      expect(_width(tester), 500);
      tester.view.physicalSize = const Size(440, 800);
      await tester.pump();
      expect(_width(tester), 220);
      expect(
        find.byKey(const ValueKey('directory.resizeShield')),
        findsNothing,
      );
      await drag.up();
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();
      expect(_width(tester), 600);
      expect(harness.saved, isEmpty);
    },
  );

  testWidgets(
    'touch grip accepts horizontal motion, not vertical motion or a second finger',
    (tester) async {
      final harness = await _mount(tester);
      expect(tester.getSize(find.byKey(_resize)), const Size(44, 48));
      final vertical = await tester.startGesture(
        tester.getCenter(find.byKey(_resize)),
      );
      await vertical.moveBy(const Offset(0, -90));
      await vertical.up();
      await tester.pumpAndSettle();
      expect(_width(tester), 360);
      expect(harness.saved, isEmpty);
      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(_resize)),
      );
      await drag.moveBy(const Offset(90, 0));
      await tester.pump();
      expect(_width(tester), 450);
      final second = await tester.startGesture(
        tester.getCenter(find.byKey(_resize)),
        pointer: 20,
      );
      await tester.pump();
      expect(_width(tester), 360);
      await second.up();
      await drag.up();
      await tester.pumpAndSettle();
      expect(harness.saved, isEmpty);
    },
  );

  testWidgets('drag previews, commits once and shares limits in both layouts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var preferred = 360.0;
    var docked = true;
    final saved = <double>[];
    late StateSetter update;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return DirectoryPanelRegion(
              availableWidth: 1280,
              minimumContentWidth: 220,
              preferredWidth: preferred,
              docked: docked,
              visible: true,
              panel: const Material(child: Text('Directory')),
              onClose: () {},
              onWidthChanged: (width) {
                saved.add(width);
                setState(() => preferred = width);
              },
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_resize)),
    );
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    expect(tester.getSize(find.byKey(_panel)).width, 480);
    expect(saved, isEmpty);
    await gesture.up();
    await tester.pump();
    expect(saved, [480]);
    update(() => docked = false);
    await tester.pump();
    expect(tester.getSize(find.byKey(_panel)).width, 480);
    await tester.drag(find.byKey(_resize), const Offset(-900, 0));
    await tester.pump();
    expect(preferred, 240);
    expect(tester.getSize(find.byKey(_panel)).width, 240);
    await tester.drag(find.byKey(_resize), const Offset(900, 0));
    await tester.pump();
    expect(preferred, 600);
    update(() => docked = true);
    await tester.pump();
    expect(tester.getSize(find.byKey(_panel)).width, 600);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(preferred, 590);
    expect(saved, [480, 240, 600, 590]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('window constraints and cancelled drags retain preferred width', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final saved = <double>[];
    Future<void> resize(double width) async {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(
        _host(
          LayoutBuilder(
            builder: (context, constraints) => DirectoryPanelRegion(
              availableWidth: constraints.maxWidth,
              minimumContentWidth: 220,
              preferredWidth: 600,
              docked: true,
              visible: true,
              panel: const Material(child: Text('Directory')),
              onClose: () {},
              onWidthChanged: saved.add,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await resize(1280);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_resize)),
    );
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();
    expect(tester.getSize(find.byKey(_panel)).width, 500);
    await gesture.cancel();
    await tester.pump();
    expect(tester.getSize(find.byKey(_panel)).width, 600);
    await resize(1000);
    expect(tester.getSize(find.byKey(_panel)).width, 600);
    await resize(440);
    expect(tester.getSize(find.byKey(_panel)).width, 220);
    await resize(240);
    expect(tester.getSize(find.byKey(_panel)).width, 20);
    await resize(1280);
    expect(tester.getSize(find.byKey(_panel)).width, 600);
    expect(saved, isEmpty);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

double _width(WidgetTester tester) => tester.getSize(find.byKey(_panel)).width;

class _Harness {
  _Harness(this.preferred, this.docked);
  double preferred;
  final bool docked;
  final saved = <double>[];
  int closed = 0;
}

Future<_Harness> _mount(
  WidgetTester tester, {
  double preferred = 360,
  bool docked = true,
  TargetPlatform? platform,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = _Harness(preferred, docked);
  await tester.pumpWidget(
    _host(
      StatefulBuilder(
        builder: (context, setState) => LayoutBuilder(
          builder: (context, constraints) => DirectoryPanelRegion(
            availableWidth: constraints.maxWidth,
            minimumContentWidth: 220,
            preferredWidth: harness.preferred,
            docked: harness.docked,
            visible: true,
            panel: const Material(child: Text('Directory')),
            onClose: () => harness.closed++,
            onWidthChanged: (width) => setState(() {
              harness.preferred = width;
              harness.saved.add(width);
            }),
            child: const SizedBox.expand(),
          ),
        ),
      ),
      platform: platform,
    ),
  );
  return harness;
}

Widget _host(Widget child, {TargetPlatform? platform}) => MaterialApp(
  theme: AppTheme.dark(platform: platform),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);
