import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shen_view/main.dart' as app;
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/locale_controller.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/zoomable_viewport.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const application = String.fromEnvironment('EXTERNAL_OPEN_UI_APP');
  const processName = String.fromEnvironment('EXTERNAL_OPEN_UI_PROCESS');
  const input = String.fromEnvironment(
    'EXTERNAL_OPEN_UI_FILE',
    defaultValue: 'testdata/formats/format_multisize.ico',
  );
  testWidgets(
    'right click works after opening and closing a real external application',
    (tester) async {
      final propagate = binding.shouldPropagateDevicePointerEvents;
      final framePolicy = binding.framePolicy;
      binding.shouldPropagateDevicePointerEvents = true;
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      addTearDown(() => binding.shouldPropagateDevicePointerEvents = propagate);
      addTearDown(() => binding.framePolicy = framePolicy);
      await windowManager.ensureInitialized();
      final root = await Directory.systemTemp.createTemp(
        'shenview-menu-launch-',
      );
      final file = File(input).absolute;
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      final locale = AppLocaleController()..setPreference('zh');
      addTearDown(locale.dispose);
      const capture = ValueKey('external-open-native-capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: app.ShenViewApp(
            localeController: locale,
            initialPath: file.path,
            initialSettings: const ViewerSettings(
              localeCode: 'zh',
              showDirectoryPanel: false,
            ),
            configStore: AppConfigStore(filePath: '${root.path}/settings.json'),
          ),
        ),
      );
      await windowManager.show();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setAlwaysOnTop(false);
      await windowManager.focus();
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(ZoomableViewport).evaluate().isNotEmpty) break;
      }
      for (var attempt = 0; attempt < 3; attempt++) {
        final before = await _applicationProcesses(processName);
        final imageCenter = tester.getCenter(find.byType(ZoomableViewport));
        await _nativeClick(tester, imageCenter, secondary: true);
        await tester.pumpAndSettle();
        expect(find.text('用其他程序打开'), findsOneWidget);
        await tester.ensureVisible(find.text('用其他程序打开'));
        await _nativeClick(
          tester,
          tester.getCenter(find.text('用其他程序打开')),
          hoverOnly: true,
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < 100; i++) {
          if (find.text(application).evaluate().isNotEmpty) break;
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(
          find.text(application),
          findsOneWidget,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data)
              .join(' | '),
        );
        await tester.pumpAndSettle();
        await _nativeClick(tester, tester.getCenter(find.text(application)));
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(seconds: 2));
        final opened = (await _applicationProcesses(processName))
            .difference(before);
        expect(opened, hasLength(1), reason: 'Expected a new external window');
        await _closeApplication(opened.single);
        expect(tester.takeException(), isNull);
      }
      await _nativeClick(
        tester,
        tester.getCenter(find.byType(ZoomableViewport)),
        secondary: true,
      );
      await tester.pumpAndSettle();
      expect(find.text('用其他程序打开'), findsOneWidget);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      final picture = await boundary.toImage();
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      final screenshot = File('build/external-open-review/menu-return.png');
      await screenshot.parent.create(recursive: true);
      await screenshot.writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    },
    skip: !Platform.isWindows || application.isEmpty || processName.isEmpty,
  );
}

Future<Set<int>> _applicationProcesses(String name) async {
  final result = await _applicationWindow(['-Name', name]);
  return const LineSplitter()
      .convert(result)
      .where((line) => line.trim().isNotEmpty)
      .map((line) => int.parse(line.trim()))
      .toSet();
}

Future<void> _closeApplication(int processId) async {
  await _applicationWindow(['-ProcessId', processId.toString()]);
}

Future<String> _applicationWindow(List<String> arguments) async {
  final result = await Process.run(
    '${Platform.environment['WINDIR']}/System32/WindowsPowerShell/v1.0/powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      File('integration_test/support/external_application_window.ps1')
          .absolute
          .path,
      ...arguments,
    ],
  );
  expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  return result.stdout as String;
}

Future<void> _nativeClick(
  WidgetTester tester,
  Offset point, {
  bool secondary = false,
  bool hoverOnly = false,
}) async {
  final scale = tester.view.devicePixelRatio;
  final result = await Process.run(
    '${Platform.environment['WINDIR']}/System32/WindowsPowerShell/v1.0/powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      File('integration_test/support/window_click.ps1').absolute.path,
      '-ProcessId',
      pid.toString(),
      '-X',
      (point.dx * scale).round().toString(),
      '-Y',
      (point.dy * scale).round().toString(),
      if (secondary) '-Secondary',
      if (hoverOnly) '-HoverOnly',
    ],
  );
  expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
}
