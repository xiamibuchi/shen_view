import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:shen_view/src/application/archive_index.dart';
import 'package:shen_view/src/application/archive_service.dart';

/// Synthetic metadata timings. Does not measure decoding, painting or FPS.
Future<void> main() async {
  final temporary = await Directory.systemTemp.createTemp('directory-probe-');
  try {
    const volumes = 10;
    const chapters = 50;
    const pages = 100;
    final archive = Archive();
    for (var volume = 1; volume <= volumes; volume++) {
      for (var chapter = 1; chapter <= chapters; chapter++) {
        for (var page = 1; page <= pages; page++) {
          archive.addFile(
            ArchiveFile.bytes(
              '卷$volume/第${chapter.toString().padLeft(2, '0')}章/$page.png',
              [0],
            ),
          );
        }
      }
    }
    final file = File('${temporary.path}/large.cbz')
      ..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
    final service = ArchiveService(
      cachePolicy: ArchiveCachePolicy(
        directory: Directory('${temporary.path}/cache'),
      ),
    );
    final timer = Stopwatch()..start();
    final session = await service.open(file);
    final listingUs = timer.elapsedMicroseconds;
    try {
      timer.reset();
      final root = archiveIndex(
        session,
        root: temporary.path,
        continuous: false,
      );
      final directoryTreeUs = timer.elapsedMicroseconds;
      timer.reset();
      var matched = 0;
      for (var volume = 1; volume <= volumes; volume++) {
        final index = archiveIndex(
          session,
          root: temporary.path,
          prefix: '卷$volume',
          continuous: false,
        );
        matched += index.childFolders
            .where((folder) => folder.name.contains('02'))
            .length;
        if (index.childFolders.any(
          (folder) => folder.hasNavigableChildren != false,
        )) {
          throw StateError('Image-only chapters must be known leaves');
        }
      }
      final hierarchySearchUs = timer.elapsedMicroseconds;
      final samples = <int>[];
      var imageCount = 0;
      for (var volume = 1; volume <= volumes; volume++) {
        for (var chapter = 1; chapter <= chapters; chapter++) {
          timer.reset();
          final index = archiveIndex(
            session,
            root: temporary.path,
            prefix: '卷$volume/第${chapter.toString().padLeft(2, '0')}章',
            continuous: false,
          );
          samples.add(timer.elapsedMicroseconds);
          imageCount += index.images.length;
        }
      }
      samples.sort();
      final cache = await service.cacheStats();
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert({
          'platform': Platform.operatingSystem,
          'entries': session.entries.length,
          'chapters': volumes * chapters,
          'rootFolders': root.childFolders.length,
          'archiveListingUs': listingUs,
          'firstDirectoryTreeUs': directoryTreeUs,
          'hierarchySearchUs': hierarchySearchUs,
          'matchingChapters': matched,
          'chapterListingMedianUs': samples[samples.length ~/ 2],
          'chapterListingP95Us': samples[(samples.length * .95).floor()],
          'imagesIndexed': imageCount,
          'extractedFiles': cache.files,
          'notes': 'One synthetic run; archive listing and first metadata tree reported separately. Search timing excludes the 250 ms input debounce and Flutter painting. Chapter timing includes creating/sorting 100 image entries. No image decoding or extraction.',
        }),
      );
    } finally {
      await session.close();
    }
  } finally {
    await temporary.delete(recursive: true);
  }
}
