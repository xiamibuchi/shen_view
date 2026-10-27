import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/archive_contract.dart';
import 'package:shen_view/src/application/archive_disk_cache.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/domain/archive_failure.dart';
import 'package:path/path.dart' as paths;

ArchiveCacheItem item(int id, int bytes, {bool optional = false}) =>
    ArchiveCacheItem(
      key: id.toRadixString(16).padLeft(16, '0'),
      extension: '.PNG',
      expectedBytes: bytes,
      maximumBytes: bytes + 10,
      optional: optional,
    );

Future<void> writeOutputs(List<ArchiveCacheOutput> outputs) async {
  for (final output in outputs) {
    await output.file.writeAsBytes(
      List.filled(
        output.item.expectedBytes,
        int.parse(output.item.key, radix: 16),
      ),
    );
  }
}

Future<void> releaseAll(Map<String, ArchiveFileLease> leases) async {
  for (final lease in leases.values) {
    await lease.release();
  }
}

void main() {
  late Directory directory;
  late ArchiveDiskCache cache;

  void configure({
    int maxBytes = 64,
    int maxFiles = 8,
    bool persistent = true,
  }) {
    cache = ArchiveDiskCache.forPolicy(
      ArchiveCachePolicy(
        directory: directory,
        maxBytes: maxBytes,
        maxFiles: maxFiles,
        persistent: persistent,
      ),
    );
  }

  Future<Map<String, ArchiveFileLease>> seed(List<ArchiveCacheItem> items) =>
      cache.acquireBatch(items: items, request: null, write: writeOutputs);

  Future<List<File>> pending() async => [
    await for (final entity in directory.list(recursive: true))
      if (entity is File && entity.path.contains('.pending-')) entity,
  ];

  Matcher failure(ArchiveFailureKind kind) => throwsA(
    isA<ArchiveOpenException>().having((error) => error.kind, 'kind', kind),
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('archive-disk-batch-');
    configure();
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'mixed hits and misses share one write and all hits avoid extraction',
    () async {
      final existing = await seed([item(1, 3)]);
      await releaseAll(existing);
      var writes = 0;
      final leases = await cache.acquireBatch(
        items: [item(1, 3), item(2, 4), item(3, 5)],
        request: null,
        write: (outputs) async {
          writes++;
          expect(outputs.map((output) => output.item.key), [
            item(2, 4).key,
            item(3, 5).key,
          ]);
          expect(outputs.first.maximumBytes, 14);
          await writeOutputs(outputs);
        },
      );
      expect(writes, 1);
      expect(leases.length, 3);
      expect(await leases[item(3, 5).key]!.file.readAsBytes(), [3, 3, 3, 3, 3]);
      await releaseAll(leases);
      final hits = await cache.acquireBatch(
        items: [item(1, 3), item(2, 4)],
        request: null,
        write: (_) async => fail('Cached batch must not call the extractor'),
      );
      await releaseAll(hits);
      expect((await cache.stats()).bytes, 12);
      expect(await pending(), isEmpty);
    },
  );

  test(
    'mandatory admission precedes optional order and skips oversized neighbors',
    () async {
      configure(maxBytes: 5);
      final leases = await cache.acquireBatch(
        items: [
          item(1, 4, optional: true),
          item(2, 2, optional: true),
          item(3, 3),
        ],
        request: null,
        write: (outputs) async {
          expect(outputs.map((output) => output.item.key), [
            item(3, 3).key,
            item(2, 2).key,
          ]);
          expect(outputs.every((output) => output.maximumBytes == 5), isTrue);
          await writeOutputs(outputs);
        },
      );
      expect(leases.keys, unorderedEquals([item(2, 2).key, item(3, 3).key]));
      expect((await cache.stats()).bytes, 5);
      await releaseAll(leases);
    },
  );

  test(
    'mandatory cache hits never trigger extraction of optional neighbors',
    () async {
      final original = await seed([item(1, 2)]);
      await releaseAll(original);
      final leases = await cache.acquireBatch(
        items: [item(1, 2), item(2, 2, optional: true)],
        request: null,
        write: (_) async =>
            fail('Cached foreground must not restart solid extraction'),
      );
      expect(leases.keys, [item(1, 2).key]);
      expect((await cache.stats()).files, 1);
      await releaseAll(leases);
    },
  );

  for (final active in [false, true]) {
    test(
      'truncated optional cache does not block mandatory page (active=$active)',
      () async {
        final optional = await seed([item(1, 3)]);
        final damaged = optional.values.single.file;
        if (!active) await releaseAll(optional);
        await damaged.writeAsBytes([1]);
        final leases = await cache.acquireBatch(
          items: [item(2, 2), item(1, 3, optional: true)],
          request: null,
          write: (outputs) async {
            expect(outputs.map((output) => output.item.key), [item(2, 2).key]);
            await writeOutputs(outputs);
          },
        );
        expect(leases.keys, [item(2, 2).key]);
        expect(await leases.values.single.file.readAsBytes(), [2, 2]);
        expect(await damaged.exists(), active);
        expect(await pending(), isEmpty);
        await releaseAll(leases);
        if (active) await releaseAll(optional);
      },
    );
  }

  test(
    'truncated mandatory cache still reports corruption explicitly',
    () async {
      final original = await seed([item(1, 3)]);
      final damaged = original.values.single.file;
      await releaseAll(original);
      await damaged.writeAsBytes([1]);
      await expectLater(
        cache.acquireBatch(
          items: [item(1, 3)],
          request: null,
          write: (_) async => fail('A damaged mandatory hit must be reported'),
        ),
        failure(ArchiveFailureKind.corrupt),
      );
      await cache.clear();
      expect((await cache.stats()).files, 0);
    },
  );

  test('optional lease I/O failure is skipped while mandatory lease I/O still fails', () async {
    final original = await seed([item(1, 3)]);
    final target = original.values.single.file;
    await releaseAll(original);
    final markerPath = '${target.path}.lease';
    await File(markerPath).delete();
    final obstructedMarker = await Directory(markerPath).create();
    final leases = await cache.acquireBatch(
      items: [item(2, 2), item(1, 3, optional: true)],
      request: null,
      write: (outputs) async {
        expect(outputs.map((output) => output.item.key), [item(2, 2).key]);
        await writeOutputs(outputs);
      },
    );
    expect(leases.keys, [item(2, 2).key]);
    await releaseAll(leases);
    await expectLater(
      cache.acquireBatch(
        items: [item(1, 3)],
        request: null,
        write: (_) async => fail('Mandatory I/O failures must remain visible'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    await obstructedMarker.delete();
    await cache.clear();
    expect((await cache.stats()).files, 0);
  });

  test(
    'file count budget skips optional items without evicting batch hits',
    () async {
      configure(maxFiles: 2);
      final first = await seed([item(1, 2)]);
      await releaseAll(first);
      final leases = await seed([
        item(1, 2),
        item(2, 2),
        item(3, 2, optional: true),
      ]);
      expect(leases.keys, unorderedEquals([item(1, 2).key, item(2, 2).key]));
      expect((await cache.stats()).files, 2);
      expect(await leases[item(1, 2).key]!.file.readAsBytes(), [1, 1]);
      await releaseAll(leases);
    },
  );

  test(
    'active external leases cannot be evicted for a mandatory batch',
    () async {
      configure(maxBytes: 4);
      final active = await seed([item(1, 4)]);
      await expectLater(
        cache.acquireBatch(
          items: [item(2, 1)],
          request: null,
          write: (_) async => fail('Cannot extract before admission succeeds'),
        ),
        failure(ArchiveFailureKind.resource),
      );
      expect(await active.values.single.file.readAsBytes(), [1, 1, 1, 1]);
      await releaseAll(active);
      expect(await pending(), isEmpty);
    },
  );

  test(
    'one invalid output rolls back the whole batch and releases hit leases',
    () async {
      final existing = await seed([item(1, 2)]);
      await releaseAll(existing);
      await expectLater(
        cache.acquireBatch(
          items: [item(1, 2), item(2, 2), item(3, 3)],
          request: null,
          write: (outputs) async {
            await writeOutputs(outputs);
            await outputs.last.file.writeAsBytes([3]);
          },
        ),
        failure(ArchiveFailureKind.corrupt),
      );
      expect((await cache.stats()).files, 1);
      expect(await pending(), isEmpty);
      await cache.clear();
      expect((await cache.stats()).files, 0);
    },
  );

  test(
    'extractor failure removes partial outputs and releases all hit leases',
    () async {
      final existing = await seed([item(1, 2)]);
      await releaseAll(existing);
      await expectLater(
        cache.acquireBatch(
          items: [item(1, 2), item(2, 2), item(3, 3)],
          request: null,
          write: (outputs) async {
            await outputs.first.file.writeAsBytes([2]);
            throw StateError('extractor failed');
          },
        ),
        throwsStateError,
      );
      expect((await cache.stats()).files, 1);
      expect(await pending(), isEmpty);
      await cache.clear();
      expect((await cache.stats()).files, 0);
    },
  );

  test(
    'an oversized optional output rolls back mandatory output too',
    () async {
      configure(maxBytes: 5);
      await expectLater(
        cache.acquireBatch(
          items: [item(1, 2), item(2, 3, optional: true)],
          request: null,
          write: (outputs) async {
            await writeOutputs(outputs);
            await outputs.last.file.writeAsBytes(List.filled(6, 2));
          },
        ),
        failure(ArchiveFailureKind.corrupt),
      );
      expect((await cache.stats()).files, 0);
      expect(await pending(), isEmpty);
    },
  );

  test(
    'legacy and batch acquisitions share the same lease protection',
    () async {
      final first = item(1, 2);
      final legacy = await cache.acquire(
        key: first.key,
        extension: first.extension,
        expectedBytes: first.expectedBytes,
        maximumBytes: first.maximumBytes,
        request: null,
        write: (output, maximum) => output.writeAsBytes([1, 1]),
      );
      final batch = await seed([first, item(2, 2)]);
      await legacy.release();
      await legacy.release();
      await cache.clear();
      expect((await cache.stats()).files, 2);
      await releaseAll(batch);
      await cache.clear();
      expect((await cache.stats()).files, 0);
    },
  );

  test(
    'cancellation after extraction leaves no new files or retained hit leases',
    () async {
      final existing = await seed([item(1, 2)]);
      await releaseAll(existing);
      final request = DecodeRequest();
      await expectLater(
        cache.acquireBatch(
          items: [item(1, 2), item(2, 2), item(3, 3)],
          request: request,
          write: (outputs) async {
            await writeOutputs(outputs);
            request.cancel();
          },
        ),
        throwsA(isA<DecodeCancelled>()),
      );
      expect((await cache.stats()).files, 1);
      expect(await pending(), isEmpty);
      await cache.clear();
      expect((await cache.stats()).files, 0);
    },
  );

  test(
    'rename failure after first commit removes the already published file',
    () async {
      await expectLater(
        cache.acquireBatch(
          items: [item(1, 2), item(2, 2)],
          request: null,
          write: (outputs) async {
            await writeOutputs(outputs);
            // A directory at the second destination forces rename failure only
            // after the first valid output has been committed.
            await Directory(outputs.last.file.path.split('.pending-').first)
                .create();
          },
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect((await cache.stats()).files, 0);
      expect(await pending(), isEmpty);
      final retried = await seed([item(1, 2)]);
      expect(await retried.values.single.file.readAsBytes(), [1, 1]);
      await releaseAll(retried);
    },
  );

  test(
    'maintenance stays locked until batch write and commit are complete',
    () async {
      final started = Completer<void>();
      final finish = Completer<void>();
      final batch = cache.acquireBatch(
        items: [item(1, 2), item(2, 2)],
        request: null,
        write: (outputs) async {
          started.complete();
          await finish.future;
          await writeOutputs(outputs);
        },
      );
      await started.future;
      var statsFinished = false;
      final stats = cache.stats().then((value) {
        statsFinished = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(statsFinished, isFalse);
      finish.complete();
      final leases = await batch;
      expect((await stats).files, 2);
      await releaseAll(leases);
    },
  );

  test('sensitive batches stay private and preserve ordinary cache policy switching', () async {
    final ordinary = await seed([item(1, 2)]);
    final (private, marker) = await cache.privateDirectory();
    try {
      final leases = await cache.acquireBatch(
        items: [item(2, 2), item(3, 2)],
        request: null,
        privateRoot: private,
        sensitive: true,
        write: writeOutputs,
      );
      expect(
        leases.values.every(
          (lease) => paths.equals(lease.file.parent.path, private.path),
        ),
        isTrue,
      );
      configure(persistent: false);
      await releaseAll(ordinary);
      expect((await cache.stats()).files, 2);
      await releaseAll(leases);
      await expectLater(
        cache.acquireBatch(
          items: [item(4, 1)],
          request: null,
          write: writeOutputs,
        ),
        failure(ArchiveFailureKind.resource),
      );
    } finally {
      await marker.close();
    }
  });

  test(
    'batch input caps reject excessive or duplicate keys before extraction',
    () async {
      for (final items in [
        List.generate(17, (index) => item(index, 1)),
        [item(1, 1), item(1, 1)],
      ]) {
        await expectLater(
          cache.acquireBatch(
            items: items,
            request: null,
            write: (_) async =>
                fail('Invalid batches cannot invoke extraction'),
          ),
          throwsArgumentError,
        );
      }
      expect((await cache.stats()).files, 0);
      expect(await pending(), isEmpty);
    },
  );
}
