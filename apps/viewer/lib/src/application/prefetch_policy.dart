import 'dart:math' as math;

import 'prefetch_planner.dart';

/// Automatic degradation with quick pressure response and deliberately slow recovery.
class AdaptivePrefetchPolicy {
  AdaptivePrefetchPolicy({
    DateTime? now,
    this.maxLevel = PrefetchLevel.normal,
    int? physicalMemoryBytes,
    int? availableMemoryBytes,
    this.userMemoryLimitBytes = 256 * 1024 * 1024,
  }) : _physicalMemoryBytes = physicalMemoryBytes,
       _availableMemoryBytes = availableMemoryBytes,
       _level = physicalMemoryBytes == null || availableMemoryBytes == null
           ? PrefetchLevel.conservative
           : PrefetchLevel.normal,
       _lastChange = now ?? DateTime.now(),
       _stableSince = now ?? DateTime.now();

  final int userMemoryLimitBytes;
  PrefetchLevel maxLevel;
  PrefetchLevel _level;
  int? _physicalMemoryBytes;
  int? _availableMemoryBytes;
  DateTime _lastChange;
  DateTime _stableSince;
  DateTime? _slowSince;
  DateTime? _lastSlow;
  bool _resourcePressure = false;
  bool _active = true;
  double? _decodeMilliseconds;
  String _reason = 'startup';

  PrefetchLevel get resourceLevel => !_active ? PrefetchLevel.onDemand : _level;
  PrefetchLevel get level => !_active
      ? PrefetchLevel.onDemand
      : PrefetchLevel.values[math.max(_level.index, maxLevel.index)];
  int get maxConcurrent => level == PrefetchLevel.normal ? 2 : 1;
  int get maxBackgroundConcurrent => level == PrefetchLevel.onDemand ? 0 : 1;
  String get reason => _reason;

  int get memoryBudgetBytes {
    // Focus and prefetch preferences control speculative work, not whether
    // a user-requested image fits in memory. Only measured pressure caps it.
    var budget = 256 * 1024 * 1024;
    if (_resourcePressure && _reason != 'diskSpace') {
      budget = 64 * 1024 * 1024;
    }
    budget = math.min(budget, math.max(0, userMemoryLimitBytes));
    if (_physicalMemoryBytes case final physical?) {
      budget = math.min(budget, math.max(0, physical) ~/ 32);
    }
    if (_availableMemoryBytes case final available?) {
      budget = math.min(budget, math.max(0, available) ~/ 4);
    }
    return budget;
  }

  void configure({required PrefetchLevel maxLevel, DateTime? now}) {
    this.maxLevel = maxLevel;
  }

  void setActive(bool active, {DateTime? now}) {
    _active = active;
    _stableSince = now ?? DateTime.now();
  }

  void updateMemory({
    int? physicalMemoryBytes,
    int? availableMemoryBytes,
    DateTime? now,
  }) {
    _physicalMemoryBytes = physicalMemoryBytes;
    _availableMemoryBytes = availableMemoryBytes;
    if (availableMemoryBytes != null &&
        availableMemoryBytes < 32 * 1024 * 1024) {
      pressure(now: now, reason: 'availableMemory');
    }
  }

  /// Caller clears pressure only after memory/disk safety margins are restored.
  void pressure({DateTime? now, String reason = 'memoryPressure'}) {
    _resourcePressure = true;
    _reason = reason;
    _change(PrefetchLevel.onDemand, now ?? DateTime.now(), reason);
  }

  void clearPressure({DateTime? now}) {
    _resourcePressure = false;
    _stableSince = now ?? DateTime.now();
    _slowSince = null;
  }

  void recordFrame({
    required Duration elapsed,
    required Duration frameBudget,
    required bool hasSpeculativeWork,
    DateTime? now,
  }) {
    final time = now ?? DateTime.now();
    final slow =
        hasSpeculativeWork &&
        elapsed.inMicroseconds > frameBudget.inMicroseconds * 1.5;
    _recordLoad(slow, time, 'frameTime');
  }

  void recordDecode({
    required Duration elapsed,
    required bool hasSpeculativeWork,
    bool foregroundWaiting = false,
    DateTime? now,
  }) {
    final milliseconds = elapsed.inMicroseconds / 1000;
    _decodeMilliseconds = _decodeMilliseconds == null
        ? milliseconds
        : _decodeMilliseconds! * .8 + milliseconds * .2;
    // A slow format alone is not evidence that the machine is overloaded.
    _recordLoad(
      hasSpeculativeWork && foregroundWaiting && _decodeMilliseconds! > 250,
      now ?? DateTime.now(),
      'decodeWait',
    );
  }

  void _recordLoad(bool slow, DateTime now, String reason) {
    if (slow) {
      if (_lastSlow == null ||
          now.difference(_lastSlow!) > const Duration(seconds: 1)) {
        _slowSince = now;
      }
      _slowSince ??= now;
      _lastSlow = now;
      _stableSince = now;
      if (now.difference(_slowSince!) >= const Duration(seconds: 2) &&
          now.difference(_lastChange) >= const Duration(seconds: 2)) {
        final next = PrefetchLevel.values[math.min(_level.index + 1, 2)];
        _change(next, now, reason);
        _slowSince = now;
      }
    }
    tick(now: now);
  }

  void tick({DateTime? now}) {
    final time = now ?? DateTime.now();
    if (!_active || _resourcePressure || _level == PrefetchLevel.normal) {
      return;
    }
    if (time.difference(_lastChange) < const Duration(seconds: 10) ||
        time.difference(_stableSince) < const Duration(seconds: 30)) {
      return;
    }
    final physical = _physicalMemoryBytes;
    final available = _availableMemoryBytes;
    if (physical == null ||
        available == null ||
        available < 128 * 1024 * 1024) {
      return;
    }
    _change(PrefetchLevel.values[_level.index - 1], time, 'stable');
  }

  void _change(PrefetchLevel next, DateTime now, String reason) {
    if (next == _level) return;
    _level = next;
    _lastChange = now;
    _stableSince = now;
    _reason = reason;
  }
}
