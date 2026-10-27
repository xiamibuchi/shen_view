import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:path/path.dart' as paths;
import 'package:shen_view/src/application/archive_service.dart';

import 'support/local_tools.dart';

/// Backend-only synthetic fixture: measures actual listing/selected extraction
/// and cache reuse, not image decoding, UI latency or a speed ranking.
Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('viewer-archive-probe-');
  try {
    final inputs = Directory(paths.join(root.path, 'input'));
    await inputs.create();
    var seed = 12345;
    final bytes = Uint8List(128 * 1024);
    for (var index = 0; index < bytes.length; index++) {
      seed = (seed * 1664525 + 1013904223) & 0xffffffff;
      bytes[index] = seed >> 24;
    }
    for (var page = 0; page < 64; page++) {
      bytes[0] = page;
      await File(
        paths.join(inputs.path, '${page.toString().padLeft(3, '0')}.png'),
      ).writeAsBytes(bytes);
    }
    final sevenZip = findSevenZip();
    if (sevenZip == null) {
      throw StateError('需要 7-Zip，请将 7z/7zz 加入 PATH 或设置 SHENVIEW_7ZIP。');
    }
    final results = <Map<String, Object?>>[];
    for (final type in ['zip', '7z']) {
      final file = File(paths.join(root.path, 'fixture.$type'));
      final encoded = await Process.run(sevenZip, [
        'a',
        '-t$type',
        if (type == '7z') '-ms=on',
        file.path,
        paths.join(inputs.path, '*'),
      ]);
      if (encoded.exitCode != 0) throw StateError('Fixture encoder failed');
      final cache = Directory(paths.join(root.path, 'cache-$type'));
      final service = ArchiveService(
        cachePolicy: ArchiveCachePolicy(directory: cache),
      );
      final timer = Stopwatch()..start();
      final session = await service.open(file);
      final listingUs = timer.elapsedMicroseconds;
      final before = await service.cacheStats();
      timer.reset();
      final cold = await session.acquireFile(session.entries.last);
      final coldUs = timer.elapsedMicroseconds;
      await cold.release();
      final after = await service.cacheStats();
      timer.reset();
      final warm = await session.acquireFile(session.entries.last);
      final warmUs = timer.elapsedMicroseconds;
      await warm.release();
      results.add({
        'format': type,
        'solid': session.solid,
        'entries': session.entries.length,
        'archiveBytes': await file.length(),
        'uncompressedBytes': 64 * 128 * 1024,
        'listingUs': listingUs,
        'coldLastEntryUs': coldUs,
        'warmLastEntryUs': warmUs,
        'outputFilesAtListing': before.files,
        'outputBytesAtListing': before.bytes,
        'outputFilesAfterSelectedRead': after.files,
        'outputBytesAfterSelectedRead': after.bytes,
      });
      await session.close();
    }
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'platform': Platform.operatingSystem,
        'measurements': results,
        'notes': 'One synthetic cold/warm sample per format, includes SDK process startup in listing; excludes image decode, GPU, UI and CPU profiling. Solid reads may restart block dictionaries.',
      }),
    );
  } finally {
    await root.delete(recursive: true);
  }
}
