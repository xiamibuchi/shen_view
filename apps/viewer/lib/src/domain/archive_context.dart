import 'dart:io';

import 'package:path/path.dart' as paths;

import '../application/archive_service.dart';

/// The archive container the viewer is currently browsing.
///
/// [extractionRoot] is an implementation detail and must never be exposed in
/// the session file, the window title, or the information panel.
class ArchiveContext {
  const ArchiveContext({
    required this.archiveFile,
    required this.extractionRoot,
    required this.originFolder,
    required this.displayName,
    this.session,
    this.parent,
    this.parentFolderPath,
    this.parentSelectedId,
    this.parentEntryDirectory,
    this.entryId,
  });

  final File archiveFile;
  final String extractionRoot;
  final String originFolder;
  final String displayName;
  final ArchiveSession? session;
  final ArchiveContext? parent;
  final String? parentFolderPath;
  final String? parentSelectedId;
  final String? parentEntryDirectory;
  final String? entryId;

  bool contains(String path) {
    final normalizedPath = paths.normalize(path);
    final normalizedRoot = paths.normalize(extractionRoot);
    return paths.equals(normalizedPath, normalizedRoot) ||
        paths.isWithin(normalizedRoot, normalizedPath);
  }

  /// Returns a display path such as `book.cbz/chapter/001.jpg`.
  String displayPath(String path) {
    final relative = paths.relative(path, from: extractionRoot);
    if (relative == '.' || relative.isEmpty) return displayName;
    return '$displayName/${relative.replaceAll('\\', '/')}';
  }
}
