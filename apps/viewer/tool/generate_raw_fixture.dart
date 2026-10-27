import 'dart:io';
import 'dart:typed_data';

// Owned, uncompressed Bayer DNG, with no embedded JPEG/preview. Every output
// pixel must therefore be developed from the sensor mosaic.
void main() {
  const width = 256, height = 192;
  Uint8List shorts(List<int> values) {
    final b = ByteData(values.length * 2);
    for (var i = 0; i < values.length; i++) {
      b.setUint16(i * 2, values[i], Endian.little);
    }
    return b.buffer.asUint8List();
  }

  Uint8List longs(List<int> values) {
    final b = ByteData(values.length * 4);
    for (var i = 0; i < values.length; i++) {
      b.setInt32(i * 4, values[i], Endian.little);
    }
    return b.buffer.asUint8List();
  }

  final tags = <(int, int, int, Uint8List)>[];
  void short(int id, List<int> v) => tags.add((id, 3, v.length, shorts(v)));
  void long(int id, List<int> v) => tags.add((id, 4, v.length, longs(v)));
  void bytes(int id, List<int> v) =>
      tags.add((id, 1, v.length, Uint8List.fromList(v)));
  void string(int id, String v) =>
      tags.add((id, 2, v.length + 1, Uint8List.fromList([...v.codeUnits, 0])));
  void rational(int id, List<int> v, {bool signed = false}) =>
      tags.add((id, signed ? 10 : 5, v.length ~/ 2, longs(v)));
  long(256, [width]);
  long(257, [height]);
  short(258, [16]);
  short(259, [1]);
  short(262, [32803]);
  short(277, [1]);
  long(278, [height]);
  long(279, [width * height * 2]);
  short(274, [1]);
  short(284, [1]);
  short(33421, [2, 2]);
  bytes(33422, [0, 1, 1, 2]);
  bytes(50706, [1, 4, 0, 0]);
  bytes(50707, [1, 1, 0, 0]);
  string(50708, 'ShenView Synthetic Bayer');
  string(271, 'ShenView');
  string(272, 'Synthetic CFA');
  bytes(50710, [0, 1, 2]);
  short(50711, [1]);
  short(50713, [1, 1]);
  rational(50714, [64, 1]);
  long(50717, [4095]);
  rational(50718, [1, 1, 1, 1]);
  long(50719, [0, 0]);
  long(50720, [width, height]);
  // XYZ D65 to a simple synthetic camera with nontrivial white balance.
  rational(50721, [
    10000,
    10000,
    0,
    10000,
    0,
    10000,
    0,
    10000,
    10000,
    10000,
    0,
    10000,
    0,
    10000,
    0,
    10000,
    10000,
    10000,
  ], signed: true);
  rational(50728, [1, 2, 1, 1, 3, 4]);
  short(50778, [21]);
  long(50829, [0, 0, height, width]);
  long(273, [0]);
  tags.sort((a, b) => a.$1.compareTo(b.$1));
  final extraStart = 8 + 2 + tags.length * 12 + 4;
  var next = extraStart;
  for (final t in tags) {
    if (t.$4.length > 4) next += (t.$4.length + 1) & ~1;
  }
  final pixelsStart = next;
  final result = Uint8List(pixelsStart + width * height * 2);
  final data = ByteData.sublistView(result);
  result[0] = 73;
  result[1] = 73;
  data.setUint16(2, 42, Endian.little);
  data.setUint32(4, 8, Endian.little);
  data.setUint16(8, tags.length, Endian.little);
  next = extraStart;
  for (var i = 0; i < tags.length; i++) {
    final t = tags[i];
    final offset = 10 + i * 12;
    data.setUint16(offset, t.$1, Endian.little);
    data.setUint16(offset + 2, t.$2, Endian.little);
    data.setUint32(offset + 4, t.$3, Endian.little);
    if (t.$1 == 273) {
      data.setUint32(offset + 8, pixelsStart, Endian.little);
    } else if (t.$4.length <= 4) {
      result.setRange(offset + 8, offset + 8 + t.$4.length, t.$4);
    } else {
      data.setUint32(offset + 8, next, Endian.little);
      result.setRange(next, next + t.$4.length, t.$4);
      next += (t.$4.length + 1) & ~1;
    }
  }
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final c = y.isEven ? (x.isEven ? 0 : 1) : (x.isEven ? 1 : 2);
      final colors = x < width ~/ 3
          ? [0.65, 0.12, 0.08]
          : x < width * 2 ~/ 3
          ? [0.08, 0.65, 0.12]
          : [0.12, 0.08, 0.65];
      final sample = (64 + 4031 * colors[c] * (0.4 + 0.6 * y / (height - 1)))
          .round();
      data.setUint16(pixelsStart + (y * width + x) * 2, sample, Endian.little);
    }
  }
  File('testdata/formats/raw_bayer_no_preview.dng').writeAsBytesSync(result);
  final orientationTag = tags.indexWhere((tag) => tag.$1 == 274);
  data.setUint16(10 + orientationTag * 12 + 8, 6, Endian.little);
  File('testdata/formats/raw_bayer_rotated.dng').writeAsBytesSync(result);
  data.setUint16(10 + orientationTag * 12 + 8, 1, Endian.little);
  // Identical scene two stops underexposed, without changing the black level.
  // This exercises bounded default exposure separately from demosaicing.
  for (var i = pixelsStart; i < result.length; i += 2) {
    final original = data.getUint16(i, Endian.little);
    data.setUint16(i, 64 + ((original - 64) / 4).round(), Endian.little);
  }
  File('testdata/formats/raw_bayer_underexposed.dng').writeAsBytesSync(result);
  // A covered sensor must stay black, rather than amplifying noise to white.
  for (var i = pixelsStart; i < result.length; i += 2) {
    data.setUint16(i, 64, Endian.little);
  }
  File('testdata/formats/raw_bayer_black.dng').writeAsBytesSync(result);
}
