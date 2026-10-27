import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as paths;

import 'development_codec_paths.dart';

import '../domain/archive_failure.dart';
import 'archive_contract.dart';
import 'archive_disk_cache.dart';
import 'decode_request.dart';
export 'archive_disk_cache.dart';

class ArchiveEntry {
  const ArchiveEntry({
    required this.index,
    required this.name,
    required this.originalName,
    required this.size,
    required this.isDirectory,
    required this.encrypted,
    this.modified,
    this.crc,
    this.block,
  });
  final int index;

  /// Normalized virtual path. Never used as an extraction destination.
  final String name;
  final String originalName;
  final int size;
  final bool isDirectory;
  final bool encrypted;
  final DateTime? modified;
  final int? crc;
  final int? block;
  bool get isArchive =>
      !isDirectory &&
      const {
        '.zip',
        '.cbz',
        '.rar',
        '.cbr',
        '.7z',
        '.cb7',
        '.tar',
        '.cbt',
      }.contains(paths.posix.extension(name).toLowerCase());
  bool get isImage =>
      !isDirectory &&
      const {
        '.jpg',
        '.jpeg',
        '.jpe',
        '.png',
        '.gif',
        '.webp',
        '.bmp',
        '.ico',
        '.tif',
        '.tiff',
        '.apng',
        '.heic',
        '.heif',
        '.avif',
        '.avis',
        '.jxl',
        '.psd',
        '.dng',
        '.cr2',
        '.cr3',
        '.nef',
        '.arw',
        '.orf',
        '.rw2',
        '.raf',
        '.pef',
        '.srw',
        '.raw',
        '.exr',
        '.hdr',
        '.pic',
        '.dds',
        '.svg',
        '.hif',
        '.hevc',
        '.h265',
      }.contains(paths.posix.extension(name).toLowerCase());
}

class ArchiveSession {
  ArchiveSession._(
    this.source,
    this.limits,
    this._cache,
    this._helperExecutable,
    this._password,
    this.parent,
    this._parentLease,
  );
  final File source;
  final ArchiveLimits limits;
  final ArchiveDiskCache _cache;
  final String? _helperExecutable;
  String? _password;
  final ArchiveSession? parent;
  final ArchiveFileLease? _parentLease;
  late final String identity;
  late final List<ArchiveEntry> entries;
  late final bool encrypted;
  late final bool solid;
  late final String format;
  late String _version;
  int get depth => (parent?.depth ?? -1) + 1;
  Directory? _privateRoot;
  RandomAccessFile? _privateLock;
  _ArchiveHelper? _helper;
  bool _closed = false;
  int _leases = 0;
  Future<void>? _closing;
  Future<void>? _privateCleanup;
  final _pending = <int, _SharedEntry>{};
  final _solidQueue = <(ArchiveEntry, _SharedEntry)>[];
  Map<int, List<ArchiveEntry>>? _blockImages;
  Timer? _batchTimer;
  Future<void>? _draining;
  int _extractionPasses = 0;
  int _reportedWorkBytes = 0;

  /// Native extraction invocations, excluding directory reads and disk hits.
  int get extractionPasses => _extractionPasses;

  /// Cumulative SDK completed-byte reports for successful extraction commands.
  /// This is backend work telemetry, not decoded-image or process memory usage.
  int get reportedWorkBytes => _reportedWorkBytes;

