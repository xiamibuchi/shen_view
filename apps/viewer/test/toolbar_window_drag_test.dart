import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';

const _topBarKey = ValueKey('viewer-top-bar');

/// Hosts a floating-toolbar viewer whose window move stays blocked until the
/// returned completer is completed, exactly like the OS move loop that owns the
/// pointer for the whole drag.
Future<Completer<void>> _pumpFloatingViewer(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  const windowManagerChannel = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final drag = Completer<void>();
  messenger.setMockMethodCallHandler(windowManagerChannel, (call) async {
    switch (call.method) {
      case 'startDragging':
        await drag.future;
        return null;
      case 'isFullScreen':
      case 'isMaximized':
      case 'isAlwaysOnTop':
        return false;
    }
    return null;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(windowManagerChannel, null);
    if (!drag.isCompleted) drag.complete();
  });

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const ViewerPage(
        initialSettings: ViewerSettings(
          showDirectoryPanel: false,
          toolbarMode: ToolbarMode.floating,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return drag;
}

double _topBarOpacity(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(find.byKey(_topBarKey)).opacity;

Future<void> _disposeViewer(WidgetTester tester, TestGesture mouse) async {
  await mouse.removePointer();
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('window drag keeps the floating toolbar on screen', (
    tester,
  ) async {
    final drag = await _pumpFloatingViewer(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(640, 600));
    await tester.pump();

    // Control: an ordinary pointer exit still auto-hides the bar.
    await mouse.moveTo(const Offset(512, 16));
    await tester.pump();
    expect(_topBarOpacity(tester), 1);
    await mouse.moveTo(const Offset(640, 600));
    await tester.pump(const Duration(milliseconds: 900));
    expect(
      _topBarOpacity(tester),
      0,
      reason: 'without a drag the bar must still hide on pointer exit',
    );

    await mouse.moveTo(const Offset(512, 16));
    await tester.pump();
    expect(_topBarOpacity(tester), 1);

    await mouse.down(const Offset(512, 16));
    await mouse.moveTo(const Offset(512, 40));
    await tester.pump();

    // The move loop owns the cursor, so the bar stops receiving hover reports.
    await mouse.moveTo(const Offset(900, 620));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(_topBarOpacity(tester), 1, reason: '拖住标题栏移动窗口时，标题栏不能在拖动过程中消失');

    // The move loop ends away from the bar: the next pointer report hides it.
    drag.complete();
    await tester.pump();
    await mouse.moveTo(const Offset(910, 640));
    await tester.pump(const Duration(milliseconds: 900));
    expect(_topBarOpacity(tester), 0, reason: '拖动结束后指针已离开标题栏，应恢复自动隐藏');

    await mouse.up();
    await _disposeViewer(tester, mouse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('window drag ending on the bar keeps it visible', (tester) async {
    final drag = await _pumpFloatingViewer(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(512, 16));
    await tester.pump();
    expect(_topBarOpacity(tester), 1);

    await mouse.down(const Offset(512, 16));
    await mouse.moveTo(const Offset(512, 40));
    await tester.pump();
    await mouse.moveTo(const Offset(900, 620));
    await tester.pump(const Duration(milliseconds: 900));
    expect(_topBarOpacity(tester), 1);

    // The window followed the pointer, so the release still happens on the bar.
    drag.complete();
    await tester.pump();
    await mouse.moveTo(const Offset(520, 20));
    await tester.pump(const Duration(milliseconds: 900));
    expect(_topBarOpacity(tester), 1, reason: '指针停在标题栏上时，拖动结束不能把标题栏隐藏');

    await mouse.up();
    await _disposeViewer(tester, mouse);
    expect(tester.takeException(), isNull);
  });
}
