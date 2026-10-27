import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Capture actual elevation rather than Flutter's hard-edged shadow stand-in.
class StyleReviewBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}

String windowsFontPath(String name) {
  final windows =
      Platform.environment['WINDIR'] ?? Platform.environment['SystemRoot'];
  if (windows == null || windows.isEmpty) {
    throw UnsupportedError('Windows 字体截图需要 WINDIR 或 SystemRoot。');
  }
  return '$windows/Fonts/$name';
}

Future<ByteData> loadReviewFontData(String path) => path.startsWith('packages/')
    ? rootBundle.load(path)
    : File(path).readAsBytes().then(ByteData.sublistView);

/// Load installed fonts under their real family names for desktop captures.
/// Regular tests retain Flutter's deterministic test font.
Future<void> loadStyleReviewFonts(WidgetTester tester) async {
  if (!Platform.isWindows) return;
  await tester.runAsync(() async {
    for (final (family, path) in [
      ('Segoe UI Variable', windowsFontPath('SegUIVar.ttf')),
      ('Segoe UI', windowsFontPath('segoeui.ttf')),
      ('Microsoft YaHei UI', windowsFontPath('msyh.ttc')),
    ]) {
      await (FontLoader(
        family,
      )..addFont(File(path).readAsBytes().then(ByteData.sublistView))).load();
    }
    for (final (family, asset) in [
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      for (final weight in ['Regular', 'Filled'])
        (
          'packages/fluentui_system_icons/FluentSystemIcons-$weight',
          'packages/fluentui_system_icons/fonts/FluentSystemIcons-$weight.ttf',
        ),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
  });
}
