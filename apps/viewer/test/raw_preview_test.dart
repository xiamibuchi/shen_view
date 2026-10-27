import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as imaging;
import 'package:shen_view/src/application/codec_process.dart';
import 'package:shen_view/src/application/decode_scheduler.dart';
import 'package:shen_view/src/application/image_resource_service.dart';
import 'package:shen_view/src/application/metadata_service.dart';
import 'package:shen_view/src/application/native_decoder.dart';
import 'package:shen_view/src/application/raw_developer.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';

Uint8List png(int width, int height) => imaging.encodePng(
  imaging.Image(width: width, height: height)
    ..clear(imaging.ColorRgb8(40, 80, 120)),
);

class _Metadata extends MetadataService {
  @override
  Future<ImageMetadata> read(String path, {DecodeRequest? request}) async =>
      const ImageMetadata(
        width: 2400,
        height: 1600,
        values: {'rawPreviewBytes': '2048'},
      );
}

class _Decoder extends NativeDecoder {
  Uint8List previewBytes = png(240, 160);
  bool absent = false;
  int developments = 0;
  int previews = 0;
  final priorities = <DecodePriority>[];
  Completer<void>? gate;
  final started = Completer<DecodeRequest>();
  @override
  Future<RawEmbeddedPreview?> rawPreview(
    String path, {
    int? targetWidth,
    int? targetHeight,
    DecodeRequest? request,
  }) async {
    previews++;
    if (!started.isCompleted) started.complete(request!);
    await gate?.future;
    request?.throwIfCancelled();
    return absent ? null : RawEmbeddedPreview(previewBytes, 240, 160);
  }

  @override
  Future<Uint8List> decode(
    String path, {
    int? targetWidth,
    int? targetHeight,
    DecodeRequest? request,
    int frame = 0,
    String? crop,
    bool Function()? allowTimeoutFallback,
  }) async {
    if (!started.isCompleted) started.complete(request!);
    await gate?.future;
    request?.throwIfCancelled();
    developments++;
    priorities.add(request!.priority);
    final width = targetWidth ?? 2400;
    return png(width, (width * 2 / 3).round());
  }
}

class _RealDecoder extends NativeDecoder {
  int developments = 0;
  @override
  Future<Uint8List> decode(
    String path, {
    int? targetWidth,
    int? targetHeight,
    DecodeRequest? request,
    int frame = 0,
    String? crop,
    bool Function()? allowTimeoutFallback,
  }) {
    developments++;
    return super.decode(
      path,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      request: request,
      frame: frame,
      crop: crop,
      allowTimeoutFallback: allowTimeoutFallback,
    );
  }
}

ImageEntry entry() => ImageEntry(
  file: File('testdata/formats/raw_nikon_d2h.nef'),
  format: ImageFormat.raw,
  width: 160,
  height: 120,
  byteLength: 3236017,
  modifiedAt: DateTime(2026, 10, 24),
);

