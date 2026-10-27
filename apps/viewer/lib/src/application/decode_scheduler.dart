import 'dart:async';
import 'dart:math' as math;

import 'decode_request.dart';
import 'decode_priority.dart';
export 'decode_priority.dart';

class DecodeScheduler {
  DecodeScheduler({int maxConcurrent = 2, int maxBackgroundConcurrent = 1})
    : _maxConcurrent = math.max(1, maxConcurrent),
      _maxBackgroundConcurrent = math.max(0, maxBackgroundConcurrent);

  int _maxConcurrent;
  int _maxBackgroundConcurrent;
  final _queued = <_ScheduledDecode>[];
  final _running = <_ScheduledDecode>{};
  final _shared = <Object, _SharedDecode>{};
  bool _disposed = false;
  int _sequence = 0;
  Timer? _idleTimer;
  DateTime? _lastForeground;
  bool? _lastThumbnail;
  int _backgroundStreak = 0;

  void refresh() => _pump();

  int get maxConcurrent => _maxConcurrent;
  set maxConcurrent(int value) => setLimits(maxConcurrent: value);
  int get maxBackgroundConcurrent => _maxBackgroundConcurrent;
  int get queuedCount => _queued.length;
  int get runningCount => _running.length;
  bool get foregroundWaiting => _queued.any(
    (task) => task.priority.index <= DecodePriority.visible.index,
  );

  void setLimits({int? maxConcurrent, int? maxBackgroundConcurrent}) {
    if (maxConcurrent != null) _maxConcurrent = math.max(1, maxConcurrent);
    if (maxBackgroundConcurrent != null) {
      _maxBackgroundConcurrent = math.max(0, maxBackgroundConcurrent);
    }
    _pump();
  }

  /// Reorders queued work, including a prefetch becoming visible.
  void updatePriority(
    DecodeRequest request, {
    required DecodePriority priority,
    double distance = 0,
  }) {
    for (final task in [..._queued, ..._running]) {
      if (identical(task.request, request)) {
        task.priority = priority;
        task.distance = _distance(distance);
        task.request.updatePriority(priority, distance: task.distance);
      }
    }
    for (final shared in _shared.values) {
      var changed = false;
      for (final consumer in shared.consumers.values) {
        if (!identical(consumer.request, request)) continue;
        consumer.priority = priority;
        consumer.distance = _distance(distance);
        changed = true;
      }
      if (changed) _promoteShared(shared);
    }
    _pump();
  }

  Future<T> schedule<T>(
    Future<T> Function() operation, {
    required DecodeRequest request,
    DecodePriority priority = DecodePriority.foreground,
    double distance = 0,
    void Function(T result)? onDiscard,
    bool Function()? canStart,
  }) {
    if (_disposed || request.cancelled) {
      return Future<T>.error(DecodeCancelled());
    }
    final completer = Completer<T>();
    request.updatePriority(priority, distance: _distance(distance));
    if (priority.index <= DecodePriority.visible.index) {
      _lastForeground = DateTime.now();
      if (_maxConcurrent == 1) {
        for (final task in _running.toList()) {
          if (task.background) task.request.cancel();
        }
      }
    }
    late final _ScheduledDecode task;
    void cancelQueued() {
      if (_queued.remove(task) && !completer.isCompleted) {
        request.removeCancelListener(cancelQueued);
        completer.completeError(DecodeCancelled());
        _pump();
      }
    }

    task = _ScheduledDecode(
      request: request,
      priority: priority,
      distance: _distance(distance),
      sequence: _sequence++,
      canStart: canStart,
      run: () async {
        request.removeCancelListener(cancelQueued);
        _running.add(task);
        try {
          request.throwIfCancelled();
          final result = await operation();
          if (request.cancelled) {
            onDiscard?.call(result);
            throw DecodeCancelled();
          }
          completer.complete(result);
        } catch (error, stack) {
          completer.completeError(error, stack);
        } finally {
          _running.remove(task);
          _pump();
        }
      },
    );
    _queued.add(task);
    request.addCancelListener(cancelQueued);
    _pump();
    return completer.future;
  }

