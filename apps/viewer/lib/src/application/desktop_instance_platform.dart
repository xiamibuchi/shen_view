import 'dart:io';

import 'package:flutter/services.dart';

/// OS launch/file events stay outside the viewer and its reading state.
class DesktopInstancePlatform {
  static const _channel = MethodChannel('shenview/app_instance');

  static Future<void> allowActivation(int processId) async {
    if (Platform.isWindows) {
      await _channel.invokeMethod<void>('allowActivation', processId);
    }
  }

  static void listen(void Function(List<String>) onOpen) {
    if (!Platform.isMacOS) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openFiles') {
        onOpen(List<String>.from(call.arguments as List));
      }
    });
  }

  static Future<List<String>> takeInitialFiles() async {
    if (!Platform.isMacOS) return const [];
    return await _channel.invokeListMethod<String>('ready') ?? const [];
  }

  static Future<void> launchNew({String? path}) async {
    final arguments = [
      '--new-window',
      if (path != null) ...['--', path],
    ];
    if (Platform.isMacOS) {
      await _channel.invokeMethod<void>('newInstance', arguments);
    } else {
      await Process.start(
        Platform.resolvedExecutable,
        arguments,
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
    }
  }
}
