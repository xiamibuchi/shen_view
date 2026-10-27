import 'package:flutter/foundation.dart';

import '../domain/auto_play_settings.dart';
import '../domain/viewer_mode.dart';

enum AutoPlayStatus { stopped, playing, paused }

typedef AutoPlayAnimationState = ({bool ready, bool playedOnce, bool paused});

/// Advances only by visible, unsuspended time supplied by the display ticker.
/// Loading and OS suspension never consume the next image's display interval.
class AutoPlayController extends ChangeNotifier {
  AutoPlaySettings settings = const AutoPlaySettings();
  ViewerMode mode = ViewerMode.single;
  AutoPlayStatus status = AutoPlayStatus.stopped;
  Duration _elapsed = Duration.zero;
  bool waitingForAnimation = false;
  int _reportedTenths = -1;

  bool get playing => status == AutoPlayStatus.playing;
  bool get active => status != AutoPlayStatus.stopped;
  bool get scrolling =>
      mode == ViewerMode.comic || mode == ViewerMode.longImage;
  double get remainingSeconds =>
      (settings.intervalFor(mode) - _elapsed.inMicroseconds / 1000000).clamp(
        0,
        3600,
      );

  void configure(AutoPlaySettings value, ViewerMode viewerMode) {
    if (settings == value && mode == viewerMode) return;
    final reset =
        mode != viewerMode ||
        settings.intervalFor(mode) != value.intervalFor(viewerMode) ||
        settings.animationPolicy != value.animationPolicy;
    settings = value;
    mode = viewerMode;
    if (reset) {
      resetInterval();
    } else {
      notifyListeners();
    }
  }

  void start() {
    status = AutoPlayStatus.playing;
    notifyListeners();
  }

  void pause() {
    if (!playing) return;
    status = AutoPlayStatus.paused;
    notifyListeners();
  }

  void stop() {
    status = AutoPlayStatus.stopped;
    resetInterval();
  }

  void resetInterval() {
    _elapsed = Duration.zero;
    _reportedTenths = -1;
    waitingForAnimation = false;
    notifyListeners();
  }

  /// Returns true once this picture is eligible to advance. The caller must
  /// suspend ticks until navigation and the next picture's display complete.
  bool tick(
    Duration delta, {
    required bool ready,
    bool suspended = false,
    bool timedScrollHold = false,
    List<AutoPlayAnimationState> animations = const [],
  }) {
    if (!playing || !ready || suspended) return false;
    if (scrolling && !timedScrollHold) return false;
    if (animations.any((animation) => !animation.ready)) return false;
    if (animations.isNotEmpty &&
        settings.animationPolicy == AutoPlayAnimationPolicy.stop) {
      pause();
      return false;
    }
    if (animations.any((animation) => animation.paused)) {
      pause();
      return false;
    }
    _elapsed += delta;
    final expired = remainingSeconds <= 0;
    final waiting =
        expired &&
        settings.animationPolicy == AutoPlayAnimationPolicy.completeOnce &&
        animations.any((animation) => !animation.playedOnce);
    final tenths = (remainingSeconds * 10).ceil();
    if (tenths != _reportedTenths || waiting != waitingForAnimation) {
      _reportedTenths = tenths;
      waitingForAnimation = waiting;
      notifyListeners();
    }
    return expired && !waiting;
  }
}
