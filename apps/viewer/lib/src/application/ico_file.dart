import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as imaging;

import '../domain/image_resource_key.dart';
import 'decode_request.dart';

class IcoVariant {
  const IcoVariant({
    required this.index,
    required this.width,
    required this.height,
    required this.bitDepth,
    required this.codec,
    required this.hasAlpha,
    required this.offset,
    required this.byteLength,
  });

  final int index;
  final int width;
  final int height;
  final int bitDepth;
  final String codec;
  final bool? hasAlpha;
  final int offset;
  final int byteLength;
}

class IcoFile {
  static const maxEntryBytes = 2 * 1024 * 1024;
  static const maxEntries = 4096;

  static bool matches(List<int> bytes) =>
      bytes.length >= 6 &&
      bytes[0] == 0 &&
      bytes[1] == 0 &&
      bytes[2] == 1 &&
      bytes[3] == 0 &&
      (bytes[4] != 0 || bytes[5] != 0);

  static int largest(List<IcoVariant> variants) {
    var best = variants.first;
    for (final variant in variants.skip(1)) {
      final area = variant.width * variant.height;
      final bestArea = best.width * best.height;
      if (area > bestArea ||
          area == bestArea && variant.bitDepth > best.bitDepth) {
        best = variant;
      }
    }
    return best.index;
  }

  static Future<List<IcoVariant>> inspect(
    String path, {
    DecodeRequest? request,
  }) async {
    final file = await File(path).open();
    try {
      request?.throwIfCancelled();
      final header = await file.read(6);
      if (!matches(header)) throw const FormatException('Invalid ICO header');
      final count = ByteData.sublistView(header).getUint16(4, Endian.little);
      if (count > maxEntries) throw const FormatException('ICO entry limit');
      final directory = await file.read(count * 16);
      if (directory.length != count * 16) {
        throw const FormatException('Truncated ICO directory');
      }
      final data = ByteData.sublistView(directory);
      final length = await file.length();
      final variants = <IcoVariant>[];
      for (var index = 0; index < count; index++) {
        request?.throwIfCancelled();
        final at = index * 16;
        final width = directory[at] == 0 ? 256 : directory[at];
        final height = directory[at + 1] == 0 ? 256 : directory[at + 1];
        final size = data.getUint32(at + 8, Endian.little);
        final offset = data.getUint32(at + 12, Endian.little);
        if (size < 16 ||
            size > maxEntryBytes ||
            offset < 6 + count * 16 ||
            offset + size > length) {
          throw const FormatException('Invalid ICO entry bounds');
        }
        await file.setPosition(offset);
        final prefix = await file.read(size < 40 ? size : 40);
        final imageData = ByteData.sublistView(prefix);
        final png =
            prefix.length >= 26 &&
            prefix[0] == 0x89 &&
            prefix[1] == 0x50 &&
            prefix[2] == 0x4e &&
            prefix[3] == 0x47;
        int depth;
        bool? alpha;
        if (png) {
          if (imageData.getUint32(16) != width ||
              imageData.getUint32(20) != height) {
            throw const FormatException('ICO PNG dimensions mismatch');
          }
          final channels = switch (prefix[25]) {
            0 || 3 => 1,
            2 => 3,
            4 => 2,
            6 => 4,
            _ => throw const FormatException('Invalid ICO PNG color type'),
          };
          depth = prefix[24] * channels;
          alpha = prefix[25] == 4 || prefix[25] == 6 ? true : null;
        } else {
          if (prefix.length < 40 ||
              imageData.getUint32(0, Endian.little) < 40 ||
              imageData.getInt32(4, Endian.little) != width ||
              imageData.getInt32(8, Endian.little).abs() != height * 2) {
            throw const FormatException('Invalid ICO bitmap header');
          }
          depth = imageData.getUint16(14, Endian.little);
          alpha = true; // DIB icons carry an AND transparency mask.
        }
        variants.add(
          IcoVariant(
            index: index,
            width: width,
            height: height,
            bitDepth: depth,
            codec: png ? 'PNG' : 'BMP',
            hasAlpha: alpha,
            offset: offset,
            byteLength: size,
          ),
        );
      }
      return List.unmodifiable(variants);
    } finally {
      await file.close();
    }
  }

  static Future<Uint8List> decode(
    String path, {
    int? index,
    ImageRegion? region,
    DecodeRequest? request,
  }) async {
    final variants = await inspect(path, request: request);
    final selected = index ?? largest(variants);
    if (selected < 0 || selected >= variants.length) {
      throw const FormatException('Invalid ICO variant');
    }
    final variant = variants[selected];
    final file = await File(path).open();
    late final Uint8List payload;
    try {
      await file.setPosition(variant.offset);
      payload = await file.read(variant.byteLength);
    } finally {
      await file.close();
    }
    request?.throwIfCancelled();
    final result = await Isolate.run(() {
      // A single-entry container avoids decoding the other sizes as frames.
      final bytes = Uint8List(22 + payload.length);
      final header = ByteData.sublistView(bytes);
      header.setUint16(2, 1, Endian.little);
      header.setUint16(4, 1, Endian.little);
      bytes[6] = variant.width == 256 ? 0 : variant.width;
      bytes[7] = variant.height == 256 ? 0 : variant.height;
      header.setUint16(10, 1, Endian.little);
      header.setUint16(12, variant.bitDepth, Endian.little);
      header.setUint32(14, payload.length, Endian.little);
      header.setUint32(18, 22, Endian.little);
      bytes.setRange(22, bytes.length, payload);
      var image = imaging.IcoDecoder(maxPixels: 256 * 256)
          .decode(bytes, frame: 0);
      if (image == null) throw const FormatException('ICO decode failed');
      if (image.width != variant.width || image.height != variant.height) {
        throw const FormatException('ICO decoded dimensions mismatch');
      }
      if (variant.codec == 'BMP' && variant.bitDepth == 32) {
        final dib = ByteData.sublistView(payload);
        final stride = image.width * 4;
        final maskStride = ((image.width + 31) ~/ 32) * 4;
        final maskOffset =
            dib.getUint32(0, Endian.little) +
            dib.getUint32(32, Endian.little) * 4 +
            stride * image.height;
        final hasMask =
            maskOffset + maskStride * image.height <= payload.length;
        // Older 32-bit icons leave every alpha byte zero and use only AND.
        final legacy = !image.any((pixel) => pixel.a != 0);
        for (final pixel in image) {
          if (legacy) pixel.a = 255;
          final maskY = dib.getInt32(8, Endian.little) > 0
              ? image.height - pixel.y - 1
              : pixel.y;
          if (hasMask &&
              payload[maskOffset + maskY * maskStride + pixel.x ~/ 8] &
                      (1 << (7 - pixel.x % 8)) !=
                  0) {
            pixel.a = 0;
          }
        }
      }
      if (region != null) {
        if (region.left < 0 ||
            region.top < 0 ||
            region.width <= 0 ||
            region.height <= 0 ||
            region.left + region.width > image.width ||
            region.top + region.height > image.height) {
          throw const FormatException('Invalid ICO region');
        }
        image = imaging.copyCrop(
          image,
          x: region.left,
          y: region.top,
          width: region.width,
          height: region.height,
        );
      }
      return imaging.encodePng(image);
    });
    request?.throwIfCancelled();
    return result;
  }
}
