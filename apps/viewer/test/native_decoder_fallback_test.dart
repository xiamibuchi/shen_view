import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/native_decoder.dart';
import 'package:shen_view/src/application/raw_developer.dart';

class _Raw extends RawDeveloper {
  Object failure = DecodeTimedOut('RAW timeout');
  Completer<void>? gate;
  @override
  Future<Uint8List> decode(
    String path, {
    DecodeRequest? request,
    int? targetWidth,
    int? targetHeight,
  }) async {
    await gate?.future;
    throw failure;
  }
}

class _Decoder extends NativeDecoder {
  _Decoder(_Raw raw) : super(rawDeveloper: raw);
  int compatible = 0;
  @override
  Future<String> executable() async => 'unused';
  @override
  Future<Uint8List> run(
    List<String> arguments, {
    DecodeRequest? request,
  }) async {
    compatible++;
    return Uint8List.fromList([1]);
  }
}

void main() {
  test('background RAW timeout stops before the compatible backend', () async {
    final decoder = _Decoder(_Raw());
    await expectLater(
      decoder.decode('page.dng', allowTimeoutFallback: () => false),
      throwsA(isA<DecodeTimedOut>()),
    );
    expect(decoder.compatible, 0);
    expect(await decoder.decode('page.dng'), [1]);
    expect(decoder.compatible, 1);
  });

  test('RAW timeout observes promotion to foreground while decoding', () async {
    final raw = _Raw()..gate = Completer<void>();
    final decoder = _Decoder(raw);
    var foreground = false;
    final result = decoder.decode(
      'page.dng',
      allowTimeoutFallback: () => foreground,
    );
    foreground = true;
    raw.gate!.complete();
    expect(await result, [1]);
    expect(decoder.compatible, 1);
  });

  test(
    'RAW cancellation and budget rejection never try another backend',
    () async {
      for (final failure in [
        DecodeCancelled(),
        DecodeBudgetExceeded('budget'),
      ]) {
        final decoder = _Decoder(_Raw()..failure = failure);
        await expectLater(decoder.decode('page.dng'), throwsA(same(failure)));
        expect(decoder.compatible, 0);
      }
    },
  );
}
