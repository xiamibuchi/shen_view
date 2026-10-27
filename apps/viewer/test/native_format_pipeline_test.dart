import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/decoder_registry.dart';
import 'package:shen_view/src/application/format_detector.dart';
import 'package:shen_view/src/application/native_decoder.dart';
import 'package:shen_view/src/application/metadata_service.dart';
import 'package:shen_view/src/application/hdr_source_profile.dart';
import 'package:shen_view/src/domain/image_format.dart';

void main() {
  final formats = Directory('testdata/formats').absolute;

  test('ships real RAW, HDR and EXR fixtures', () async {
    for (final name in [
      'raw_canon_white_paper.cr2',
      'hdr_gradient.hdr',
      'hdr_gradient.exr',
    ]) {
      final file = File('${formats.path}/$name');
      expect(file.existsSync(), isTrue, reason: name);
      expect(file.lengthSync(), greaterThan(0), reason: name);
    }
    final icc = File('${formats.path}/format_srgb_icc.png');
    expect(icc.existsSync(), isTrue);
    expect(_contains(icc.readAsBytesSync(), 'iCCP'.codeUnits), isTrue);
    expect((await MetadataService().read(icc.path)).colorSpace, contains('ICC'));
  });

  test(
    'ships the HDR regression chart and keeps each source standard explicit',
    () async {
      final detector = FormatDetector();
      const fixtures = <String, ImageFormat>{
        'hdr_highlights.hdr': ImageFormat.hdr,
        'hdr_highlights.exr': ImageFormat.exr,
        'hdr_rec2020.exr': ImageFormat.exr,
        'hdr_transparent.exr': ImageFormat.exr,
      };

      for (final entry in fixtures.entries) {
        final file = File('${formats.path}/${entry.key}');
        expect(file.existsSync(), isTrue, reason: entry.key);
        expect(file.lengthSync(), greaterThan(1024), reason: entry.key);
        expect(await detector.detect(file), entry.value, reason: entry.key);
      }

      final rec709 = HdrSourceProfile.exrChromaticities(
        File('${formats.path}/hdr_highlights.exr').readAsBytesSync(),
      );
      expect(rec709, isNotNull);
      expect(rec709![0], closeTo(0.64, 0.0001));
      expect(rec709[1], closeTo(0.33, 0.0001));

      final rec2020 = HdrSourceProfile.exrChromaticities(
        File('${formats.path}/hdr_rec2020.exr').readAsBytesSync(),
      );
      expect(rec2020, isNotNull);
      expect(rec2020![0], closeTo(0.708, 0.0001));
      expect(rec2020[1], closeTo(0.292, 0.0001));
    },
  );

  test('keeps TIFF based camera RAW files on the RAW route', () async {
    final detector = FormatDetector();
    expect(
      await detector.detect(File('${formats.path}/raw_canon_white_paper.cr2')),
      ImageFormat.raw,
    );
    expect(
      await detector.detect(File('${formats.path}/hdr_gradient.hdr')),
      ImageFormat.hdr,
    );
    expect(
      await detector.detect(File('${formats.path}/hdr_gradient.exr')),
      ImageFormat.exr,
    );
  });

  test('HDR fallback normalizes to sRGB and applies an SDR transfer', () {
    final args = NativeDecoder.decodeArguments(
      '${formats.path}/hdr_gradient.hdr',
      targetWidth: 1024,
    );
    expect(args, contains('-evaluate'));
    expect(args, contains('Pow'));
    expect(args, contains('-clamp'));
    expect(args, contains('-strip'));

    final regular = NativeDecoder.decodeArguments(
      '${formats.path}/raw_canon_white_paper.cr2',
    );
    expect(regular, contains('-colorspace'));
    expect(regular, contains('sRGB'));
    expect(regular, contains('-strip'));
    final managed = NativeDecoder.decodeArguments(
      '${formats.path}/format_srgb_icc.png',
      destinationProfile: 'sRGB.icc',
    );
    expect(managed, contains('-profile'));
    expect(managed, contains('-black-point-compensation'));
    expect(managed, contains('sRGB.icc'));
  });

  test('native extended formats expose metadata capabilities', () {
    final capabilities = DecoderRegistry().capabilities();
    for (final format in [ImageFormat.raw, ImageFormat.hdr, ImageFormat.exr]) {
      final capability = capabilities.singleWhere(
        (item) => item.format == format,
      );
      expect(capability.metadata, isTrue, reason: format.label);
      if (Platform.isWindows || Platform.isMacOS) {
        expect(capability.available, isTrue, reason: format.label);
      }
      if (Platform.isWindows &&
          (format == ImageFormat.hdr || format == ImageFormat.exr)) {
        expect(capability.sourceKind, DecoderSource.imageMagickFallback);
      }
    }
  });

  test('ImageMagick fallback decodes RAW/HDR/EXR and ICC fixtures', () async {
    final bundled = File(
      Directory('build/windows/x64/runner/Release/codecs/magick.exe')
          .absolute
          .path,
    );
    final configured = Platform.environment['SHENVIEW_MAGICK'];
    final executable = configured != null && File(configured).existsSync()
        ? configured
        : bundled.existsSync()
        ? bundled.path
        : null;
    if (executable == null) {
      markTestSkipped('需要 ImageMagick HDRI，设置 SHENVIEW_MAGICK 后运行');
      return;
    }

    final decoder = NativeDecoder(executableOverride: executable);
    for (final name in [
      'raw_canon_white_paper.cr2',
      'hdr_gradient.hdr',
      'hdr_gradient.exr',
      'format_srgb_icc.png',
      'hdr_highlights.hdr',
      'hdr_highlights.exr',
      'hdr_rec2020.exr',
      'hdr_transparent.exr',
    ]) {
      final bytes = await decoder.decode(
        '${formats.path}/$name',
        targetWidth: 1024,
      );
      expect(bytes.length, greaterThan(100), reason: name);
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (name.startsWith('hdr_') && !name.startsWith('hdr_gradient.')) {
        expect(descriptor.width, 384, reason: name);
        expect(descriptor.height, 192, reason: name);
      }
      final codec = await descriptor.instantiateCodec();
      expect(codec.frameCount, greaterThanOrEqualTo(1), reason: name);
      if (name == 'hdr_transparent.exr') {
        final image = (await codec.getNextFrame()).image;
        final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        expect(rgba!.getUint8(3), closeTo(128, 1));
        image.dispose();
      }
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  });
}

bool _contains(List<int> bytes, List<int> needle) {
  for (var index = 0; index <= bytes.length - needle.length; index++) {
    var matches = true;
    for (var offset = 0; offset < needle.length; offset++) {
      if (bytes[index + offset] != needle[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}
