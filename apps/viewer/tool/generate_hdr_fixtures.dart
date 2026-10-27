import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

// Deterministic scene-linear RGBE chart; no copyrighted/downloaded pixels.
void main(List<String> arguments) {
  const width = 384, height = 192;
  const stops = [0.18, 1.0, 2.0, 4.0, 8.0, 16.0];
  final bytes = BytesBuilder()
    ..add(
      ascii.encode(
        '#?RADIANCE\n# Synthetic linear Rec.709; white=1; stops=0.18,1,2,4,8,16\n'
        'FORMAT=32-bit_rle_rgbe\n\n-Y $height +X $width\n',
      ),
    );
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final level = stops[x ~/ 64] * (0.65 + 0.35 * ((x % 64) / 63));
      final color = y < 64
          ? [1.0, 1.0, 1.0]
          : y < 128
          ? [1.0, 0.25, 0.05]
          : [0.05, 0.4, 1.0];
      final rgb = color.map((v) => v * level).toList();
      final exponent = (math.log(rgb.reduce(math.max)) / math.ln2).floor() + 1;
      final factor = 256 / math.pow(2, exponent);
      bytes.add([
        ...rgb.map((v) => (v * factor).floor().clamp(0, 255)),
        exponent + 128,
      ]);
    }
  }
  File('testdata/formats/hdr_highlights.hdr')
      .writeAsBytesSync(bytes.takeBytes());
  const rec709 = [0.64, 0.33, 0.30, 0.60, 0.15, 0.06, 0.3127, 0.329];
  _exr('hdr_highlights.exr', rec709);
  _exr('hdr_rec2020.exr', [
    0.708,
    0.292,
    0.170,
    0.797,
    0.131,
    0.046,
    0.3127,
    0.329,
  ]);
  _exr('hdr_transparent.exr', rec709, alpha: true);
}

// Minimal uncompressed scanline FLOAT EXR. Writes actual chromaticities, not
// an ImageMagick-inferred default, and uses no external codec to generate data.
void _exr(String name, List<double> primaries, {bool alpha = false}) {
  const width = 384, height = 192;
  Uint8List ints(List<int> values) {
    final data = ByteData(values.length * 4);
    for (var i = 0; i < values.length; i++) {
      data.setUint32(i * 4, values[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  Uint8List floats(List<double> values) {
    final data = ByteData(values.length * 4);
    for (var i = 0; i < values.length; i++) {
      data.setFloat32(i * 4, values[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  final header = BytesBuilder()..add(ints([20000630, 2]));
  void attribute(String name, String type, List<int> value) {
    header
      ..add(ascii.encode('$name\x00$type\x00'))
      ..add(ints([value.length]))
      ..add(value);
  }

  final channels = alpha ? ['A', 'B', 'G', 'R'] : ['B', 'G', 'R'];
  final channelList = BytesBuilder();
  for (final channel in channels) {
    channelList
      ..add(ascii.encode('$channel\x00'))
      ..add(ints([2, 0, 1, 1]));
  }
  channelList.addByte(0);
  attribute('channels', 'chlist', channelList.takeBytes());
  attribute('compression', 'compression', [0]);
  attribute('dataWindow', 'box2i', ints([0, 0, width - 1, height - 1]));
  attribute('displayWindow', 'box2i', ints([0, 0, width - 1, height - 1]));
  attribute('lineOrder', 'lineOrder', [0]);
  attribute('pixelAspectRatio', 'float', floats([1]));
  attribute('screenWindowCenter', 'v2f', floats([0, 0]));
  attribute('screenWindowWidth', 'float', floats([1]));
  attribute('chromaticities', 'chromaticities', floats(primaries));
  header.addByte(0);
  final headerBytes = header.takeBytes();
  final output = BytesBuilder()..add(headerBytes);
  final rowBytes = width * channels.length * 4;
  final offsets = ByteData(height * 8);
  for (var y = 0; y < height; y++) {
    offsets.setUint64(
      y * 8,
      headerBytes.length + height * 8 + y * (rowBytes + 8),
      Endian.little,
    );
  }
  output.add(offsets.buffer.asUint8List());
  for (var y = 0; y < height; y++) {
    output.add(ints([y, rowBytes]));
    final row = <double>[];
    for (final channel in channels) {
      for (var x = 0; x < width; x++) {
        final level =
            [0.18, 1.0, 2.0, 4.0, 8.0, 16.0][x ~/ 64] *
            (0.65 + 0.35 * (x % 64) / 63);
        final color = y < 64
            ? [1.0, 1.0, 1.0]
            : y < 128
            ? [1.0, 0.25, 0.05]
            : [0.05, 0.4, 1.0];
        row.add(
          channel == 'A'
              ? 0.5
              : level * color[{'R': 0, 'G': 1, 'B': 2}[channel]!],
        );
      }
    }
    output.add(floats(row));
  }
  File('testdata/formats/$name').writeAsBytesSync(output.takeBytes());
}
