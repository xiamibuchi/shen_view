import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:shen_view/src/application/archive_service.dart';
import 'package:path/path.dart' as paths;

import 'support/local_tools.dart';

/// Reproducible backend comparison with an application-cold, OS-warm cache.
/// Payloads are synthetic binary data, not real images or UI latency samples.
Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('viewer-solid-probe-');
  try {
    final input = await Directory(paths.join(root.path, 'input')).create();
    const pages = 256;
    const pageBytes = 1024 * 1024;
    final bytes = Uint8List(pageBytes);
    var seed = 12345;
    for (var page = 0; page < pages; page++) {
      for (var index = 0; index < bytes.length; index++) {
        seed = (seed * 1664525 + 1013904223) & 0xffffffff;
        bytes[index] = seed >> 24;
      }
      bytes[0] = page;
      await File(
        paths.join(input.path, '${page.toString().padLeft(3, '0')}.png'),
      ).writeAsBytes(bytes);
    }
    final source = File(paths.join(root.path, 'large-solid.cb7'));
    final encoded = await Process.run(
      findSevenZip() ??
          (throw StateError('需要 7-Zip，请将 7z/7zz 加入 PATH 或设置 SHENVIEW_7ZIP。')),
      [
        'a',
        '-t7z',
        '-ms=on',
        '-mx=1',
        '-md=1m',
        '-mmt=2',
        source.path,
        paths.join(input.path, '*'),
      ],
    );
    if (encoded.exitCode != 0) throw StateError('Solid fixture encoder failed');
    final results = <Map<String, Object?>>[];
    const trace = [
      223,
      222,
      221,
      220,
      127,
      126,
      125,
      124,
      255,
      254,
      253,
      252,
      63,
      62,
      61,
      60,
    ];
    var cacheId = 0;
    Future<void> measure({
      required String name,
      required int window,
      required List<int> requests,
      bool concurrent = false,
    }) async {
      final service = ArchiveService(
        cachePolicy: ArchiveCachePolicy(
          directory: Directory(paths.join(root.path, 'cache-${cacheId++}')),
          solidCacheEntries: window,
        ),
      );
      final session = await service.open(source);
      try {
        if (!session.solid) throw StateError('Fixture is not solid');
        final timer = Stopwatch()..start();
        Future<void> read(int page) async {
          final lease = await session.acquireFile(session.entries[page]);
          try {
            if (await lease.file.length() != pageBytes) {
              throw StateError('Invalid extracted size');
            }
            final file = await lease.file.open();
            try {
              if ((await file.read(1)).single != page) {
                throw StateError('Wrong indexed page content');
              }
            } finally {
              await file.close();
            }
          } finally {
            await lease.release();
          }
        }

        if (concurrent) {
          await Future.wait([for (final page in requests) read(page)]);
        } else {
          for (final page in requests) {
            await read(page);
          }
        }
        timer.stop();
        final stats = await service.cacheStats();
        results.add({
          'case': name,
          'optionalPrecedingPages': window,
          'requestedPages': requests,
          'concurrentRequests': concurrent,
          'elapsedUs': timer.elapsedMicroseconds,
          'nativeExtractionPasses': session.extractionPasses,
          'sdkReportedWorkBytes': session.reportedWorkBytes,
          'diskCacheFiles': stats.files,
          'diskCacheBytes': stats.bytes,
        });
      } finally {
        await session.close();
      }
    }

    for (var run = 0; run < 3; run++) {
      // Alternate order to reduce a consistently favored OS-cache order.
      for (final window in run.isEven ? [0, 3] : [3, 0]) {
        await measure(
          name: 'jump-and-reverse-$run',
          window: window,
          requests: trace,
        );
      }
    }
    await measure(
      name: 'separate-four-pages',
      window: 0,
      requests: [223, 224, 225, 226],
    );
    await measure(
      name: 'coalesced-four-pages',
      window: 0,
      requests: [223, 224, 225, 226],
      concurrent: true,
    );
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'platform': Platform.operatingSystem,
        'fixture': {
          'pages': pages,
          'pageBytes': pageBytes,
          'uncompressedBytes': pages * pageBytes,
          'archiveBytes': await source.length(),
        },
        'measurements': results,
        'notes': 'Synthetic 256 MiB single-solid-block data. Fresh application disk cache for every case, OS storage cache not flushed. Timings include version checks, extraction, cache writes and lease release; exclude image decode, UI, GPU, and CPU/peak-memory profiling. window=0/sequential is a per-entry-extraction reference using the same current native engine. SDK work progress is format-dependent. Three runs do not establish population P95. Arbitrary uncached distant targets can still restart the block dictionary.',
      }),
    );
  } finally {
    await root.delete(recursive: true);
  }
}
