import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/hdr_frame.dart';
import 'package:shen_view/src/application/hdr_frame_cache.dart';
import 'package:shen_view/src/domain/image_resource_key.dart';

ImageFileVersion key(String path, [int revision = 0]) => ImageFileVersion(
  path: path,
  modifiedMicroseconds: 0,
  byteLength: 100,
  revision: revision,
);
HdrFrame frame() => HdrFrame(1, 1, Uint8List(16));

void main() {
  test(
    'consumers share a frame and cancelling one leaves the worker alive',
    () async {
      final cache = HdrFrameCache()..configure(64);
      addTearDown(cache.dispose);
      final gate = Completer<HdrFrame>();
      final first = DecodeRequest();
      DecodeRequest? worker;
      var calls = 0;
      Future<HdrFrame> decode(DecodeRequest request) {
        calls++;
        worker = request;
        return gate.future;
      }

      final cancelled = cache.load(key('a'), first, decode);
      final cancellation = expectLater(
        cancelled,
        throwsA(isA<DecodeCancelled>()),
      );
      final visible = cache.load(key('a'), DecodeRequest(), decode);
      first.cancel();
      await cancellation;
      expect(worker!.cancelled, false);
      final result = frame();
      gate.complete(result);
      expect(await visible, same(result));
      expect(await cache.load(key('a'), DecodeRequest(), decode), same(result));
      expect(calls, 1);
      expect(cache.currentBytes, 16);
    },
  );

  test(
    'last cancellation stops work and a late result cannot replace its retry',
    () async {
      final cache = HdrFrameCache()..configure(64);
      addTearDown(cache.dispose);
      final gate = Completer<HdrFrame>();
      final consumer = DecodeRequest();
      late DecodeRequest worker;
      final old = cache.load(key('a'), consumer, (request) {
        worker = request;
        return gate.future;
      });
      var settled = false;
      final cancelled = expectLater(
        old.whenComplete(() => settled = true),
        throwsA(isA<DecodeCancelled>()),
      );
      consumer.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(
        settled,
        false,
        reason: 'worker still owns the source and its reservation',
      );
      expect(worker.cancelled, true);
      final replacement = frame();
      await cache.load(key('a'), DecodeRequest(), (_) async => replacement);
      gate.complete(frame());
      await cancelled;
      await Future<void>.delayed(Duration.zero);
      expect(
        await cache.load(
          key('a'),
          DecodeRequest(),
          (_) => throw StateError('cache miss'),
        ),
        same(replacement),
      );
    },
  );

  test(
    'byte-bounded LRU, version changes and invalidation expire frames',
    () async {
      final cache = HdrFrameCache()..configure(32);
      addTearDown(cache.dispose);
      var decodes = 0;
      Future<HdrFrame> get(ImageFileVersion version) =>
          cache.load(version, DecodeRequest(), (_) async {
            decodes++;
            return frame();
          });
      await get(key('a'));
      await get(key('b'));
      await get(key('a'));
      await get(key('c'));
      expect(decodes, 3);
      await get(key('b'));
      expect(decodes, 4);
      expect(cache.currentBytes, 32);
      await get(key('b', 1));
      expect(decodes, 5);
      cache.invalidate('b');
      expect(cache.currentBytes, 0);
      await get(key('b', 1));
      expect(decodes, 6);
      cache.configure(0);
      expect(cache.currentBytes, 0);
      await get(key('b', 1));
      await get(key('b', 1));
      expect(decodes, 8);
    },
  );

  test(
    'collection removal cancels waiting consumers and rejects late results',
    () async {
      final cache = HdrFrameCache()..configure(64);
      addTearDown(cache.dispose);
      final gate = Completer<HdrFrame>();
      final pending = cache.load(key('a'), DecodeRequest(), (_) => gate.future);
      final cancelled = expectLater(pending, throwsA(isA<DecodeCancelled>()));
      cache.retainPaths({'b'});
      gate.complete(frame());
      await cancelled;
      await Future<void>.delayed(Duration.zero);
      expect(cache.currentBytes, 0);
    },
  );

  test(
    'failures remain retryable without poisoning shared consumers',
    () async {
      final cache = HdrFrameCache()..configure(64);
      addTearDown(cache.dispose);
      await expectLater(
        cache.load(
          key('a'),
          DecodeRequest(),
          (_) async => throw FormatException('bad source'),
        ),
        throwsFormatException,
      );
      expect(
        await cache.load(key('a'), DecodeRequest(), (_) async => frame()),
        isA<HdrFrame>(),
      );
    },
  );
}
