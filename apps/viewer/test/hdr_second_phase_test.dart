import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/hdr_frame.dart';
import 'package:shen_view/src/application/hdr_decoder.dart';
import 'package:shen_view/src/application/native_decoder.dart';
import 'package:shen_view/src/application/codec_process.dart';
import 'package:shen_view/src/application/hdr_input_metadata.dart';
import 'package:shen_view/src/application/hdr_transfer.dart';
import 'package:shen_view/src/application/hdr_video_decoder.dart';
import 'package:shen_view/src/application/metadata_service.dart';

void main() {
  test('primary item metadata is not replaced by SDR thumbnail properties', () {
    Uint8List box(String type, List<int> payload) {
      final bytes = Uint8List(payload.length + 8);
      ByteData.sublistView(bytes).setUint32(0, bytes.length);
      bytes.setRange(4, 8, ascii.encode(type));
      bytes.setRange(8, bytes.length, payload);
      return bytes;
    }

    final primary = box('pitm', [0, 0, 0, 0, 0, 1]);
    final hdr = box('colr', [...ascii.encode('nclx'), 0, 9, 0, 16, 0, 0, 128]);
    final sdr = box('colr', [...ascii.encode('nclx'), 0, 1, 0, 13, 0, 0, 128]);
    final ipco = box('ipco', [...hdr, ...sdr]);
    final ipma = box('ipma', [0, 0, 0, 0, 0, 0, 0, 2, 0, 1, 1, 1, 0, 2, 1, 2]);
    final result = HdrInputMetadata.fromIsoMeta(
      Uint8List.fromList([
        0,
        0,
        0,
        0,
        ...primary,
        ...box('iprp', [...ipco, ...ipma]),
      ]),
    );
    expect(result.encoding, HdrEncoding.pq);
    expect(result.primaries, 9);
  });

  test('metadata distinguishes SDR files from HDR images', () async {
    final info = await MetadataService().read(
      'testdata/formats/format_static.png',
    );
    expect(info.isHdr, false);
    final pq = await MetadataService().read('testdata/formats/hdr_pq.png');
    expect(pq.isHdr, true);
    expect(pq.hdrEncoding, HdrEncoding.pq);
  });

  test('cancelled HDR operations do not launch optional codecs', () async {
    final request = DecodeRequest()..cancel();
    await expectLater(
      CodecProcess.run('missing-codec', const [], request: request),
      throwsA(isA<DecodeCancelled>()),
    );
  });

  test(
    'a malformed HDR PNG does not silently change the transfer function',
    () {
      final bytes = File('testdata/formats/hdr_pq.png').readAsBytesSync();
      final at = ascii.decode(bytes, allowInvalid: true).indexOf('cICP');
      bytes[at + 5] = 18;
      expect(() => HdrInputMetadata.fromBytes(bytes), throwsFormatException);
    },
  );

  test('HEIF ISO gain map reconstructs the linked enhancement image', () async {
    final path = File('testdata/formats/hdr_gain_map.heic').absolute.path;
    final info = await HdrInputMetadata.read(path);
    expect(info.encoding, HdrEncoding.gainMap);
    expect(
      (await HdrInputMetadata.read('testdata/formats/hdr_gain_map.heif'))
          .encoding,
      HdrEncoding.gainMap,
    );
    late final String helper;
    try {
      helper = await CodecProcess.locate(
        'viewer_heif_gainmap',
        'SHENVIEW_HEIF_GAINMAP',
      );
    } catch (_) {
      markTestSkipped('需要 libheif HEIF Gain Map 解码组件');
      return;
    }
    final raw = await CodecProcess.run(helper, ['decode', path]);
    final headerEnd = raw.indexOf(10);
    expect(utf8.decode(raw.sublist(0, headerEnd)), 'FVGAIN32 700 476 0');
    final frame = await HdrDecoder().decode(
      path,
      DecodeRequest(),
      metadata: info,
    );
    expect(frame.width, 700);
    expect(frame.height, 476);
    final values = ByteData.sublistView(frame.pixels);
    var maximum = 0.0;
    for (var i = 0; i < frame.width * frame.height; i++) {
      for (var c = 0; c < 3; c++) {
        maximum = math.max(
          maximum,
          values.getFloat32(i * 16 + c * 4, Endian.little),
        );
      }
    }
    expect(maximum, greaterThan(1));
  }, timeout: const Timeout(Duration(seconds: 60)));
  test(
    'real PQ/HLG, gain-map and Dolby Vision inputs retain HDR values',
    () async {
      try {
        await NativeDecoder().executable();
        await CodecProcess.locate('viewer_gainmap', 'SHENVIEW_GAINMAP');
        await CodecProcess.locate('ffmpeg', 'SHENVIEW_FFMPEG');
      } catch (_) {
        markTestSkipped('需要完整 HDR 解码组件');
        return;
      }
      final decoder = HdrDecoder();
      for (final file in [
        'hdr_pq.png',
        'hdr_hlg.png',
        'hdr_pq.avif',
        'hdr_hlg.avif',
        'hdr_pq_alpha.png',
        'hdr_gain_map.jpg',
        'hdr_dovi_p81.hevc',
      ]) {
        final frame = await decoder.decode(
          File('testdata/formats/$file').absolute.path,
          DecodeRequest(),
        );
        expect(frame.width, 384, reason: file);
        expect(frame.height, 192, reason: file);
        final values = ByteData.sublistView(frame.pixels);
        expect(
          values.getFloat32(383 * 16, Endian.little),
          greaterThan(1),
          reason: file,
        );
        if (file == 'hdr_pq.png' ||
            file == 'hdr_hlg.png' ||
            file.endsWith('.avif')) {
          // Authored absolute luminance, checked at every neutral patch and
          // on all channels. A bright last pixel alone misses gamma/exposure
          // errors in midtones and channel-dependent color casts.
          const nits = [0.0, 100.0, 203.0, 400.0, 700.0, 1000.0];
          for (var patch = 0; patch < nits.length; patch++) {
            for (var c = 0; c < 3; c++) {
              expect(
                values.getFloat32(
                  (32 * frame.width + patch * 64 + 32) * 16 + c * 4,
                  Endian.little,
                ),
                // AVIF is a lossy fixture: allow 2% luminance error plus
                // quantization near black, not an arbitrary exposure shift.
                closeTo(
                  nits[patch] / 203,
                  file.endsWith('.avif')
                      ? nits[patch] / 203 * 0.02 + 0.01
                      : 0.01,
                ),
                reason: '$file neutral patch $patch channel $c',
              );
            }
          }
          // PQ fixtures start in linear Rec.709; HLG fixtures deliberately
          // author the color in Rec.2020. Fixed converted values below are
          // independent of the production matrix/transfer implementation.
          final expected = file.startsWith('hdr_hlg')
              ? [1.510432, 0.158258, 0.012629]
              : [1.0, 0.25, 0.05];
          for (var c = 0; c < 3; c++) {
            expect(
              values.getFloat32(
                (96 * frame.width + 160) * 16 + c * 4,
                Endian.little,
              ),
              closeTo(expected[c], 0.04),
              reason: '$file colored patch channel $c',
            );
          }
        }
        if (file == 'hdr_pq_alpha.png') {
          expect(frame.hasTransparency, true);
          for (final probe in [(32, 0.0), (160, 0.5), (352, 1.0)]) {
            final at = (32 * frame.width + probe.$1) * 16;
            expect(
              values.getFloat32(at + 12, Endian.little),
              closeTo(probe.$2, 0.001),
            );
          }
          // Half-transparent 203-nit patch must be premultiplied once.
          expect(
            values.getFloat32((32 * frame.width + 160) * 16, Endian.little),
            closeTo(0.5, 0.01),
          );
        }
        if (file == 'hdr_gain_map.jpg') {
          const stops = [0.18, 1.0, 2.0, 4.0, 8.0, 16.0];
          for (var patch = 0; patch < stops.length; patch++) {
            final expected = stops[patch] * (0.65 + 0.35 * 32 / 63);
            for (var c = 0; c < 3; c++) {
              expect(
                values.getFloat32(
                  (32 * frame.width + patch * 64 + 32) * 16 + c * 4,
                  Endian.little,
                ),
                closeTo(expected, expected * 0.05 + 0.03),
                reason: '$file reconstructed patch $patch channel $c',
              );
            }
          }
        }
      }
    },
    timeout: const Timeout(Duration(seconds: 100)),
  );

  test('FFmpeg converts PQ and HLG YUV frames without clipping HDR', () async {
    try {
      await CodecProcess.locate('ffmpeg', 'SHENVIEW_FFMPEG');
      await CodecProcess.locate('ffprobe', 'SHENVIEW_FFPROBE');
    } catch (_) {
      markTestSkipped('需要 FFmpeg 与 ffprobe');
      return;
    }
    for (final sample in [
      ('hdr_pq.avif', HdrEncoding.pq),
      ('hdr_hlg.avif', HdrEncoding.hlg),
    ]) {
      final path = File('testdata/formats/${sample.$1}').absolute.path;
      final metadata = await HdrInputMetadata.readVideo(path);
      expect(metadata.encoding, sample.$2);
      final frame = await HdrVideoDecoder().decode(
        path,
        metadata,
        DecodeRequest(),
      );
      expect((frame.width, frame.height), (384, 192));
      final values = ByteData.sublistView(frame.pixels);
      expect(values.getFloat32(383 * 16, Endian.little), greaterThan(1));
    }
  });

  test(
    'bundled second-phase fixtures advertise their transfer standards',
    () async {
      final pq = HdrInputMetadata.fromBytes(
        File('testdata/formats/hdr_pq.png').readAsBytesSync(),
      );
      expect(pq.encoding, HdrEncoding.pq);
      final hlg = HdrInputMetadata.fromBytes(
        File('testdata/formats/hdr_hlg.png').readAsBytesSync(),
      );
      expect(hlg.encoding, HdrEncoding.hlg);
      final gainMap = HdrInputMetadata.fromBytes(
        File('testdata/formats/hdr_gain_map.jpg').readAsBytesSync(),
      );
      expect(gainMap.encoding, HdrEncoding.gainMap);
      final avifPq = await HdrInputMetadata.read(
        'testdata/formats/hdr_pq.avif',
      );
      expect(avifPq.encoding, HdrEncoding.pq);
      expect(avifPq.primaries, 9);
      final avifHlg = await HdrInputMetadata.read(
        'testdata/formats/hdr_hlg.avif',
      );
      expect(avifHlg.encoding, HdrEncoding.hlg);
    },
  );

  test(
    'AVIF ISO gain map metadata and synthesis are exercised by a real item',
    () async {
      final info = await HdrInputMetadata.read(
        'testdata/formats/hdr_gain_map.avif',
      );
      expect(info.encoding, HdrEncoding.gainMap);
      try {
        await CodecProcess.locate('viewer_gainmap', 'SHENVIEW_GAINMAP');
      } catch (_) {
        markTestSkipped('需要 libavif/AOM Gain Map 解码组件');
        return;
      }
      final frame = await HdrDecoder().decode(
        File('testdata/formats/hdr_gain_map.avif').absolute.path,
        DecodeRequest(),
        metadata: info,
      );
      expect(frame.width, 192);
      expect(frame.height, 96);
      final values = ByteData.sublistView(frame.pixels);
      // Encoded base 188/255 is ~0.5029 linear. The gain map stores 0,
      // 127/255 and 1, with max log2 gain 3. Check the actual reconstruction,
      // not merely a file tag or a non-black image.
      expect(values.getFloat32(32 * 16, Endian.little), closeTo(0.5029, 0.003));
      expect(values.getFloat32(96 * 16, Endian.little), closeTo(1.416, 0.01));
      expect(values.getFloat32(160 * 16, Endian.little), closeTo(4.023, 0.01));
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('PQ and HLG transfer functions retain absolute highlight ordering', () {
    expect(HdrTransfer.pqToNits(0), 0);
    expect(HdrTransfer.pqToNits(HdrTransfer.nitsToPq(203)), closeTo(203, 0.01));
    expect(
      HdrTransfer.pqToNits(HdrTransfer.nitsToPq(1000)),
      closeTo(1000, 0.1),
    );
    expect(HdrTransfer.hlgToScene(0), 0);
    expect(HdrTransfer.hlgToScene(1), greaterThan(HdrTransfer.hlgToScene(0.5)));
  });

  test('PQ frame decoding applies EOTF before the native upload', () {
    final raw = ByteData(16);
    raw.setFloat32(0, HdrTransfer.nitsToPq(203), Endian.little);
    raw.setFloat32(4, HdrTransfer.nitsToPq(203), Endian.little);
    raw.setFloat32(8, HdrTransfer.nitsToPq(203), Endian.little);
    raw.setFloat32(12, 1, Endian.little);
    final bytes =
        (BytesBuilder()
              ..add('FVHDR32 1 1\n'.codeUnits)
              ..add(raw.buffer.asUint8List()))
            .takeBytes();
    final frame = HdrFrame.fromRaw(bytes, encoding: HdrEncoding.pq);
    expect(
      ByteData.sublistView(frame.pixels).getFloat32(0, Endian.little),
      closeTo(1, 0.001),
    );
  });

  test('PNG HDR metadata rejects limited-range cICP', () {
    final bytes = Uint8List.fromList([
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
      0,
      0,
      0,
      4,
      99,
      73,
      67,
      80,
      9,
      16,
      1,
      0,
    ]);
    expect(() => HdrInputMetadata.fromBytes(bytes), throwsFormatException);
  });
}
