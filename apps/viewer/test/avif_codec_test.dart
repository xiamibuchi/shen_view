import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/avif_codec.dart';
import 'package:shen_view/src/application/animation_playback_controller.dart';
import 'package:shen_view/src/application/codec_process.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/image_resource_service.dart';
import 'package:shen_view/src/application/image_source.dart';
import 'package:shen_view/src/application/hdr_source_profile.dart';
import 'package:shen_view/src/application/hdr_transfer.dart';
import 'package:shen_view/src/application/metadata_service.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var available = false;
  setUpAll(() async {
    try {
      await CodecProcess.locate(
        'viewer_avif_animation',
        'SHENVIEW_AVIF_ANIMATION',
      );
      available = true;
    } on StateError {
      available = false;
    }
  });
  setUp(() {
    if (!available) {
      markTestSkipped('先在仓库根构建 AVIF 动画组件：tool/build/build_hdr_codecs.ps1');
    }
  });

  test(
    'libavif distinguishes animated, static and single-frame AVIF',
    () async {
      final animated = await AvifCodec.inspect(
        'testdata/formats/format_animated.avif',
      );
      expect(animated.animated, isTrue);
      expect(animated.timeline.durations, [100, 200, 300]);
      expect(animated.timeline.totalPlays, 0);
      final finite = await AvifCodec.inspect(
        'testdata/formats/format_animated_finite.avif',
      );
      expect(finite.timeline.totalPlays, 2);
      for (final name in [
        'format_static.avif',
        'format_single_frame.avif',
        'format_progressive.avif',
      ]) {
        expect(
          (await AvifCodec.inspect('testdata/formats/$name')).animated,
          isFalse,
        );
        expect(
          (await MetadataService().read('testdata/formats/$name')).animation,
          isNull,
        );
      }
    },
  );

  test(
    'libavif renders frame colors, alpha, timings, loops and direct seeks',
    () async {
      final codec = await AvifCodec.open(
        'testdata/formats/format_animated.avif',
        maxPixels: 4096,
      );
      addTearDown(codec.dispose);
      expect(codec.frameCount, 3);
      expect(codec.repetitionCount, -1);
      for (final index in [0, 1, 2, 0, 2, 1]) {
        final frame = await codec.getFrame(index);
        try {
          expect(frame.duration.inMilliseconds, [100, 200, 300][index]);
          final pixels = (await frame.image.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba,
          ))!;
          expect(pixels.getUint8(index), closeTo(195, 2));
          expect(pixels.getUint8(3), 128);
          expect(pixels.getUint8(24 * 4 + index), closeTo(195, 2));
          expect(pixels.getUint8(24 * 4 + 3), 255);
        } finally {
          frame.image.dispose();
        }
      }
    },
  );

  test('embedded ICC animation preserves sRGB frame colors', () async {
    final codec = await AvifCodec.open(
      'testdata/formats/format_animated_icc.avif',
      maxPixels: 4096,
    );
    addTearDown(codec.dispose);
    for (var index = 0; index < 3; index++) {
      final frame = await codec.getNextFrame();
      final pixels = (await frame.image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!;
      frame.image.dispose();
      expect(pixels.getUint8(24 * 4 + index), closeTo(195, 2));
      expect(pixels.getUint8(3), 128);
    }
  });

  for (final type in ['pq', 'hlg']) {
    test(
      '10/12-bit $type animation has bounded SDR output and alpha',
      () async {
        final codec = await AvifCodec.open(
          'testdata/formats/format_animated_$type.avif',
          maxPixels: 4096,
        );
        addTearDown(codec.dispose);
        expect(codec.info.depth, type == 'pq' ? 10 : 12);
        for (var index = 0; index < 3; index++) {
          final frame = await codec.getNextFrame();
          final pixels = (await frame.image.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba,
          ))!;
          frame.image.dispose();
          const signals = [
            [50000, 10000, 5000],
            [10000, 50000, 5000],
            [5000, 10000, 50000],
          ];
          final signal = signals[index].map((v) => v / 65535).toList();
          final linear = type == 'pq'
              ? signal.map((v) => HdrTransfer.pqToNits(v) / 203).toList()
              : HdrTransfer.hlgToDisplayLinear2020(signal);
          final matrix = HdrSourceProfile.toLinear709(HdrTransfer.rec2020);
          for (var c = 0; c < 3; c++) {
            final v =
                (matrix[c * 3] * linear[0] +
                        matrix[c * 3 + 1] * linear[1] +
                        matrix[c * 3 + 2] * linear[2])
                    .clamp(0.0, 65504.0);
            final expected = (HdrTransfer.linearToSrgb(v / (1 + v)) * 255)
                .round()
                .clamp(0, 255);
            expect(pixels.getUint8(24 * 4 + c), closeTo(expected, 3));
          }
          expect(
            pixels.getUint8(index),
            greaterThan(pixels.getUint8((index + 1) % 3)),
          );
          expect(pixels.getUint8(3), closeTo(128, 1));
        }
      },
    );
  }

  test(
    'cancel closes a persistent decoder and releases its file lease',
    () async {
      final released = Completer<void>();
      final request = DecodeRequest();
      final codec = await AvifCodec.open(
        'testdata/formats/format_animated.avif',
        maxPixels: 4096,
        request: request,
        releaseFile: () async => released.complete(),
      );
      request.cancel();
      await released.future.timeout(const Duration(seconds: 5));
      await expectLater(codec.getNextFrame(), throwsA(isA<DecodeCancelled>()));
      codec.dispose();
    },
  );

  test(
    'native pixel limits reject oversized work before frame decoding',
    () async {
      await expectLater(
        AvifCodec.open('testdata/formats/format_animated.avif', maxPixels: 100),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'AVIF controller seeks in one session and obeys finite repetition',
    () async {
      const path = 'testdata/formats/format_animated_finite.avif';
      final info = await AvifCodec.inspect(path);
      var opened = 0;
      final controller = AnimationPlaybackController(
        timeline: info.timeline,
        autoPlay: false,
        openCodec: () {
          opened++;
          return AvifCodec.open(path, maxPixels: 4096);
        },
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      Future<void> until(bool Function() condition) async {
        final clock = Stopwatch()..start();
        while (!condition() && clock.elapsed < const Duration(seconds: 5)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(condition(), isTrue);
        expect(controller.error, isNull);
      }

      controller.seekFrame(2);
      await until(() => controller.frame == 2);
      controller.seekFrame(1);
      await until(() => controller.frame == 1);
      expect(opened, 1);
      controller.setSpeed(2);
      controller.restart();
      await until(() => controller.snapshot.ended);
      expect(controller.snapshot.completedPlays, 2);
      expect(controller.frame, 2);
      expect(controller.playing, isFalse);
      expect(opened, 1);
    },
  );

  test(
    'animation resources keep decoder memory reserved until disposal',
    () async {
      final file = File('testdata/formats/format_animated.avif').absolute;
      final stat = file.statSync();
      final entry = ImageEntry(
        file: file,
        format: ImageFormat.avif,
        width: null,
        height: null,
        byteLength: stat.size,
        modifiedAt: stat.modified,
      );
      final resources = ImageResourceService();
      addTearDown(resources.dispose);
      final metadata = await resources.metadata(entry);
      expect(metadata.animation?.durationsMs, [100, 200, 300]);
      expect(resources.isAnimated(entry), isTrue);
      final codec = await resources.animationCodec(
        entry,
        request: DecodeRequest(),
      );
      expect(resources.inflightBytes, greaterThanOrEqualTo(48 * 32 * 64));
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      codec.dispose();
      expect(resources.inflightBytes, 0);
    },
  );

  test(
    'Unicode archive paths retain their lease until native decoder exit',
    () async {
      final directory = Directory.systemTemp.createTempSync('avif-中文路径-');
      final file = File('testdata/formats/format_animated.avif')
          .copySync('${directory.path}/动画图片.avif');
      final source = _LeasedAvifSource(file);
      final stat = file.statSync();
      final entry = ImageEntry.fromSource(
        source: source,
        format: ImageFormat.avif,
        byteLength: stat.size,
        modifiedAt: stat.modified,
      );
      final resources = ImageResourceService();
      addTearDown(() async {
        resources.dispose();
        await source.released.future.timeout(const Duration(seconds: 5));
        directory.deleteSync(recursive: true);
      });
      await resources.metadata(entry);
      expect(source.leases, 0);
      final codec = await resources.animationCodec(
        entry,
        request: DecodeRequest(),
      );
      expect(source.leases, 1);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      expect(source.leases, 1);
      source.waitingForExit = true;
      codec.dispose();
      await source.released.future.timeout(const Duration(seconds: 5));
      expect(source.leases, 0);
    },
  );
}

class _LeasedAvifSource implements ImageSource {
  _LeasedAvifSource(this.file);
  final File file;
  int leases = 0;
  bool waitingForExit = false;
  final released = Completer<void>();
  @override
  String get id => 'archive://avif/动画图片.avif';
  @override
  String get name => '动画图片.avif';
  @override
  String get relativePath => name;
  @override
  bool get sensitive => false;
  @override
  Future<SourceFileLease> acquireFile({DecodeRequest? request}) async {
    request?.throwIfCancelled();
    leases++;
    return SourceFileLease(
      file,
      onRelease: () async {
        leases--;
        if (waitingForExit && leases == 0 && !released.isCompleted) {
          released.complete();
        }
      },
    );
  }
}
