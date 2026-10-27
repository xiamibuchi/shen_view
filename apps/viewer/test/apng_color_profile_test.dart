import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shen_view/src/application/apng_codec.dart';

import 'support/photo_metadata_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('apng-color');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  for (final kind in ['p3', 'gamma', 'untagged']) {
    test(
      'APNG $kind color matches the static renderer over repeated playback',
      () async {
        final image = img.Image(width: 4, height: 2, numChannels: 4);
        img.fill(image, color: img.ColorRgba8(128, 64, 32, 255));
        if (kind == 'p3') {
          image.iccProfile = img.IccProfile(
            'Display P3',
            img.IccProfileCompression.none,
            File('testdata/photo_metadata/display_p3.icc').readAsBytesSync(),
          );
        }
        final second = img.Image.from(image);
        img.fill(second, color: img.ColorRgba8(32, 64, 128, 128));
        image.addFrame(second);
        var encoded = img.encodePng(image);
        if (kind == 'gamma') {
          encoded = Uint8List.fromList([
            ...encoded.take(33),
            ...pngChunk(
              'gAMA',
              (ByteData(4)..setUint32(0, 100000)).buffer.asUint8List(),
            ),
            ...encoded.skip(33),
          ]);
        }
        final path = '${dir.path}/$kind.apng';
        File(path).writeAsBytesSync(encoded);
        final codec = await ApngCodec.open(path, maxPixels: 16);
        addTearDown(codec.dispose);
        final reference = await ui.instantiateImageCodec(encoded);
        addTearDown(reference.dispose);
        for (var i = 0; i < 6; i++) {
          final frame = await codec.getNextFrame();
          final expected = await reference.getNextFrame();
          try {
            final actualPixels = await _render(frame.image);
            final expectedPixels = await _render(expected.image);
            for (var c = 0; c < 4; c++) {
              expect(
                actualPixels[c],
                closeTo(expectedPixels[c], 1),
                reason: '$kind frame $i channel $c',
              );
            }
            if (i == 0 && kind == 'p3') {
              for (final (c, value) in [138, 59, 21, 255].indexed) {
                expect(actualPixels[c], closeTo(value, 2));
              }
            }
            if (i == 0 && kind == 'untagged') {
              expect(actualPixels, [128, 64, 32, 255]);
            }
          } finally {
            frame.image.dispose();
            expected.image.dispose();
          }
        }
      },
    );
  }
}

Future<List<int>> _render(ui.Image image) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImage(image, ui.Offset.zero, ui.Paint());
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(image.width, image.height);
  try {
    return (await rendered.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!.buffer.asUint8List().sublist(0, 4);
  } finally {
    rendered.dispose();
    picture.dispose();
  }
}
