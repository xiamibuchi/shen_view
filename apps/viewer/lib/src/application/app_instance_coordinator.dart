import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as path_util;

import 'app_config_store.dart';
import 'process_file_lock.dart';

/// Paths are absolute at the sender, never interpreted relative to the receiver.
class AppLaunchRequest {
  const AppLaunchRequest({this.paths = const []});

  factory AppLaunchRequest.fromArguments(List<String> arguments) {
    var optionsEnded = false;
    final files = <String>[];
    for (final argument in arguments) {
      if (!optionsEnded && argument == '--') {
        optionsEnded = true;
      } else if (optionsEnded || !argument.startsWith('-')) {
        files.add(path_util.normalize(path_util.absolute(argument)));
      }
    }
    return AppLaunchRequest(paths: List.unmodifiable(files));
  }

  final List<String> paths;
}

/// Every viewer publishes a local endpoint. Single-process launches choose the
/// most recently active viewer, including viewers created in multi-process mode.
/// The startup lock covers election, forwarding and registration, so simultaneous
/// cold starts cannot both become the single viewer. No permanent broker needed.
class AppInstanceCoordinator {
  AppInstanceCoordinator._(
    this._server,
    this._record,
    this._token,
    this._lease,
  );

  final ServerSocket _server;
  final File _record;
  final String _token;
  final RandomAccessFile _lease;
  static final _liveRecords = <String>{};
  final _pending = <AppLaunchRequest>[];
  void Function(AppLaunchRequest)? _handler;
  bool _closed = false;

  static const _maxMessageBytes = 128 * 1024;
  static const _protocol = 1;

