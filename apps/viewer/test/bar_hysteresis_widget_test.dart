import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';

/// Pumps the same `ViewerPage` at a new width so the page keeps its previous
/// bar decision between frames, exactly like a live window resize.
Future<void> _resize(WidgetTester tester, double width, {Size? initial}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, initial?.height ?? 700);
  if (initial != null) {
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
  }
  await tester.pump();
}

bool _visible(WidgetTester tester, String tooltip) =>
    find.byTooltip(tooltip).evaluate().isNotEmpty;

int _visibleCommands(WidgetTester tester) => [
  '顺时针旋转 · R',
  '水平翻转 · Ctrl+M',
  '打印 · Ctrl+P',
].where((tooltip) => _visible(tester, tooltip)).length;

void main() {
  testWidgets('slow shrink leaves every bar group monotone', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _resize(tester, 900, initial: const Size(900, 700));

    var previousLabel = find.text('查看顺序').evaluate().isNotEmpty;
    var previousPin = _visible(tester, '窗口置顶 · Ctrl+Shift+T');
    var previousCommands = _visibleCommands(tester);
    var previousZoom = _visible(tester, '缩小 · -');
    var previousScaleModes = _visible(tester, '适应窗口 · F');
    expect(previousCommands, 3);

    for (var width = 900.0; width >= 420; width -= 4) {
      await _resize(tester, width);
      final label = find.text('查看顺序').evaluate().isNotEmpty;
      final pin = _visible(tester, '窗口置顶 · Ctrl+Shift+T');
      final commands = _visibleCommands(tester);
      // The status bar has no image here, so the observable groups are the zoom
      // cluster and the two scale modes.
      final zoom = _visible(tester, '缩小 · -');
      final scaleModes = _visible(tester, '适应窗口 · F');

      expect(
        previousLabel || !label,
        isTrue,
        reason: 'sort label came back at $width',
      );
      expect(previousPin || !pin, isTrue, reason: 'pin came back at $width');
      expect(
        commands,
        lessThanOrEqualTo(previousCommands),
        reason: 'a command returned at $width',
      );
      expect(
        previousZoom || !zoom,
        isTrue,
        reason: 'zoom cluster came back at $width',
      );
      expect(
        previousScaleModes || !scaleModes,
        isTrue,
        reason: 'scale modes came back at $width',
      );
      expect(tester.takeException(), isNull);

      previousLabel = label;
      previousPin = pin;
      previousCommands = commands;
      previousZoom = zoom;
      previousScaleModes = scaleModes;
    }

    expect(previousCommands, lessThan(3));
    expect(previousScaleModes, isFalse);
  });

  testWidgets('flapping around the collapse width does not flicker', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _resize(tester, 900, initial: const Size(900, 700));
    expect(find.text('查看顺序'), findsOneWidget);

    // Find the width where the labelled sort control collapses. Collapsing is
    // immediate, so scanning down finds the real threshold.
    double? collapseWidth;
    for (var width = 900.0; width >= 480; width -= 2) {
      await _resize(tester, width);
      if (find.text('查看顺序').evaluate().isEmpty) {
        collapseWidth = width;
        break;
      }
    }
    final collapseAt = collapseWidth!;

    var flips = 0;
    var labelVisible = false;
    // The scan stepped over collapseAt + 2, where the label was still visible,
    // so alternating between the two states would flicker without hysteresis.
    for (var i = 0; i < 40; i++) {
      final width = i.isEven ? collapseAt + 2 : collapseAt;
      await _resize(tester, width);
      final next = find.text('查看顺序').evaluate().isNotEmpty;
      if (next != labelVisible) flips++;
      labelVisible = next;
      expect(tester.takeException(), isNull);
    }

    expect(
      flips,
      lessThanOrEqualTo(1),
      reason: 'the label flickered $flips times',
    );
    expect(labelVisible, isFalse);

    // It comes back once the window regains more than the hysteresis band.
    await _resize(tester, collapseAt + 64);
    expect(find.text('查看顺序'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status bar zoom cluster needs the band to come back', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _resize(tester, 1280, initial: const Size(1280, 700));
    expect(_visible(tester, '缩小 · -'), isTrue);

    double? collapseWidth;
    for (var width = 1280.0; width >= 700; width -= 2) {
      await _resize(tester, width);
      if (!_visible(tester, '缩小 · -')) {
        collapseWidth = width;
        break;
      }
    }
    final collapseAt = collapseWidth!;

    var flips = 0;
    var zoomVisible = false;
    // Same idea as the command bar: both ends of the oscillation are widths the
    // scan already visited, one with the cluster and one without.
    for (var i = 0; i < 40; i++) {
      final width = i.isEven ? collapseAt + 2 : collapseAt;
      await _resize(tester, width);
      final next = _visible(tester, '缩小 · -');
      if (next != zoomVisible) flips++;
      zoomVisible = next;
      expect(tester.takeException(), isNull);
    }
    expect(flips, lessThanOrEqualTo(1));
    expect(zoomVisible, isFalse);

    await _resize(tester, collapseAt + 64);
    expect(_visible(tester, '缩小 · -'), isTrue);
    expect(tester.takeException(), isNull);
  });
}
