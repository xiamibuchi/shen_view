import 'dart:io';
import 'dart:math' as math;

import 'decode_priority.dart';

class DecodeCancelled implements Exception {}

class DecodeBudgetExceeded extends StateError {
  DecodeBudgetExceeded(super.message);
}

class DecodeTimedOut extends StateError {
  DecodeTimedOut(super.message);
}

class DecodeRequest {
  bool _cancelled = false;
  DecodePriority _priority = DecodePriority.foreground;
  double _distance = 0;
  Process? process;
  final _listeners = <void Function()>{};
  final _priorityListeners = <void Function()>{};

  bool get cancelled => _cancelled;
  DecodePriority get priority => _priority;
  double get distance => _distance;

  void updatePriority(DecodePriority priority, {double distance = 0}) {
    final next = distance.isFinite ? math.max(0.0, distance) : double.maxFinite;
    if (_cancelled || (_priority == priority && _distance == next)) return;
    _priority = priority;
    _distance = next;
    for (final listener in _priorityListeners.toList()) {
      listener();
    }
  }

  void addPriorityListener(void Function() listener) {
    if (!_cancelled) _priorityListeners.add(listener);
  }

  void removePriorityListener(void Function() listener) {
    _priorityListeners.remove(listener);
  }

  void addCancelListener(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void removeCancelListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void throwIfCancelled() {
    if (_cancelled) throw DecodeCancelled();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    process?.kill();
    for (final listener in _listeners.toList()) {
      listener();
    }
    _listeners.clear();
    _priorityListeners.clear();
  }
}
