import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as imaging;
import 'package:shen_view/src/application/codec_process.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/raw_developer.dart';
import 'package:shen_view/src/application/hdr_input_metadata.dart';
import 'package:shen_view/src/application/hdr_decoder.dart';
import 'package:shen_view/src/application/hdr_transfer.dart';

void main() {
  test(
    'CR2 default development renders the photographed white background',
    () async {
      try {
        await CodecProcess.locate('viewer_raw', 'SHENVIEW_RAW');
      } catch (_) {
        markTestSkipped('需要 LibRaw 显影组件');
        return;
      }
      final png = await RawDeveloper().decode(
        'testdata/formats/raw_canon_white_paper.cr2',
        targetWidth: 2048,
        targetHeight: 2048,
      );
      Directory('../../artifacts/hdr').createSync(recursive: true);
      File('../../artifacts/hdr/cr2-developed.png').writeAsBytesSync(png);
      final image = imaging.decodePng(png)!;
      final background = image.getPixel(image.width ~/ 8, image.height ~/ 2);
      final rgb = [
        background.rNormalized,
        background.gNormalized,
        background.bNormalized,
      ];
      // This fixture photographs a toy against white paper. A valid default
      // development must not leave that paper at sensor-linear mid-grey.
      expect(rgb, everyElement(inInclusiveRange(0.65, 0.99)));
      final linear = await RawDeveloper().decodeLinear(
        'testdata/formats/raw_canon_white_paper.cr2',
        targetWidth: 2048,
        targetHeight: 2048,
      );
      expect((linear.width, linear.height), (image.width, image.height));
      final offset = (image.height ~/ 2 * image.width + image.width ~/ 8) * 16;
      final values = ByteData.sublistView(linear.pixels);
      for (var c = 0; c < 3; c++) {
        final value = values.getFloat32(offset + c * 4, Endian.little);
        expect(
          value,
          greaterThan(0.4),
          reason: 'HDR must share the corrected exposure',
        );
        expect(HdrTransfer.linearToSrgb(value), closeTo(rgb[c], 0.015));
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('RAW development reads CFA data without an embedded preview', () async {
    try {
      await CodecProcess.locate('viewer_raw', 'SHENVIEW_RAW');
    } catch (_) {
      markTestSkipped('需要 LibRaw 显影组件');
      return;
    }
    final png = await RawDeveloper().decode(
      File('testdata/formats/raw_bayer_no_preview.dng').absolute.path,
    );
    final image = imaging.decodePng(png)!;
    expect(image.width, 256);
    expect(image.height, 192);
    expect(image.format, imaging.Format.uint16);
    final red = image.getPixel(32, 150);
    final green = image.getPixel(128, 150);
    final blue = image.getPixel(224, 150);
    expect(red.r, greaterThan(red.g));
    expect(green.g, greaterThan(green.r));
    expect(blue.b, greaterThan(blue.r));
    expect(image.getPixel(128, 150).g, greaterThan(image.getPixel(128, 30).g));
    final target = await RawDeveloper().decode(
      'testdata/formats/raw_bayer_no_preview.dng',
      targetWidth: 64,
    );
    final thumb = imaging.decodePng(target)!;
    expect(thumb.width, 64);
    expect(thumb.height, 48);
    final bounded = imaging.decodePng(
      await RawDeveloper().decode(
        'testdata/formats/raw_bayer_no_preview.dng',
        targetWidth: 64,
        targetHeight: 64,
      ),
    )!;
    expect(
      (bounded.width, bounded.height),
      (64, 48),
      reason: 'A bounding box must not add black pixels to the RAW image',
    );
    Directory('../../artifacts/hdr').createSync(recursive: true);
    File('../../artifacts/hdr/raw-developed.png').writeAsBytesSync(png);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('cancellation propagates before RAW process launch', () async {
    final request = DecodeRequest()..cancel();
    await expectLater(
      RawDeveloper().decode(
        'testdata/formats/raw_bayer_no_preview.dng',
        request: request,
      ),
      throwsA(isA<DecodeCancelled>()),
    );
  });

  test(
    'RAW linear development returns an HDR frame without preview data',
    () async {
      try {
        await CodecProcess.locate('viewer_raw', 'SHENVIEW_RAW');
      } catch (_) {
        markTestSkipped('需要 LibRaw 显影组件');
        return;
      }
      final frame = await RawDeveloper().decodeLinear(
        'testdata/formats/raw_bayer_no_preview.dng',
      );
      expect(frame.width, 256);
      expect(frame.height, 192);
      final data = ByteData.sublistView(frame.pixels);
      expect(data.getFloat32(0, Endian.little), greaterThan(0));
      expect(frame.pixels.length, 256 * 192 * 16);
      var minimum = double.infinity, maximum = double.negativeInfinity;
      for (var i = 0; i < frame.pixels.length; i += 16) {
        for (var c = 0; c < 3; c++) {
          final value = data.getFloat32(i + c * 4, Endian.little);
          expect(value.isFinite, true);
          if (value < minimum) minimum = value;
          if (value > maximum) maximum = value;
        }
      }
      expect(maximum, closeTo(1.87965, 0.005));
      expect(minimum, closeTo(-0.48239, 0.005));
      final rotated = await RawDeveloper().decodeLinear(
        'testdata/formats/raw_bayer_rotated.dng',
      );
      expect(rotated.width, frame.height);
      expect(rotated.height, frame.width);
      final turned = ByteData.sublistView(rotated.pixels);
      for (var c = 0; c < 4; c++) {
        expect(
          turned.getFloat32(
            (32 * rotated.width + (191 - 150)) * 16 + c * 4,
            Endian.little,
          ),
          closeTo(
            data.getFloat32(
              (150 * frame.width + 32) * 16 + c * 4,
              Endian.little,
            ),
            0.0001,
          ),
        );
      }
    },
  );

  test('RAW metadata selects the linear HDR route', () async {
    final info = await HdrInputMetadata.read(
      'testdata/formats/raw_bayer_no_preview.dng',
    );
    expect(info.encoding, HdrEncoding.sceneLinear);
  });

  for (final black in [false, true]) {
    test(
      black
          ? 'covered RAW sensor stays black in SDR and HDR'
          : 'underexposed RAW retains usable brightness and camera colors',
      () async {
        try {
          await CodecProcess.locate('viewer_raw', 'SHENVIEW_RAW');
        } catch (_) {
          markTestSkipped('需要 LibRaw 显影组件');
          return;
        }
        final name = black ? 'black' : 'underexposed';
        final path = 'testdata/formats/raw_bayer_$name.dng';
        final developer = RawDeveloper();
        final image = imaging.decodePng(await developer.decode(path))!;
        final frame = await developer.decodeLinear(path);
        expect((image.width, image.height), (256, 192));
        expect((frame.width, frame.height), (256, 192));
        final linear = ByteData.sublistView(frame.pixels);
        if (black) {
          for (final pixel in image) {
            expect([pixel.r, pixel.g, pixel.b], everyElement(0));
          }
          for (var i = 0; i < 256 * 192; i++) {
            for (var c = 0; c < 3; c++) {
              expect(linear.getFloat32(i * 16 + c * 4, Endian.little), 0);
            }
          }
        } else {
          for (final probe in [(32, 0), (128, 1), (224, 2)]) {
            final pixel = image.getPixel(probe.$1, 150);
            final rgb = [
              pixel.rNormalized,
              pixel.gNormalized,
              pixel.bNormalized,
            ];
            // These are colored patches, not white surfaces: only the red
            // patch approaches white after this chart's camera-to-XYZ matrix.
            expect(rgb[probe.$2], greaterThan(probe.$2 == 0 ? 0.9 : 0.5));
            for (var c = 0; c < 3; c++) {
              if (c != probe.$2) expect(rgb[probe.$2], greaterThan(rgb[c]));
              final value = linear.getFloat32(
                (150 * 256 + probe.$1) * 16 + c * 4,
                Endian.little,
              );
              expect(value.isFinite, isTrue);
              // Compare non-clipped components: the same exposure must feed
              // both paths, followed by exactly one SDR transfer function.
              if (value > 0 && value < 0.9) {
                expect(HdrTransfer.linearToSrgb(value), closeTo(rgb[c], 0.015));
              }
            }
          }
        }
      },
    );
  }

  test('HDR decoder routes RAW through linear development', () async {
    try {
      await CodecProcess.locate('viewer_raw', 'SHENVIEW_RAW');
    } catch (_) {
      markTestSkipped('需要 LibRaw 显影组件');
      return;
    }
    final frame = await HdrDecoder().decode(
      'testdata/formats/raw_bayer_no_preview.dng',
      DecodeRequest(),
    );
    expect(frame.width, 256);
    expect(frame.height, 192);
  });

  for (final name in ['raw_nikon_d2h.nef', 'raw_sony_a7s.arw']) {
    test(
      'real camera RAW develops finite pixels with camera geometry: $name',
      () async {
        try {
          await CodecProcess.locate('viewer_raw', 'SHENVIEW_RAW');
        } catch (_) {
          markTestSkipped('需要 LibRaw 显影组件');
          return;
        }
        final path = 'testdata/formats/$name';
        final developer = RawDeveloper();
        final png = await developer.decode(
          path,
          targetWidth: 256,
          targetHeight: 256,
        );
        final image = imaging.decodePng(png)!;
        expect(image.width, 256);
        expect(image.width / image.height, closeTo(1.5, 0.025));
        if (name == 'raw_nikon_d2h.nef') {
          // This independently photographed color target has six neutral steps
          // along its bottom row and known red/green/blue patches above them.
          // Check scene relationships rather than freezing this decoder's PNG.
          var previous = 2.0;
          for (final x in [79, 98, 117, 136, 155, 174]) {
            final p = image.getPixel(x, 118);
            final rgb = [p.rNormalized, p.gNormalized, p.bNormalized]..sort();
            expect(rgb.last - rgb.first, lessThan(0.12));
            final mean = (p.rNormalized + p.gNormalized + p.bNormalized) / 3;
            expect(previous - mean, greaterThan(0.07));
            previous = mean;
            if (x == 79) expect(mean, inInclusiveRange(0.8, 0.99));
            if (x == 174) expect(mean, inInclusiveRange(0.1, 0.3));
          }
          for (final point in [(117, 96, 0), (98, 97, 1), (79, 97, 2)]) {
            final p = image.getPixel(point.$1, point.$2);
            final rgb = [p.rNormalized, p.gNormalized, p.bNormalized];
            for (var c = 0; c < 3; c++) {
              if (c != point.$3) {
                expect(rgb[point.$3] - rgb[c], greaterThan(0.15));
              }
            }
          }
        }
        final frame = await developer.decodeLinear(path);
        expect(
          frame.width / frame.height,
          closeTo(image.width / image.height, 0.01),
        );
        final pixels = ByteData.sublistView(frame.pixels);
        var peak = 0.0;
        for (var i = 0; i < frame.width * frame.height; i++) {
          for (var c = 0; c < 3; c++) {
            final value = pixels.getFloat32(i * 16 + c * 4, Endian.little);
            expect(value.isFinite, isTrue);
            if (value > peak) peak = value;
          }
          expect(pixels.getFloat32(i * 16 + 12, Endian.little), 1);
        }
        expect(peak, inInclusiveRange(0.5, 32.0));
        Directory('../../artifacts/raw').createSync(recursive: true);
        File('../../artifacts/raw/$name.png').writeAsBytesSync(png);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }
}
