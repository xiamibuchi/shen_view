import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/apng_codec.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/image_resource_service.dart';
import 'package:shen_view/src/domain/animation_timeline.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('APNG source/over, previous/background disposal and loop reset compose correctly', () {
    final bytes = _apng();
    final decoder = ApngFrameDecoder(bytes, maxPixels: 2);
    expect(decoder.timeline.durations, [50, 50, 50, 50]);
    expect(decoder.timeline.totalPlays, 2);
    expect(decoder.next().getBytes().toList(), [
      255,
      0,
      0,
      255,
      255,
      0,
      0,
      255,
    ]);
    expect(decoder.next().getBytes().toList(), [0, 0, 0, 0, 255, 0, 0, 255]);
    expect(decoder.next().getBytes().toList(), [
      255,
      0,
      0,
      255,
      0,
      0,
      255,
      255,
    ]);
    expect(decoder.next().getBytes().toList(), [0, 255, 0, 255, 0, 0, 0, 0]);
    expect(decoder.next().getBytes().toList(), [
      255,
      0,
      0,
      255,
      255,
      0,
      0,
      255,
    ]);
    expect(
      () => ApngFrameDecoder(bytes, maxPixels: 1),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'resource codec streams APNG on a worker and releases its reservation',
    () async {
      final dir = Directory.systemTemp.createTempSync('apng-playback');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/sample.apng')..writeAsBytesSync(_apng());
      final resources = ImageResourceService();
      addTearDown(resources.dispose);
      final stat = file.statSync();
      final entry = ImageEntry(
        file: file,
        format: ImageFormat.apng,
        width: 2,
        height: 1,
        byteLength: stat.size,
        modifiedAt: stat.modified,
      );
      final codec = await resources.animationCodec(
        entry,
        request: DecodeRequest(),
      );
      expect(codec.frameCount, 4);
      expect(codec.repetitionCount, 1);
      for (var i = 0; i < 9; i++) {
        final frame = await codec.getNextFrame();
        expect(frame.duration.inMilliseconds, 50);
        expect(frame.image.width, 2);
        final pixels = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (i % 4 == 1) expect(pixels!.getUint8(3), 0);
        frame.image.dispose();
      }
      codec.dispose();
      expect(resources.inflightBytes, 0);
    },
  );

  test('malformed/truncated animation headers do not invent a timeline', () {
    final bytes = _apng();
    expect(
      AnimationTimeline.parse(Uint8List.fromList(bytes.take(20).toList())),
      isNull,
    );
    expect(AnimationTimeline.parse(Uint8List(0)), isNull);
    expect(AnimationTimeline.parse(Uint8List.fromList([71, 73, 70])), isNull);
  });
}

Uint8List _apng() {
  final out = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> body) {
    final data = [...type.codeUnits, ...body];
    out.add((ByteData(4)..setUint32(0, body.length)).buffer.asUint8List());
    out.add(data);
    out.add((ByteData(4)..setUint32(0, getCrc32(data))).buffer.asUint8List());
  }

  final ihdr = ByteData(13)
    ..setUint32(0, 2)
    ..setUint32(4, 1)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk(
    'acTL',
    (ByteData(8)
          ..setUint32(0, 4)
          ..setUint32(4, 2))
        .buffer
        .asUint8List(),
  );
  var sequence = 0;
  final frames = [
    (2, 0, 0, 0, [255, 0, 0, 255, 255, 0, 0, 255]),
    (1, 0, 2, 0, [0, 0, 0, 0]),
    (1, 1, 1, 1, [0, 0, 255, 255]),
    (1, 0, 0, 1, [0, 255, 0, 255]),
  ];
  for (final (i, frame) in frames.indexed) {
    final (width, x, dispose, blend, pixels) = frame;
    final control = ByteData(26)
      ..setUint32(0, sequence++)
      ..setUint32(4, width)
      ..setUint32(8, 1)
      ..setUint32(12, x)
      ..setUint16(20, 5)
      ..setUint16(22, 0)
      ..setUint8(24, dispose)
      ..setUint8(25, blend);
    chunk('fcTL', control.buffer.asUint8List());
    final compressed = zlib.encode([0, ...pixels]);
    if (i == 0) {
      chunk('IDAT', compressed);
    } else {
      chunk('fdAT', [
        ...(ByteData(4)..setUint32(0, sequence++)).buffer.asUint8List(),
        ...compressed,
      ]);
    }
  }
  chunk('IEND', []);
  return out.toBytes();
}
