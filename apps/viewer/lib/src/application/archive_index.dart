import 'dart:io';

import 'package:path/path.dart' as paths;

import '../domain/folder_entry.dart';
import '../domain/file_name_comparator.dart';
import '../domain/folder_index_result.dart';
import '../domain/image_entry.dart';
import '../domain/image_format.dart';
import '../domain/sort_order.dart';
import 'archive_image_source.dart';
import 'archive_service.dart';
import 'format_detector.dart';

// One metadata tree per open session. Expando lets closed sessions and their
// trees be collected together, without retaining passwords or extracted files.
final _directoryTrees = Expando<Map<String, _ArchiveDirectory>>();

Map<String, _ArchiveDirectory> _directories(ArchiveSession session) =>
    _directoryTrees[session] ??= _buildDirectories(session);

Map<String, _ArchiveDirectory> _buildDirectories(ArchiveSession session) {
  final directories = <String, _ArchiveDirectory>{'': _ArchiveDirectory()};
  for (final entry in session.entries) {
    if (entry.isDirectory) continue;
    final format = FormatDetector.formatForPath(entry.name);
    if (format == null || format == ImageFormat.unknown) continue;
    final parts = entry.name.split('/');
    var prefix = '';
    var directory = directories['']!;
    final archive = format == ImageFormat.archive;
    for (var i = 0; i < parts.length; i++) {
      if (archive) {
        directory.archives++;
      } else {
        directory.images++;
      }
      if (i == parts.length - 1) {
        directory.entries.add(entry);
        break;
      }
      prefix = prefix.isEmpty ? parts[i] : '$prefix/${parts[i]}';
      directory = directory.children.putIfAbsent(
        parts[i],
        () => directories.putIfAbsent(prefix, _ArchiveDirectory.new),
      );
    }
  }
  return directories;
}

class _ArchiveDirectory {
  final entries = <ArchiveEntry>[];
  final children = <String, _ArchiveDirectory>{};
  int images = 0;
  int archives = 0;

  Iterable<ArchiveEntry> descendants() sync* {
    yield* entries;
    for (final child in children.values) {
      yield* child.descendants().where(
        (entry) =>
            FormatDetector.formatForPath(entry.name) != ImageFormat.archive,
      );
    }
  }
}

/// Indexes archive metadata without creating or scanning extracted files.
FolderIndexResult archiveIndex(
  ArchiveSession session, {
  required String root,
  String prefix = '',
  bool continuous = true,
  SortOrder sort = SortOrder.nameAscending,
  FileNameSortMode fileNameSortMode = FileNameSortMode.natural,
}) {
  final images = <ImageEntry>[];
  final containers = <ImageEntry>[];
  final directory = _directories(session)[prefix] ?? _ArchiveDirectory();
  for (final entry
      in continuous ? directory.descendants() : directory.entries) {
    final format = FormatDetector.formatForPath(entry.name);
    final isArchive = format == ImageFormat.archive;
    final isImage =
        format != null && format != ImageFormat.unknown && !isArchive;
    if (!isArchive && !isImage) continue;
    final source = ArchiveImageSource(session, entry);
    final image = ImageEntry.fromSource(
      source: source,
      format: format!,
      byteLength: entry.size,
      modifiedAt: entry.modified ?? DateTime.fromMillisecondsSinceEpoch(0),
      relativeFolder: entry.name.contains('/')
          ? entry.name.substring(0, entry.name.lastIndexOf('/'))
          : null,
    );
    (isArchive ? containers : images).add(image);
  }
  int compare(ImageEntry left, ImageEntry right) {
    final leftDir = left.relativeFolder ?? '';
    final rightDir = right.relativeFolder ?? '';
    final leftParts = leftDir.isEmpty ? const <String>[] : leftDir.split('/');
    final rightParts = rightDir.isEmpty
        ? const <String>[]
        : rightDir.split('/');
    var directory = 0;
    for (var i = 0; i < leftParts.length && i < rightParts.length; i++) {
      directory = compareNames(leftParts[i], rightParts[i], fileNameSortMode);
      if (directory != 0) break;
    }
    if (directory == 0) {
      directory = leftParts.length.compareTo(rightParts.length);
    }
    if (directory != 0) return directory;
    final pathOrder = leftDir.compareTo(rightDir);
    if (pathOrder != 0) return pathOrder;
    final leftArchive = (left.source! as ArchiveImageSource).entry;
    final rightArchive = (right.source! as ArchiveImageSource).entry;
    if (sort == SortOrder.modifiedNewest || sort == SortOrder.modifiedOldest) {
      final missing = (leftArchive.modified == null ? 1 : 0).compareTo(
        rightArchive.modified == null ? 1 : 0,
      );
      if (missing != 0) return missing;
    }
    final order = switch (sort) {
      SortOrder.sizeAscending => left.byteLength.compareTo(right.byteLength),
      SortOrder.sizeDescending => right.byteLength.compareTo(left.byteLength),
      SortOrder.modifiedNewest => right.modifiedAt.compareTo(left.modifiedAt),
      SortOrder.modifiedOldest => left.modifiedAt.compareTo(right.modifiedAt),
      SortOrder.nameDescending => compareFileNames(
        right.name,
        left.name,
        fileNameSortMode,
      ),
      _ => compareFileNames(left.name, right.name, fileNameSortMode),
    };
    if (order != 0) return order;
    final name = compareFileNames(left.name, right.name, fileNameSortMode);
    if (name != 0) return name;
    final path = leftArchive.name.compareTo(rightArchive.name);
    return path != 0 ? path : leftArchive.index.compareTo(rightArchive.index);
  }

  images.sort(compare);
  containers.sort(compare);
  final children = directory.children.entries.toList()
    ..sort((a, b) {
      final order = compareNames(a.key, b.key, fileNameSortMode);
      return order != 0 ? order : a.key.compareTo(b.key);
    });
  return FolderIndexResult(
    images: images,
    containers: containers,
    childFolders: [
      for (final folder in children)
        FolderEntry(
          directory: Directory(
            paths.normalize(paths.join(root, prefix, folder.key)),
          ),
          modifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
          imageCount: folder.value.images,
          archiveCount: folder.value.archives,
          hasNavigableChildren:
              folder.value.children.isNotEmpty ||
              folder.value.entries.any(
                (entry) =>
                    FormatDetector.formatForPath(entry.name) ==
                    ImageFormat.archive,
              ),
        ),
    ],
    truncated: false,
    scannedDirectoryCount: children.length + 1,
  );
}
