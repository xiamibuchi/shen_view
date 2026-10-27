import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as paths;

import 'process_file_lock.dart';
import 'windows_distribution.dart';

class AppConfigStore {
  AppConfigStore({String? filePath})
    : filePath = filePath ?? _defaultFilePath();

  static const fileName = 'settings.json';
  static const maxFileBytes = 16 * 1024 * 1024;
  static const maxNestingDepth = 64;
  static const readTimeout = Duration(seconds: 2);

  final String filePath;
  final _pendingReads = <Completer<Map<String, dynamic>>, Timer>{};

  // Readers see a complete old or new snapshot because writers replace the
  // committed file atomically. Only read-modify-write transactions need a lock.
  Future<Map<String, dynamic>> read() => _readUnlocked();

  /// Optional saved state must never prevent the viewer from opening. Writes
  /// still use the strict reader, so a permissions failure cannot erase data.
  Future<Map<String, dynamic>> readOrEmpty() {
    final result = Completer<Map<String, dynamic>>();
    void complete(Map<String, dynamic> value) {
      _pendingReads.remove(result)?.cancel();
      if (!result.isCompleted) result.complete(value);
    }

    void fallback(Object error, StackTrace stack) {
      developer.log(
        'Unable to read settings; using defaults.',
        name: 'ShenView.config',
        error: error,
        stackTrace: stack,
      );
      complete(<String, dynamic>{});
    }

    _pendingReads[result] = Timer(readTimeout, () {
      fallback(TimeoutException('Settings read timed out'), StackTrace.current);
    });
    unawaited(Future.sync(read).then<void>(complete, onError: fallback));
    return result.future;
  }

  /// Disposing a window cancels its optional reads, without cancelling strict
  /// persistence transactions or preventing another window from using the store.
  void cancelPendingReads() {
    final pending = _pendingReads.entries.toList();
    _pendingReads.clear();
    for (final entry in pending) {
      entry.value.cancel();
      if (!entry.key.isCompleted) entry.key.complete(<String, dynamic>{});
    }
  }

  Future<Map<String, dynamic>> _readUnlocked() async {
    final file = File(filePath);
    final waiting = Stopwatch()..start();
    while (true) {
      try {
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in file.openRead(0, maxFileBytes + 1)) {
          bytes.add(chunk);
          if (bytes.length > maxFileBytes) {
            throw FileSystemException(
              'Settings file exceeds size limit',
              filePath,
            );
          }
        }
        final text = utf8.decode(bytes.takeBytes());
        _checkNesting(text);
        final decoded = jsonDecode(text);
        if (decoded is! Map) return <String, dynamic>{};
        return Map<String, dynamic>.from(decoded);
      } on FormatException {
        return <String, dynamic>{};
      } on FileSystemException catch (error) {
        if (_retryWindowsSharing(error, waiting)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          continue;
        }
        // An unreadable existing config is not an empty config. Propagating
        // the error prevents update() from replacing user data with defaults.
        final code = error.osError?.errorCode;
        if (code == 2 || (Platform.isWindows && code == 3)) {
          return <String, dynamic>{};
        }
        rethrow;
      }
    }
  }

  static void _checkNesting(String text) {
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (final unit in text.codeUnits) {
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (unit == 92) {
          escaped = true;
        } else if (unit == 34) {
          quoted = false;
        }
      } else if (unit == 34) {
        quoted = true;
      } else if (unit == 123 || unit == 91) {
        if (++depth > maxNestingDepth) {
          throw const FormatException('Settings nesting exceeds limit');
        }
      } else if (unit == 125 || unit == 93) {
        depth--;
      }
    }
  }

  Future<void> write(Map<String, dynamic> config) {
    return ProcessFileLock.run('$filePath.lock', () => _writeNow(config));
  }

  Future<void> update(
    Map<String, dynamic> Function(Map<String, dynamic> config) transform,
  ) {
    return ProcessFileLock.run('$filePath.lock', () async {
      final config = await _readUnlocked();
      await _writeNow(transform(config));
    });
  }

  Future<void> _writeNow(Map<String, dynamic> config) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    final temporary = File(
      '$filePath.tmp-$pid-${Random.secure().nextInt(1 << 32)}',
    );
    try {
      await temporary.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config),
        flush: true,
      );
      // Dart replaces an existing file on rename. Never delete the committed
      // file first: a crash must leave the previous complete config intact.
      await _replaceCommittedFile(temporary);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _replaceCommittedFile(File temporary) async {
    final waiting = Stopwatch()..start();
    while (true) {
      try {
        await temporary.rename(filePath);
        return;
      } on FileSystemException catch (error) {
        // Windows readers may briefly hold a handle without FILE_SHARE_DELETE.
        // Retry only sharing/access conflicts, preserving the complete old file
        // and our transaction lock. A persistent failure still reaches callers.
        if (!_retryWindowsSharing(error, waiting)) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  }

  static bool _retryWindowsSharing(
    FileSystemException error,
    Stopwatch waiting,
  ) {
    final code = error.osError?.errorCode;
    return Platform.isWindows &&
        (code == 5 || code == 32 || code == 33) &&
        waiting.elapsed < const Duration(seconds: 1);
  }

  static String _defaultFilePath() => Platform.isMacOS
      ? paths.join(
          Platform.environment['HOME'] ?? Directory.systemTemp.path,
          'Library',
          'Application Support',
          'ShenView',
          fileName,
        )
      : paths.join(
          Platform.isWindows
              ? WindowsDistribution.currentDataDirectory()
              : paths.dirname(Platform.resolvedExecutable),
          fileName,
        );
}
