import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/codec_process.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/hdr_video_decoder.dart';
import 'package:shen_view/src/application/hdr_video_worker.dart';
import 'package:shen_view/src/application/hdr_input_metadata.dart';

void main() {
  String? helper, ffmpeg;
  final sample = File('testdata/formats/hdr_dovi_p81.hevc').absolute.path;
  setUpAll(() async {
    try {
      helper = await CodecProcess.locate(
        'viewer_hdr_video',
        'SHENVIEW_HDR_VIDEO',
      );
      ffmpeg = await CodecProcess.locate('ffmpeg', 'SHENVIEW_FFMPEG');
    } catch (_) {
      /* Optional on platforms without a native runtime. */
    }
  });

  test('native GPU owner matches the existing Dolby filter across files and sizes', () async {
    if (helper == null || ffmpeg == null) {
      markTestSkipped('需要 HDR video helper 和 FFmpeg');
      return;
    }
    var starts = 0;
    final worker = HdrVideoWorker(
      startProcess: () async {
        starts++;
        return Process.start(helper!, const []);
      },
    );
    addTearDown(worker.close);
    final directory = await Directory.systemTemp.createTemp('shenview-dolby-');
    addTearDown(() => directory.delete(recursive: true));
    final copy = await File(sample)
        .copy(directory.uri.resolve('不同文件 空格.hevc').toFilePath());
    final times = <Map<String, Object>>[];
    for (final size in [(384, 192), (128, 64), (256, 128), (384, 192)]) {
      final path = times.length.isEven ? sample : copy.path;
      final watch = Stopwatch()..start();
      final pixels = await worker.decode(
        path,
        width: size.$1,
        height: size.$2,
        sourceWidth: 384,
        sourceHeight: 192,
        request: DecodeRequest(),
      );
      watch.stop();
      times.add({
        'width': size.$1,
        'height': size.$2,
        'ms': watch.elapsedMicroseconds / 1000,
      });
      final width = size.$1, height = size.$2;
      final filter =
          'libplacebo=w=$width:h=$height:apply_dolbyvision=1:format=rgba64le:colorspace=0:color_primaries=9:color_trc=16:range=2:tonemapping=clip:peak_detect=0';
      final baseline = await CodecProcess.run(ffmpeg!, [
        '-v',
        'error',
        '-nostdin',
        '-threads',
        '2',
        '-i',
        sample,
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
      ], maxOutput: size.$1 * size.$2 * 8);
      expect(pixels, baseline, reason: size.toString());
    }
    expect(starts, 1);
    debugPrint(jsonEncode({'event': 'native-dolby-worker', 'timings': times}));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('native cancellation drains, memory trim reinitializes and process stays usable', () async {
    if (helper == null) {
      markTestSkipped('需要 HDR video helper');
      return;
    }
    var starts = 0;
    final worker = HdrVideoWorker(
      startProcess: () async {
        starts++;
        return Process.start(helper!, const []);
      },
    );
    addTearDown(worker.close);
    Future<Uint8List> decode(int width, int height, DecodeRequest request) =>
        worker.decode(
          sample,
          width: width,
          height: height,
          sourceWidth: 384,
          sourceHeight: 192,
          request: request,
        );
    final before = await decode(384, 192, DecodeRequest());
    final request = DecodeRequest();
    final cancelled = decode(2048, 1024, request);
    final checked = expectLater(cancelled, throwsA(isA<DecodeCancelled>()));
    await Future<void>.delayed(const Duration(milliseconds: 1));
    request.cancel();
    await checked;
    expect(await decode(384, 192, DecodeRequest()), before);
    worker.releaseGpu();
    expect(await decode(384, 192, DecodeRequest()), before);
    expect(starts, 1);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test(
    'Dolby decoder returns linear HDR directly from raw transport',
    () async {
      if (helper == null) {
        markTestSkipped('需要 HDR video helper');
        return;
      }
      addTearDown(HdrVideoWorker.shared.close);
      final info = await HdrInputMetadata.readVideo(sample);
      final times = <double>[];
      for (var i = 0; i < 3; i++) {
        final watch = Stopwatch()..start();
        final frame = await HdrVideoDecoder().decode(
          sample,
          info,
          DecodeRequest(),
        );
        watch.stop();
        times.add(watch.elapsedMicroseconds / 1000);
        expect((frame.width, frame.height), (384, 192));
        expect(
          ByteData.sublistView(frame.pixels)
              .getFloat32(383 * 16, Endian.little),
          greaterThan(1),
        );
      }
      debugPrint(jsonEncode({'event': 'dolby-linear-frame', 'ms': times}));
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
