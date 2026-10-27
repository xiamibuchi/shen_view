import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as imaging;

import 'codec_process.dart';
import 'hdr_frame.dart';
import 'hdr_input_metadata.dart';
import 'hdr_source_profile.dart';
import 'hdr_transfer.dart';
import 'hdr_video_decoder.dart';
import 'native_decoder.dart';
import 'raw_developer.dart';

class HdrDecoder {
  HdrDecoder({NativeDecoder? decoder}) : _decoder = decoder ?? NativeDecoder();
  final NativeDecoder _decoder;

  Future<HdrFrame> decode(
    String path,
    DecodeRequest request, {
    HdrInputMetadata? metadata,
  }) async {
    final info =
        metadata ?? await HdrInputMetadata.read(path, request: request);
    request.throwIfCancelled();
    if (!info.isHdr) {
      throw const FormatException('Input has no supported HDR signal');
    }
    if (RawDeveloper.candidate(path)) {
      return RawDeveloper().decodeLinear(path, request: request);
    }
    if (info.encoding == HdrEncoding.gainMap) {
      final isHeif = RegExp(
        r'\.(heic|heif)$',
        caseSensitive: false,
      ).hasMatch(path);
      final helper = await CodecProcess.locate(
        isHeif ? 'viewer_heif_gainmap' : 'viewer_gainmap',
        isHeif ? 'SHENVIEW_HEIF_GAINMAP' : 'SHENVIEW_GAINMAP',
      );
      final bytes = await CodecProcess.run(helper, [
        'decode',
        path,
      ], request: request);
      request.throwIfCancelled();
      return compute(_gainMapFrame, bytes);
    }
    if (info.encoding == HdrEncoding.dolbyVision) {
      final video = info.width == null
          ? await HdrInputMetadata.readVideo(path, request: request)
          : info;
      if (video.encoding != HdrEncoding.dolbyVision) {
        throw const FormatException('Missing parsed Dolby Vision metadata');
      }
      return HdrVideoDecoder().decode(path, video, request);
    }
    if (info.width != null && info.height != null) {
      return HdrVideoDecoder().decode(path, info, request);
    }
    if (info.encoding == HdrEncoding.hlg && info.primaries != 9) {
      throw const FormatException('HLG requires BT.2020 primaries');
    }
    final matrix = info.encoding == HdrEncoding.sceneLinear
        ? await HdrSourceProfile.read(path)
        : HdrSourceProfile.toLinear709(switch (info.primaries) {
            9 => HdrTransfer.rec2020,
            12 => HdrTransfer.displayP3,
            1 => HdrSourceProfile.rec709,
            _ => throw const FormatException('Unsupported HDR primaries'),
          });
    final bytes = await _decoder.run([
      '$path[0]',
      '-auto-orient',
      '-resize',
      '2048x2048>',
      '-set',
      'colorspace',
      'RGB',
      '-alpha',
      'on',
      '-format',
      'FVHDR32 %w %h\n',
      '-write',
      'info:-',
      '-define',
      'quantum:format=floating-point',
      '-depth',
      '32',
      '-endian',
      'LSB',
      'rgba:-',
    ], request: request);
    request.throwIfCancelled();
    final frame = await compute(_parse, (bytes, matrix, info.encoding));
    request.throwIfCancelled();
    return frame;
  }

  static Future<Uint8List> sdrPng(HdrFrame frame) => compute(_sdrPng, frame);
}

HdrFrame _parse((Uint8List, List<double>?, HdrEncoding) input) =>
    HdrFrame.fromRaw(input.$1, colorTransform: input.$2, encoding: input.$3);

HdrFrame _gainMapFrame(Uint8List bytes) {
  final end = bytes.indexOf(10);
  if (end < 0 || end > 128) throw const FormatException('Gain map header');
  final fields = ascii.decode(bytes.sublist(0, end)).split(' ');
  if (fields.length != 4 || fields[0] != 'FVGAIN32') {
    throw const FormatException('Gain map header');
  }
  final primaries = switch (int.parse(fields[3])) {
    0 => HdrSourceProfile.rec709,
    1 => HdrTransfer.displayP3,
    2 => HdrTransfer.rec2020,
    _ => throw const FormatException('Gain map gamut'),
  };
  final header = 'FVHDR32 ${fields[1]} ${fields[2]}\n';
  final data =
      (BytesBuilder()
            ..add(ascii.encode(header))
            ..add(bytes.sublist(end + 1)))
          .takeBytes();
  return HdrFrame.fromRaw(
    data,
    colorTransform: HdrSourceProfile.toLinear709(primaries),
  );
}

Uint8List _sdrPng(HdrFrame frame) {
  final image = imaging.Image(
    width: frame.width,
    height: frame.height,
    numChannels: 4,
  );
  final data = ByteData.sublistView(frame.pixels);
  for (var i = 0; i < frame.width * frame.height; i++) {
    final a = data.getFloat32(i * 16 + 12, Endian.little).clamp(0.0, 1.0);
    int channel(int c) {
      final value = a == 0
          ? 0.0
          : (data.getFloat32(i * 16 + c * 4, Endian.little) / a).clamp(
              0.0,
              65504.0,
            );
      return (HdrTransfer.linearToSrgb(value / (1 + value)) * 255)
          .round()
          .clamp(0, 255);
    }

    image.setPixelRgba(
      i % frame.width,
      i ~/ frame.width,
      channel(0),
      channel(1),
      channel(2),
      (a * 255).round(),
    );
  }
  return imaging.encodePng(image);
}
