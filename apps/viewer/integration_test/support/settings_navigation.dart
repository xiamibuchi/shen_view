import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/presentation/settings_page.dart';

Future<void> openViewerSettings(WidgetTester tester) async {
  final modifier = Platform.isMacOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.comma);
  await tester.sendKeyUpEvent(modifier);
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(SettingsPage).evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('等待设置页打开超时');
}
