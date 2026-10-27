import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../domain/animation_timeline.dart';
import 'indexed_animation_codec.dart';

export '../domain/animation_timeline.dart';

typedef AnimationPlaybackSnapshot = ({
  int frame,
  bool playing,
  double speed,
  AnimationLoopMode loopMode,
  int completedPlays,
  bool ended,
  double remainingMs,
});

/// Serializes codec work, keeps only the displayed image, and coalesces seeks.
class AnimationPlaybackController extends ChangeNotifier {
  AnimationPlaybackController({
    required this.openCodec,
    required this.timeline,
    bool autoPlay = true,
    this.loopMode = AnimationLoopMode.file,
  }) : _playing = autoPlay;

  final Future<ui.Codec> Function() openCodec;
  final AnimationTimeline timeline;
  ui.Codec? _codec;
  ui.Image? image;
  Object? error;
  Timer? _timer;
  final _clock = Stopwatch();
  final _mediaClock = Stopwatch();
  double _mediaPosition = 0;
  bool muted = true;
  int audioTrack = 0;
  bool get _realtime =>
      _codec is MediaPlaybackCodec && (_codec! as MediaPlaybackCodec).realtime;
  int get audioTrackCount => _codec is MediaPlaybackCodec
      ? (_codec! as MediaPlaybackCodec).audioTrackCount
      : 0;
  double get _mediaNow =>
      (_mediaPosition + _mediaClock.elapsedMicroseconds / 1000 * speed).clamp(
        0,
        timeline.durationMs.toDouble(),
      );
  void _syncAudio(bool playing) {
    if (_realtime) {
      (_codec! as MediaPlaybackCodec).synchronizePlayback(
        positionMs: _mediaNow.round(),
        speed: speed,
        playing: playing,
        muted: muted,
        audioTrack: audioTrack,
      );
    }
  }

  void setMuted(bool value) {
    if (_disposed || muted == value) return;
    muted = value;
    _syncAudio(_running);
    notifyListeners();
  }

  void setAudioTrack(int index) {
    if (_disposed || index < 0 || index >= audioTrackCount) return;
    audioTrack = index;
    _syncAudio(_running);
    notifyListeners();
  }

  double _remainingMs = 0;
  bool _disposed = false;
  bool _busy = false;
  bool _playing;
  bool _suspended = false;
  bool seeking = false;
  bool _resumeAfterSeek = false;
  bool _ended = false;
  int _codecFrame = -1;
  int? _wantedFrame;
  int? _decodingTarget;
  bool _refreshCodec = false;
  int _completedPlays = 0;
  int frame = 0;
  double speed = 1;
  AnimationLoopMode loopMode;

  bool get playing => _playing;
  Object? get audioError => _codec is MediaPlaybackCodec
      ? (_codec! as MediaPlaybackCodec).audioError
      : null;
  void retryAudio() {
    if (_disposed) return;
    muted = false;
    _syncAudio(_running);
    notifyListeners();
  }

  bool get ready => image != null && error == null;
  int get frameCount => timeline.durations.length;
  int get positionMs => _ended
      ? timeline.durationMs
      : _realtime
      ? _mediaNow.round()
      : timeline.starts[frame];
  bool get _running => _playing && !_suspended && !seeking && !_disposed;
  AnimationPlaybackSnapshot get snapshot => (
    frame: frame,
    playing: _playing,
    speed: speed,
    loopMode: loopMode,
    completedPlays: _completedPlays,
    ended: _ended,
    remainingMs:
        (_remainingMs -
                (_clock.isRunning
                    ? _clock.elapsedMicroseconds / 1000 * speed
                    : 0))
            .clamp(0, double.infinity),
  );

  Future<void> initialize({AnimationPlaybackSnapshot? restore}) async {
    if (restore != null) {
      _playing = restore.playing;
      speed = restore.speed;
      loopMode = restore.loopMode;
    }
    _wantedFrame = (restore?.frame ?? 0).clamp(0, frameCount - 1);
    await _drain();
    if (restore != null && !_disposed && error == null) {
      _stopClock();
      _remainingMs = restore.remainingMs;
      _completedPlays = restore.completedPlays;
      _ended = restore.ended;
      notifyListeners();
      _schedule();
    }
  }

  void _stopClock() {
    _timer?.cancel();
    if (_realtime) {
      _mediaPosition = _mediaNow;
      _mediaClock
        ..stop()
        ..reset();
      _syncAudio(false);
    }
    if (_clock.isRunning) {
      _remainingMs = (_remainingMs - _clock.elapsedMicroseconds / 1000 * speed)
          .clamp(0, double.infinity);
    }
    _clock
      ..stop()
      ..reset();
  }

  void _schedule() {
    if (!_running || !ready || _busy || frameCount < 2) return;
    if (_realtime) {
      _scheduleMedia();
      return;
    }
    _timer?.cancel();
    _clock
      ..reset()
      ..start();
    _timer = Timer(
      Duration(microseconds: (_remainingMs / speed * 1000).round()),
      () {
        _clock
          ..stop()
          ..reset();
        if (!_running) return;
        if (frame == frameCount - 1) {
          _completedPlays++;
          final limit = switch (loopMode) {
            AnimationLoopMode.file => timeline.totalPlays,
            AnimationLoopMode.once => 1,
            AnimationLoopMode.infinite => 0,
          };
          if (limit > 0 && _completedPlays >= limit) {
            _playing = false;
            _ended = true;
            notifyListeners();
            return;
          }
        }
        _wantedFrame = (frame + 1) % frameCount;
        unawaited(_drain());
      },
    );
  }

