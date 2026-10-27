import 'dart:async';
import 'dart:math' as math;

import '../domain/image_entry.dart';
import '../domain/image_resource_key.dart';
import '../domain/image_format.dart';
import '../domain/thumbnail_prefetch_mode.dart';
import 'decode_request.dart';
import 'prefetch_planner.dart';

class ThumbnailPrefetchTask {
  const ThumbnailPrefetchTask(this.entry, this.key, this.distance);
  final ImageEntry entry;
  final ImageResourceKey key;
  final double distance;
}

class ThumbnailPrefetchDeferred implements Exception {}

class ThumbnailPrefetchSkipped implements Exception {}

/// Session-owned plans survive hidden or unmounted thumbnail surfaces. Only one
/// speculative consumer is submitted at a time; the shared scheduler admits it.
class ThumbnailPrefetchService {
  ThumbnailPrefetchService({
    required this.version,
    required this.load,
    required this.isCached,
    required this.onRetainedChanged,
  });

  final ImageFileVersion Function(ImageEntry) version;
  final Future<void> Function(ThumbnailPrefetchTask, DecodeRequest) load;
  final bool Function(ImageResourceKey) isCached;
  final void Function(Set<ImageResourceKey>) onRetainedChanged;
  final _views = <Object, _ThumbnailViewport>{};
  final _attempted = <ImageResourceKey>{};
  final _deferred = <ImageResourceKey>{};
  ThumbnailPrefetchMode _mode = ThumbnailPrefetchMode.automatic;
  PrefetchLevel _level = PrefetchLevel.conservative;
  Object? _collection;
  DecodeRequest? _request;
  ImageResourceKey? _running;
  Timer? _timer;
  bool _disposed = false;

  void setCollection(Object collection) {
    if (_collection == collection || _disposed) return;
    _collection = collection;
    _request?.cancel();
    _request = null;
    _running = null;
    _views.clear();
    _attempted.clear();
    _deferred.clear();
    _publish();
  }

  /// Refreshing or sorting a folder preserves its frozen viewport plan.
  void replaceEntries(List<ImageEntry> entries) {
    final positions = {
      for (final (index, entry) in entries.indexed) entry.id: index,
    };
    for (final owner in _views.keys.toList()) {
      final view = _views[owner]!;
      if (entries.isEmpty) {
        _views.remove(owner);
        continue;
      }
      final indices = view.indices == null
          ? null
          : [
              for (final index in view.indices!)
                if (positions[view.entries[index].id] case final int position)
                  position,
            ];
      final length = indices?.length ?? entries.length;
      if (length == 0) {
        _views.remove(owner);
        continue;
      }
      _views[owner] = _ThumbnailViewport(
        entries,
        view.first.clamp(0, length - 1),
        view.last.clamp(0, length - 1),
        view.width,
        view.height,
        view.direction,
        indices,
      );
    }
    _publish();
  }

  void configure(ThumbnailPrefetchMode mode, PrefetchLevel level) {
    if (_disposed || (_mode == mode && _level == level)) return;
    final resume = _level == PrefetchLevel.onDemand && level != _level;
    _mode = mode;
    _level = level;
    if (mode == ThumbnailPrefetchMode.off || level == PrefetchLevel.onDemand) {
      _timer?.cancel();
      _timer = null;
      _request?.cancel();
    }
    if (resume) _attempted.removeWhere((key) => !isCached(key));
    _publish();
  }

  void updateViewport({
    required Object owner,
    required List<ImageEntry> entries,
    required int first,
    required int last,
    required int targetWidth,
    required int targetHeight,
    List<int>? indices,
    int direction = 0,
    bool visible = true,
  }) {
    final length = indices?.length ?? entries.length;
    if (_disposed || !visible || length == 0) return;
    _views[owner] = _ThumbnailViewport(
      entries,
      first.clamp(0, length - 1),
      last.clamp(first.clamp(0, length - 1), length - 1),
      math.max(1, targetWidth),
      math.max(1, targetHeight),
      direction,
      indices,
    );
    _publish();
  }

