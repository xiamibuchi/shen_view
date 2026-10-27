import 'dart:async';
import 'dart:io';

/// Serializes callers in this isolate and across OS processes. Keep the lock
/// file stable: replacing/deleting it would allow two independent lock owners.
class ProcessFileLock {
  static final _queues = <String, Future<void>>{};

  static Future<T> run<T>(String path, Future<T> Function() action) {
    final key = File(path).absolute.path;
    final previous = _queues[key] ?? Future<void>.value();
    final operation = previous.then((_) => _run(key, action));
    final tail = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    _queues[key] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_queues[key], tail)) _queues.remove(key);
      }),
    );
    return operation;
  }

  static Future<T> _run<T>(String path, Future<T> Function() action) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final handle = await file.open(mode: FileMode.append);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    try {
      while (true) {
        try {
          await handle.lock(FileLock.exclusive);
          break;
        } on FileSystemException {
          if (DateTime.now().isAfter(deadline)) rethrow;
          // Nonblocking acquisition avoids exhausting Dart's I/O thread pool
          // while the lock holder is itself waiting for disk I/O.
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
      return await action();
    } finally {
      await handle.close();
    }
  }
}
