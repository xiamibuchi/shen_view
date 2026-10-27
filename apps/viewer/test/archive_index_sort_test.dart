import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/archive_image_source.dart';
import 'package:shen_view/src/application/archive_index.dart';
import 'package:shen_view/src/application/archive_service.dart';
import 'package:shen_view/src/domain/sort_order.dart';
import 'package:path/path.dart' as paths;

void main() {
  late Directory directory;
  late ArchiveService service;
  var fixtureId = 0;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('archive-index-sort-');
    service = ArchiveService(
      cachePolicy: ArchiveCachePolicy(
        directory: Directory(paths.join(directory.path, 'cache')),
      ),
    );
    addTearDown(() => directory.delete(recursive: true));
  });

  Future<ArchiveSession> open(
    List<String> names, {
    bool tar = false,
    bool duplicateJpeg = false,
  }) async {
    final archive = Archive();
    for (var i = 0; i < names.length; i++) {
      // Only metadata is read: image decoding must not affect page order.
      archive.addFile(ArchiveFile.bytes(names[i], [i]));
    }
    final bytes = tar
        ? TarEncoder().encodeBytes(archive)
        : ZipEncoder().encodeBytes(archive);
    if (duplicateJpeg) {
      // Archive.addFile replaces duplicate names. Rename both ZIP headers after
      // encoding to exercise two actual entries with the same complete name.
      final marker = utf8.encode('02.jpg');
      var replacements = 0;
      for (var i = 0; i <= bytes.length - marker.length; i++) {
        if (List.generate(
          marker.length,
          (j) => bytes[i + j],
        ).indexed.every((pair) => pair.$2 == marker[pair.$1])) {
          bytes[i + 1] = 0x31;
          replacements++;
        }
      }
      expect(replacements, 2, reason: 'local and central ZIP headers');
    }
    final source = File(
      paths.join(
        directory.path,
        'fixture-${fixtureId++}.${tar ? 'tar' : 'cbz'}',
      ),
    );
    await source.writeAsBytes(bytes);
    final session = await service.open(source);
    addTearDown(session.close);
    return session;
  }

  const numericInput = [
    '10.png',
    '01.png',
    '0001.png',
    '2.jpg',
    '01-2.jpg',
    '01.jpg',
    '001.png',
    '1.png',
    '10.jpg',
    '2.png',
  ];
  const naturalAscending = [
    '1.png',
    '01.jpg',
    '01.png',
    '01-2.jpg',
    '001.png',
    '0001.png',
    '2.jpg',
    '2.png',
    '10.jpg',
    '10.png',
  ];
  const stringAscending = [
    '0001.png',
    '001.png',
    '01.jpg',
    '01.png',
    '01-2.jpg',
    '1.png',
    '10.jpg',
    '10.png',
    '2.jpg',
    '2.png',
  ];

  for (final mode in FileNameSortMode.values) {
    for (final order in [SortOrder.nameAscending, SortOrder.nameDescending]) {
      final descending = order == SortOrder.nameDescending;
      final label = '${mode.name}/${order.name}';
      for (final tar in [false, true]) {
        test(
          'real ${tar ? 'TAR' : 'ZIP'} stem, padding and extension order: $label',
          () async {
            final ascending = mode == FileNameSortMode.natural
                ? naturalAscending
                : stringAscending;
            final expected = descending
                ? ascending.reversed.toList()
                : ascending;
            for (final input in [
              numericInput,
              numericInput.reversed.toList(),
            ]) {
              final session = await open(input, tar: tar);
              final index = archiveIndex(
                session,
                root: directory.path,
                sort: order,
                fileNameSortMode: mode,
              );
              expect(index.images.map((image) => image.name), expected);
              expect(
                index.images.map((image) => image.id).toSet().length,
                input.length,
              );
              expect(index.containers, isEmpty);
            }
            expect((await service.cacheStats()).files, 0);
          },
        );
      }

      test(
        'archive extensions are alphabetical and dotted stems use the selected rule: $label',
        () async {
          const extensions = [
            'avif',
            'bmp',
            'gif',
            'heic',
            'jpeg',
            'jpg',
            'jxl',
            'png',
            'tiff',
            'webp',
          ];
          final session = await open([
            'page.v10.jpg',
            'page.v2.png',
            'page.v2.jpg',
            for (final extension in extensions.reversed) '01.$extension',
            'readme.txt',
          ]);
          final dottedNames = mode == FileNameSortMode.natural
              ? ['page.v2.jpg', 'page.v2.png', 'page.v10.jpg']
              : ['page.v10.jpg', 'page.v2.jpg', 'page.v2.png'];
          final ascending = [
            for (final extension in extensions) '01.$extension',
            ...dottedNames,
          ];
          final index = archiveIndex(
            session,
            root: directory.path,
            sort: order,
            fileNameSortMode: mode,
          );
          expect(
            index.images.map((image) => image.name),
            descending ? ascending.reversed : ascending,
          );
        },
      );

      test(
        'case-insensitive name ties have stable identities in both directions: $label',
        () async {
          // Insertion order is deliberately opposite to the raw-path tiebreaker.
          final session = await open([
            'page.jpg',
            'PAGE.png',
            'page.JPG',
            'Page.avif',
          ]);
          final expected = descending
              ? ['PAGE.png', 'page.JPG', 'page.jpg', 'Page.avif']
              : ['Page.avif', 'page.JPG', 'page.jpg', 'PAGE.png'];
          for (var repeat = 0; repeat < 2; repeat++) {
            final index = archiveIndex(
              session,
              root: directory.path,
              sort: order,
              fileNameSortMode: mode,
            );
            expect(index.images.map((image) => image.name), expected);
            expect(index.images.map((image) => image.id).toSet().length, 4);
          }
        },
      );

      test(
        'duplicate complete names follow extensions then entry index: $label',
        () async {
          final session = await open([
            '01.png',
            '02.jpg',
            '01.jpg',
          ], duplicateJpeg: true);
          expect(session.entries.map((entry) => entry.name), [
            '01.png',
            '01.jpg',
            '01.jpg',
          ]);
          final index = archiveIndex(
            session,
            root: directory.path,
            sort: order,
            fileNameSortMode: mode,
          );
          expect(
            index.images.map(
              (image) => (image.source! as ArchiveImageSource).entry.index,
            ),
            descending ? [0, 1, 2] : [1, 2, 0],
          );
          expect(index.images.map((image) => image.id).toSet().length, 3);
        },
      );

      test(
        'continuous and chapter views keep same-name formats in their directories: $label',
        () async {
          const directories = ['第2章', '第10章'];
          final session = await open([
            for (final folder in directories.reversed) ...[
              '$folder/01.png',
              '$folder/01.jpg',
            ],
            '01.png',
            '01.jpg',
          ]);
          final chapters = mode == FileNameSortMode.natural
              ? directories
              : directories.reversed.toList();
          final names = descending
              ? ['01.png', '01.jpg']
              : ['01.jpg', '01.png'];
          final index = archiveIndex(
            session,
            root: directory.path,
            sort: order,
            fileNameSortMode: mode,
          );
          expect(index.images.map((image) => image.relativePath), [
            ...names,
            for (final folder in chapters)
              for (final name in names) '$folder/$name',
          ]);
          expect(index.childFolders.map((folder) => folder.name), chapters);
          final chapter = archiveIndex(
            session,
            root: directory.path,
            prefix: '第2章',
            continuous: false,
            sort: order,
            fileNameSortMode: mode,
          );
          expect(chapter.images.map((image) => image.relativePath), [
            for (final name in names) '第2章/$name',
          ]);
        },
      );
    }
  }
}
