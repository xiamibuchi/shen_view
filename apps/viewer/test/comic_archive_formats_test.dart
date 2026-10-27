import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as bitmap;
import 'package:shen_view/src/application/archive_service.dart';
import 'package:shen_view/src/application/format_detector.dart';
import 'package:shen_view/src/domain/image_format.dart';
import 'package:path/path.dart' as paths;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final helper = File(
    paths.join(
      '..',
      '..',
      'build',
      'archive-helper',
      'bin',
      Platform.isWindows ? 'viewer_archive.exe' : 'viewer_archive',
    ),
  );

  test('comic suffixes route through the shared archive detector', () {
    for (final extension in ['cbz', 'cbr', 'cb7']) {
      for (final suffix in [extension, extension.toUpperCase()]) {
        expect(FormatDetector.isArchivePath('book.$suffix'), isTrue);
        expect(
          FormatDetector.formatForPath('book.$suffix'),
          ImageFormat.archive,
        );
      }
    }
  });

  group(
    'comic archives use the bundled engine and real image codecs',
    () {
      late Directory directory;
      late ArchiveService service;
      setUp(() async {
        directory = await Directory.systemTemp.createTemp('comic-formats-');
        service = ArchiveService(
          helperExecutable: helper.absolute.path,
          cachePolicy: ArchiveCachePolicy(
            directory: Directory(paths.join(directory.path, 'cache')),
          ),
        );
      });
      tearDown(() => directory.delete(recursive: true));

      test(
        'CBZ contains ZIP pages that index lazily and decode exact pixels',
        () async {
          final pages = [
            _png(64, 48, (213, 52, 83)),
            _png(72, 56, (47, 171, 99)),
          ];
          final archive = Archive();
          for (var index = 0; index < pages.length; index++) {
            archive.addFile(
              ArchiveFile.bytes('00${index + 1}.png', pages[index]),
            );
          }
          final source = File(paths.join(directory.path, 'pages.cbz'))
            ..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
          expect(await FormatDetector().detect(source), ImageFormat.archive);
          final session = await service.open(source);
          addTearDown(session.close);
          expect(session.format, 'zip');
          expect(session.solid, isFalse);
          expect(session.entries.map((entry) => (entry.name, entry.size)), [
            ('001.png', pages[0].length),
            ('002.png', pages[1].length),
          ]);
          expect((await service.cacheStats()).files, 0);
          await _decodePages(session, [
            (64, 48, (213, 52, 83)),
            (72, 56, (47, 171, 99)),
          ]);
        },
      );

      test(
        'CBR RAR4 compressed JPEG and PNG decode the checkerboard',
        () async {
          final source = File('testdata/formats/format_comic_rar.cbr');
          expect(await FormatDetector().detect(source), ImageFormat.archive);
          final session = await service.open(source);
          addTearDown(session.close);
          expect(session.format, 'rar');
          expect(session.solid, isFalse);
          expect(session.entries.map((entry) => (entry.name, entry.size)), [
            ('testfile.jpg', 220),
            ('testfile.png', 87),
          ]);
          expect((await service.cacheStats()).files, 0);
          for (final entry in session.entries.reversed) {
            expect(entry.isImage, isTrue);
            final lease = await session.acquireFile(entry);
            try {
              final bytes = await lease.file.readAsBytes();
              expect(bytes.length, entry.size);
              await _decode(bytes, (image, rgba) {
                expect((image.width, image.height), (2, 2));
                for (var pixel = 0; pixel < 4; pixel++) {
                  final expected = pixel == 0 || pixel == 3 ? 0 : 255;
                  for (var channel = 0; channel < 3; channel++) {
                    expect(
                      (rgba.getUint8(pixel * 4 + channel) - expected).abs(),
                      lessThanOrEqualTo(6),
                    );
                  }
                  expect(rgba.getUint8(pixel * 4 + 3), 255);
                }
              });
            } finally {
              await lease.release();
            }
          }
        },
      );

      for (final fixture in [
        ('comic-nonsolid.cb7', false, false),
        ('comic-solid.cb7', true, false),
        ('comic-header-encrypted.cb7', true, true),
      ]) {
        test(
          'CB7 ${fixture.$1} indexes and decodes both real PNG pages',
          () async {
            final source = File('testdata/archives/${fixture.$1}');
            expect(await FormatDetector().detect(source), ImageFormat.archive);
            final session = await service.open(
              source,
              password: fixture.$3 ? 'comic-fixture-password' : null,
            );
            addTearDown(session.close);
            expect(session.format, '7z');
            expect(session.solid, fixture.$2);
            expect(session.encrypted, fixture.$3);
            expect(session.entries.map((entry) => (entry.name, entry.size)), [
              ('001.png', 219),
              ('002.png', 247),
            ]);
            expect((await service.cacheStats()).files, 0);
            await _decodePages(session, [
              (64, 48, (213, 52, 83)),
              (72, 56, (47, 171, 99)),
            ]);
          },
        );
      }

      for (final fixture in [
        ('rar5-compressed.rar', false, 1),
        ('rar5-solid.rar', true, 7),
      ]) {
        test(
          'CBR ${fixture.$1} validates RAR5 binary data, not image coverage',
          () async {
            final source = await File('testdata/archives/${fixture.$1}')
                .copy(paths.join(directory.path, '${fixture.$1}.cbr'));
            expect(await FormatDetector().detect(source), ImageFormat.archive);
            final session = await service.open(source);
            addTearDown(session.close);
            expect(session.format, 'rar5');
            expect(session.solid, fixture.$2);
            expect(session.entries.length, fixture.$3);
            expect(session.entries.every((entry) => !entry.isImage), isTrue);
            expect(session.entries.first.name, 'test.bin');
            expect(session.entries.first.size, 1200);
            expect((await service.cacheStats()).files, 0);
            final entry = session.entries.last;
            expect(entry.name, fixture.$2 ? 'test6.bin' : 'test.bin');
            expect(entry.size, fixture.$2 ? 4096 : 1200);
            final lease = await session.acquireFile(entry);
            try {
              final bytes = await lease.file.readAsBytes();
              expect(bytes.length, entry.size);
              expect(getCrc32(bytes), fixture.$2 ? 0x36a448ff : 0x7cca70cd);
            } finally {
              await lease.release();
            }
          },
        );
      }
    },
    skip: helper.existsSync()
        ? false
        : 'Bundled archive helper missing: ${helper.path}. Build it with the repository archive-helper CMake target before running real format validation.',
  );
}

