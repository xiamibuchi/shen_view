import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shen_view/src/application/image_resource_service.dart';
import 'package:shen_view/src/application/native_decoder.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';

import 'support/photo_metadata_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (hint, managed) in [(2, true), (1, false), (65535, false)]) {
    test(
      'unprofiled JPEG EXIF ColorSpace=$hint has consistent main, thumbnail and crop colors',
      () async {
        try {
          await NativeDecoder().executable();
        } catch (_) {
          markTestSkipped('需要 ImageMagick');
          return;
        }
        final dir = Directory.systemTemp.createTempSync('photo-color');
        addTearDown(() => dir.deleteSync(recursive: true));
        final image = metadataPhoto()..exif.imageIfd.orientation = 1;
        image.exif.exifIfd[0xa001] = img.IfdValueShort(hint);
        final file = File('${dir.path}/source.jpg')
          ..writeAsBytesSync(img.encodeJpg(image));
        final source = img.decodeJpg(file.readAsBytesSync())!.getPixel(0, 0);
        final samples = [source.r / 255, source.g / 255, source.b / 255];
        final expected = managed ? _adobeToSrgb(samples) : samples;
        final native = img
            .decodePng(await NativeDecoder().decode(file.path))!
            .getPixel(0, 0);
        for (var c = 0; c < 3; c++) {
          expect(
            [native.r, native.g, native.b][c],
            closeTo(expected[c] * 255, 2),
          );
        }
        final resources = ImageResourceService();
        addTearDown(resources.dispose);
        addTearDown(PaintingBinding.instance.imageCache.clear);
        final stat = file.statSync();
        final entry = ImageEntry(
          file: file,
          format: ImageFormat.jpeg,
          width: 16,
          height: 8,
          byteLength: stat.size,
          modifiedAt: stat.modified,
        );
        for (final size in [16, 4]) {
          final decoded = await _load(
            resources.provider(entry, targetWidth: size, targetHeight: size),
          );
          try {
            final data = await decoded.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            for (var c = 0; c < 3; c++) {
              expect(data!.getUint8(c), closeTo(expected[c] * 255, 2));
            }
          } finally {
            decoded.dispose();
          }
        }
        final cropped = img
            .decodePng(
              await NativeDecoder().decode(file.path, crop: '4x4+2+2'),
            )!
            .getPixel(0, 0);
        for (var c = 0; c < 3; c++) {
          expect(
            [cropped.r, cropped.g, cropped.b][c],
            closeTo(expected[c] * 255, 2),
          );
        }
      },
    );
  }
}

// Adobe RGB (1998), D65, gamma 563/256, converted to D65 sRGB.
// Independent matrix/transfer arithmetic avoids baselining against ImageMagick.
List<double> _adobeToSrgb(List<double> rgb) {
  final linear = rgb.map((v) => math.pow(v, 563 / 256).toDouble()).toList();
  final converted = [
    1.398283 * linear[0] - .398283 * linear[1],
    linear[1],
    -.042938 * linear[1] + 1.042938 * linear[2],
  ];
  return converted
      .map(
        (v) => (v <= .0031308 ? 12.92 * v : 1.055 * math.pow(v, 1 / 2.4) - .055)
            .clamp(0.0, 1.0)
            .toDouble(),
      )
      .toList();
}

Future<ui.Image> _load(ImageProvider<Object> provider) {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      completer.complete(info.image.clone());
    },
    onError: (Object error, StackTrace? stack) {
      stream.removeListener(listener);
      completer.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  return completer.future.timeout(const Duration(seconds: 30));
}
