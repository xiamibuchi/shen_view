import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/decode_fallback.dart';
import 'package:shen_view/src/application/decode_request.dart';

class FakeCodec implements ui.Codec {
  FakeCodec(this.next);
  final Future<ui.FrameInfo> Function() next;
  int disposed = 0;
  int frames = 0;
  @override
  int get frameCount => 3;
  @override
  int get repetitionCount => 7;
  @override
  Future<ui.FrameInfo> getNextFrame() {
    frames++;
    return next();
  }

  @override
  void dispose() {
    disposed++;
  }
}

Future<ui.Image> image() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(2, 2);
  } finally {
    picture.dispose();
  }
}

class Frame implements ui.FrameInfo {
  Frame(this.image);
  @override
  final ui.Image image;
  @override
  Duration get duration => const Duration(milliseconds: 50);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'creation and first-frame failures both fall back and dispose codecs',
    () async {
      final pixels = await image();
      final broken = FakeCodec(() async => throw StateError('bad pixels'));
      final good = FakeCodec(() async => Frame(pixels));
      final order = <String>[];
      final codec = await decodeWithFallback([
        DecodeBackend('Flutter', () async {
          order.add('Flutter');
          throw StateError('unsupported');
        }),
        DecodeBackend('platform', () async {
          order.add('platform');
          return broken;
        }),
        DecodeBackend('compatible', () async {
          order.add('compatible');
          return good;
        }),
      ], request: DecodeRequest());
      expect(order, ['Flutter', 'platform', 'compatible']);
      expect(broken.disposed, 1);
      expect(good.frames, 1);
      expect(codec.frameCount, 3);
      expect(codec.repetitionCount, 7);
      expect((await codec.getNextFrame()).image, same(pixels));
      expect(good.frames, 1);
      await codec.getNextFrame();
      expect(good.frames, 2);
      codec.dispose();
      codec.dispose();
      expect(good.disposed, 1);
      pixels.dispose();
    },
  );

  test(
    'budget rejection and cancellation never try a different backend',
    () async {
      for (final error in [
        DecodeBudgetExceeded('too large'),
        DecodeCancelled(),
      ]) {
        var next = false;
        final broken = FakeCodec(() async => throw error);
        await expectLater(
          decodeWithFallback([
            DecodeBackend('first', () async => broken),
            DecodeBackend('second', () async {
              next = true;
              return null;
            }),
          ], request: DecodeRequest()),
          throwsA(same(error)),
        );
        expect(next, false);
        expect(broken.disposed, 1);
      }
    },
  );

  test(
    'cancellation during the first frame disposes the late result',
    () async {
      final request = DecodeRequest();
      final gate = Completer<ui.FrameInfo>();
      final pixels = await image();
      final broken = FakeCodec(() => gate.future);
      var next = false;
      final future = decodeWithFallback([
        DecodeBackend('first', () async => broken),
        DecodeBackend('second', () async {
          next = true;
          return null;
        }),
      ], request: request);
      final expectation = expectLater(future, throwsA(isA<DecodeCancelled>()));
      await Future<void>.delayed(Duration.zero);
      request.cancel();
      gate.complete(Frame(pixels));
      await expectation;
      expect(next, false);
      expect(broken.disposed, 1);
      expect(pixels.debugDisposed, true);
    },
  );

  test(
    'background timeout stops the chain; foreground may continue once',
    () async {
      for (final background in [true, false]) {
        var next = 0;
        final result = decodeWithFallback(
          [
            DecodeBackend('slow', () async => throw DecodeTimedOut('timeout')),
            DecodeBackend('compatible', () async {
              next++;
              return null;
            }),
          ],
          request: DecodeRequest(),
          speculative: background,
        );
        await expectLater(
          result,
          throwsA(
            background ? isA<DecodeTimedOut>() : isA<ImageDecodeFailure>(),
          ),
        );
        expect(next, background ? 0 : 1);
      }
    },
  );

  test('all unsupported or failed backends report each reason once', () async {
    await expectLater(
      decodeWithFallback([
        DecodeBackend('unsupported', () async => null),
        DecodeBackend('corrupt', () async => throw StateError('bad file')),
      ], request: DecodeRequest()),
      throwsA(
        isA<ImageDecodeFailure>().having(
          (error) => error.attempts.keys.toList(),
          'attempts',
          ['unsupported', 'corrupt'],
        ),
      ),
    );
  });
}
