import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/hdr_frame.dart';
import 'package:shen_view/src/application/hdr_input_metadata.dart';
import 'package:shen_view/src/application/hdr_transfer.dart';

void main() {
  test(
    'RGBA16 preserves PQ luminance, alpha and negative gamut components',
    () {
      final encoded = ByteData(8);
      final signal = (HdrTransfer.nitsToPq(203) * 65535).round();
      for (var c = 0; c < 3; c++) {
        encoded.setUint16(c * 2, signal, Endian.little);
      }
      encoded.setUint16(6, 32768, Endian.little);
      final frame = HdrFrame.fromRgba16(
        encoded.buffer.asUint8List(),
        width: 1,
        height: 1,
        encoding: HdrEncoding.pq,
        colorTransform: [-1, 0, 0, 0, 1, 0, 0, 0, 1],
      );
      final pixel = ByteData.sublistView(frame.pixels);
      expect(pixel.getFloat32(0, Endian.little), closeTo(-0.5, 0.001));
      expect(pixel.getFloat32(4, Endian.little), closeTo(0.5, 0.001));
      expect(pixel.getFloat32(12, Endian.little), closeTo(0.5, 0.0001));
      expect(frame.hasTransparency, true);
    },
  );

  test('RGBA16 HLG keeps highlights above reference white', () {
    final encoded = Uint8List(8)..fillRange(0, 8, 255);
    final frame = HdrFrame.fromRgba16(
      encoded,
      width: 1,
      height: 1,
      encoding: HdrEncoding.hlg,
    );
    expect(
      ByteData.sublistView(frame.pixels).getFloat32(0, Endian.little),
      closeTo(1000 / 203, 0.001),
    );
  });

  test(
    'RGBA16 rejects truncated, trailing, oversized and malformed matrices',
    () {
      for (final n in [0, 7, 9]) {
        expect(
          () => HdrFrame.fromRgba16(
            Uint8List(n),
            width: 1,
            height: 1,
            encoding: HdrEncoding.pq,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => HdrFrame.fromRgba16(
          Uint8List(8),
          width: 100000,
          height: 100000,
          encoding: HdrEncoding.pq,
        ),
        throwsFormatException,
      );
      expect(
        () => HdrFrame.fromRgba16(
          Uint8List(8),
          width: 1,
          height: 1,
          encoding: HdrEncoding.pq,
          colorTransform: [1],
        ),
        throwsFormatException,
      );
    },
  );
}
