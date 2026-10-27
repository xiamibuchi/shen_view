import 'package:flutter/gestures.dart';

/// Accumulates small deltas and limits continuous input to a steady page rate.
/// Device kind alone cannot distinguish legacy trackpad scroll from a wheel.
class ScrollNavigationController {
  static const _distanceThreshold = 20.0;
  static const _gestureGap = Duration(milliseconds: 250);

  Duration? _lastEventTime;
  int? _device;
  Offset _distance = Offset.zero;
  bool _blocked = false;
  bool _vertical = false;
  Duration? _lastTurnTime;

  int? handle(
    PointerScrollEvent event, {
    bool enabled = true,
    Duration interval = const Duration(milliseconds: 180),
  }) {
    final delta = event.scrollDelta;
    if (!delta.dx.isFinite || !delta.dy.isFinite || delta == Offset.zero) {
      return null;
    }
    final previous = _lastEventTime;
    if (_device != event.device ||
        previous == null ||
        event.timeStamp < previous ||
        event.timeStamp - previous >= _gestureGap) {
      reset();
    }
    _device = event.device;
    _lastEventTime = event.timeStamp;
    if (!enabled) _blocked = true;
    if (_blocked) return null;

    _distance += delta;
    if (!_vertical &&
        _distance.dx.abs() >= _distanceThreshold &&
        _distance.dx.abs() >= _distance.dy.abs()) {
      // Lock horizontal gestures too, so their vertical tail cannot turn pages.
      _blocked = true;
    } else if (_distance.dy.abs() >= _distanceThreshold &&
        (_vertical || _distance.dy.abs() > _distance.dx.abs())) {
      _vertical = true;
      final lastTurn = _lastTurnTime;
      if (lastTurn != null &&
          event.timeStamp >= lastTurn &&
          event.timeStamp - lastTurn < interval) {
        // Keep at most one threshold of motion; never queue delayed page turns.
        _distance = Offset(0, _distance.dy.sign * _distanceThreshold);
        return null;
      }
      _lastTurnTime = event.timeStamp;
      final direction = _distance.dy.sign.toInt();
      _distance = Offset.zero;
      return direction;
    }
    return null;
  }

  /// Starts a fresh gesture without bypassing the page-rate limit.
  void reset() {
    _lastEventTime = null;
    _device = null;
    _distance = Offset.zero;
    _blocked = false;
    _vertical = false;
  }
}
