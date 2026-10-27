import 'dart:io';

import 'decode_request.dart';

/// Stable image identity; a file is acquired only when a consumer needs bytes.
abstract interface class ImageSource {
  String get id;
  String get name;
  String get relativePath;
  bool get sensitive;
  Future<SourceFileLease> acquireFile({DecodeRequest? request});
}

class SourceFileLease {
  SourceFileLease(this.file, {this.onRelease});
  final File file;
  final Future<void> Function()? onRelease;
  bool _released = false;

  Future<void> release() async {
    if (_released) return;
    _released = true;
    await onRelease?.call();
  }
}