  static Future<ArchiveSession> open(
    File source, {
    required ArchiveLimits limits,
    required ArchiveCachePolicy cachePolicy,
    String? helperExecutable,
    DecodeRequest? request,
    String? password,
    bool sensitive = false,
    ArchiveSession? parent,
    ArchiveFileLease? parentLease,
  }) async {
    request?.throwIfCancelled();
    if ((parent?.depth ?? -1) + 1 > limits.maxDepth) {
      throw const ArchiveOpenException(ArchiveFailureKind.limit);
    }
    final session = ArchiveSession._(
      source,
      limits,
      ArchiveDiskCache.forPolicy(cachePolicy),
      helperExecutable,
      password ?? parent?._password,
      parent,
      parentLease,
    );
    try {
      session._version = await _sourceVersion(
        source,
        includeModified: parent == null,
      );
      final listing = await session._openHelper(request);
      final list = <ArchiveEntry>[];
      var names = 0;
      for (final data in listing.$1) {
        final rawName = data['name'] as String;
        final name = rawName.replaceAll('\\', '/');
        names += utf8.encode(rawName).length;
        if (list.length >= limits.maxFiles ||
            names > limits.maxNameBytes ||
            name.length > 32768) {
          throw const ArchiveOpenException(ArchiveFailureKind.limit);
        }
        if (!_safePath(name) || data['link'] == true) {
          throw const ArchiveOpenException(ArchiveFailureKind.unsafePath);
        }
        final size = data['size'] as int? ?? 0;
        if (size < 0) {
          throw const ArchiveOpenException(ArchiveFailureKind.corrupt);
        }
        final modified = data['modified'] as int?;
        list.add(
          ArchiveEntry(
            index: data['index'] as int,
            name: paths.posix.normalize(name),
            originalName: rawName,
            size: size,
            isDirectory: data['directory'] == true,
            encrypted: data['encrypted'] == true,
            modified: modified == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(modified),
            crc: data['crc'] as int?,
            block: data['block'] as int?,
          ),
        );
      }
      session.entries = List.unmodifiable(list);
      session.encrypted =
          sensitive ||
          (parent?.encrypted ?? false) ||
          listing.$2['encrypted'] == true ||
          list.any((entry) => entry.encrypted);
      session.solid = listing.$2['solid'] == true;
      session.format = listing.$2['format'] as String? ?? '';
      if (list.any((entry) => entry.encrypted) && session._password == null) {
        throw const ArchiveOpenException(ArchiveFailureKind.encrypted);
      }
      final fingerprint = list
          .map(
            (entry) =>
                '${entry.index}:${entry.originalName}:${entry.size}:${entry.crc}:${entry.modified?.millisecondsSinceEpoch}:${entry.block}',
          )
          .join('|');
      session.identity = archiveDigest(
        '${parent?.identity ?? ''}|${parent == null ? source.absolute.path : paths.basename(source.path)}|${session._version}|$fingerprint',
      );
      await session._verifySource();
      // Reserve an empty session directory so a live persistence setting change
      // can select private storage atomically at cache admission.
      final private = await session._cache.privateDirectory();
      session._privateRoot = private.$1;
      session._privateLock = private.$2;
      request?.throwIfCancelled();
      return session;
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  Future<(List<Map<String, Object?>>, Map<String, Object?>)> _openHelper(
    DecodeRequest? request,
  ) async {
    final helper = await _ArchiveHelper.start(
      _helperExecutable,
      limits.timeout,
    );
    if (_closed) {
      await helper.close();
      throw DecodeCancelled();
    }
    _helper = helper;
    final entries = <Map<String, Object?>>[];
    try {
      final result = await helper.command(
        'open\t${_hex(source.absolute.path)}\t${_password == null ? '-' : _hex(_password!)}\t${limits.maxFiles}\t${limits.maxNameBytes}',
        request: request,
        onEvent: (event) {
          if (event['event'] == 'entry') entries.add(event);
        },
      );
      return (entries, result);
    } catch (_) {
      await helper.close();
      _helper = null;
      rethrow;
    }
  }

  Future<void>? _helperOpening;

  Future<void> _ensureHelper(DecodeRequest request) async {
    request.throwIfCancelled();
    if (_closed) throw DecodeCancelled();
    if (_helper != null && !_helper!.closed) return;
    // Reopening belongs to the session, not to one speculative consumer.
    final pending = _helperOpening ??= _openHelper(null).then<void>((_) {});
    try {
      await pending;
    } finally {
      if (identical(_helperOpening, pending)) _helperOpening = null;
    }
    request.throwIfCancelled();
    if (_closed) throw DecodeCancelled();
  }

  Future<Map<String, Object?>> _readCommand(
    String command, {
    required DecodeRequest request,
    void Function(Map<String, Object?>)? onEvent,
  }) async {
    for (var attempt = 0; ; attempt++) {
      await _ensureHelper(request);
      try {
        final readResult = await _helper!.command(
          command,
          request: request,
          onEvent: onEvent,
        );
        return readResult;
      } on DecodeCancelled {
        // Cancelling a different entry may kill the shared helper. A queued
        // foreground consumer is still valid and gets one fresh read attempt.
        if (request.cancelled || _closed || attempt >= 1) rethrow;
      }
    }
  }

  Future<void> _verifySource() async {
    if (await _sourceVersion(source, includeModified: parent == null) !=
        _version) {
      throw const ArchiveOpenException(ArchiveFailureKind.sourceChanged);
    }
    if (parent != null) await parent!._verifySource();
  }

  Future<ArchiveFileLease> acquireFile(
    ArchiveEntry entry, {
    DecodeRequest? request,
    void Function(int completed, int? total)? onProgress,
    bool speculative = false,
  }) async {
    request?.throwIfCancelled();
    if (_closed) throw const ArchiveOpenException(ArchiveFailureKind.io);
    if (entry.isDirectory ||
        !entries.any((candidate) => identical(candidate, entry))) {
      throw const ArchiveOpenException(ArchiveFailureKind.unsafePath);
    }
    final maximum = entry.isArchive
        ? _cache.policy.maxBytes
        : limits.maxFileBytes;
    if (entry.size > maximum) {
      throw const ArchiveOpenException(ArchiveFailureKind.limit);
    }
    await _verifySource();
    request?.throwIfCancelled();
    if (_closed) throw DecodeCancelled();
    final state = _pending.putIfAbsent(entry.index, () => _SharedEntry());
    state.users++;
    _leases++;
    state.future ??= solid
        ? _queueSolidRead(entry, state)
        : _cache.acquire(
            key: _entryKey(entry),
            extension: paths.posix.extension(entry.name),
            expectedBytes: entry.size,
            maximumBytes: maximum,
            request: state.request,
            privateRoot: _privateRoot,
            sensitive: encrypted,
            write: (output, maximumBytes) async {
              if (_closed) throw DecodeCancelled();
              _extractionPasses++;
              final result = await _readCommand(
                'read\t${entry.index}\t${_hex(output.path)}\t$maximumBytes\t${limits.maxTotalBytes}',
                request: state.request,
                onEvent: (data) {
                  if (data['event'] == 'progress') {
                    for (final listener in state.progress.toList()) {
                      listener(
                        data['completed'] as int? ?? 0,
                        solid ? null : entry.size,
                      );
                    }
                  }
                },
              );
              _reportedWorkBytes += result['workBytes'] as int? ?? 0;
              await _verifySource();
            },
          );
    if (onProgress != null) state.progress.add(onProgress);
    var released = false;
    Future<void> release() async {
      if (released) return;
      released = true;
      if (onProgress != null) state.progress.remove(onProgress);
      state.users--;
      _leases--;
      if (state.users == 0) {
        _pending.remove(entry.index);
        state.request.cancel();
        try {
          await (await state.future!).release();
        } catch (_) {
          /* Failed materialization has no file lease. */
        }
      }
      if (_closed && _leases == 0 && _draining == null) {
        await _cleanupPrivate();
      }
    }

    final cancelled = Completer<ArchiveFileLease>();
    void cancel() {
      if (!cancelled.isCompleted) cancelled.completeError(DecodeCancelled());
    }

    request?.addCancelListener(cancel);
    try {
      final lease = await Future.any([state.future!, cancelled.future]);
      request?.throwIfCancelled();
      return ArchiveFileLease(lease.file, release);
    } catch (_) {
      await release();
      rethrow;
    } finally {
      request?.removeCancelListener(cancel);
    }
  }

  String _entryKey(ArchiveEntry entry) => archiveDigest(
    '$identity:${entry.index}:${entry.originalName}:${entry.size}:${entry.crc}',
  );

  Future<ArchiveFileLease> _queueSolidRead(
    ArchiveEntry entry,
    _SharedEntry state,
  ) {
    final result = Completer<ArchiveFileLease>();
    state.result = result;
    _solidQueue.add((entry, state));
    if (_draining == null && _batchTimer == null) {
      // Coalesce independently completed file-version checks without holding a
      // foreground request behind a long debounce or a background decode.
      _batchTimer = Timer(const Duration(milliseconds: 2), () {
        _batchTimer = null;
        _startSolidDrain();
      });
    }
    return result.future;
  }

  void _startSolidDrain() {
    if (_draining != null) return;
    _draining = _drainSolidReads().whenComplete(() async {
      // Internal optional cache leases must be released before deleting the
      // private root, even if the last visible consumer has already left.
      try {
        if (_closed && _leases == 0) await _cleanupPrivate();
      } on FileSystemException {
        // Cleanup failure must not become an unhandled background error.
      } on ArchiveOpenException {
        // Startup maintenance retries orphan cleanup.
      } finally {
        _draining = null;
        if (_solidQueue.isNotEmpty) _startSolidDrain();
      }
    });
  }

  Future<void> _drainSolidReads() async {
    while (_solidQueue.isNotEmpty) {
      final batch = <(ArchiveEntry, _SharedEntry)>[];
      var bytes = 0;
      for (final queued in _solidQueue.toList()) {
        final (entry, state) = queued;
        if (_closed || state.request.cancelled) {
          _solidQueue.remove(queued);
          state.result!.completeError(DecodeCancelled());
          continue;
        }
        if (batch.isNotEmpty &&
            (batch.length == 16 ||
                bytes + entry.size > _cache.policy.maxBytes)) {
          break;
        }
        batch.add(queued);
        bytes += entry.size;
        _solidQueue.remove(queued);
      }
      if (batch.isEmpty) continue;
      await _readSolidBatch(batch);
    }
  }

  List<ArchiveEntry> _solidWindow(List<ArchiveEntry> targets) {
    final count = _cache.policy.solidCacheEntries.clamp(0, 3);
    if (count == 0) return const [];
    final blocks = _blockImages ??= {
      for (final entry in entries)
        if (entry.block != null && entry.isImage)
          entry.block!: <ArchiveEntry>[],
    };
    if (blocks.values.every((images) => images.isEmpty)) {
      for (final entry in entries) {
        if (entry.isImage) blocks[entry.block]?.add(entry);
      }
    }
    final selected = <int>{for (final entry in targets) entry.index};
    final result = <ArchiveEntry>[];
    var remaining = math.min(32 * 1024 * 1024, _cache.policy.maxBytes ~/ 8);
    for (final target in targets) {
      final images = blocks[target.block];
      if (images == null) continue;
      final position = images.indexWhere(
        (entry) => entry.index == target.index,
      );
      for (
        var distance = 1;
        distance <= count && position >= distance;
        distance++
      ) {
        if (selected.length == 16) return result;
        final candidate = images[position - distance];
        if (candidate.index >= target.index ||
            selected.contains(candidate.index) ||
            _pending.containsKey(candidate.index) ||
            candidate.size > limits.maxFileBytes ||
            candidate.size > remaining) {
          continue;
        }
        selected.add(candidate.index);
        result.add(candidate);
        remaining -= candidate.size;
      }
    }
    return result;
  }

  Future<void> _readSolidBatch(List<(ArchiveEntry, _SharedEntry)> batch) async {
    final request = DecodeRequest();
    void updateCancellation() {
      if (_closed || batch.every((item) => item.$2.request.cancelled)) {
        request.cancel();
      }
    }

    for (final (_, state) in batch) {
      state.request.addCancelListener(updateCancellation);
    }
    final targets = [for (final (entry, _) in batch) entry];
    final optional = _solidWindow(targets);
    final allEntries = {
      for (final entry in [...targets, ...optional]) _entryKey(entry): entry,
    };
    Map<String, ArchiveFileLease>? leases;
    try {
      leases = await _cache.acquireBatch(
        items: [
          for (final entry in [...targets, ...optional])
            ArchiveCacheItem(
              key: _entryKey(entry),
              extension: paths.posix.extension(entry.name),
              expectedBytes: entry.size,
              maximumBytes: entry.isArchive
                  ? _cache.policy.maxBytes
                  : limits.maxFileBytes,
              optional: !targets.contains(entry),
            ),
        ],
        request: request,
        privateRoot: _privateRoot,
        sensitive: encrypted,
        write: (outputs) async {
          request.throwIfCancelled();
          if (_closed) throw DecodeCancelled();
          final total = outputs.fold<int>(
            0,
            (sum, output) => sum + output.item.expectedBytes,
          );
          final command = StringBuffer(
            'readMany\t$total\t${limits.maxTotalBytes}',
          );
          for (final output in outputs) {
            command.write(
              '\t${allEntries[output.item.key]!.index}\t${_hex(output.file.path)}\t${output.maximumBytes}',
            );
          }
          _extractionPasses++;
          final result = await _readCommand(
            command.toString(),
            request: request,
            onEvent: (data) {
              if (data['event'] != 'progress') return;
              for (final (_, state) in batch) {
                for (final listener in state.progress.toList()) {
                  listener(data['completed'] as int? ?? 0, null);
                }
              }
            },
          );
          _reportedWorkBytes += result['workBytes'] as int? ?? 0;
          await _verifySource();
        },
      );
      for (final (entry, state) in batch) {
        final lease = leases.remove(_entryKey(entry));
        if (state.request.cancelled) {
          state.result!.completeError(DecodeCancelled());
          await _releaseCacheLease(lease);
        } else if (lease == null) {
          state.result!.completeError(
            const ArchiveOpenException(ArchiveFailureKind.corrupt),
          );
        } else {
          state.result!.complete(lease);
        }
      }
    } catch (error, stack) {
      for (final (_, state) in batch) {
        if (!state.result!.isCompleted) {
          state.result!.completeError(error, stack);
        }
      }
    } finally {
      for (final (_, state) in batch) {
        state.request.removeCancelListener(updateCancellation);
      }
      if (leases != null) {
        for (final lease in leases.values) {
          await _releaseCacheLease(lease);
        }
      }
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    _batchTimer?.cancel();
    _batchTimer = null;
    for (final state in _pending.values.toList()) {
      state.request.cancel();
    }
    await _helper?.close();
    _helper = null;
    if (_solidQueue.isNotEmpty) _startSolidDrain();
    await _draining;
    _password = null;
    if (_leases == 0) await _cleanupPrivate();
  }

  Future<void> _cleanupPrivate() => _privateCleanup ??= _deletePrivate();

  Future<void> _releaseCacheLease(ArchiveFileLease? lease) async {
    try {
      await lease?.release();
    } on FileSystemException {
      // A canceled or optional lease must not invalidate another visible page.
    } on ArchiveOpenException {
      // Startup maintenance retries pending reclamation.
    }
  }

  Future<void> _deletePrivate() async {
    try {
      await _privateLock?.close();
    } on FileSystemException {
      // Continue directory and parent cleanup; process exit also drops the lock.
    }
    _privateLock = null;
    final directory = _privateRoot;
    _privateRoot = null;
    if (directory != null) {
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        /* Startup sweeps crash and delayed-lock remnants. */
      }
    }
    await _releaseCacheLease(_parentLease);
  }
}

class _SharedEntry {
  Future<ArchiveFileLease>? future;
  Completer<ArchiveFileLease>? result;
  int users = 0;
  final request = DecodeRequest();
  final progress = <void Function(int, int?)>{};
}

bool _safePath(String value) =>
    value.isNotEmpty &&
    !value.startsWith('/') &&
    !value.contains(':') &&
    !value.contains('\u0000') &&
    !value.split('/').contains('..');
String _hex(String value) => utf8
    .encode(value)
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

/// Two independent 32-bit streams avoid platform-dependent int overflow.
String archiveDigest(String value) {
  var a = 0x811c9dc5;
  var b = 0x9e3779b9;
  for (final byte in utf8.encode(value)) {
    a = ((a ^ byte) * 0x01000193) & 0xffffffff;
    b = ((b ^ byte) * 0x85ebca6b) & 0xffffffff;
  }
  return '${a.toRadixString(16).padLeft(8, '0')}${b.toRadixString(16).padLeft(8, '0')}';
}

Future<String> _sourceVersion(File file, {bool includeModified = true}) async {
  try {
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw const ArchiveOpenException(ArchiveFailureKind.sourceChanged);
    }
    final input = await file.open();
    try {
      final head = await input.read(65536);
      await input.setPosition(stat.size > 65536 ? stat.size - 65536 : 0);
      final tail = await input.read(65536);
      return '${stat.size}:${includeModified ? stat.modified.microsecondsSinceEpoch : 0}:${archiveDigest(base64Encode([...head, ...tail]))}';
    } finally {
      await input.close();
    }
  } on FileSystemException catch (error) {
    throw ArchiveOpenException(ArchiveFailureKind.sourceChanged, error);
  }
}

class _ArchiveHelper {
  _ArchiveHelper(this.process, this.timeout) {
    _subscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _event,
          onError: (Object error) =>
              _fail(ArchiveOpenException(ArchiveFailureKind.io, error)),
          onDone: () {
            closed = true;
            _fail(
              _terminalError ??
                  const ArchiveOpenException(ArchiveFailureKind.io),
            );
          },
        );
    process.stderr.drain<void>();
  }
  final Process process;
  final Duration timeout;
  late final StreamSubscription<String> _subscription;
  Completer<Map<String, Object?>>? _response;
  void Function(Map<String, Object?>)? _onEvent;
  Future<void> _tail = Future<void>.value();
  bool closed = false;
  Object? _terminalError;
  static Future<_ArchiveHelper> start(
    String? executable,
    Duration timeout,
  ) async {
    final filename = Platform.isWindows
        ? 'viewer_archive.exe'
        : 'viewer_archive';
    final candidates = [
      ?executable,
      if (Platform.isWindows)
        paths.join(
          paths.dirname(Platform.resolvedExecutable),
          'codecs',
          'archive',
          filename,
        ),
      paths.join(
        paths.dirname(Platform.resolvedExecutable),
        'codecs',
        filename,
      ),
      paths.join(paths.dirname(Platform.resolvedExecutable), filename),
      ...developmentCodecCandidates('archive-helper/bin/$filename'),
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) {
        try {
          return _ArchiveHelper(
            await Process.start(candidate, const []),
            timeout,
          );
        } on ProcessException catch (error) {
          throw ArchiveOpenException(ArchiveFailureKind.missingTool, error);
        }
      }
    }
    throw const ArchiveOpenException(ArchiveFailureKind.missingTool);
  }

  void _fail(Object error) {
    _terminalError ??= error;
    if (_response?.isCompleted == false) _response!.completeError(error);
  }

  void _event(String line) {
    try {
      final event = Map<String, Object?>.from(jsonDecode(line) as Map);
      if (event['event'] == 'error') {
        final kind =
            ArchiveFailureKind.values
                .where((kind) => kind.name == event['kind'])
                .firstOrNull ??
            ArchiveFailureKind.corrupt;
        _fail(ArchiveOpenException(kind));
      } else if (event['event'] == 'done') {
        if (_response?.isCompleted == false) _response!.complete(event);
      } else {
        _onEvent?.call(event);
      }
    } catch (error) {
      _fail(ArchiveOpenException(ArchiveFailureKind.corrupt, error));
    }
  }

  Future<Map<String, Object?>> command(
    String command, {
    DecodeRequest? request,
    void Function(Map<String, Object?>)? onEvent,
  }) {
    final result = Completer<Map<String, Object?>>();
    _tail = _tail.then((_) async {
      void cancel() {
        process.kill();
        closed = true;
        _fail(DecodeCancelled());
      }

      try {
        request?.throwIfCancelled();
        if (closed) {
          throw _terminalError ??
              const ArchiveOpenException(ArchiveFailureKind.io);
        }
        final response = _response = Completer<Map<String, Object?>>();
        // Cancellation can happen while stdin.flush is pending. Attach an
        // error handler now, before the response is awaited below.
        unawaited(
          response.future.then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {},
          ),
        );
        _onEvent = onEvent;
        request?.addCancelListener(cancel);
        process.stdin.writeln(command);
        await process.stdin.flush();
        result.complete(
          await response.future.timeout(
            timeout,
            onTimeout: () {
              process.kill();
              closed = true;
              throw const ArchiveOpenException(ArchiveFailureKind.timeout);
            },
          ),
        );
      } catch (error, stack) {
        result.completeError(error, stack);
      } finally {
        request?.removeCancelListener(cancel);
        _response = null;
        _onEvent = null;
      }
    });
    return result.future;
  }

  Future<void> close() async {
    closed = true;
    process.kill();
    _fail(DecodeCancelled());
    // A pending flush owns the sink until the command unwinds after process
    // termination; closing it earlier can throw synchronously.
    await _tail;
    try {
      await process.stdin.close();
    } catch (_) {
      // Terminated helper pipes need no further cleanup.
    }
    await _subscription.cancel();
    await process.exitCode;
  }
}
