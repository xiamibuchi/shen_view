import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/app_info.dart';

void main() {
  test('about version stays in sync with pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([^\s+]+)\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec.yaml must declare name+build');
    expect(match!.group(1), AppInfo.version);
    expect(int.parse(match.group(2)!), AppInfo.buildNumber);
  });
}
