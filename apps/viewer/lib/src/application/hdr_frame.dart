import 'dart:typed_data';

import 'hdr_input_metadata.dart';
import 'hdr_transfer.dart';

/// Display-referred, linear Rec.709 RGB. 1.0 is the chosen reference white,
/// not the maximum channel value. Bytes are top-down little-endian RGBA float.
class HdrFrame {
  const HdrFrame(
    this.width,
    this.height,
    this.pixels, {
    this.hasTransparency = false,
  });

  static const maxPixels = 4 * 1024 * 1024;
  final int width;
  final int height;
  final Uint8List pixels;
  final bool hasTransparency;

  /// Parses ImageMagick's size header followed by straight-alpha float pixels.
  /// Alpha premultiplication and invalid-sample cleanup run off the UI isolate.
  static HdrFrame fromRaw(
    Uint8List data, {
    List<double>? colorTransform,
    HdrEncoding encoding = HdrEncoding.sceneLinear,
  }) {
    final newline = data.indexOf(10);
    if (newline < 0 || newline > 128) {
      throw const FormatException('HDR float header');
    }
    final header = String.fromCharCodes(data.sublist(0, newline)).split(' ');
    if (header.length != 3 || header[0] != 'FVHDR32') {
      throw const FormatException('HDR float header');
    }
    final width = int.parse(header[1]), height = int.parse(header[2]);
    final offset = newline + 1;
    if (width < 1 ||
        height < 1 ||
        width * height > maxPixels ||
        data.length - offset != width * height * 16) {
      throw const FormatException('HDR float bounds');
    }
    return _fromPixels(
      width,
      height,
      ByteData.sublistView(data),
      offset,
      unsigned16: false,
      colorTransform: colorTransform,
      encoding: encoding,
    );
  }

  static HdrFrame fromRgba16(
    Uint8List data, {
    required int width,
    required int height,
    required HdrEncoding encoding,
    List<double>? colorTransform,
  }) {
    if (width < 1 ||
        height < 1 ||
        width * height > maxPixels ||
        data.length != width * height * 8) {
      throw const FormatException('HDR RGBA16 bounds');
    }
    return _fromPixels(
      width,
      height,
      ByteData.sublistView(data),
      0,
      unsigned16: true,
      colorTransform: colorTransform,
      encoding: encoding,
    );
  }

  static HdrFrame _fromPixels(
    int width,
    int height,
    ByteData input,
    int offset, {
    required bool unsigned16,
    required HdrEncoding encoding,
    List<double>? colorTransform,
  }) {
    if (colorTransform != null && colorTransform.length != 9) {
      throw const FormatException('HDR color matrix');
    }
    final result = Uint8List(width * height * 16);
    final output = ByteData.sublistView(result);
    if (colorTransform != null &&
        colorTransform.any((value) => !value.isFinite)) {
      throw const FormatException('HDR color matrix');
    }
    var hasTransparency = false;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final source = offset + (y * width + x) * (unsigned16 ? 8 : 16);
        final target = (y * width + x) * 16;
        double channel(int c) => unsigned16
            ? input.getUint16(source + c * 2, Endian.little) / 65535
            : input.getFloat32(source + c * 4, Endian.little);
        final rawAlpha = channel(3);
        final alpha = rawAlpha.isFinite ? rawAlpha.clamp(0.0, 1.0) : 0.0;
        hasTransparency |= alpha < 1;
        var rgb = [for (var c = 0; c < 3; c++) channel(c)];
        if (encoding == HdrEncoding.pq) {
          rgb = rgb
              .map((v) => HdrTransfer.pqToNits(v) / HdrTransfer.referenceWhite)
              .toList();
        } else if (encoding == HdrEncoding.hlg) {
          rgb = HdrTransfer.hlgToDisplayLinear2020(rgb);
        }
        for (var c = 0; c < 3; c++) {
          final value = rgb[c];
          // Invalid EXR samples must not poison a whole GPU render target.
          output.setFloat32(
            target + c * 4,
            value.isFinite ? value.clamp(-65504, 65504) * alpha : 0,
            Endian.little,
          );
        }
        output.setFloat32(target + 12, alpha, Endian.little);
        if (colorTransform != null) {
          final r = output.getFloat32(target, Endian.little);
          final g = output.getFloat32(target + 4, Endian.little);
          final b = output.getFloat32(target + 8, Endian.little);
          for (var c = 0; c < 3; c++) {
            final value =
                colorTransform[c * 3] * r +
                colorTransform[c * 3 + 1] * g +
                colorTransform[c * 3 + 2] * b;
            output.setFloat32(
              target + c * 4,
              value.isFinite ? value.clamp(-65504, 65504) : 0,
              Endian.little,
            );
          }
        }
      }
    }
    return HdrFrame(width, height, result, hasTransparency: hasTransparency);
  }
}
