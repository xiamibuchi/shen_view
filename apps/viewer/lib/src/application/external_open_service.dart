import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as paths;

import '../domain/image_entry.dart';

class ExternalApplication {
  const ExternalApplication({required this.id, required this.name, this.icon});

  final String id;
  final String name;
  final Uint8List? icon;
}

class ExternalOpenService {
  const ExternalOpenService();

  static const channel = MethodChannel('shenview/external_open');

  Future<List<ExternalApplication>> applications(ImageEntry entry) async {
    final values = await channel.invokeListMethod<Object?>('applications', {
      'extension': paths.extension(entry.name).toLowerCase(),
      if (entry.source == null) 'path': entry.file.absolute.path,
    });
    final seen = <String>{};
    return [
      for (final value in values ?? const [])
        if (value is Map &&
            value['id'] is String &&
            (value['id'] as String).isNotEmpty &&
            value['name'] is String &&
            (value['name'] as String).isNotEmpty &&
            seen.add(value['id'] as String))
          ExternalApplication(
            id: value['id'] as String,
            name: value['name'] as String,
            icon: value['icon'] is Uint8List
                ? value['icon'] as Uint8List
                : null,
          ),
    ];
  }

  Future<bool> open(
    ImageEntry entry, {
    ExternalApplication? application,
    required Future<File?> Function(File source) saveCopy,
  }) async {
    File file;
    if (entry.source == null) {
      file = entry.file;
    } else {
      final lease = await entry.acquireFile();
      try {
        // External editors outlive archive sessions and may replace the file.
        // Give them a user-owned copy rather than a cache lease.
        final saved = await saveCopy(lease.file);
        if (saved == null) return false;
        file = saved;
      } finally {
        await lease.release();
      }
    }
    if (!await file.exists()) {
      throw FileSystemException('File no longer exists', file.path);
    }
    return await channel.invokeMethod<bool>(
          application == null ? 'choose' : 'open',
          {
            'path': file.absolute.path,
            if (application != null) 'application': application.id,
          },
        ) ??
        false;
  }
}
