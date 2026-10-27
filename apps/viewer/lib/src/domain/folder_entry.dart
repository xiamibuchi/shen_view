import 'dart:io';

class FolderEntry {
  const FolderEntry({
    required this.directory,
    required this.modifiedAt,
    this.imageCount = 0,
    this.archiveCount = 0,
    this.hasNavigableChildren,
  });

  final Directory directory;
  final DateTime modifiedAt;

  /// Images in this folder and all of its descendants.
  final int imageCount;

  /// Archives in this folder and all of its descendants.
  final int archiveCount;

  /// Whether this folder has visible subfolders or archives; null if unknown.
  final bool? hasNavigableChildren;

  bool get hasContent => imageCount > 0 || archiveCount > 0;

  String get name {
    final normalized = directory.path.replaceAll('\\', '/');
    final trimmed = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    return trimmed.split('/').last;
  }
}