  void _scheduleMedia() {
    _timer?.cancel();
    if (!_mediaClock.isRunning) {
      _mediaClock.start();
      _syncAudio(true);
    }
    final next = frame + 1 < frameCount
        ? timeline.starts[frame + 1]
        : timeline.durationMs;
    final wait = ((next - _mediaNow) / speed * 1000).round().clamp(
      1000,
      0x7fffffff,
    );
    _timer = Timer(Duration(microseconds: wait), () {
      if (!_running) return;
      final position = _mediaNow.round();
      if (position >= timeline.durationMs) {
        _completedPlays++;
        final limit = switch (loopMode) {
          AnimationLoopMode.file => timeline.totalPlays,
          AnimationLoopMode.once => 1,
          AnimationLoopMode.infinite => 0,
        };
        _stopClock();
        if (limit > 0 && _completedPlays >= limit) {
          _ended = true;
          _playing = false;
          notifyListeners();
          return;
        }
        _mediaPosition = 0;
        _wantedFrame = 0;
      } else {
        final target = timeline.frameAt(position);
        if (target == frame) {
          _scheduleMedia();
          return;
        }
        _wantedFrame = target;
      }
      unawaited(_drain());
    });
  }

  void toggle() => setPlaying(!_playing);
  void setPlaying(bool value) {
    if (_disposed || _playing == value) return;
    _stopClock();
    _playing = value;
    if (value && _ended) {
      restart();
      return;
    }
    notifyListeners();
    _schedule();
  }

  void setSuspended(bool value) {
    if (_disposed || _suspended == value) return;
    _stopClock();
    _suspended = value;
    _schedule();
  }

  void setSpeed(double value) {
    if (_disposed || !animationPlaybackSpeeds.contains(value)) return;
    _stopClock();
    speed = value;
    notifyListeners();
    _schedule();
  }

  void setLoopMode(AnimationLoopMode value) {
    if (_disposed) return;
    loopMode = value;
    _completedPlays = 0;
    notifyListeners();
  }

  void beginSeek() {
    if (seeking || _disposed) return;
    _stopClock();
    _resumeAfterSeek = playing;
    seeking = true;
    _playing = false;
    notifyListeners();
  }

  void seekTime(int ms) => seekFrame(timeline.frameAt(ms));
  void seekFrame(int index) {
    if (_disposed) return;
    _stopClock();
    _ended = false;
    _completedPlays = 0;
    _wantedFrame = index.clamp(0, frameCount - 1);
    _mediaPosition = timeline.starts[_wantedFrame!].toDouble();
    unawaited(_drain());
  }

  void endSeek() {
    if (!seeking || _disposed) return;
    seeking = false;
    _playing = _resumeAfterSeek;
    notifyListeners();
    _schedule();
  }

  void step(int delta) {
    setPlaying(false);
    seekFrame(((_wantedFrame ?? frame) + delta).clamp(0, frameCount - 1));
  }

  void restart() {
    if (_disposed) return;
    _playing = true;
    notifyListeners();
    seekFrame(0);
  }

  /// Re-decode at a new display size without clearing the visible frame.
  void refreshResolution() {
    if (_disposed) return;
    _stopClock();
    _refreshCodec = true;
    _wantedFrame ??= _decodingTarget ?? frame;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_busy || _disposed) return;
    _busy = true;
    try {
      while (_wantedFrame != null && !_disposed) {
        final target = _wantedFrame!;
        _decodingTarget = target;
        _wantedFrame = null;
        if (target == 0 && _codecFrame == frameCount - 1 && frameCount > 1) {
          _codecFrame = -1;
        }
        if (_codec == null ||
            _refreshCodec ||
            (target < _codecFrame && !_supportsFrameIndex) ||
            (target == _codecFrame && frame != target)) {
          _codec?.dispose();
          _refreshCodec = false;
          _codec = null;
          final codec = await openCodec();
          if (_disposed) {
            codec.dispose();
            return;
          }
          _codec = codec;
          if (_realtime) _mediaPosition = timeline.starts[target].toDouble();
          _codecFrame = -1;
          if (codec.frameCount != frameCount) {
            throw StateError('Animation frame count mismatch');
          }
        }
        if (_supportsFrameIndex && _codecFrame != target) _codecFrame = -1;
        while (_codecFrame < target && !_disposed) {
          final indexed = _supportsFrameIndex;
          final info = indexed
              ? await (_codec! as IndexedAnimationCodec).getFrame(target)
              : await _codec!.getNextFrame();
          if (_disposed) {
            info.image.dispose();
            return;
          }
          _codecFrame = indexed ? target : _codecFrame + 1;
          if (_codecFrame != target || _wantedFrame != null) {
            info.image.dispose();
          } else {
            final previous = image;
            image = info.image;
            frame = target;
            _remainingMs = timeline.durations[frame].toDouble();
            previous?.dispose();
            notifyListeners();
          }
          // A newer drag target supersedes this decode, including during long seeks.
          if (_wantedFrame != null) break;
        }
        if (_codecFrame == target && frame == target) {
          _remainingMs = timeline.durations[frame].toDouble();
          if (!_disposed) notifyListeners();
        }
      }
    } on Object catch (failure) {
      if (!_disposed) {
        _stopClock();
        error = failure;
        _playing = false;
        notifyListeners();
      }
    } finally {
      _decodingTarget = null;
      _busy = false;
      if (_disposed) {
        _codec?.dispose();
        _codec = null;
      } else {
        _schedule();
      }
    }
  }

  bool get _supportsFrameIndex =>
      _codec is IndexedAnimationCodec &&
      (_codec! as IndexedAnimationCodec).supportsFrameIndex;

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _clock.stop();
    _mediaClock.stop();
    _syncAudio(false);
    if (!_busy) _codec?.dispose();
    image?.dispose();
    super.dispose();
  }
}