  /// Null means the existing viewer acknowledged and queued this launch.
  static Future<AppInstanceCoordinator?> start({
    required AppConfigStore config,
    required AppLaunchRequest request,
    Future<void> Function(int processId)? allowActivation,
  }) async {
    final root = Directory('${config.filePath}.instances');
    return ProcessFileLock.run(
      path_util.join(root.path, 'startup.lock'),
      () async {
        final saved = await config.readOrEmpty();
        final settings = saved['settings'];
        final multi =
            settings is Map && settings['instanceMode'] == 'multiProcess';
        if (!multi) {
          final records = <File>[];
          await for (final entity in root.list(followLinks: false)) {
            if (entity is File && entity.path.endsWith('.json')) {
              records.add(entity);
            }
          }
          final modified = <String, DateTime>{};
          for (final record in records) {
            if (!await _isAlive(record)) {
              if (await record.exists()) await record.delete();
              final marker = File('${record.path}.active');
              if (await marker.exists()) await marker.delete();
              continue;
            }
            modified[record.path] = await record.lastModified();
          }
          records.removeWhere((record) => !modified.containsKey(record.path));
          records.sort(
            (a, b) => modified[b.path]!.compareTo(modified[a.path]!),
          );
          for (final record in records) {
            final decoded = jsonDecode(await record.readAsString());
            if (decoded is! Map ||
                decoded['protocol'] != _protocol ||
                decoded['port'] is! int ||
                decoded['token'] is! String ||
                decoded['pid'] is! int) {
              throw const FormatException('Invalid live instance endpoint');
            }
            final endpoint = Map<String, dynamic>.from(decoded);
            // A held lifetime lock means a live viewer. Connection failure or a
            // protocol mismatch must not unregister it and create a duplicate.
            await allowActivation?.call(endpoint['pid'] as int);
            await _forward(endpoint, request);
            return null;
          }
        }
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final random = Random.secure();
        final token = List.generate(
          32,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        final record = File(path_util.join(root.path, '$pid-$token.json'));
        RandomAccessFile lease;
        try {
          lease = await File('${record.path}.active')
              .open(mode: FileMode.append);
          try {
            await lease.lock(FileLock.exclusive);
          } catch (_) {
            await lease.close();
            rethrow;
          }
        } catch (_) {
          await server.close();
          rethrow;
        }
        final coordinator = AppInstanceCoordinator._(
          server,
          record,
          token,
          lease,
        );
        _liveRecords.add(record.path);
        server.listen((socket) => unawaited(coordinator._receive(socket)));
        try {
          await record.writeAsString(
            jsonEncode({
              'protocol': _protocol,
              'port': server.port,
              'pid': pid,
              'token': token,
            }),
            flush: true,
          );
        } catch (_) {
          await coordinator._closeUnlocked();
          rethrow;
        }
        return coordinator;
      },
    );
  }

  static Future<bool> _isAlive(File record) async {
    // POSIX locks are process-scoped. Do not probe our own live lock using
    // another handle (closing it could release the original lock).
    if (_liveRecords.contains(record.path)) return true;
    final marker = await File('${record.path}.active')
        .open(mode: FileMode.append);
    try {
      await marker.lock(FileLock.exclusive);
      return false;
    } on FileSystemException {
      return true;
    } finally {
      await marker.close();
    }
  }

  static Future<String> _readLine(Socket socket) {
    final result = Completer<String>();
    final bytes = <int>[];
    socket.listen(
      (chunk) {
        if (result.isCompleted) return;
        final newline = chunk.indexOf(10);
        bytes.addAll(newline < 0 ? chunk : chunk.take(newline));
        if (bytes.length > _maxMessageBytes) {
          result.completeError(
            const FormatException('Instance request too large'),
          );
        } else if (newline >= 0) {
          try {
            result.complete(utf8.decode(bytes));
          } catch (error, stack) {
            result.completeError(error, stack);
          }
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
      onDone: () {
        if (!result.isCompleted) {
          result.completeError(
            const FormatException('Incomplete instance request'),
          );
        }
      },
    );
    return result.future.timeout(const Duration(seconds: 3));
  }

  static Future<void> _forward(
    Map<String, dynamic> endpoint,
    AppLaunchRequest request,
  ) async {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      endpoint['port'] as int,
      timeout: const Duration(seconds: 2),
    );
    try {
      final message = jsonEncode({
        'protocol': _protocol,
        'token': endpoint['token'],
        'paths': request.paths,
      });
      if (utf8.encode(message).length > _maxMessageBytes - 1) {
        throw const FormatException('Instance request too large');
      }
      socket.writeln(message);
      await socket.flush();
      if (await _readLine(socket) != 'accepted') {
        throw StateError('Instance rejected launch request');
      }
    } finally {
      socket.destroy();
    }
  }

  Future<void> _receive(Socket socket) async {
    try {
      final decoded = jsonDecode(await _readLine(socket));
      if (_closed ||
          decoded is! Map ||
          decoded['protocol'] != _protocol ||
          decoded['token'] != _token ||
          decoded['paths'] is! List) {
        return;
      }
      final raw = decoded['paths'] as List;
      if (_pending.length >= 256 ||
          raw.length > 256 ||
          raw.any((path) => path is! String || !path_util.isAbsolute(path))) {
        return;
      }
      final request = AppLaunchRequest(paths: List<String>.from(raw));
      _pending.add(request);
      socket.writeln('accepted');
      await socket.flush();
      _drain();
    } catch (_) {
      // Invalid/local stale clients cannot terminate the viewer.
    } finally {
      socket.destroy();
    }
  }

  /// Attach only after the initial content and Flutter navigation are ready.
  void attach(void Function(AppLaunchRequest) handler) {
    _handler = handler;
    _drain();
  }

  void detach() => _handler = null;

  void _drain() {
    final handler = _handler;
    if (handler == null) return;
    final requests = List<AppLaunchRequest>.of(_pending);
    _pending.clear();
    for (final request in requests) {
      handler(request);
    }
  }

  Future<void> markActive() async {
    if (_closed) return;
    try {
      await _record.setLastModified(DateTime.now());
    } on FileSystemException {
      /* Exiting. */
    }
  }

  Future<void> close() => ProcessFileLock.run(
    path_util.join(_record.parent.path, 'startup.lock'),
    _closeUnlocked,
  );

  Future<void> _closeUnlocked() async {
    if (_closed) return;
    _closed = true;
    detach();
    await _server.close();
    try {
      if (await _record.exists()) await _record.delete();
    } on FileSystemException {
      /* Reaped on next launch. */
    }
    await _lease.close();
    _liveRecords.remove(_record.path);
    try {
      await File('${_record.path}.active').delete();
    } on FileSystemException {
      /* Reaped later. */
    }
  }
}
