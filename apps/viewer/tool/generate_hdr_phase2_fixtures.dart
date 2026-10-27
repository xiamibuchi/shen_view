import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as imaging;

import 'package:shen_view/src/application/hdr_frame.dart';

import 'support/hdr_pq_png.dart';

void main() {
  const width = 384, height = 192;
  final floats = ByteData(width * height * 16);
  final transparent = ByteData(width * height * 16);
  final hlg = imaging.Image(
    width: width,
    height: height,
    numChannels: 3,
    format: imaging.Format.uint16,
  );
  const nits = [0.0, 100.0, 203.0, 400.0, 700.0, 1000.0];
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final level = nits[x ~/ 64];
      final alpha = x < 128
          ? 0.0
          : x < 256
          ? 0.5
          : 1.0;
      final rgb = y < 64
          ? [1.0, 1.0, 1.0]
          : y < 128
          ? [1.0, 0.25, 0.05]
          : [0.05, 0.4, 1.0];
      for (var c = 0; c < 3; c++) {
        floats.setFloat32(
          (y * width + x) * 16 + c * 4,
          rgb[c] * level / 203,
          Endian.little,
        );
        transparent.setFloat32(
          (y * width + x) * 16 + c * 4,
          rgb[c] * level / 203 * alpha,
          Endian.little,
        );
      }
      floats.setFloat32((y * width + x) * 16 + 12, 1, Endian.little);
      transparent.setFloat32((y * width + x) * 16 + 12, alpha, Endian.little);
      // Independent BT.2100 encoder, reference 1000-nit display.
      final display = rgb.map((c) => c * level / 1000).toList();
      final lum =
          display[0] * 0.2627 + display[1] * 0.678 + display[2] * 0.0593;
      final gain = lum == 0 ? 0.0 : math.pow(lum, -0.2 / 1.2).toDouble();
      int encode(double value) {
        final scene = value * gain;
        final signal = scene <= 1 / 12
            ? math.sqrt(3 * scene)
            : 0.17883277 * math.log(12 * scene - 0.28466892) + 0.55991073;
        return (signal * 65535).round().clamp(0, 65535);
      }

      hlg.setPixelRgb(
        x,
        y,
        encode(display[0]),
        encode(display[1]),
        encode(display[2]),
      );
    }
  }
  File('testdata/formats/hdr_pq.png').writeAsBytesSync(
    HdrPqPng.encode(HdrFrame(width, height, floats.buffer.asUint8List())),
  );
  File('testdata/formats/hdr_pq_alpha.png').writeAsBytesSync(
    HdrPqPng.encode(
      HdrFrame(
        width,
        height,
        transparent.buffer.asUint8List(),
        hasTransparency: true,
      ),
    ),
  );
  final encoded = imaging.encodePng(hlg);
  final cicp = Uint8List.fromList([...ascii.encode('cICP'), 9, 18, 0, 1]);
  final chunk = ByteData(16)
    ..setUint32(0, 4)
    ..setUint32(12, getCrc32(cicp));
  final bytes = chunk.buffer.asUint8List()..setRange(4, 12, cicp);
  File('testdata/formats/hdr_hlg.png').writeAsBytesSync([
    ...encoded.sublist(0, 33),
    ...bytes,
    ...encoded.sublist(33),
  ]);
}
