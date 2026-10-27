import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as imaging;
import 'package:shen_view/src/application/archive_session.dart';
import 'package:shen_view/src/application/decoder_registry.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/decode_scheduler.dart';
import 'package:shen_view/src/application/file_association_formats.dart';
import 'package:shen_view/src/application/folder_index_service.dart';
import 'package:shen_view/src/application/format_detector.dart';
import 'package:shen_view/src/application/ico_file.dart';
import 'package:shen_view/src/application/image_resource_service.dart';
import 'package:shen_view/src/application/metadata_service.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';
import 'package:shen_view/src/presentation/histogram_sample.dart';

import '../tool/generate_ico_fixtures.dart' as fixtures;

const _multi = 'testdata/formats/format_multisize.ico';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'ICO recognition, scanning, archive admission and association agree',
    () async {
      final detector = FormatDetector();
      expect(await detector.detect(File(_multi)), ImageFormat.ico);
      expect(
        detector.fromSignature(File(_multi).readAsBytesSync()),
        ImageFormat.ico,
      );
      expect(FormatDetector.formatForPath('ICON.ICO'), ImageFormat.ico);
      final cur = File(_multi).readAsBytesSync()..[2] = 2;
      expect(detector.fromSignature(cur), ImageFormat.unknown);
      final folder = await FolderIndexService().index('testdata/formats');
      expect(
        folder.where((entry) => entry.format == ImageFormat.ico),
        hasLength(3),
      );
      expect(
        const ArchiveEntry(
          index: 0,
          name: 'icon.ICO',
          originalName: 'icon.ICO',
          size: 100,
          isDirectory: false,
          encrypted: false,
        ).isImage,
        isTrue,
      );
      expect(FileAssociationFormats.images, contains('ico'));
      final capability = DecoderRegistry().capabilities().singleWhere(
        (c) => c.format == ImageFormat.ico,
      );
      expect(capability.available, isTrue);
      expect(capability.metadata, isTrue);
      expect(capability.animated, isFalse);
    },
  );

  test('directory normalizes 256 and preserves same-size variants', () async {
    final metadata = await MetadataService().read(_multi);
    expect((metadata.width, metadata.height, metadata.icoIndex), (256, 256, 2));
    expect(metadata.animation, isNull);
    expect(
      metadata.icoVariants.map((v) => (v.width, v.height, v.bitDepth, v.codec)),
      [
        (16, 16, 24, 'BMP'),
        (32, 32, 32, 'PNG'),
        (256, 256, 32, 'PNG'),
        (32, 32, 8, 'BMP'),
        (32, 32, 32, 'PNG'),
      ],
    );
    final bitmap = await MetadataService().read(
      'testdata/formats/format_bitmap.ico',
    );
    expect(bitmap.icoIndex, 4);
    expect(bitmap.bitDepth, 32);
  });

  for (final name in [
    'format_multisize.ico',
    'format_bitmap.ico',
    'format_single.ico',
  ]) {
    test(
      'all versions decode correct pixels and transparency: $name',
      () async {
        final path = 'testdata/formats/$name';
        final variants = await IcoFile.inspect(path);
        for (final variant in variants) {
          final image = imaging.decodePng(
            await IcoFile.decode(path, index: variant.index),
          )!;
          expect((image.width, image.height), (variant.width, variant.height));
          final transparent = image.getPixel(0, image.height ~/ 2);
          final center = image.getPixel(image.width ~/ 2, image.height ~/ 2);
          expect(transparent.a, 0);
          expect(center.a, 255);
          final expected = name == 'format_single.ico'
              ? (35, 90, 230)
              : [
                  (220, 40, 30),
                  (30, 190, 60),
                  (35, 90, 230),
                  (240, 170, 20),
                  (170, 50, 210),
                ][variant.index];
          expect((center.r, center.g, center.b), expected);
        }
      },
    );
  }

  test(
    'selected versions have distinct cache keys; thumbnails keep largest',
    () async {
      final resources = ImageResourceService();
      addTearDown(resources.dispose);
      addTearDown(PaintingBinding.instance.imageCache.clear);
      final entry = icoEntry(_multi);
      await resources.metadata(entry);
      final before = await resources
          .provider(entry)
          .obtainKey(ImageConfiguration.empty);
      resources.selectIcoVariant(entry, 0);
      final after = await resources
          .provider(entry)
          .obtainKey(ImageConfiguration.empty);
      expect(after, isNot(before));
      expect(after.icoIndex, 0);
      expect((await resources.metadata(entry)).width, 16);
      final main = await loadIcoImage(resources.provider(entry));
      expect((main.width, main.height), (16, 16));
      main.dispose();
      final thumbnail = await loadIcoImage(
        resources.provider(
          entry,
          targetWidth: 64,
          targetHeight: 64,
          priority: DecodePriority.visibleThumbnail,
        ),
      );
      expect((thumbnail.width, thumbnail.height), (64, 64));
      final pixel = (await thumbnail.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      expect(pixel.getUint8((32 * 64 + 32) * 4 + 2), 230);
      thumbnail.dispose();
      final histogram = await readImageHistogram(
        resources,
        entry,
        DecodeRequest(),
      );
      expect(histogram.samples, 16 * 12);
      final printed = imaging.decodePng(await resources.printBytes(entry))!;
      expect(printed.width, 16);
      resources.selectIcoVariant(entry, 4);
      final purple = await loadIcoImage(resources.provider(entry));
      final rgba = (await purple.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      expect(rgba.getUint8((16 * 32 + 16) * 4), 170);
      purple.dispose();
      resources.invalidate(entry.id);
      expect((await resources.metadata(entry)).width, 256);
    },
  );

  test(
    'corrupt offsets, truncated input, oversize and cancellation are bounded',
    () async {
      final dir = Directory.systemTemp.createTempSync('ico-corrupt-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final original = File(_multi).readAsBytesSync();
      for (final bytes in [
        original.sublist(0, 10),
        Uint8List.fromList(original)
          ..[18] = 0xff
          ..[19] = 0xff
          ..[20] = 0xff
          ..[21] = 0x7f,
        Uint8List.fromList(original)
          ..[4] = 0xff
          ..[5] = 0xff,
        fixtures.icoContainer([
          (16, 16, 32, fixtures.pngIcon(256, 256, 0, 0, 0)),
        ]),
      ]) {
        final file = File('${dir.path}/bad.ico')..writeAsBytesSync(bytes);
        await expectLater(IcoFile.inspect(file.path), throwsFormatException);
      }
      await expectLater(
        IcoFile.decode(_multi, index: 100),
        throwsFormatException,
      );
      final request = DecodeRequest()..cancel();
      await expectLater(
        IcoFile.decode(_multi, request: request),
        throwsA(isA<DecodeCancelled>()),
      );
    },
  );
}

ImageEntry icoEntry(String path) {
  final file = File(path);
  final stat = file.statSync();
  return ImageEntry(
    file: file,
    format: ImageFormat.ico,
    width: null,
    height: null,
    byteLength: stat.size,
    modifiedAt: stat.modified,
  );
}

Future<ui.Image> loadIcoImage(ImageProvider<Object> provider) {
  final result = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!result.isCompleted) result.complete(info.image.clone());
      stream.removeListener(listener);
    },
    onError: (Object error, StackTrace? stack) {
      if (!result.isCompleted) result.completeError(error, stack);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return result.future.timeout(const Duration(seconds: 15));
}