Uint8List _png(int width, int height, (int, int, int) color) {
  final image = bitmap.Image(width: width, height: height);
  bitmap.fill(image, color: bitmap.ColorRgb8(color.$1, color.$2, color.$3));
  return Uint8List.fromList(bitmap.encodePng(image));
}

Future<void> _decodePages(
  ArchiveSession session,
  List<(int, int, (int, int, int))> expected,
) async {
  // Read the last page first, including a target later in a solid block.
  for (var index = expected.length - 1; index >= 0; index--) {
    final entry = session.entries[index];
    expect(entry.isImage, isTrue);
    final lease = await session.acquireFile(entry);
    try {
      final bytes = await lease.file.readAsBytes();
      expect(bytes.length, entry.size);
      await _decode(bytes, (image, rgba) {
        final (width, height, color) = expected[index];
        expect((image.width, image.height), (width, height));
        for (var pixel = 0; pixel < width * height; pixel++) {
          final offset = pixel * 4;
          expect(
            (
              rgba.getUint8(offset),
              rgba.getUint8(offset + 1),
              rgba.getUint8(offset + 2),
              rgba.getUint8(offset + 3),
            ),
            (color.$1, color.$2, color.$3, 255),
          );
        }
      });
    } finally {
      await lease.release();
    }
  }
}

Future<void> _decode(
  Uint8List bytes,
  void Function(ui.Image image, ByteData rgba) verify,
) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    try {
      final rgba = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      verify(frame.image, rgba!);
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