Future<ui.Image> load(ImageProvider<Object> provider) {
  final done = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      done.complete(info.image.clone());
      stream.removeListener(listener);
    },
    onError: (Object error, StackTrace? stack) {
      done.completeError(error, stack);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return done.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  ImageResourceService resources(_Decoder decoder) {
    final service = ImageResourceService(
      decoder: decoder,
      metadataService: _Metadata(),
    );
    addTearDown(service.dispose);
    return service;
  }

  for (final priority in [
    DecodePriority.foreground,
    DecodePriority.adjacent,
    DecodePriority.preload,
  ]) {
    test(
      'main RAW develops even when the embedded preview has enough pixels: $priority',
      () async {
        final decoder = _Decoder();
        final service = resources(decoder);
        final image = await load(
          service.provider(
            entry(),
            targetWidth: 180,
            targetHeight: 120,
            priority: priority,
          ),
        );
        expect((image.width, image.height), (180, 120));
        image.dispose();
        expect(decoder.previews, 0);
        expect(decoder.developments, 1);
        expect(service.inflightBytes, 0);
        final promoted = await load(
          service.provider(entry(), targetWidth: 180, targetHeight: 120),
        );
        promoted.dispose();
        expect(decoder.previews, 0);
        expect(
          decoder.developments,
          1,
          reason: 'Promotion reuses developed pixels',
        );
      },
    );
  }

  test(
    'a small thumbnail cannot satisfy the same-size main cache key',
    () async {
      final decoder = _Decoder();
      final service = resources(decoder);
      final thumb = await load(
        service.provider(
          entry(),
          targetWidth: 600,
          targetHeight: 400,
          priority: DecodePriority.visibleThumbnail,
        ),
      );
      expect((thumb.width, thumb.height), (240, 160));
      thumb.dispose();
      expect(decoder.developments, 0);
      final main = await load(
        service.provider(entry(), targetWidth: 600, targetHeight: 400),
      );
      expect((main.width, main.height), (600, 400));
      main.dispose();
      expect(decoder.developments, 1);
      expect(decoder.priorities, [DecodePriority.foreground]);
      expect(service.inflightBytes, 0);
    },
  );

  for (final absent in [true, false]) {
    test(
      '${absent ? 'missing' : 'corrupt'} preview falls back to sensor development',
      () async {
        final decoder = _Decoder()..absent = absent;
        if (!absent) decoder.previewBytes = Uint8List.fromList([0, 1, 2]);
        final service = resources(decoder);
        final image = await load(
          service.provider(
            entry(),
            targetWidth: 180,
            targetHeight: 120,
            priority: DecodePriority.visibleThumbnail,
          ),
        );
        image.dispose();
        expect(decoder.developments, 1);
        expect(service.inflightBytes, 0);
      },
    );
  }

  test('cancelling extraction never starts sensor development', () async {
    final decoder = _Decoder()..gate = Completer<void>();
    final service = resources(decoder);
    final e = entry();
    final pending = load(
      service.provider(
        e,
        targetWidth: 180,
        targetHeight: 120,
        priority: DecodePriority.visibleThumbnail,
      ),
    );
    final assertion = expectLater(pending, throwsA(isA<DecodeCancelled>()));
    final request = await decoder.started.future;
    service.invalidate(e.id);
    expect(request.cancelled, true);
    decoder.gate!.complete();
    await assertion;
    expect(decoder.developments, 0);
    expect(service.inflightBytes, 0);
  });

  test(
    'zoom cancels an obsolete RAW size while retaining the thumbnail request',
    () async {
      final decoder = _Decoder()..gate = Completer<void>();
      final service = resources(decoder);
      final pending = load(
        service.provider(entry(), targetWidth: 180, targetHeight: 120),
      );
      final assertion = expectLater(pending, throwsA(isA<DecodeCancelled>()));
      final previous = await decoder.started.future;
      final thumbnail = load(
        service.provider(
          entry(),
          targetWidth: 90,
          targetHeight: 60,
          priority: DecodePriority.visibleThumbnail,
        ),
      );
      final upgraded = load(
        service.provider(entry(), targetWidth: 600, targetHeight: 400),
      );
      expect(previous.cancelled, true);
      decoder.gate!.complete();
      await assertion;
      final image = await upgraded;
      expect((image.width, image.height), (600, 400));
      image.dispose();
      expect(decoder.developments, 1);
      final thumb = await thumbnail;
      expect((thumb.width, thumb.height), (90, 60));
      thumb.dispose();
    },
  );

  test('small RAW previews remain available under pressure and failed development can recover', () async {
    final decoder = _Decoder();
    final service = resources(decoder);
    final e = entry();
    service.applyWorkingSet(
      protectedIds: {e.id},
      retainedIds: {e.id},
      memoryBudgetBytes: 8 * 1024 * 1024,
    );
    final thumb = await load(
      service.provider(
        e,
        targetWidth: 180,
        targetHeight: 120,
        priority: DecodePriority.visibleThumbnail,
      ),
    );
    thumb.dispose();
    expect(decoder.developments, 0);
    for (var attempt = 0; attempt < 2; attempt++) {
      await expectLater(
        load(service.provider(e, targetWidth: 600, targetHeight: 400)),
        throwsA(isA<ImageResourceUnavailable>()),
      );
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }
    expect(
      decoder.previews,
      1,
      reason: 'Main-image recovery must not extract an unused camera preview',
    );
    expect(service.inflightBytes, 0);
    service.applyWorkingSet(
      protectedIds: {e.id},
      retainedIds: {e.id},
      memoryBudgetBytes: 256 * 1024 * 1024,
    );
    final image = await load(
      service.provider(e, targetWidth: 600, targetHeight: 400),
    );
    image.dispose();
    expect(decoder.developments, 1);
  });

  test('a mislabeled preview cannot replace main RAW development', () async {
    final decoder = _Decoder()..previewBytes = png(24, 16);
    final service = resources(decoder);
    final image = await load(
      service.provider(entry(), targetWidth: 180, targetHeight: 120),
    );
    expect((image.width, image.height), (180, 120));
    image.dispose();
    expect(decoder.developments, 1);
  });

  test('real CR2, ARW and NEF main images use sensor development', () async {
    try {
      await CodecProcess.locate('viewer_raw', 'SHENVIEW_RAW');
    } catch (_) {
      markTestSkipped('需要 LibRaw 解码组件');
      return;
    }
    final decoder = _RealDecoder();
    final service = ImageResourceService(decoder: decoder);
    addTearDown(service.dispose);
    for (final name in [
      'raw_canon_white_paper.cr2',
      'raw_sony_a7s.arw',
      'raw_nikon_d2h.nef',
    ]) {
      final file = File('testdata/formats/$name');
      final stat = await file.stat();
      final e = ImageEntry(
        file: file,
        format: ImageFormat.raw,
        width: null,
        height: null,
        byteLength: stat.size,
        modifiedAt: stat.modified,
      );
      final image = await load(
        service.provider(e, targetWidth: 1024, targetHeight: 1024),
      );
      expect(image.width, inInclusiveRange(1022, 1024), reason: name);
      expect(image.width / image.height, closeTo(1.5, .03));
      image.dispose();
      expect(decoder.developments, 1);
      decoder.developments = 0;
    }
    expect(service.inflightBytes, 0);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('CR2 main image keeps corrected exposure at 100 percent within the sensor budget', () async {
    try {
      await CodecProcess.locate('viewer_raw', 'SHENVIEW_RAW');
    } catch (_) {
      markTestSkipped('需要 LibRaw 解码组件');
      return;
    }
    final decoder = _RealDecoder();
    final service = ImageResourceService(decoder: decoder);
    addTearDown(service.dispose);
    final file = File('testdata/formats/raw_canon_white_paper.cr2');
    final stat = await file.stat();
    final e = ImageEntry(
      file: file,
      format: ImageFormat.raw,
      width: null,
      height: null,
      byteLength: stat.size,
      modifiedAt: stat.modified,
    );
    final metadata = await service.metadata(e);
    final image = await load(
      service.provider(
        e,
        targetWidth: metadata.width,
        targetHeight: metadata.height,
      ),
    );
    expect(image.width, greaterThan(2048));
    expect(image.width, lessThanOrEqualTo(metadata.width));
    expect(image.width / image.height, closeTo(1.5, .01));
    final pixels = (await image.toByteData())!;
    final paper = (image.height ~/ 2 * image.width + image.width ~/ 8) * 4;
    for (var c = 0; c < 3; c++) {
      expect(pixels.getUint8(paper + c), inInclusiveRange(166, 252));
    }
    image.dispose();
    expect(decoder.developments, 1);
    expect(service.inflightBytes, 0);
  });

  test('real RAW previews extract without developing the sensor and metadata uses sensor size', () async {
    try {
      await CodecProcess.locate('viewer_raw', 'SHENVIEW_RAW');
    } catch (_) {
      markTestSkipped('需要 LibRaw 解码组件');
      return;
    }
    final raw = RawDeveloper();
    for (final sample in [
      ('raw_canon_white_paper.cr2', 3888, 2592),
      ('raw_nikon_d2h.nef', 570, 375),
      ('raw_sony_a7s.arw', 1616, 1080),
    ]) {
      final path = 'testdata/formats/${sample.$1}';
      final preview = (await raw.preview(path))!;
      expect((preview.width, preview.height), (sample.$2, sample.$3));
      final decoded = imaging.decodeJpg(preview.bytes)!;
      expect((decoded.width, decoded.height), (sample.$2, sample.$3));
      final metadata = await MetadataService().read(path);
      expect(metadata.width, greaterThan(2000));
      expect(metadata.height, greaterThan(1500));
    }
    expect(
      await raw.preview('testdata/formats/raw_bayer_no_preview.dng'),
      isNull,
    );
  });

  test(
    'RAW development exceeds 2048 when requested but remains target bounded',
    () async {
      String helper;
      try {
        helper = await CodecProcess.locate('viewer_raw', 'SHENVIEW_RAW');
      } catch (_) {
        markTestSkipped('需要 LibRaw 解码组件');
        return;
      }
      final bytes = await CodecProcess.run(helper, [
        'decode',
        'testdata/formats/raw_canon_white_paper.cr2',
        '3000',
        '2000',
      ], maxOutput: 40 * 1024 * 1024);
      final header = ascii
          .decode(bytes.sublist(0, bytes.indexOf(10)))
          .split(' ');
      expect(header.first, 'FVRAW16');
      final width = int.parse(header[1]), height = int.parse(header[2]);
      expect(width, inInclusiveRange(2049, 3000));
      expect(height, lessThanOrEqualTo(2000));
      expect(width / height, closeTo(1.5, .02));
      final bounded = imaging.decodePng(
        await RawDeveloper().decode(
          'testdata/formats/raw_bayer_no_preview.dng',
          targetWidth: 65,
          targetHeight: 49,
        ),
      )!;
      expect(bounded.width, lessThanOrEqualTo(65));
      expect(bounded.height, lessThanOrEqualTo(49));
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'embedded preview orientation and Unicode paths are preserved',
    () async {
      try {
        await CodecProcess.locate('viewer_raw', 'SHENVIEW_RAW');
      } catch (_) {
        markTestSkipped('需要 LibRaw 解码组件');
        return;
      }
      final folder = await Directory.systemTemp.createTemp(
        'shenview_raw_preview_',
      );
      addTearDown(() => folder.delete(recursive: true));
      final bytes = await File('testdata/formats/raw_canon_white_paper.cr2')
          .readAsBytes();
      final data = ByteData.sublistView(bytes);
      var offset = data.getUint32(4, Endian.little);
      while (offset != 0) {
        final count = data.getUint16(offset, Endian.little);
        for (var i = 0; i < count; i++) {
          final tag = offset + 2 + i * 12;
          if (data.getUint16(tag, Endian.little) == 274) {
            data.setUint16(tag + 8, 6, Endian.little);
          }
        }
        offset = data.getUint32(offset + 2 + count * 12, Endian.little);
      }
      final file = await File('${folder.path}/旋转预览.cr2').writeAsBytes(bytes);
      final preview = (await RawDeveloper().preview(file.path))!;
      expect((preview.width, preview.height), (2592, 3888));
      final buffer = await ui.ImmutableBuffer.fromUint8List(preview.bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final codec = await descriptor.instantiateCodec(targetWidth: 120);
      final frame = await codec.getNextFrame();
      expect(frame.image.width / frame.image.height, closeTo(2 / 3, .02));
      frame.image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    },
  );
}
