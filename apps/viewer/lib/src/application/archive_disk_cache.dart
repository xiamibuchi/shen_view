import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as paths;

import '../domain/archive_failure.dart';
import 'archive_contract.dart';
import 'decode_request.dart';
import 'windows_distribution.dart';

/// A path is valid only while this lease is held. Release is idempotent.
class ArchiveFileLease {
  ArchiveFileLease(this.file, Future<void> Function() release)
    : _release = release;
  final File file;
  final Future<void> Function() _release;
  bool _released = false;
  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _release();
  }
}

class ArchiveCacheItem {
  const ArchiveCacheItem({
    required this.key,
    required this.extension,
    required this.expectedBytes,
    required this.maximumBytes,
    this.optional = false,
  });

  final String key;
  final String extension;
  final int expectedBytes;
  final int maximumBytes;
  final bool optional;
}

class ArchiveCacheOutput {
  const ArchiveCacheOutput({
    required this.item,
    required this.file,
    required this.maximumBytes,
  });

  final ArchiveCacheItem item;
  final File file;
  final int maximumBytes;
}

class ArchiveDiskCache {
  ArchiveDiskCache._(this.policy, this.root);
  static final _instances = <String, ArchiveDiskCache>{};
  static ArchiveDiskCache forPolicy(ArchiveCachePolicy policy) {
    final location =
        policy.directory ??
        Directory(
          paths.join(
            Platform.isWindows
                ? paths.join(
                    WindowsDistribution.currentDataDirectory(),
                    'cache',
                  )
                : Platform.isMacOS
                ? paths.join(
                    Platform.environment['HOME'] ?? Directory.systemTemp.path,
                    'Library',
                    'Caches',
                  )
                : (Platform.environment['XDG_CACHE_HOME'] ??
                      paths.join(
                        Platform.environment['HOME'] ??
                            Directory.systemTemp.path,
                        '.cache',
                      )),
            'ShenView',
            'archives-v2',
          ),
        );
    final cache = _instances.putIfAbsent(
      location.absolute.path,
      () => ArchiveDiskCache._(policy, location),
    );
    cache.policy = policy;
    return cache;
  }

  ArchiveCachePolicy policy;
  Directory root;
  final _references = <String, int>{};
  final _leaseLocks = <String, RandomAccessFile>{};
  Future<void> _tail = Future<void>.value();
  Future<void>? _initialized;
  bool _pendingSwept = false;
  bool _reclaimAfterRelease = false;

  Future<void> _initialize() => _initialized ??= _prepare();
  Future<void> _prepare() async {
    try {
      await root.create(recursive: true);
      final probe = File(paths.join(root.path, '.probe-$pid'));
      await probe.writeAsString('');
      await probe.delete();
    } on FileSystemException {
      root = Directory(
        paths.join(Directory.systemTemp.path, 'shen_view-archives-v2'),
      );
      try {
        await root.create(recursive: true);
      } on FileSystemException catch (error) {
        throw ArchiveOpenException(ArchiveFailureKind.io, error);
      }
    }
  }

  Future<void> _removePrivateOrphans() async {
    // Private directories hold an OS lock for their complete lifetime. A crash
    // releases it, allowing the next process to remove sensitive leftovers.
    await for (final directory in root.list(followLinks: false)) {
      if (directory is! Directory ||
          !paths.basename(directory.path).startsWith('private-')) {
        continue;
      }
      RandomAccessFile? marker;
      try {
        marker = await File(paths.join(directory.path, '.active'))
            .open(mode: FileMode.append);
        await marker.lock(FileLock.exclusive);
        await marker.close();
        marker = null;
        await directory.delete(recursive: true);
      } on FileSystemException {
        // Active in another process, or cleanup will be retried later.
      } finally {
        await marker?.close();
      }
    }
  }

