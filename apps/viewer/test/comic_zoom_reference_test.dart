import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_bottom_bar.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';
import 'package:shen_view/src/presentation/zoomable_viewport.dart';

void main() {
  testWidgets('double-page keeps the fit scale without entering comic mode', (
    tester,
  ) async {
    _configureView(tester);
    final directory = _createFolder();
    addTearDown(() => _deleteFolder(directory));
    await _pumpViewer(tester, directory);

    await _selectMode(tester, '双页');
    final viewport = find.byType(ZoomableViewport);
    expect(viewport, findsOneWidget);
    final controller = tester.widget<ZoomableViewport>(viewport).controller;
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.0001));

    // The tiny SVG is the current page. Its source width must not clamp the
    // fitted spread when the user starts dragging.
    await tester.drag(viewport, const Offset(0, -120));
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.0001));

    final thumbnail = find.descendant(
      of: find.byType(ViewerBottomBar),
      matching: find.bySemanticsLabel('b-page.png'),
    );
    expect(thumbnail, findsOneWidget);
    await tester.tap(thumbnail);
    await tester.pump(const Duration(milliseconds: 200));
    final bottomBar = tester.widget<ViewerBottomBar>(
      find.byType(ViewerBottomBar),
    );
    expect(bottomBar.controller.currentEntry?.name, 'b-page.png');
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.0001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('vertical comic keeps the canvas scale across mixed pages', (
    tester,
  ) async {
    _configureView(tester);
    final directory = _createFolder();
    addTearDown(() => _deleteFolder(directory));
    await _pumpViewer(tester, directory);

    await _selectMode(tester, '连续阅读');
    final viewport = find.byType(ZoomableViewport);
    expect(viewport, findsOneWidget);
    final controller = tester.widget<ZoomableViewport>(viewport).controller;
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.0001));

    // Dragging away from the tiny SVG page must not clamp the canvas scale.
    await tester.drag(viewport, const Offset(0, -220));
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.0001));

    // Scrolling to the PNG must keep the same canvas scale instead of using the
    // PNG source width as a new zoom reference and magnifying it.
    await tester.drag(viewport, const Offset(0, -2200));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    final bottomBar = tester.widget<ViewerBottomBar>(
      find.byType(ViewerBottomBar),
    );
    expect(bottomBar.controller.currentEntry?.name, 'b-page.png');
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.0001));
    expect(tester.takeException(), isNull);
  });
}

void _configureView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  const windowManagerChannel = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(windowManagerChannel, (call) async {
    if (call.method == 'isFullScreen' ||
        call.method == 'isMaximized' ||
        call.method == 'isAlwaysOnTop') {
      return false;
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(windowManagerChannel, null),
  );
}

Directory _createFolder() {
  final directory = Directory.systemTemp.createTempSync('comic-zoom-test');
  // A tiny SVG stretched to the canvas width must not become the zoom
  // reference for the whole strip or spread.
  File('${directory.path}/a-icon.svg').writeAsStringSync(
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
    '<rect width="24" height="24" fill="#e33"/></svg>',
  );
  File('testdata/formats/format_static.png')
      .copySync('${directory.path}/b-page.png');
  return directory;
}

void _deleteFolder(Directory directory) {
  try {
    directory.deleteSync(recursive: true);
  } on FileSystemException {
    // The decoder may still hold a copied file briefly on Windows.
  }
}

Future<void> _pumpViewer(WidgetTester tester, Directory directory) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: ViewerPage(
        configStore: AppConfigStore(filePath: '${directory.path}/viewer.json'),
        initialPath: '${directory.path}/a-icon.svg',
        initialSettings: const ViewerSettings(
          showDirectoryPanel: false,
          sortOrder: SortOrder.nameAscending,
        ),
      ),
    ),
  );
  await _pumpUntil(tester, find.byType(ZoomableViewport));
}

Future<void> _selectMode(WidgetTester tester, String label) async {
  final canvas = tester.getRect(find.byType(ZoomableViewport));
  final mouse = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await mouse.addPointer(location: canvas.center);
  await mouse.down(canvas.center);
  await mouse.up();
  await mouse.removePointer();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 150));
  expect(find.text('查看方式'), findsOneWidget);
  await tester.tap(find.text('查看方式'));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text(label), findsOneWidget);
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    });
  }
  fail('等待查看器加载超时：$finder');
}
