import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as paths;

/// A debounced batch of file system changes under the watched folder.
class FolderChangeBatch {
  const FolderChangeBatch({required this.paths, required this.overflowed});

  /// Normalized paths that changed since the previous batch.
  final Set<String> paths;

  /// True when more paths changed than the tracker keeps. Consumers must then
  /// treat the whole watched folder as changed instead of individual paths.
  final bool overflowed;
}

typedef FolderWatchStreamFactory = Stream<FileSystemEvent> Function(
  String path,
  bool recursive,
);

/// Returns true when a changed path can affect the indexed image list.
typedef FolderChangePathFilter = bool Function(String path);

/// Watches one folder and reports coalesced changes.
///
/// Large folders produce a lot of events while files are copied, so the
/// watcher never forwards every event:
/// - changes are collected for [debounce] after the last relevant event;
/// - a continuous stream of events still reaches the consumer every
///   [maxLatency], instead of waiting for the copy to finish;
/// - while paused (window unfocused) changes keep accumulating and are
///   delivered on the next [flushNow] or resume;
/// - [includePath] drops irrelevant files before they can extend the debounce;
/// - at most [_maxPendingPaths] paths are kept; beyond that the batch is
///   reported as [FolderChangeBatch.overflowed].
class FolderChangeWatcher {
  FolderChangeWatcher({
    this.debounce = defaultDebounce,
    this.maxLatency = defaultMaxLatency,
    this.includePath,
    FolderWatchStreamFactory? streamFactory,
  }) : _streamFactory = streamFactory ?? _platformWatch;

  static const defaultDebounce = Duration(seconds: 2);
  static const defaultMaxLatency = Duration(seconds: 10);
  static const _maxPendingPaths = 512;

  final Duration debounce;
  final Duration maxLatency;
  final FolderWatchStreamFactory _streamFactory;

  /// Drops paths that cannot affect the indexed list.
  FolderChangePathFilter? includePath;

  /// Called with every debounced batch. Errors from the watch stream are
  /// reported through [onError] and stop the subscription.
  void Function(FolderChangeBatch batch)? onChanged;
  void Function(Object error, StackTrace? stackTrace)? onError;

  StreamSubscription<FileSystemEvent>? _subscription;
  String? _path;
  bool _recursive = false;
  bool _paused = false;
  bool _disposed = false;
  int _epoch = 0;
  Set<String> _pending = <String>{};
  bool _overflowed = false;
  Stopwatch? _pendingSince;
  Timer? _debounceTimer;

  bool get isActive => _subscription != null;

  bool get isRecursive => _recursive;

  bool get hasPendingChanges => _pending.isNotEmpty;

  /// Starts watching [path]. Calling it again with the same target keeps the
  /// subscription and its pending changes, so refreshes never drop events.
  void watch(
    String path, {
    required bool recursive,
    FolderChangePathFilter? includePath,
  }) {
    if (_disposed) return;
    final normalized = paths.normalize(path);
    this.includePath = includePath ?? this.includePath;
    if (_subscription != null &&
        _recursive == recursive &&
        _samePath(_path, normalized)) {
      return;
    }
    _cancelSubscription(clearPending: true);
    _path = normalized;
    _recursive = recursive;
    final epoch = ++_epoch;
    try {
      _subscription = _streamFactory(normalized, recursive).listen(
        (event) => _handleEvent(epoch, event),
        onError: (Object error, StackTrace stackTrace) =>
            _handleError(epoch, error, stackTrace),
        onDone: () => _handleError(
          epoch,
          FileSystemException('Folder watch stream ended', normalized),
          null,
        ),
        cancelOnError: false,
      );
    } catch (error, stackTrace) {
      _path = null;
      onError?.call(error, stackTrace);
    }
  }

  /// Stops watching. Pending changes are dropped by default because they
  /// belong to a folder the consumer no longer shows.
  void stop({bool clearPending = true}) {
    _cancelSubscription(clearPending: clearPending);
    _path = null;
    _recursive = false;
  }

  /// Pauses or resumes delivery. The subscription stays open so changes made
  /// while the window is unfocused are still known when it returns.
  void setPaused(bool value) {
    if (_disposed || _paused == value) return;
    _paused = value;
    if (_paused) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      return;
    }
    if (_pending.isNotEmpty) _schedule();
  }

  /// Delivers pending changes immediately, ignoring [debounce].
  void flushNow() {
    if (_disposed || _paused) return;
    _flush();
  }

  void dispose() {
    _disposed = true;
    _cancelSubscription(clearPending: true);
    _path = null;
    _recursive = false;
    onChanged = null;
    onError = null;
  }

  void _handleEvent(int epoch, FileSystemEvent event) {
    if (_disposed || epoch != _epoch) return;
    _addPath(event.path, isDirectory: event.isDirectory);
    if (event is FileSystemMoveEvent && event.destination != null) {
      _addPath(event.destination!, isDirectory: event.isDirectory);
    }
  }

  void _addPath(String changedPath, {required bool isDirectory}) {
    final path = paths.normalize(changedPath);
    if (path.isEmpty || path == '.') return;
    final includePath = this.includePath;
    // Directory names may contain dots or look like ignored file extensions.
    if (!isDirectory && includePath != null && !includePath(path)) return;
    final wasEmpty = _pending.isEmpty;
    if (_pending.length >= _maxPendingPaths) {
      _pending = <String>{};
      _overflowed = true;
      final watched = _path;
      if (watched != null) _pending.add(watched);
    } else {
      _pending.add(path);
    }
    if (wasEmpty || _pendingSince == null) {
      _pendingSince = Stopwatch()..start();
    }
    _schedule();
  }

  void _handleError(int epoch, Object error, StackTrace? stackTrace) {
    if (_disposed || epoch != _epoch) return;
    // Deliver already observed changes before losing the subscription. If
    // paused, the consumer's focus fallback will reconcile the whole scope.
    if (!_paused) _flush();
    if (_disposed || epoch != _epoch) return;
    _cancelSubscription(clearPending: true);
    _path = null;
    _recursive = false;
    onError?.call(error, stackTrace);
  }

  void _schedule() {
    if (_disposed || _paused || _pending.isEmpty) return;
    _debounceTimer?.cancel();
    final elapsed = _pendingSince?.elapsed ?? Duration.zero;
    if (elapsed >= maxLatency) {
      _debounceTimer = null;
      _flush();
      return;
    }
    final remaining = maxLatency - elapsed;
    _debounceTimer = Timer(remaining < debounce ? remaining : debounce, _flush);
  }

  void _flush() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_disposed || _paused || _pending.isEmpty) return;
    final batch = FolderChangeBatch(
      paths: Set<String>.unmodifiable(_pending),
      overflowed: _overflowed,
    );
    _pending = <String>{};
    _overflowed = false;
    _pendingSince = null;
    onChanged?.call(batch);
  }

  void _cancelSubscription({required bool clearPending}) {
    _epoch++;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    if (clearPending) {
      _pending = <String>{};
      _overflowed = false;
      _pendingSince = null;
    }
  }

  static bool _samePath(String? a, String b) =>
      a != null &&
      (a == b || (Platform.isWindows && a.toLowerCase() == b.toLowerCase()));

  static Stream<FileSystemEvent> _platformWatch(String path, bool recursive) =>
      Directory(path).watch(recursive: recursive);
}