  Future<(Directory, RandomAccessFile)> privateDirectory() =>
      _exclusive(() async {
        final directory = await root.createTemp('private-$pid-');
        final lock = await File(paths.join(directory.path, '.active'))
            .open(mode: FileMode.append);
        await lock.lock(FileLock.exclusive);
        return (directory, lock);
      });

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      RandomAccessFile? guard;
      try {
        await _initialize();
        guard = await File(paths.join(root.path, '.maintenance'))
            .open(mode: FileMode.append);
        await guard.lock(FileLock.blockingExclusive);
        if (!_pendingSwept) {
          _pendingSwept = true;
          await _removePrivateOrphans();
          // Every writer holds this process-shared lock, so pending files
          // observed here cannot belong to an active extraction.
          await for (final entity in root.list(
            recursive: true,
            followLinks: false,
          )) {
            if (entity is File &&
                paths.basename(entity.path).contains('.pending-')) {
              try {
                await entity.delete();
              } on FileSystemException {
                /* Retry on later startup. */
              }
            }
          }
        }
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      } finally {
        try {
          await guard?.close();
        } on FileSystemException {
          /* OS closes the handle at process exit. */
        }
      }
    });
    return result.future;
  }

  Future<List<File>> _files() async => [
    await for (final entity in root.list(recursive: true, followLinks: false))
      if (entity is File &&
          RegExp(r'^entry-[0-9a-f]{16}\.[a-z0-9]+$')
              .hasMatch(paths.basename(entity.path)))
        entity,
  ];

  Future<ArchiveCacheStats> stats() => _exclusive(() async {
    var bytes = 0;
    final files = await _files();
    for (final file in files) {
      bytes += await file.length();
    }
    return ArchiveCacheStats(bytes: bytes, files: files.length);
  });

  Future<bool> _evict(File file) async {
    if ((_references[file.path] ?? 0) > 0) return false;
    RandomAccessFile? lock;
    try {
      lock = await File('${file.path}.lease').open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      await file.delete();
      await lock.close();
      lock = null;
      try {
        await File('${file.path}.lease').delete();
        final discard = File('${file.path}.discard');
        if (await discard.exists()) await discard.delete();
      } on FileSystemException {
        /* Another process may have opened the marker. */
      }
      return true;
    } on FileSystemException {
      return false;
    } finally {
      await lock?.close();
    }
  }

  Future<void> clear() => _exclusive(() async {
    for (final file in await _files()) {
      await _evict(file);
    }
  });

  Future<void> sweep({bool discardOrdinary = false}) => _exclusive(() async {
    if (discardOrdinary) {
      for (final file in await _files()) {
        if (paths.equals(file.parent.path, root.path)) {
          // The marker also informs another process's eventual lease release.
          await File('${file.path}.discard').writeAsString('');
          await _evict(file);
        }
      }
    }
    try {
      await _makeRoom(0, additionalFiles: 0);
      _reclaimAfterRelease = false;
    } on ArchiveOpenException {
      // Lowered budgets may be temporarily exceeded by protected live leases.
      _reclaimAfterRelease = true;
    }
  });

  Future<void> _makeRoom(int additional, {int additionalFiles = 1}) async {
    if (additional > policy.maxBytes || policy.maxFiles < additionalFiles) {
      throw const ArchiveOpenException(ArchiveFailureKind.resource);
    }
    final candidates = <(File, FileStat)>[];
    var bytes = 0;
    for (final file in await _files()) {
      final stat = await file.stat();
      bytes += stat.size;
      candidates.add((file, stat));
    }
    candidates.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    var count = candidates.length;
    for (final (file, stat) in candidates) {
      final expired = DateTime.now().difference(stat.modified) > policy.maxAge;
      final discarded = await File('${file.path}.discard').exists();
      if (!expired &&
          !discarded &&
          bytes + additional <= policy.maxBytes &&
          count + additionalFiles <= policy.maxFiles) {
        continue;
      }
      if (await _evict(file)) {
        bytes -= stat.size;
        count--;
      }
    }
    if (bytes + additional > policy.maxBytes ||
        count + additionalFiles > policy.maxFiles) {
      throw const ArchiveOpenException(ArchiveFailureKind.resource);
    }
  }

  Future<ArchiveFileLease> acquire({
    required String key,
    required String extension,
    required int expectedBytes,
    required Future<void> Function(File output, int maximumBytes) write,
    required int maximumBytes,
    required DecodeRequest? request,
    Directory? privateRoot,
    bool sensitive = false,
  }) => _exclusive(() async {
    request?.throwIfCancelled();
    final activePrivateRoot = sensitive || !policy.persistent
        ? privateRoot
        : null;
    if ((sensitive || !policy.persistent) && activePrivateRoot == null) {
      throw const ArchiveOpenException(ArchiveFailureKind.resource);
    }
    final folder = activePrivateRoot ?? root;
    final safeExtension = RegExp(r'^\.[a-zA-Z0-9]{1,10}$').hasMatch(extension)
        ? extension.toLowerCase()
        : '.bin';
    final target = File(paths.join(folder.path, 'entry-$key$safeExtension'));
    if (!await target.exists()) {
      await _makeRoom(expectedBytes);
      final output = File(
        '${target.path}.pending-$pid-${Random.secure().nextInt(1 << 32)}',
      );
      try {
        await write(output, min(maximumBytes, policy.maxBytes));
        request?.throwIfCancelled();
        final length = await output.length();
        if (length != expectedBytes || length > maximumBytes) {
          throw const ArchiveOpenException(ArchiveFailureKind.corrupt);
        }
        await output.rename(target.path);
      } finally {
        if (await output.exists()) await output.delete();
      }
    }
    return _lease(target, activePrivateRoot);
  });

  /// Admits and publishes one extraction transaction under the maintenance lock.
  /// Optional items are selected only after every mandatory item has room.
  Future<Map<String, ArchiveFileLease>> acquireBatch({
    required List<ArchiveCacheItem> items,
    required DecodeRequest? request,
    Directory? privateRoot,
    bool sensitive = false,
    required Future<void> Function(List<ArchiveCacheOutput>) write,
  }) => _exclusive(() async {
    request?.throwIfCancelled();
    if (items.length > 16 ||
        items.map((item) => item.key).toSet().length != items.length) {
      throw ArgumentError('A cache batch requires at most 16 unique keys.');
    }
    final activePrivateRoot = sensitive || !policy.persistent
        ? privateRoot
        : null;
    if ((sensitive || !policy.persistent) && activePrivateRoot == null) {
      throw const ArchiveOpenException(ArchiveFailureKind.resource);
    }
    final folder = activePrivateRoot ?? root;
    final leases = <String, ArchiveFileLease>{};
    final outputs = <ArchiveCacheOutput>[];
    final targets = <String, File>{};
    final committed = <File>[];
    var reservedBytes = 0;

    File targetFor(ArchiveCacheItem item) {
      if (!RegExp(r'^[0-9a-f]{16}$').hasMatch(item.key)) {
        throw ArgumentError.value(
          item.key,
          'key',
          'Expected a 16-digit cache key',
        );
      }
      final extension =
          RegExp(r'^\.[a-zA-Z0-9]{1,10}$').hasMatch(item.extension)
          ? item.extension.toLowerCase()
          : '.bin';
      return File(paths.join(folder.path, 'entry-${item.key}$extension'));
    }

    Future<bool> takeHit(ArchiveCacheItem item) async {
      final target = targets[item.key]!;
      if (!await target.exists()) return false;
      final length = await target.length();
      if (length != item.expectedBytes || length > item.maximumBytes) {
        throw const ArchiveOpenException(ArchiveFailureKind.corrupt);
      }
      leases[item.key] = await _lease(target, activePrivateRoot);
      return true;
    }

    void addOutput(ArchiveCacheItem item) {
      reservedBytes += item.expectedBytes;
      outputs.add(
        ArchiveCacheOutput(
          item: item,
          file: File(
            '${targets[item.key]!.path}.pending-$pid-${Random.secure().nextInt(1 << 32)}',
          ),
          maximumBytes: min(item.maximumBytes, policy.maxBytes),
        ),
      );
    }

    try {
      for (final item in items) {
        if (item.expectedBytes < 0 || item.maximumBytes < item.expectedBytes) {
          throw const ArchiveOpenException(ArchiveFailureKind.resource);
        }
        targets[item.key] = targetFor(item);
      }
      // Lease all mandatory hits before eviction can consider any batch item.
      for (final item in items.where((item) => !item.optional)) {
        request?.throwIfCancelled();
        if (!await takeHit(item)) addOutput(item);
      }
      if (outputs.isNotEmpty) {
        await _makeRoom(reservedBytes, additionalFiles: outputs.length);
      }
      final hasMandatoryMiss = outputs.isNotEmpty;
      for (final item in items.where(
        (item) => item.optional && hasMandatoryMiss,
      )) {
        request?.throwIfCancelled();
        try {
          if (await takeHit(item)) continue;
          await _makeRoom(
            reservedBytes + item.expectedBytes,
            additionalFiles: outputs.length + 1,
          );
        } on ArchiveOpenException catch (error) {
          if (error.kind == ArchiveFailureKind.corrupt) {
            // A speculative neighbor must not prevent the requested page from
            // opening. Discard it only when no current owner holds its lease,
            // and do not turn this damaged hit into another extraction target.
            try {
              await _evict(targets[item.key]!);
            } on FileSystemException {
              /* Optional cache cleanup can be retried on the next sweep. */
            }
            continue;
          }
          if (error.kind == ArchiveFailureKind.resource) continue;
          rethrow;
        } on FileSystemException {
          // Only optional hit/admission I/O is best-effort. The shared writer
          // and mandatory output validation below retain transactional errors.
          continue;
        }
        addOutput(item);
      }
      if (outputs.isNotEmpty) {
        await write(List.unmodifiable(outputs));
        request?.throwIfCancelled();
        // Validate every output before making even one new entry visible.
        for (final output in outputs) {
          final length = await output.file.length();
          if (length != output.item.expectedBytes ||
              length > output.maximumBytes) {
            throw const ArchiveOpenException(ArchiveFailureKind.corrupt);
          }
        }
        request?.throwIfCancelled();
        for (final output in outputs) {
          final target = targets[output.item.key]!;
          await output.file.rename(target.path);
          committed.add(target);
          request?.throwIfCancelled();
        }
        for (final output in outputs) {
          leases[output.item.key] = await _lease(
            targets[output.item.key]!,
            activePrivateRoot,
          );
        }
      }
      request?.throwIfCancelled();
      return leases;
    } catch (_) {
      // Public lease release reacquires this lock. Roll back directly instead.
      for (final lease in leases.values) {
        await _releaseLease(lease.file, activePrivateRoot);
      }
      for (final target in committed) {
        if (await target.exists()) await _evict(target);
      }
      rethrow;
    } finally {
      for (final output in outputs) {
        if (await output.file.exists()) await output.file.delete();
      }
    }
  });

  Future<ArchiveFileLease> _lease(
    File target,
    Directory? activePrivateRoot,
  ) async {
    await target.setLastModified(DateTime.now());
    _references.update(target.path, (count) => count + 1, ifAbsent: () => 1);
    RandomAccessFile? lock = _leaseLocks[target.path];
    try {
      if (lock == null) {
        lock = await File('${target.path}.lease').open(mode: FileMode.append);
        await lock.lock(FileLock.shared);
        _leaseLocks[target.path] = lock;
      }
    } catch (_) {
      await lock?.close();
      _references.update(target.path, (count) => count - 1);
      rethrow;
    }
    return ArchiveFileLease(
      target,
      () => _exclusive(() => _releaseLease(target, activePrivateRoot)),
    );
  }

  Future<void> _releaseLease(File target, Directory? activePrivateRoot) async {
    final remaining = _references.update(target.path, (count) => count - 1);
    // POSIX locks can be process-scoped: closing one of several handles can
    // drop all locks for that marker. Keep exactly one shared handle here.
    if (remaining == 0) {
      await _leaseLocks.remove(target.path)?.close();
      if (await File('${target.path}.discard').exists() ||
          (!policy.persistent && activePrivateRoot == null) ||
          DateTime.now().difference((await target.stat()).modified) >
              policy.maxAge) {
        await _evict(target);
      }
      if (_reclaimAfterRelease) {
        try {
          await _makeRoom(0, additionalFiles: 0);
          _reclaimAfterRelease = false;
        } on ArchiveOpenException {
          // Other live leases may still exceed the newly lowered budget.
        }
      }
    }
    if (activePrivateRoot != null &&
        (_references[target.path] ?? 0) == 0 &&
        !await activePrivateRoot.exists()) {
      _references.remove(target.path);
    }
  }
}
