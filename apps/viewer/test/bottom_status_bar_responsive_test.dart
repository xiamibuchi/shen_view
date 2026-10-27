import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';

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

Rect _rect(WidgetTester tester, Finder finder) => tester.getRect(finder);

/// Center of the info toggle inside the status bar, so the bar's own center
/// can be compared against it.
double _infoCenterX(WidgetTester tester) {
  final rect = _rect(tester, find.byTooltip('显示信息 · I'));
  return rect.center.dx;
}

void main() {
  testWidgets('wide bar keeps both scale modes and the slider', (tester) async {
    await _pumpViewer(tester, const Size(1280, 700));

    expect(find.byTooltip('适应窗口 · F'), findsOneWidget);
    expect(find.byTooltip('实际大小 · 0'), findsOneWidget);
    expect(find.byTooltip('缩小 · -'), findsOneWidget);
    expect(find.byTooltip('放大 · +'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byTooltip('更多缩放操作'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a 900 px bar still keeps both scale modes inline', (
    tester,
  ) async {
    await _pumpViewer(tester, const Size(900, 700));

    // The slider cluster is the only group that does not fit any more.
    expect(find.byTooltip('适应窗口 · F'), findsOneWidget);
    expect(find.byTooltip('实际大小 · 0'), findsOneWidget);
    expect(find.byTooltip('缩小 · -'), findsNothing);
    expect(find.byTooltip('放大 · +'), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(find.byTooltip('更多缩放操作'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the popover always exposes the complete sizing choices', (
    tester,
  ) async {
    await _pumpViewer(tester, const Size(700, 700));

    expect(find.byTooltip('更多缩放操作'), findsOneWidget);
    final trigger = _rect(tester, find.byTooltip('更多缩放操作'));
    await tester.tap(find.byTooltip('更多缩放操作'));
    await tester.pump();

    expect(find.byType(Slider), findsOneWidget);
    expect(find.byTooltip('缩小 · -'), findsOneWidget);
    expect(find.byTooltip('放大 · +'), findsOneWidget);
    expect(find.text('适应窗口'), findsOneWidget);
    expect(find.text('适应宽度'), findsOneWidget);
    expect(find.text('适应高度'), findsOneWidget);
    expect(find.text('实际大小'), findsOneWidget);
    expect(find.text('换图时保持缩放比例'), findsOneWidget);

    // It opens above the trigger and keeps the trigger's right edge.
    final panel = _rect(tester, find.byType(Slider));
    expect(panel.bottom, lessThan(trigger.top));
    expect(panel.right, lessThanOrEqualTo(trigger.right));
    expect(tester.takeException(), isNull);

    // It stays open across frames; only an explicit dismissal closes it.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(Slider), findsOneWidget);

    await tester.tapAt(const Offset(4, 200));
    await tester.pump();
    expect(find.byType(Slider), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow bar moves the scale modes into the same popover', (
    tester,
  ) async {
    await _pumpViewer(tester, const Size(440, 700));

    expect(find.byTooltip('适应窗口 · F'), findsNothing);
    expect(find.byTooltip('实际大小 · 0'), findsNothing);
    expect(find.byTooltip('更多缩放操作'), findsOneWidget);
    expect(find.byTooltip('全屏 · F11'), findsOneWidget);

    await tester.tap(find.byTooltip('更多缩放操作'));
    await tester.pump();

    // Scale modes come first, then the zoom tools below a divider.
    final fit = _rect(tester, find.text('适应窗口'));
    final actual = _rect(tester, find.text('实际大小'));
    final slider = _rect(tester, find.byType(Slider));
    expect(fit.top, lessThan(actual.top));
    expect(actual.bottom, lessThan(slider.top));
    expect(find.byTooltip('缩小 · -'), findsOneWidget);
    expect(find.byTooltip('放大 · +'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // It also survives the following frames.
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(Slider), findsOneWidget);

    await tester.tap(find.text('实际大小'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(Slider), findsNothing);
    expect(find.text('实际大小'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('escape closes the zoom popover', (tester) async {
    await _pumpViewer(tester, const Size(440, 700));
    await tester.tap(find.byTooltip('更多缩放操作'));
    await tester.pump();
    expect(find.byType(Slider), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(Slider), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('info toggle stays in the middle of the bar at every width', (
    tester,
  ) async {
    for (final width in [1280.0, 1000.0, 900.0, 700.0, 520.0, 440.0]) {
      await _pumpViewer(tester, Size(width, 700));
      expect(_infoCenterX(tester), closeTo(width / 2, 0.5), reason: '$width');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'directory toggle precedes thumbnails and works without a folder',
    (tester) async {
      for (final width in [1280.0, 440.0]) {
        await _pumpViewer(tester, Size(width, 700));
        final directory = find.byKey(const ValueKey('navigation.directory'));
        final thumbnails = find.byKey(const ValueKey('navigation.thumbnails'));
        expect(directory, findsOneWidget);
        expect(
          _rect(tester, directory).right,
          lessThanOrEqualTo(_rect(tester, thumbnails).left),
        );
        expect(find.byTooltip('展开目录面板 · D'), findsOneWidget);
        await tester.tap(directory);
        await tester.pumpAndSettle();
        expect(find.text('尚未打开文件夹'), findsOneWidget);
        expect(find.byTooltip('收起目录面板 · D'), findsOneWidget);
        final openSize = _rect(tester, directory).size;
        await tester.tap(directory);
        await tester.pumpAndSettle();
        expect(find.byTooltip('展开目录面板 · D'), findsOneWidget);
        expect(_rect(tester, directory).size, openSize);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
        await tester.pumpAndSettle();
        expect(directory, findsOneWidget, reason: 'independent of filmstrip');
        await tester.tap(directory);
        await tester.pumpAndSettle();
        expect(find.text('尚未打开文件夹'), findsOneWidget);
        await tester.tap(directory);
        await tester.pumpAndSettle();
        expect(_infoCenterX(tester), closeTo(width / 2, 0.5));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
