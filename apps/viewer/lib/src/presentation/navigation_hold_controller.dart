import 'dart:async';

/// Repeats navigation independently of the operating system's key-repeat rate.
class NavigationHoldController {
  NavigationHoldController(this.onNavigate);

  final void Function(int direction) onNavigate;
  Timer? _timer;
  int? _direction;

  void press(
    int direction, {
    bool enabled = true,
    Duration delay = const Duration(milliseconds: 400),
    Duration interval = const Duration(milliseconds: 180),
  }) {
    stop();
    _direction = direction;
    onNavigate(direction);
    if (!enabled || _direction != direction) return;
    _timer = Timer(delay, () {
      if (_direction != direction) return;
      onNavigate(direction);
      if (_direction != direction) return;
      _timer = Timer.periodic(interval, (_) => onNavigate(direction));
    });
  }

  void release(int direction) {
    if (_direction == direction) stop();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _direction = null;
  }

  void dispose() => stop();
}
