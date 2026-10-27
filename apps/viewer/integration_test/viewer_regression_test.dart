import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

import 'package:shen_view/main.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/locale_controller.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/zoomable_viewport.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1264, 800));
    await windowManager.show();
  });

  testWidgets('opens an image, navigates, and reloads in a real app', (
    tester,
  ) async {
    final image = _fixturePath(
      'normal/001-red.png',
      fallback: 'format_static.png',
    );
    await _pumpViewer(tester, image);
    await _pumpUntil(tester, find.byType(ZoomableViewport));

    expect(find.byTooltip(RegExp(r'^适应窗口(?:\s|$)')), findsOneWidget);
    expect(find.byTooltip(RegExp(r'^实际大小(?:\s|$)')), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.f5);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f5);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ZoomableViewport), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('enters long-image mode and accepts continuous scroll input', (
    tester,
  ) async {
    final image = _fixturePath(
      'long/001-long.png',
      fallback: 'format_long.png',
    );
    await _pumpViewer(tester, image);
    await _pumpUntil(tester, find.byType(ZoomableViewport));

    await tester.tapAt(const Offset(320, 320), buttons: kSecondaryMouseButton);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.text('查看方式'));
    await tester.pump(const Duration(milliseconds: 400));
    final longMode = find.text('长图');
    expect(longMode, findsOneWidget);
    await tester.tap(longMode);
    await tester.pump(const Duration(milliseconds: 250));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ZoomableViewport), findsOneWidget);
    expect(find.byKey(const ValueKey('viewer.zoomMenu')), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

Future<void> _pumpViewer(WidgetTester tester, String image) async {
  final root = await Directory.systemTemp.createTemp('viewer-regression-');
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await root.delete(recursive: true);
  });
  await tester.pumpWidget(
    ShenViewApp(
      initialPath: image,
      initialSettings: const ViewerSettings(
        localeCode: 'zh',
        showDirectoryPanel: false,
        watchFolderChanges: false,
      ),
      configStore: AppConfigStore(filePath: '${root.path}/config.json'),
      localeController: AppLocaleController()..setPreference('zh'),
    ),
  );
}

String _fixturePath(String fileName, {required String fallback}) {
  final root = Platform.environment['SHENVIEW_TESTDATA'];
  final candidate = root == null
      ? 'testdata/formats/$fallback'
      : '$root/$fileName';
  return File(candidate).absolute.path;
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('等待查看器加载超时：$finder');
}
