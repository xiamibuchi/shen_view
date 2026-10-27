import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as imaging;

import 'codec_process.dart';
import 'decode_request.dart';
import 'hdr_frame.dart';
import 'hdr_input_metadata.dart';

class RawEmbeddedPreview {
  const RawEmbeddedPreview(this.bytes, this.width, this.height);
  final Uint8List bytes;

  /// Oriented dimensions declared by the container; the codec validates them.
  final int width;
  final int height;
}

/// Develop sensor CFA data in an isolated LibRaw process. The optional codec
/// cannot crash the viewer and shares the cancellation / process budget.
class RawDeveloper {
  static const maxPixels = 16 * 1024 * 1024;
  static const maxPreviewBytes = 32 * 1024 * 1024;
  static bool candidate(String path) => RegExp(
    r'\.(dng|cr2|cr3|nef|nrw|arw|sr2|orf|rw2|raf|pef|srw)$',
    caseSensitive: false,
  ).hasMatch(path);

  Future<Map<String, dynamic>> inspect(
    String path, {
    DecodeRequest? request,
  }) async {
    request?.throwIfCancelled();
    final helper = await CodecProcess.locate('viewer_raw', 'SHENVIEW_RAW');
    final bytes = await CodecProcess.run(
      helper,
      ['info', path],
      request: request,
      maxOutput: 16384,
    );
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  Future<RawEmbeddedPreview?> preview(
    String path, {
    DecodeRequest? request,
    int? targetWidth,
    int? targetHeight,
  }) async {
    request?.throwIfCancelled();
    final helper = await CodecProcess.locate('viewer_raw', 'SHENVIEW_RAW');
    final bytes = await CodecProcess.run(
      helper,
      ['preview', path, '${targetWidth ?? 0}', '${targetHeight ?? 0}'],
      request: request,
      maxOutput: maxPreviewBytes + 256,
    );
    final result = await compute(_preview, bytes);
    request?.throwIfCancelled();
    return result;
  }

  Future<Uint8List> decode(
    String path, {
    DecodeRequest? request,
    int? targetWidth,
    int? targetHeight,
  }) async {
    request?.throwIfCancelled();
    final helper = await CodecProcess.locate('viewer_raw', 'SHENVIEW_RAW');
    final bytes = await CodecProcess.run(
      helper,
      ['decode', path, '${targetWidth ?? 0}', '${targetHeight ?? 0}'],
      request: request,
      timeout: const Duration(seconds: 60),
      maxOutput: maxPixels * 6 + 256,
    );
    request?.throwIfCancelled();
    final result = await compute(_png, (bytes, targetWidth, targetHeight));
    request?.throwIfCancelled();
    return result;
  }

  Future<HdrFrame> decodeLinear(
    String path, {
    DecodeRequest? request,
    int? targetWidth,
    int? targetHeight,
  }) async {
    request?.throwIfCancelled();
    final helper = await CodecProcess.locate('viewer_raw', 'SHENVIEW_RAW');
    final bytes = await CodecProcess.run(
      helper,
      ['decode-linear', path, '${targetWidth ?? 0}', '${targetHeight ?? 0}'],
      request: request,
      timeout: const Duration(seconds: 60),
      maxOutput: 68 * 1024 * 1024,
    );
    request?.throwIfCancelled();
    final result = await compute(_linearFrame, bytes);
    request?.throwIfCancelled();
    return result;
  }
}

RawEmbeddedPreview? _preview(Uint8List bytes) {
  final end = bytes.indexOf(10);
  if (end < 0 || end > 128) throw const FormatException('RAW preview header');
  final fields = ascii.decode(bytes.sublist(0, end)).split(' ');
  if (fields.length == 2 && fields[0] == 'FVRAWP1' && fields[1] == 'NONE') {
    return null;
  }
  if (fields.length != 6 || fields.first != 'FVRAWP1') {
    throw const FormatException('RAW preview header');
  }
  final width = int.parse(fields[2]), height = int.parse(fields[3]);
  final flip = int.parse(fields[4]), length = int.parse(fields[5]);
  if (width < 1 ||
      height < 1 ||
      width * height > 100 * 1024 * 1024 ||
      flip < 0 ||
      flip > 7 ||
      length != bytes.length - end - 1 ||
      length > RawDeveloper.maxPreviewBytes) {
    throw const FormatException('RAW preview bounds');
  }
  var encoded = Uint8List.sublistView(bytes, end + 1);
  if (fields[1] == 'RGB8') {
    if (length != width * height * 3) {
      throw const FormatException('RAW preview RGB layout');
    }
    final image = imaging.Image.fromBytes(
      width: width,
      height: height,
      bytes: encoded.buffer,
      bytesOffset: encoded.offsetInBytes,
      numChannels: 3,
    );
    image.exif.imageIfd.orientation = [1, 2, 4, 3, 5, 8, 6, 7][flip];
    encoded = imaging.encodePng(imaging.bakeOrientation(image));
  } else if (fields[1] != 'JPEG') {
    throw const FormatException('RAW preview format');
  }
  return RawEmbeddedPreview(
    encoded,
    flip & 4 != 0 ? height : width,
    flip & 4 != 0 ? width : height,
  );
}

HdrFrame _linearFrame(Uint8List bytes) {
  final end = bytes.indexOf(10);
  if (end < 0 || end > 80) throw const FormatException('RAW linear header');
  final fields = ascii.decode(bytes.sublist(0, end)).split(' ');
  if (fields.length != 3 || fields.first != 'FVHDR32') {
    throw const FormatException('RAW linear header');
  }
  final width = int.tryParse(fields[1]);
  final height = int.tryParse(fields[2]);
  if (width == null ||
      height == null ||
      width < 1 ||
      height < 1 ||
      width * height > HdrFrame.maxPixels ||
      bytes.length - end - 1 != width * height * 16) {
    throw const FormatException('RAW linear budget');
  }
  return HdrFrame.fromRaw(bytes, encoding: HdrEncoding.sceneLinear);
}

Uint8List _png((Uint8List, int?, int?) input) {
  final bytes = input.$1;
  final end = bytes.indexOf(10);
  if (end < 0 || end > 80) throw const FormatException('RAW bitmap header');
  final fields = ascii.decode(bytes.sublist(0, end)).split(' ');
  if (fields.length != 3 || fields.first != 'FVRAW16') {
    throw const FormatException('RAW bitmap header');
  }
  final width = int.parse(fields[1]), height = int.parse(fields[2]);
  if (width < 1 ||
      height < 1 ||
      width * height > RawDeveloper.maxPixels ||
      bytes.length - end - 1 != width * height * 6) {
    throw const FormatException('RAW bitmap budget');
  }
  final data = ByteData.sublistView(bytes, end + 1);
  var image = imaging.Image(
    width: width,
    height: height,
    format: imaging.Format.uint16,
  );
  for (final p in image) {
    final offset = (p.y * width + p.x) * 6;
    p.setRgb(
      data.getUint16(offset, Endian.little),
      data.getUint16(offset + 2, Endian.little),
      data.getUint16(offset + 4, Endian.little),
    );
  }
  var scale = 1.0;
  if (input.$2 case final int width when width > 0) {
    scale = math.min(scale, width / image.width);
  }
  if (input.$3 case final int height when height > 0) {
    scale = math.min(scale, height / image.height);
  }
  if (scale < 1) {
    image = imaging.copyResize(
      image,
      width: math.max(1, (image.width * scale).floor()),
      height: math.max(1, (image.height * scale).floor()),
      interpolation: imaging.Interpolation.average,
    );
  }
  return imaging.encodePng(image);
}
