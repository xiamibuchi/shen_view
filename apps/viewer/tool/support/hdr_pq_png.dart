import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:shen_view/src/application/hdr_frame.dart';
import 'package:shen_view/src/application/hdr_transfer.dart';

/// Encodes PQ/BT.2020 PNG fixtures with static luminance metadata.
class HdrPqPng {
  static Uint8List encode(HdrFrame frame) {
    final data = ByteData.sublistView(frame.pixels);
    if (frame.width < 1 ||
        frame.height < 1 ||
        frame.width * frame.height > HdrFrame.maxPixels ||
        frame.pixels.length != frame.width * frame.height * 16) {
      throw const FormatException('PQ PNG bounds');
    }
    const matrix = [
      0.6274039,
      0.3292830,
      0.0433131,
      0.0690973,
      0.9195404,
      0.0113623,
      0.0163914,
      0.0880133,
      0.8955953,
    ];
    final components = frame.hasTransparency ? 4 : 3;
    final rows = Uint8List(frame.height * (1 + frame.width * components * 2));
    final samples = ByteData.sublistView(rows);
    for (var y = 0; y < frame.height; y++) {
      for (var x = 0; x < frame.width; x++) {
        final source = (y * frame.width + x) * 16;
        final target =
            y * (1 + frame.width * components * 2) + 1 + x * components * 2;
        final a = data.getFloat32(source + 12, Endian.little);
        if (!a.isFinite || a < 0 || a > 1) {
          throw const FormatException('PQ PNG alpha');
        }
        if (components == 3 && a != 1) {
          throw const FormatException('PQ PNG transparency flag');
        }
        final rgb = [
          for (var c = 0; c < 3; c++)
            a == 0 ? 0.0 : data.getFloat32(source + c * 4, Endian.little) / a,
        ];
        for (var c = 0; c < 3; c++) {
          final value =
              matrix[c * 3] * rgb[0] +
              matrix[c * 3 + 1] * rgb[1] +
              matrix[c * 3 + 2] * rgb[2];
          if (!value.isFinite) throw const FormatException('PQ PNG sample');
          samples.setUint16(
            target + c * 2,
            (HdrTransfer.nitsToPq(value * 203) * 65535).round(),
          );
        }
        if (components == 4) samples.setUint16(target + 6, (a * 65535).round());
      }
    }
    final ihdr = ByteData(13)
      ..setUint32(0, frame.width)
      ..setUint32(4, frame.height)
      ..setUint8(8, 16)
      ..setUint8(9, components == 4 ? 6 : 2);
    final (cll, fall) = contentLight(frame);
    final clli = ByteData(8)
      ..setUint32(0, (cll * 10000).round())
      ..setUint32(4, (fall * 10000).round());
    final mdcv = ByteData(24);
    final p = HdrTransfer.rec2020;
    for (var i = 0; i < 8; i++) {
      mdcv.setUint16(i * 2, (p[i] * 50000).round());
    }
    mdcv.setUint32(16, 10000 * 10000);
    mdcv.setUint32(20, 1);
    return (BytesBuilder()
          ..add([137, 80, 78, 71, 13, 10, 26, 10])
          ..add(_chunk('IHDR', ihdr.buffer.asUint8List()))
          ..add(_chunk('cICP', Uint8List.fromList([9, 16, 0, 1])))
          ..add(_chunk('mDCv', mdcv.buffer.asUint8List()))
          ..add(_chunk('cLLi', clli.buffer.asUint8List()))
          ..add(_chunk('IDAT', Uint8List.fromList(zlib.encode(rows))))
          ..add(_chunk('IEND', Uint8List(0))))
        .takeBytes();
  }

  static (double, double) contentLight(HdrFrame frame) {
    final data = ByteData.sublistView(frame.pixels);
    var peak = 0.0, total = 0.0;
    for (var i = 0; i < frame.width * frame.height; i++) {
      final rgb = [
        for (var c = 0; c < 3; c++)
          data.getFloat32(i * 16 + c * 4, Endian.little),
      ];
      peak = math.max(peak, rgb.reduce(math.max) * 203);
      total += math.max(
        0,
        (rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722) * 203,
      );
    }
    return (
      peak.clamp(0.0, 10000.0),
      (total / (frame.width * frame.height)).clamp(0.0, 10000.0),
    );
  }

  static Uint8List _chunk(String type, Uint8List payload) {
    final result = Uint8List(payload.length + 12);
    final data = ByteData.sublistView(result)..setUint32(0, payload.length);
    result.setRange(4, 8, ascii.encode(type));
    result.setRange(8, 8 + payload.length, payload);
    var crc = 0xffffffff;
    for (var i = 4; i < result.length - 4; i++) {
      crc ^= result[i];
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >>> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
      }
    }
    data.setUint32(result.length - 4, crc ^ 0xffffffff);
    return result;
  }
}
