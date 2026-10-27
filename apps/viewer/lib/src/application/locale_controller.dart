import 'package:flutter/material.dart';

import '../domain/viewer_settings.dart';

const systemLocaleCode = 'system';
const supportedLocaleCodes = <String>[systemLocaleCode, 'zh', 'en'];

Locale? localeFromCode(String code) {
  switch (code) {
    case 'zh':
      return const Locale('zh');
    case 'en':
      return const Locale('en');
    case systemLocaleCode:
    default:
      return null;
  }
}

class AppLocaleController extends ChangeNotifier {
  String _preference = systemLocaleCode;

  String get preference => _preference;
  Locale? get locale => localeFromCode(_preference);

  Future<void> load() async {
    final settings = await ViewerSettings.load();
    _setPreference(settings.localeCode, notify: false);
  }

  void setPreference(String preference) {
    _setPreference(preference);
  }

  void _setPreference(String preference, {bool notify = true}) {
    final value = supportedLocaleCodes.contains(preference)
        ? preference
        : systemLocaleCode;
    if (_preference == value) return;
    _preference = value;
    if (notify) notifyListeners();
  }
}
