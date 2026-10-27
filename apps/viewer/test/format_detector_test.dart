import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:shen_view/src/application/format_detector.dart';
import 'package:shen_view/src/domain/image_format.dart';

void main() {
  test('AVIF sequence and compatible brands route to AVIF', () {
    for (final brands in ['avis', 'avif', 'mif1']) {
      final header = <int>[
        0,
        0,
        0,
        24,
        ...'ftyp'.codeUnits,
        ...brands.codeUnits,
        0,
        0,
        0,
        0,
        ...'avis'.codeUnits,
        ...'msf1'.codeUnits,
      ];
      expect(
        FormatDetector().fromSignature(Uint8List.fromList(header)),
        ImageFormat.avif,
      );
    }
    expect(FormatDetector.formatForPath('animation.avis'), ImageFormat.avif);
  });
  test('detects common formats from signatures', () async {
    final directory = await Directory.systemTemp.createTemp(
      'shen_view-detector',
    );
    addTearDown(() => directory.delete(recursive: true));
    final detector = FormatDetector();
    // ignore: prefer_interpolation_to_compose_strings
    final apng = File(directory.path + '/sample.apng')
      ..writeAsBytesSync([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x61,
        0x63,
        0x54,
        0x4C,
      ]);

    final jpeg = File('${directory.path}/wrong.bin')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0x00]);
    final png = File('${directory.path}/sample.png')
      ..writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    final webp = File('${directory.path}/sample.webp')
      ..writeAsBytesSync('RIFF0000WEBP'.codeUnits);

    expect(await detector.detect(jpeg), ImageFormat.jpeg);
    expect(await detector.detect(png), ImageFormat.png);
    expect(await detector.detect(webp), ImageFormat.webp);
    expect(await detector.detect(apng), ImageFormat.apng);
  });

  test('falls back to extension when a signature is unavailable', () async {
    final directory = await Directory.systemTemp.createTemp(
      'shen_view-extension',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/sample.avif')
      ..writeAsBytesSync([0x00]);
    expect(await FormatDetector().detect(file), ImageFormat.avif);
    // ignore: prefer_interpolation_to_compose_strings
    final heif = File(directory.path + '/sample.heif')
      ..writeAsBytesSync([0x00]);
    expect(await FormatDetector().detect(heif), ImageFormat.heif);
  });
}
