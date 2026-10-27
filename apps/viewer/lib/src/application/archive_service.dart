import 'dart:io';

import 'decode_request.dart';
import 'archive_contract.dart';
import 'archive_session.dart';
export 'archive_contract.dart';
export 'archive_session.dart';

class ArchiveService {
  ArchiveService({
    this.limits = const ArchiveLimits(),
    this.cachePolicy = const ArchiveCachePolicy(),
    this.helperExecutable,
  });
  final ArchiveLimits limits;
  ArchiveCachePolicy cachePolicy;
  Future<void> configureCache(ArchiveCachePolicy policy) async {
    final previous = cachePolicy;
    cachePolicy = policy;
    final cache = ArchiveDiskCache.forPolicy(policy);
    if (previous.persistent == policy.persistent &&
        previous.maxBytes == policy.maxBytes &&
        previous.maxFiles == policy.maxFiles &&
        previous.maxAge == policy.maxAge &&
        previous.directory?.absolute.path == policy.directory?.absolute.path) {
      return;
    }
    try {
      await cache.sweep(discardOrdinary: !policy.persistent);
    } on ArchiveOpenException {
      // Settings remain effective when live leases temporarily exceed limits.
    } on FileSystemException {
      // Cleanup retries on release, admission or startup when storage recovers.
    }
  }

  final String? helperExecutable;

  Future<ArchiveSession> open(
    File source, {
    DecodeRequest? request,
    String? password,
    bool sensitive = false,
    ArchiveSession? parent,
    ArchiveFileLease? parentLease,
  }) => ArchiveSession.open(
    source,
    limits: limits,
    cachePolicy: cachePolicy,
    helperExecutable: helperExecutable,
    request: request,
    password: password,
    sensitive: sensitive,
    parent: parent,
    parentLease: parentLease,
  );

  Future<ArchiveCacheStats> cacheStats() =>
      ArchiveDiskCache.forPolicy(cachePolicy).stats();
  Future<void> clearCache() => ArchiveDiskCache.forPolicy(cachePolicy).clear();

  /// Sweeps the current archive cache without interrupting active leases.
  Future<void> sweepStale() async {
    try {
      await ArchiveDiskCache.forPolicy(cachePolicy).sweep();
    } on ArchiveOpenException {
      // Opening an archive reports cache I/O without blocking startup.
    } on FileSystemException {
      // Cleanup retries when the cache becomes writable.
    }
  }
}
