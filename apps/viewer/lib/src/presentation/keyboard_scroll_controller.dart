import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class KeyboardScrollController {
  KeyboardScrollController({
    required TickerProvider vsync,
    required this.onScroll,
  }) {
    _ticker = vsync.createTicker(_tick);
  }

  final ValueChanged<double> onScroll;
  late final Ticker _ticker;
  double _direction = 0;
  bool _pressed = false;
  Duration _previousElapsed = Duration.zero;

  void press(double direction) {
    if (_pressed && direction == _direction) return;
    cancel();
    _direction = direction;
    _pressed = true;
    _ticker.start();
  }

  void release(double direction) {
    if (direction != _direction) return;
    _pressed = false;
    if (_previousElapsed >= const Duration(milliseconds: 140)) cancel();
  }

  void stopAtBoundary() => _ticker.stop();

  void cancel() {
    _ticker.stop();
    _pressed = false;
    _direction = 0;
    _previousElapsed = Duration.zero;
  }

  void _tick(Duration elapsed) {
    final previous = _previousElapsed.inMicroseconds / 1000000;
    final current = elapsed.inMicroseconds / 1000000;
    _previousElapsed = elapsed;
    var delta = _tapPosition(current) - _tapPosition(previous);
    if (_pressed && current > 0.14) {
      final seconds = math.min(0.05, current - math.max(previous, 0.14));
      final acceleration = ((current - 0.14) / 0.4).clamp(0.0, 1.0);
      delta += seconds * (300 + acceleration * 700);
    }
    if (delta > 0) onScroll(_direction * delta);
    if (!_pressed && current >= 0.14) cancel();
  }

  double _tapPosition(double seconds) {
    final progress = (seconds / 0.14).clamp(0.0, 1.0);
    return (80 * (1 - math.pow(1 - progress, 3))).toDouble();
  }

  void dispose() => _ticker.dispose();
}