  List<ThumbnailPrefetchTask> _tasks() {
    if (_mode == ThumbnailPrefetchMode.off) return const [];
    final conservative =
        _mode == ThumbnailPrefetchMode.conservative ||
        _level != PrefetchLevel.normal;
    final tasks = <ImageResourceKey, ThumbnailPrefetchTask>{};
    for (final view in _views.values) {
      final count = view.last - view.first + 1;
      final radius = conservative
          ? math.min(8, (count / 2).ceil())
          : math.min(32, count * 2);
      for (var distance = 1; distance <= radius; distance++) {
        final positions = view.direction < 0
            ? [view.first - distance, view.last + distance]
            : [view.last + distance, view.first - distance];
        for (final index in positions) {
          if (index < 0 ||
              index >= (view.indices?.length ?? view.entries.length)) {
            continue;
          }
          final entry = view.entries[view.indices?[index] ?? index];
          final key = ImageResourceKey(
            version: version(entry),
            targetWidth: view.width,
            targetHeight: view.height,
            allowSmallRawPreview: entry.format == ImageFormat.raw,
          );
          tasks.putIfAbsent(
            key,
            () => ThumbnailPrefetchTask(entry, key, distance.toDouble()),
          );
        }
      }
    }
    final ordered = tasks.values.toList();
    final sequence = {
      for (final (index, task) in ordered.indexed) task.key: index,
    };
    return ordered..sort((a, b) {
      final distance = a.distance.compareTo(b.distance);
      return distance != 0
          ? distance
          : sequence[a.key]!.compareTo(sequence[b.key]!);
    });
  }

  void _publish() {
    final tasks = _tasks();
    final keys = tasks.map((task) => task.key).toSet();
    if (_running != null && !keys.contains(_running)) _request?.cancel();
    _attempted.removeWhere((key) => !keys.contains(key));
    _deferred.removeWhere((key) => !keys.contains(key));
    onRetainedChanged(keys);
    _schedule();
  }

  void _schedule() {
    if (_disposed ||
        _request != null ||
        _timer != null ||
        _mode == ThumbnailPrefetchMode.off ||
        _level == PrefetchLevel.onDemand) {
      return;
    }
    if (!_tasks().any(
      (task) => !_attempted.contains(task.key) && !isCached(task.key),
    )) {
      return;
    }
    // Let a burst of scrolling settle and allow visible tiles to enter first.
    _timer = Timer(const Duration(milliseconds: 100), () {
      _timer = null;
      unawaited(_pump());
    });
  }

  Future<void> _pump() async {
    if (_disposed ||
        _request != null ||
        _mode == ThumbnailPrefetchMode.off ||
        _level == PrefetchLevel.onDemand) {
      return;
    }
    final candidates = _tasks().where(
      (task) => !_attempted.contains(task.key) && !isCached(task.key),
    );
    if (candidates.isEmpty) return;
    final task = candidates.first;
    final request = _request = DecodeRequest();
    _running = task.key;
    _attempted.add(task.key);
    try {
      await load(task, request);
    } on DecodeCancelled {
      _attempted.remove(task.key);
    } on ThumbnailPrefetchDeferred {
      _deferred.add(task.key);
    } catch (_) {
      // Foreground demand owns reporting/retry. Never loop on a corrupt file.
    } finally {
      if (identical(_request, request)) {
        _request = null;
        _running = null;
      }
      _schedule();
    }
  }

  void retry(String id) {
    _attempted.removeWhere((key) => key.version.path == id);
    _publish();
  }

  void capacityChanged() {
    _attempted.removeAll(_deferred);
    _deferred.clear();
    _schedule();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _request?.cancel();
    _views.clear();
    _attempted.clear();
    _deferred.clear();
  }
}

class _ThumbnailViewport {
  const _ThumbnailViewport(
    this.entries,
    this.first,
    this.last,
    this.width,
    this.height,
    this.direction,
    this.indices,
  );
  final List<ImageEntry> entries;
  final int first;
  final int last;
  final int width;
  final int height;
  final int direction;
  final List<int>? indices;
}
