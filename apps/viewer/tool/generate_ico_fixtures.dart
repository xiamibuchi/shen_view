import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as imaging;

void main() {
  final root = Directory('testdata/formats')..createSync(recursive: true);
  File('${root.path}/format_multisize.ico').writeAsBytesSync(
    icoContainer([
      (16, 16, 24, dibIcon(16, 16, 24, 220, 40, 30)),
      (32, 32, 32, pngIcon(32, 32, 30, 190, 60)),
      (256, 256, 32, pngIcon(256, 256, 35, 90, 230)),
      (32, 32, 8, dibIcon(32, 32, 8, 240, 170, 20)),
      (32, 32, 32, pngIcon(32, 32, 170, 50, 210)),
    ]),
  );
  File('${root.path}/format_bitmap.ico').writeAsBytesSync(
    icoContainer([
      (16, 16, 1, dibIcon(16, 16, 1, 220, 40, 30)),
      (32, 32, 4, dibIcon(32, 32, 4, 30, 190, 60)),
      (48, 48, 8, dibIcon(48, 48, 8, 35, 90, 230)),
      (64, 64, 24, dibIcon(64, 64, 24, 240, 170, 20)),
      (64, 64, 32, dibIcon(64, 64, 32, 170, 50, 210)),
    ]),
  );
  File('${root.path}/format_single.ico').writeAsBytesSync(
    icoContainer([(48, 48, 32, pngIcon(48, 48, 35, 90, 230))]),
  );
}

Uint8List pngIcon(int width, int height, int red, int green, int blue) {
  final image = imaging.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(x, y, red, green, blue, x < width ~/ 4 ? 0 : 255);
    }
  }
  return imaging.encodePng(image);
}

Uint8List dibIcon(
  int width,
  int height,
  int depth,
  int red,
  int green,
  int blue,
) {
  final paletteSize = depth <= 8 ? (1 << depth) * 4 : 0;
  final stride = ((width * depth + 31) ~/ 32) * 4;
  final maskStride = ((width + 31) ~/ 32) * 4;
  final bytes = Uint8List(40 + paletteSize + (stride + maskStride) * height);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 40, Endian.little);
  data.setInt32(4, width, Endian.little);
  data.setInt32(8, height * 2, Endian.little);
  data.setUint16(12, 1, Endian.little);
  data.setUint16(14, depth, Endian.little);
  if (paletteSize > 0) {
    bytes.setRange(40, 44, [blue, green, red, 0]);
  }
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (depth >= 24) {
        final at = 40 + paletteSize + y * stride + x * (depth ~/ 8);
        bytes.setRange(at, at + 3, [blue, green, red]);
        // Legacy 32-bit icons use zero alpha and rely on the AND mask.
      }
      if (x < width ~/ 4) {
        final at = 40 + paletteSize + stride * height + y * maskStride + x ~/ 8;
        bytes[at] |= 1 << (7 - x % 8);
      }
    }
  }
  return bytes;
}

Uint8List icoContainer(List<(int, int, int, Uint8List)> images) {
  final directorySize = 6 + images.length * 16;
  final bytes = Uint8List(
    directorySize + images.fold<int>(0, (n, i) => n + i.$4.length),
  );
  final data = ByteData.sublistView(bytes);
  data.setUint16(2, 1, Endian.little);
  data.setUint16(4, images.length, Endian.little);
  var offset = directorySize;
  for (var i = 0; i < images.length; i++) {
    final (width, height, depth, payload) = images[i];
    final at = 6 + i * 16;
    bytes[at] = width == 256 ? 0 : width;
    bytes[at + 1] = height == 256 ? 0 : height;
    data.setUint16(at + 4, 1, Endian.little);
    data.setUint16(at + 6, depth, Endian.little);
    data.setUint32(at + 8, payload.length, Endian.little);
    data.setUint32(at + 12, offset, Endian.little);
    bytes.setRange(offset, offset + payload.length, payload);
    offset += payload.length;
  }
  return bytes;
}
