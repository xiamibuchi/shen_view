import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/decode_scheduler.dart';
import 'package:shen_view/src/application/platform_image_decoder.dart';
import 'package:shen_view/src/application/platform_pixel_conversion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('shenview/native_decoder');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('native request lifecycle', () {
    test(
      'decode carries scheduling and promotes in flight, then detaches',
      () async {
        final gate = Completer<Map<String, Object>>();
        final started = Completer<void>();
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'decode') {
            started.complete();
            return gate.future;
          }
          return null;
        });
        final request = DecodeRequest()
          ..updatePriority(DecodePriority.thumbnail, distance: 9);
        final decoding = PlatformImageDecoder().decode(
          'sample.png',
          request: request,
        );
        await started.future;
        request.updatePriority(DecodePriority.foreground, distance: 0);
        await Future<void>.delayed(Duration.zero);
        final initial = calls.first.arguments as Map<Object?, Object?>;
        final promoted =
            calls
                    .singleWhere((call) => call.method == 'updatePriority')
                    .arguments
                as Map<Object?, Object?>;
        expect(initial['priority'], DecodePriority.thumbnail.index);
        expect(initial['distance'], 9);
        expect(promoted['requestId'], initial['requestId']);
        expect(promoted['priority'], DecodePriority.foreground.index);
        gate.complete({'width': 1, 'height': 1, 'pixels': Uint8List(4)});
        expect(await decoding, isNotNull);
        final count = calls.length;
        request.updatePriority(DecodePriority.visible);
        request.cancel();
        await Future<void>.delayed(Duration.zero);
        expect(calls.length, count);
      },
    );

    test(
      'metadata shares unique IDs and cancellation waits for native reply',
      () async {
        final gate = Completer<Map<String, Object>>();
        final started = Completer<void>();
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'metadata') {
            started.complete();
            return gate.future;
          }
          return null;
        });
        final request = DecodeRequest()
          ..updatePriority(DecodePriority.metadata);
        final pending = PlatformImageDecoder().metadata(
          'sample.heic',
          request: request,
        );
        final failed = expectLater(pending, throwsA(isA<DecodeCancelled>()));
        var finished = false;
        unawaited(
          pending.then<void>(
            (_) => finished = true,
            onError: (Object _) {
              finished = true;
            },
          ),
        );
        await started.future;
        request.cancel();
        await Future<void>.delayed(Duration.zero);
        expect(finished, false);
        expect(calls.last.method, 'cancel');
        final original = calls.first.arguments as Map<Object?, Object?>;
        expect(original['priority'], DecodePriority.metadata.index);
        expect(
          (calls.last.arguments as Map<Object?, Object?>)['requestId'],
          original['requestId'],
        );
        gate.complete({'width': 1, 'height': 1});
        await failed;
        final nextIds = <Object?>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          nextIds.add((call.arguments as Map<Object?, Object?>)['requestId']);
          return null;
        });
        await PlatformImageDecoder().metadata('other.heic');
        await PlatformImageDecoder().decode('other.png');
        expect(nextIds.toSet().length, 2);
        expect(nextIds, isNot(contains(original['requestId'])));
      },
    );
  }, skip: !Platform.isWindows && !Platform.isMacOS);

  test(
    'pixel conversion handles invalid samples and an unaligned input view',
    () async {
      final storage = Uint8List(3 + 32);
      final bytes = Uint8List.sublistView(storage, 3);
      final data = ByteData.sublistView(bytes);
      final values = [
        0.0,
        1.0,
        -1.0,
        .5,
        double.nan,
        double.infinity,
        3.0,
        double.nan,
      ];
      for (var i = 0; i < values.length; i++) {
        data.setFloat32(i * 4, values[i], Endian.little);
      }
      final mapped = await compute(toneMapPlatformFloatPixels, (bytes, 2, 1));
      expect(mapped, [0, 186, 0, 128, 0, 0, 224, 255]);
      expect(
        () => toneMapPlatformFloatPixels((bytes, 3, 1)),
        throwsFormatException,
      );
    },
  );

  test('cancelled pixels never enter codec creation or SDR fallback', () async {
    final request = DecodeRequest()..cancel();
    final image = PlatformDecodedImage(
      width: 1,
      height: 1,
      pixels: Uint8List(16),
      isFloat: true,
    );
    await expectLater(
      image.toCodec(request: request),
      throwsA(isA<DecodeCancelled>()),
    );
  });
}
