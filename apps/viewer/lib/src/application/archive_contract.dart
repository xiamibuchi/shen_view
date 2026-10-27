import 'dart:io';

import '../domain/archive_failure.dart';

class ArchiveLimits {
  const ArchiveLimits({
    this.maxFiles = 100000,
    this.maxTotalBytes = 1024 * 1024 * 1024,
    this.maxFileBytes = 128 * 1024 * 1024,
    this.timeout = const Duration(seconds: 60),
    this.maxDepth = 3,
    this.maxNameBytes = 16 * 1024 * 1024,
  });
  final int maxFiles;
  final int maxTotalBytes;
  final int maxFileBytes;
  final Duration timeout;
  final int maxDepth;
  final int maxNameBytes;
}

/// Classified failures are localized at the presentation boundary.
class ArchiveOpenException implements Exception {
  const ArchiveOpenException(this.kind, [this.cause]);
  final ArchiveFailureKind kind;
  final Object? cause;
  @override
  String toString() => 'ArchiveOpenException(${kind.name}): $cause';
}

class ArchiveCachePolicy {
  const ArchiveCachePolicy({
    this.persistent = true,
    this.maxBytes = 2 * 1024 * 1024 * 1024,
    this.maxFiles = 10000,
    this.maxAge = const Duration(days: 7),
    this.solidCacheEntries = 3,
    this.directory,
  });
  final bool persistent;
  final int maxBytes;
  final int maxFiles;
  final Duration maxAge;

  /// Retain already traversed images before a solid-block target. Zero disables
  /// this optional disk write; it never requests images after the target.
  final int solidCacheEntries;
  final Directory? directory;
}

class ArchiveCacheStats {
  const ArchiveCacheStats({required this.bytes, required this.files});
  final int bytes;
  final int files;
}
