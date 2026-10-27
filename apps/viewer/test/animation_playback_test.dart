import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/animation_playback_controller.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';

void main() {
  test('header timelines cover GIF, WebP and APNG without pixel decoding', () {
    for (final extension in ['gif', 'webp', 'apng']) {
      final timeline = AnimationTimeline.parse(
        File('testdata/formats/format_animated.$extension').readAsBytesSync(),
      );
      expect(timeline, isNotNull, reason: extension);
      expect(timeline!.durations.length, greaterThan(1));
      expect(timeline.durationMs, timeline.durations.reduce((a, b) => a + b));
      for (var i = 0; i < timeline.starts.length; i++) {
        expect(timeline.frameAt(timeline.starts[i]), i);
      }
      expect(
        timeline.frameAt(timeline.durationMs),
        timeline.durations.length - 1,
      );
    }
    final varying = AnimationTimeline([100, 400, 200]);
    expect(varying.frameAt(499), 1);
    expect(varying.frameAt(500), 2);
  });

  test(
    'animation settings survive save, copy and invalid stored values',
    () async {
      final dir = Directory.systemTemp.createTempSync('animation-settings');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = AppConfigStore(filePath: '${dir.path}/settings.json');
      final settings = const ViewerSettings().copyWith(
        animationAutoPlay: false,
        animationLoopMode: AnimationLoopMode.once,
        animationSpeed: 0.5,
        animationControlsMode: AnimationControlsMode.always,
      );
      await settings.save(store: store);
      expect(await ViewerSettings.load(store: store), settings);
      expect(
        (await ViewerSettings.load(store: store)).hashCode,
        settings.hashCode,
      );
      await store.write({
        'settings': {
          'animationLoopMode': 'invalid',
          'animationSpeed': 'fast',
          'animationControlsMode': 'invalid',
        },
      });
      final defaults = await ViewerSettings.load(store: store);
      expect(defaults.animationAutoPlay, isTrue);
      expect(defaults.animationLoopMode, AnimationLoopMode.file);
      expect(defaults.animationSpeed, 1.0);
      expect(defaults.animationControlsMode, AnimationControlsMode.autoHide);
      for (final value in [0, -1, 3.0, null, '0.5']) {
        await store.write({
          'settings': {'animationSpeed': value},
        });
        expect((await ViewerSettings.load(store: store)).animationSpeed, 1.0);
      }
    },
  );

  testWidgets('pause, steps, seek and resume preserve the selected frame', (
    tester,
  ) async {
    final c = await _controller(tester, autoPlay: false);
    expect(c.frame, 0);
    c.step(1);
    await tester.pump();
    expect(c.frame, 1);
    expect(c.playing, isFalse);
    c.step(-1);
    await tester.pump();
    expect(c.frame, 0);
    c.beginSeek();
    c.seekTime(550);
    await tester.pump();
    c.endSeek();
    expect(c.frame, 2);
    expect(c.playing, isFalse);
    c.setPlaying(true);
    c.beginSeek();
    c.seekTime(150);
    await tester.pump();
    c.endSeek();
    expect(c.frame, 1);
    expect(c.playing, isTrue);
    c.setPlaying(false);
    await tester.pump(const Duration(seconds: 2));
    expect(c.frame, 1);
  });

  testWidgets(
    'file loop count includes the initial play and holds the last frame',
    (tester) async {
      final c = await _controller(tester, totalPlays: 2);
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(c.frame, 1);
        await tester.pump(const Duration(milliseconds: 400));
        expect(c.frame, 2);
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(c.playing, isFalse);
      expect(c.frame, 2);
      expect(c.positionMs, 700);
      c.toggle();
      await tester.pump();
      expect(c.frame, 0);
      expect(c.playing, isTrue);
      c.setPlaying(false);
    },
  );

  testWidgets(
    'speed scales unequal durations; minimize suspends without changing intent',
    (tester) async {
      final c = await _controller(tester, autoPlay: false);
      c.setSpeed(2);
      c.setPlaying(true);
      await tester.pump(const Duration(milliseconds: 49));
      expect(c.frame, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(c.frame, 1);
      c.setSuspended(true);
      await tester.pump(const Duration(seconds: 5));
      expect(c.frame, 1);
      expect(c.playing, isTrue);
      c.setSuspended(false);
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.frame, 2);
      c.setPlaying(false);
      c.setSuspended(true);
      c.setSuspended(false);
      expect(c.playing, isFalse);
    },
  );

  testWidgets(
    'rapid seeks coalesce even when the last requested frame was decoded but discarded',
    (tester) async {
      final gate = Completer<void>();
      var calls = 0;
      final c = await _controller(
        tester,
        autoPlay: false,
        beforeFrame: () async {
          calls++;
          if (calls == 2) await gate.future;
        },
      );
      c.beginSeek();
      c.seekFrame(2);
      c.seekFrame(1);
      gate.complete();
      await tester.pump();
      expect(c.frame, 1);
      expect(c.error, isNull);
      c.endSeek();
      expect(c.playing, isFalse);
      expect(calls, lessThan(6));
    },
  );

  testWidgets('disposing during decode releases late images and codec', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(2, 2);
    picture.dispose();
    final gate = Completer<void>();
    final codec = _Codec(image, () => gate.future);
    final c = AnimationPlaybackController(
      openCodec: () async => codec,
      timeline: AnimationTimeline([100, 400, 200]),
    );
    final loading = c.initialize();
    await tester.pump();
    c.dispose();
    gate.complete();
    await loading;
    expect(codec.disposed, isTrue);
    image.dispose();
  });

  testWidgets(
    'resolution changes keep the frame, pause state and old pixels until ready',
    (tester) async {
      ui.Image makeImage(int size) {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder);
        final picture = recorder.endRecording();
        final image = picture.toImageSync(size, size);
        picture.dispose();
        return image;
      }

      final small = makeImage(2);
      final large = makeImage(4);
      var useLarge = false;
      final gate = Completer<void>();
      final c = AnimationPlaybackController(
        timeline: AnimationTimeline([100, 400, 200]),
        autoPlay: false,
        openCodec: () async {
          if (useLarge) await gate.future;
          return _Codec(useLarge ? large : small, null);
        },
      );
      await c.initialize();
      c.step(1);
      await tester.pump();
      useLarge = true;
      c.refreshResolution();
      expect(c.image!.width, 2);
      gate.complete();
      await tester.pump();
      expect(c.image!.width, 4);
      expect(c.frame, 1);
      expect(c.playing, isFalse);
      c.dispose();
      small.dispose();
      large.dispose();
    },
  );
}

Future<AnimationPlaybackController> _controller(
  WidgetTester tester, {
  bool autoPlay = true,
  int totalPlays = 0,
  Future<void> Function()? beforeFrame,
}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(2, 2);
  picture.dispose();
  final c = AnimationPlaybackController(
    openCodec: () async => _Codec(image, beforeFrame),
    timeline: AnimationTimeline([100, 400, 200], totalPlays: totalPlays),
    autoPlay: autoPlay,
  );
  addTearDown(() {
    c.dispose();
    image.dispose();
  });
  await c.initialize();
  return c;
}

class _Codec implements ui.Codec {
  _Codec(this.image, this.beforeFrame);
  final ui.Image image;
  final Future<void> Function()? beforeFrame;
  bool disposed = false;
  @override
  int get frameCount => 3;
  @override
  int get repetitionCount => -1;
  @override
  void dispose() => disposed = true;
  @override
  Future<ui.FrameInfo> getNextFrame() async {
    await beforeFrame?.call();
    return _Frame(image.clone());
  }
}

class _Frame implements ui.FrameInfo {
  _Frame(this.image);
  @override
  final ui.Image image;
  @override
  Duration get duration => const Duration(milliseconds: 100);
}
