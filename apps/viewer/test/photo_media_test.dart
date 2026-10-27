import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/media_container.dart';
import 'package:shen_view/src/application/photo_media_info.dart';
import 'package:shen_view/src/application/photo_media_codec.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/metadata_service.dart';
import 'package:shen_view/src/application/codec_process.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const root = 'testdata/photo_media';
  test('existing static JPEG metadata retains single-image behavior', () async {
    final metadata = await MetadataService().read(
      'testdata/formats/format_static.jpg',
    );
    expect(metadata.readable, isTrue);
    expect(metadata.animation?.frameCount ?? 1, 1);
    expect(metadata.media, isNull);
  });
  test('ordinary JPEG does not become a video', () async {
    expect(await MediaContainer.inspect('$root/cover.jpg'), isNull);
    expect((await MetadataService().read('$root/cover.jpg')).animation, isNull);
  });
  for (final name in [
    'motion-h264.jpg',
    'motion-hevc.jpg',
    'motion-av1.jpg',
    'motion-directory.jpg',
    'motion-samsung.jpg',
    'motion-heic.heic',
    'sequence.heic',
    'sequence-alpha-depth.heic',
    'motion-offset.jpg',
    'motion-hevc-main10-pq-aac.jpg',
    'motion-hevc-main10-hlg-aac.jpg',
    'motion-av1-main10-pq-aac.jpg',
  ]) {
    test('real FFmpeg decode, seek and lifetime: $name', () async {
      final path = '$root/$name';
      final info = await PhotoMediaInfo.inspect(path);
      expect(info, isNotNull);
      expect(info!.animated, isTrue);
      expect(info.timeline.durationMs, inInclusiveRange(900, 2100));
      expect(info.timestampsUs.first, 0);
      final request = DecodeRequest();
      var released = false;
      final codec = await PhotoMediaCodec.open(
        path,
        info,
        targetWidth: 64,
        targetHeight: 64,
        request: request,
        releaseFile: () async {
          released = true;
        },
      );
      final first = await codec.getFrame(0);
      expect(first.image.width, lessThanOrEqualTo(64));
      final bytes = (await first.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      expect(
        bytes.buffer.asUint8List().where((b) => b != 0).length,
        greaterThan(100),
      );
      first.image.dispose();
      final last = await codec.getFrame(codec.frameCount - 1);
      last.image.dispose();
      final back = await codec.getFrame(1);
      back.image.dispose();
      request.cancel();
      await expectLater(codec.getFrame(0), throwsA(isA<DecodeCancelled>()));
      for (var i = 0; i < 100 && !released; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(released, isTrue);
      final metadata = await MetadataService().read(path);
      expect(metadata.animation?.frameCount, info.timeline.durations.length);
      expect(metadata.media?.codec, info.codec);
    });
  }
  test('single timed HEIF sample has no playback controls metadata', () async {
    final metadata = await MetadataService().read('$root/single.heic');
    expect(metadata.media, isNotNull);
    expect(metadata.animation, isNull);
  });
  for (final name in [
    'motion-h264.jpg',
    'motion-hevc.jpg',
    'motion-av1.jpg',
    'sequence-alpha-depth.heic',
    'motion-offset.jpg',
  ]) {
    test('indexed seek matches sequential presentation order: $name', () async {
      final path = '$root/$name';
      final info = (await PhotoMediaInfo.inspect(path))!;
      final codec = await PhotoMediaCodec.open(path, info);
      final expected = <int, List<int>>{};
      for (var i = 0; i < codec.frameCount; i++) {
        final frame = await codec.getNextFrame();
        if ({0, 2, 5, 13, codec.frameCount - 1}.contains(i)) {
          expected[i] = (await frame.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List().toList();
        }
        frame.image.dispose();
      }
      for (final index in expected.keys.toList().reversed) {
        final frame = await codec.getFrame(index);
        final pixels = (await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        expect(pixels, expected[index], reason: 'frame $index');
        frame.image.dispose();
      }
      codec.dispose();
    });
  }
  test('HEIF alpha and depth are not primary image tracks', () async {
    final info = (await PhotoMediaInfo.inspect(
      '$root/sequence-alpha-depth.heic',
    ))!;
    expect(info.videoIndex, 0);
    expect(info.alphaIndex, 1);
    final codec = await PhotoMediaCodec.open(
      '$root/sequence-alpha-depth.heic',
      info,
    );
    final frame = await codec.getFrame(0);
    final bytes = (await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    expect(bytes[3], inInclusiveRange(110, 145));
    frame.image.dispose();
    codec.dispose();
  });
  test('video range cannot escape the source file', () async {
    const bad = PhotoMediaLocation(PhotoMediaKind.motionPhoto, 1, 999999999);
    await expectLater(bad.acquire('$root/cover.jpg'), throwsFormatException);
    expect(await File('$root/cover.jpg').exists(), isTrue);
  });
  test('all embedded audio tracks decode to bounded native PCM', () async {
    final path = '$root/motion-multiple-audio.jpg';
    final info = (await PhotoMediaInfo.inspect(path))!;
    expect(info.audioTracks.map((t) => t.codec).toSet(), {'aac', 'opus'});
    final lease = await info.location.acquire(path);
    try {
      final executable = await CodecProcess.locate('ffmpeg', 'SHENVIEW_FFMPEG');
      for (final track in info.audioTracks) {
        final pcm = await CodecProcess.run(executable, [
          '-v',
          'error',
          '-i',
          lease.file.path,
          '-map',
          '0:${track.index}',
          '-vn',
          '-ar',
          '48000',
          '-ac',
          '2',
          '-af',
          'atempo=2',
          '-c:a',
          'pcm_s16le',
          '-f',
          's16le',
          'pipe:1',
        ], maxOutput: 1024 * 1024);
        expect(pcm.length, inInclusiveRange(170000, 220000));
        expect(pcm.any((byte) => byte != 0), isTrue);
      }
    } finally {
      await lease.release();
    }
  });
}
