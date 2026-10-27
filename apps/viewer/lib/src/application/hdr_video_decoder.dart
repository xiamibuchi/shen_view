import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'codec_process.dart';
import 'decode_request.dart';
import 'hdr_frame.dart';
import 'hdr_input_metadata.dart';
import 'hdr_source_profile.dart';
import 'hdr_transfer.dart';
import 'hdr_video_worker.dart';

class HdrVideoDecoder {
  Future<HdrFrame> decode(
    String path,
    HdrInputMetadata info,
    DecodeRequest request,
  ) async {
    if (info.dolbyNeedsEnhancementLayer) {
      throw const FormatException('Dolby Vision enhancement layer required');
    }
    if (info.width == null || info.height == null) {
      throw const FormatException('HDR video dimensions');
    }
    if (info.encoding == HdrEncoding.hlg && info.primaries != 9) {
      throw const FormatException('HLG requires BT.2020 primaries');
    }
    final scale = math.min(1.0, 2048 / math.max(info.width!, info.height!));
    final width = (info.width! * scale).floor().clamp(1, 2048);
    final height = (info.height! * scale).floor().clamp(1, 2048);
    final dolby = info.encoding == HdrEncoding.dolbyVision;
    Future<Uint8List> rawProcess() async {
      final ffmpeg = await CodecProcess.locate('ffmpeg', 'SHENVIEW_FFMPEG');
      final filter = dolby
          ? 'libplacebo=w=$width:h=$height:apply_dolbyvision=1:format=rgba64le:colorspace=0:color_primaries=9:color_trc=16:range=2:tonemapping=clip:peak_detect=0'
          : 'zscale=w=$width:h=$height:matrix=0:range=full,format=gbrp16le,format=rgba64le';
      return CodecProcess.run(
        ffmpeg,
        [
          '-hide_banner',
          '-loglevel',
          'error',
          '-nostdin',
          '-threads',
          '2',
          '-i',
          path,
          '-map',
          '0:v:0',
          '-vf',
          filter,
          '-frames:v',
          '1',
          '-an',
          '-c:v',
          'rawvideo',
          '-pix_fmt',
          'rgba64le',
          '-f',
          'rawvideo',
          'pipe:1',
        ],
        request: request,
        maxOutput: width * height * 8,
      );
    }

    late final Uint8List bytes;
    if (dolby) {
      try {
        bytes = await HdrVideoWorker.shared.decode(
          path,
          width: width,
          height: height,
          sourceWidth: info.width!,
          sourceHeight: info.height!,
          request: request,
        );
      } on HdrWorkerUnavailable {
        // Developer macOS setups may only provide the existing CLI runtime.
        bytes = await rawProcess();
      }
    } else {
      bytes = await rawProcess();
    }
    request.throwIfCancelled();
    if (bytes.length != width * height * 8) {
      throw const FormatException('Truncated HDR RGBA16 frame');
    }
    return compute(_parse, (
      TransferableTypedData.fromList([bytes]),
      dolby ? HdrEncoding.pq : info.encoding,
      info.primaries,
      width,
      height,
    ));
  }
}

HdrFrame _parse((TransferableTypedData, HdrEncoding, int, int, int) input) =>
    HdrFrame.fromRgba16(
      input.$1.materialize().asUint8List(),
      width: input.$4,
      height: input.$5,
      encoding: input.$2,
      colorTransform: HdrSourceProfile.toLinear709(switch (input.$3) {
        9 => HdrTransfer.rec2020,
        12 => HdrTransfer.displayP3,
        1 => HdrSourceProfile.rec709,
        _ => throw const FormatException('Unsupported HDR video primaries'),
      }),
    );
