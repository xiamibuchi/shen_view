import 'package:flutter/gestures.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';

// The command bar collapses by measured content width: seven idle command buttons
// (48 px each), a labelled sort control (~90 px), the pin (36 px) and three
// window buttons (44 px each) plus a 64 px file name. That is roughly 880 px,
// so the bar keeps every group far below the old fixed breakpoints and only
// starts folding when the content actually stops fitting.

Future<void> _pumpViewer(WidgetTester tester, Size size) async {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const ViewerPage(),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('wide command bar keeps labels, pin and every command', (
    tester,
  ) async {
    await _pumpViewer(tester, const Size(1280, 800));
    expect(find.text('查看顺序'), findsOneWidget);
    expect(find.byTooltip('窗口置顶 · Ctrl+Shift+T'), findsOneWidget);
    expect(find.byTooltip('顺时针旋转 · R'), findsOneWidget);
    expect(find.byTooltip('水平翻转 · Ctrl+M'), findsOneWidget);
    expect(find.byTooltip('打印 · Ctrl+P'), findsOneWidget);
    expect(find.byTooltip('设置'), findsNothing);
    expect(find.byTooltip('颜色拾取 · Ctrl+Shift+C'), findsOneWidget);
    expect(find.byTooltip('开始自动播放 · F6'), findsOneWidget);
    expect(find.byTooltip('停止自动播放 · Shift+F6'), findsNothing);
    expect(find.byTooltip('更多操作'), findsNothing);
    final picker = tester.getRect(find.byTooltip('颜色拾取 · Ctrl+Shift+C'));
    final viewMode = tester.getRect(find.byTooltip(RegExp('^查看方式 · ')));
    final borderless = tester.getRect(find.byTooltip('进入无边框模式 · Ctrl+Shift+F'));
    expect(viewMode.left, greaterThanOrEqualTo(picker.right));
    expect(borderless.left, greaterThanOrEqualTo(viewMode.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the file name stays in the middle of the command bar', (
    tester,
  ) async {
    await _pumpViewer(tester, const Size(1280, 800));
    final title = tester.getRect(find.text('神羊看图'));
    expect(title.center.dx, closeTo(640, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a medium bar keeps every group even though it is not wide', (
    tester,
  ) async {
    // 900 px is well below the old 1120/1020/960 breakpoints, but the content
    // still fits, so nothing may collapse.
    await _pumpViewer(tester, const Size(900, 700));
    expect(find.text('查看顺序'), findsOneWidget);
    expect(find.byTooltip('窗口置顶 · Ctrl+Shift+T'), findsOneWidget);
    expect(find.byTooltip('顺时针旋转 · R'), findsOneWidget);
    expect(find.byTooltip('水平翻转 · Ctrl+M'), findsOneWidget);
    expect(find.byTooltip('打印 · Ctrl+P'), findsOneWidget);
    expect(find.byTooltip('设置'), findsNothing);
    expect(find.byTooltip('更多操作'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact sort stays usable when idle commands require overflow', (
    tester,
  ) async {
    // Idle left-hand commands determine the centered title's minimum width.
    // At this width sort and pin collapse before the last command uses overflow.
    await _pumpViewer(tester, const Size(648, 700));
    expect(find.text('查看顺序'), findsNothing);
    expect(find.byTooltip('查看顺序'), findsOneWidget);
    expect(find.byTooltip('窗口置顶 · Ctrl+Shift+T'), findsNothing);
    expect(find.byTooltip('设置'), findsNothing);
    expect(find.byTooltip('更多操作'), findsOneWidget);

    // The compact trigger still opens the same sort order panel.
    await tester.tap(find.byTooltip('查看顺序'));
    await tester.pump();
    expect(find.text('文件名升序'), findsOneWidget);
    expect(find.text('文件大小升序'), findsOneWidget);
    await tester.tapAt(const Offset(4, 400));
    await tester.pump();
    expect(find.text('文件名升序'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pin disappears once the bar gets narrower', (tester) async {
    await _pumpViewer(tester, const Size(480, 700));
    expect(find.byTooltip('窗口置顶 · Ctrl+Shift+T'), findsNothing);
    expect(find.byTooltip('取消置顶 · Ctrl+Shift+T'), findsNothing);
    expect(find.byTooltip('顺时针旋转 · R'), findsOneWidget);
    expect(find.byTooltip('水平翻转 · Ctrl+M'), findsOneWidget);

    // Only the commands that no longer fit move into the overflow menu.
    expect(find.byTooltip('更多操作'), findsOneWidget);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pump();
    expect(find.text('顺时针旋转'), findsNothing);
    expect(find.text('水平翻转'), findsNothing);
    expect(find.text('打印'), findsOneWidget);
    expect(find.text('设置'), findsNothing);
    await tester.tapAt(const Offset(4, 400));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('commands collapse into the overflow menu step by step', (
    tester,
  ) async {
    // 440 px is the narrowest supported window: two commands stay inline, the
    // rest move into the overflow menu and the title is squeezed but visible.
    await _pumpViewer(tester, const Size(440, 700));
    expect(find.byTooltip('顺时针旋转 · R'), findsOneWidget);
    expect(find.byTooltip('水平翻转 · Ctrl+M'), findsOneWidget);
    expect(find.byTooltip('打印 · Ctrl+P'), findsNothing);
    expect(find.byTooltip('设置'), findsNothing);
    expect(find.byTooltip('更多操作'), findsOneWidget);
    final title = tester.getRect(find.text('神羊看图'));
    expect(title.width, greaterThanOrEqualTo(24));
    expect(title.center.dx, closeTo(220, 0.5));

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pump();
    expect(find.text('打印'), findsOneWidget);
    expect(find.text('设置'), findsNothing);
    await tester.tapAt(const Offset(4, 400));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('context menu exposes save as in the fourth action slot', (
    tester,
  ) async {
    await _pumpViewer(tester, const Size(1280, 800));
    // Only the empty-state icon participates in hit testing, so the secondary
    // tap has to land on it to reach the canvas context menu.
    await tester.tap(
      find.byIcon(FluentIcons.image_24_regular),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('置顶'), findsNothing);
    expect(find.text('另存为'), findsOneWidget);
    expect(find.text('打开图片'), findsOneWidget);
    await tester.tapAt(const Offset(20, 700));
    await tester.pumpAndSettle();
    expect(find.text('打开图片'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