  /// Consumers share one worker request. A single user's cancellation cannot
  /// cancel another user's worker. Keys include output parameters and generation.
  Future<T> scheduleShared<T>(
    Object key,
    Future<T> Function(DecodeRequest worker) operation, {
    required DecodeRequest request,
    DecodePriority priority = DecodePriority.foreground,
    double distance = 0,
    void Function(T result)? onDiscard,
  }) {
    if (_disposed || request.cancelled) {
      return Future<T>.error(DecodeCancelled());
    }
    var shared = _shared[key];
    if (shared == null) {
      final worker = DecodeRequest();
      shared = _SharedDecode(worker);
      _shared[key] = shared;
      final created = shared;
      created.future =
          schedule<Object?>(
            () => operation(worker),
            request: worker,
            priority: priority,
            distance: distance,
            onDiscard: onDiscard == null
                ? null
                : (result) => onDiscard(result as T),
          ).whenComplete(() {
            if (identical(_shared[key], created)) _shared.remove(key);
          });
    }
    final active = shared;
    final consumer = _SharedConsumer(priority, _distance(distance));
    final token = Object();
    active.consumers[token] = consumer;
    consumer.request = request;
    final completer = Completer<T>();
    void detach() {
      active.consumers.remove(token);
      if (active.consumers.isEmpty) {
        if (identical(_shared[key], active)) _shared.remove(key);
        active.request.cancel();
      } else {
        _promoteShared(active);
      }
    }

    void cancelConsumer() {
      if (completer.isCompleted) return;
      completer.completeError(DecodeCancelled());
      detach();
    }

    request.addCancelListener(cancelConsumer);
    _promoteShared(active);
    unawaited(
      active.future.then(
        (value) {
          request.removeCancelListener(cancelConsumer);
          if (!completer.isCompleted) completer.complete(value as T);
          detach();
        },
        onError: (Object error, StackTrace stack) {
          request.removeCancelListener(cancelConsumer);
          if (!completer.isCompleted) completer.completeError(error, stack);
          detach();
        },
      ),
    );
    return completer.future;
  }

  void _promoteShared(_SharedDecode shared) {
    if (shared.consumers.isEmpty) return;
    final consumers = shared.consumers.values.toList()
      ..sort((left, right) {
        final priority = left.priority.index.compareTo(right.priority.index);
        return priority != 0
            ? priority
            : left.distance.compareTo(right.distance);
      });
    final first = consumers.first;
    for (final task in [..._queued, ..._running]) {
      if (!identical(task.request, shared.request)) continue;
      task.priority = first.priority;
      task.distance = first.distance;
      task.request.updatePriority(first.priority, distance: first.distance);
    }
    _pump();
  }

  static double _distance(double value) =>
      value.isFinite ? math.max(0, value) : double.maxFinite;

  void _pump() {
    if (_disposed) return;
    _queued.sort((left, right) {
      final priority = left.priority.index.compareTo(right.priority.index);
      if (priority != 0) return priority;
      final distance = left.distance.compareTo(right.distance);
      return distance != 0 ? distance : left.sequence.compareTo(right.sequence);
    });
    while (_running.length < _maxConcurrent && _queued.isNotEmpty) {
      final backgroundCount = _running.where((task) => task.background).length;
      final auxiliaryCount = _running.where((task) => task.auxiliary).length;
      final idleFor = _lastForeground == null
          ? 1000
          : DateTime.now().difference(_lastForeground!).inMilliseconds;
      final deferSpeculative = _maxConcurrent == 1 && idleFor < 100;
      if (deferSpeculative && _idleTimer == null) {
        _idleTimer = Timer(Duration(milliseconds: 100 - idleFor), () {
          _idleTimer = null;
          _pump();
        });
      }
      bool eligible(_ScheduledDecode task) =>
          (task.canStart?.call() ?? true) &&
          (!task.auxiliary || auxiliaryCount < 1) &&
          (!task.background ||
              (!deferSpeculative &&
                  backgroundCount < _maxBackgroundConcurrent));
      var index = _queued.indexWhere((task) => eligible(task));
      if (index < 0) return;
      if (_queued[index].background && _backgroundStreak >= 3) {
        final alternate = _queued.indexWhere(
          (task) =>
              task.background &&
              (task.priority == DecodePriority.thumbnail) != _lastThumbnail &&
              eligible(task),
        );
        if (alternate >= 0) index = alternate;
      }
      final task = _queued.removeAt(index);
      if (task.background) {
        final thumbnail = task.priority == DecodePriority.thumbnail;
        _backgroundStreak = thumbnail == _lastThumbnail
            ? _backgroundStreak + 1
            : 1;
        _lastThumbnail = thumbnail;
      }
      unawaited(task.run());
    }
  }

  void dispose() {
    _disposed = true;
    _idleTimer?.cancel();
    for (final task in [..._queued, ..._running]) {
      task.request.cancel();
    }
    for (final shared in _shared.values.toList()) {
      for (final consumer in shared.consumers.values.toList()) {
        consumer.request.cancel();
      }
    }
    _shared.clear();
  }
}

class _ScheduledDecode {
  _ScheduledDecode({
    required this.request,
    required this.priority,
    required this.distance,
    required this.sequence,
    required this.run,
    this.canStart,
  });
  final DecodeRequest request;
  DecodePriority priority;
  double distance;
  final int sequence;
  final Future<void> Function() run;
  final bool Function()? canStart;
  bool get background => priority.index >= DecodePriority.adjacent.index;
  bool get auxiliary => priority.index >= DecodePriority.visibleThumbnail.index;
}

class _SharedDecode {
  _SharedDecode(this.request);
  final DecodeRequest request;
  final consumers = <Object, _SharedConsumer>{};
  late final Future<Object?> future;
}

class _SharedConsumer {
  _SharedConsumer(this.priority, this.distance);
  late final DecodeRequest request;
  DecodePriority priority;
  double distance;
}
