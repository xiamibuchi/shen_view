import 'dart:ui' as ui;

/// Codecs with keyframe-aware seeking can skip intermediate RGB conversions.
abstract interface class IndexedAnimationCodec {
  bool get supportsFrameIndex;
  Future<ui.FrameInfo> getFrame(int index);
}

abstract interface class MediaPlaybackCodec {
  bool get realtime;
  int get audioTrackCount;
  Object? get audioError;
  void synchronizePlayback({
    required int positionMs,
    required double speed,
    required bool playing,
    required bool muted,
    required int audioTrack,
  });
}
