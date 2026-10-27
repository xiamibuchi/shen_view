import 'dart:io';

/// Release identity shown on the About page.
///
/// `test/app_info_test.dart` keeps this in sync with `pubspec.yaml`.
abstract final class AppInfo {
  static const chineseName = '神羊看图';
  static const englishName = 'ShenView';
  static const version = '0.1.0';
  static const buildNumber = 1;

  static String localizedName(String languageCode) =>
      languageCode.startsWith('zh') ? chineseName : englishName;

  static String get platformLabel {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return Platform.operatingSystem;
  }
}
