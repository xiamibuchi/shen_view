import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/codec_process.dart';

import '../tool/verify_hdr_avif.dart' as verifier;

void main() {
  for (final hlg in [false, true]) {
    final name = hlg ? 'hdr_hlg.avif' : 'hdr_pq.avif';
    test(
      'independent AV1 decoder preserves every authored color patch: $name',
      () async {
        try {
          await CodecProcess.locate('ffprobe', 'SHENVIEW_FFPROBE');
          await CodecProcess.locate('ffmpeg', 'SHENVIEW_FFMPEG');
        } catch (_) {
          markTestSkipped('需要 FFmpeg（含 zscale、AV1 解码器）和 ffprobe');
          return;
        }
        final report = await verifier.verifyHdrAvif(
          File('testdata/formats/$name'),
          hlg: hlg,
          output: Directory('../../artifacts/hdr-color-check'),
        );
        expect(
          report['maxSignalError'],
          lessThanOrEqualTo(0.004),
          reason: '$report',
        );
        expect(
          report['expectedTagsMatch'],
          isTrue,
          reason: '${report['metadata']}',
        );
        expect(report['passed'], isTrue);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }
}
