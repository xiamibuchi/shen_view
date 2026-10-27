import 'dart:io';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/archive_service.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:path/path.dart' as paths;

import '../tool/support/local_tools.dart';

void main() {
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
  final encoder = findSevenZip();
  final missingTool = !helper.existsSync() || encoder == null;

  group(
    'solid archive extraction reuse',
    () {
      late Directory root;
      late File source;
      late ArchiveService service;
      late Uint8List payload;

      setUp(() async {
        root = await Directory.systemTemp.createTemp('viewer-solid-batch-');
        final inputs = await Directory(paths.join(root.path, 'input')).create();
        payload = Uint8List(32 * 1024);
        var seed = 123456;
        for (var index = 0; index < payload.length; index++) {
          seed = (seed * 1664525 + 1013904223) & 0xffffffff;
          payload[index] = seed >> 24;
        }
        for (var page = 0; page < 48; page++) {
          payload[0] = page;
          await File(
            paths.join(inputs.path, '${page.toString().padLeft(3, '0')}.png'),
          ).writeAsBytes(payload);
        }
        source = File(paths.join(root.path, 'sample.cb7'));
        final result = await Process.run(encoder!, [
          'a',
          '-t7z',
          '-ms=on',
          '-m0=lzma2',
          '-md=1m',
          source.path,
          paths.join(inputs.path, '*'),
        ]);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        service = ArchiveService(
          helperExecutable: helper.absolute.path,
          cachePolicy: ArchiveCachePolicy(
            directory: Directory(paths.join(root.path, 'cache')),
          ),
        );
      });
      tearDown(() => root.delete(recursive: true));

      Future<void> verify(ArchiveFileLease lease, int page) async {
        final bytes = await lease.file.readAsBytes();
        expect(bytes.length, payload.length);
        expect(bytes[0], page);
        expect(bytes.sublist(1), payload.sublist(1));
      }

      test('cold jump saves bounded traversed pages and reverse jumps do not re-extract', () async {
        final session = await service.open(source);
        addTearDown(session.close);
        expect(session.solid, isTrue);
        expect(
          session.entries.map((entry) => entry.block).toSet(),
          hasLength(1),
        );
        final target = await session.acquireFile(session.entries[31]);
        await verify(target, 31);
        await target.release();
        expect(session.extractionPasses, 1);
        expect((await service.cacheStats()).files, 4);
        for (final page in [30, 28, 29, 31]) {
          final lease = await session.acquireFile(session.entries[page]);
          await verify(lease, page);
          await lease.release();
        }
        expect(session.extractionPasses, 1);
        final distant = await session.acquireFile(session.entries[7]);
        await verify(distant, 7);
        await distant.release();
        expect(session.extractionPasses, 2);
        expect((await service.cacheStats()).files, 8);
        expect(
          (await service.cacheStats()).files,
          lessThan(session.entries.length),
        );
      });

      test(
        'queued actual requests share extraction without optional caching',
        () async {
          await service.configureCache(
            ArchiveCachePolicy(
              directory: service.cachePolicy.directory,
              solidCacheEntries: 0,
            ),
          );
          final session = await service.open(source);
          addTearDown(session.close);
          final pages = [20, 21, 22, 23];
          final leases = await Future.wait([
            for (final page in pages)
              session.acquireFile(session.entries[page]),
          ]);
          for (var i = 0; i < pages.length; i++) {
            await verify(leases[i], pages[i]);
            await leases[i].release();
          }
          expect(session.extractionPasses, lessThan(pages.length));
          expect((await service.cacheStats()).files, pages.length);
          final before = session.extractionPasses;
          final reverse = await session.acquireFile(session.entries[19]);
          await reverse.release();
          expect(session.extractionPasses, before + 1);
          expect((await service.cacheStats()).files, pages.length + 1);
        },
      );

      test('cancelled consumer does not kill another queued page', () async {
        final session = await service.open(source);
        addTearDown(session.close);
        final request = DecodeRequest();
        final cancelled = session.acquireFile(
          session.entries[30],
          request: request,
        );
        final cancellation = expectLater(
          cancelled,
          throwsA(isA<DecodeCancelled>()),
        );
        final survivor = session.acquireFile(session.entries[31]);
        request.cancel();
        await cancellation;
        final lease = await survivor;
        await verify(lease, 31);
        await lease.release();
        final afterwards = await session.acquireFile(session.entries[32]);
        await verify(afterwards, 32);
        await afterwards.release();
      });

      test(
        'cancelled queued page can be immediately requested again',
        () async {
          final session = await service.open(source);
          addTearDown(session.close);
          final request = _CancelOnAttachRequest();
          late Future<ArchiveFileLease> replacement;
          request.onAttached = () {
            request.cancel();
            replacement = session.acquireFile(session.entries[31]);
          };
          await expectLater(
            session
                .acquireFile(session.entries[31], request: request)
                .timeout(const Duration(seconds: 5)),
            throwsA(isA<DecodeCancelled>()),
          );
          final lease = await replacement.timeout(const Duration(seconds: 5));
          await verify(lease, 31);
          await lease.release();
        },
      );

      test(
        'disk pressure skips optional window and preserves the current page',
        () async {
          await service.configureCache(
            ArchiveCachePolicy(
              directory: service.cachePolicy.directory,
              maxBytes: payload.length,
              maxFiles: 1,
            ),
          );
          final session = await service.open(source);
          addTearDown(session.close);
          final lease = await session.acquireFile(session.entries[31]);
          await verify(lease, 31);
          expect((await service.cacheStats()).files, 1);
          expect((await service.cacheStats()).bytes, payload.length);
          await lease.release();
        },
      );

      test('encrypted solid windows stay private until the last visible lease releases', () async {
        final encrypted = File(paths.join(root.path, 'encrypted.cb7'));
        final result = await Process.run(encoder!, [
          'a',
          '-t7z',
          '-ms=on',
          '-md=1m',
          '-pfixture-password',
          '-mhe=on',
          encrypted.path,
          paths.join(root.path, 'input', '*'),
        ]);
        expect(result.exitCode, 0);
        final session = await service.open(
          encrypted,
          password: 'fixture-password',
        );
        final lease = await session.acquireFile(session.entries[31]);
        await verify(lease, 31);
        final privateRoot = lease.file.parent;
        expect(paths.basename(privateRoot.path), startsWith('private-'));
        expect((await service.cacheStats()).files, 4);
        await session.close();
        expect(await lease.file.exists(), isTrue);
        await lease.release();
        expect(await privateRoot.exists(), isFalse);
        expect((await service.cacheStats()).files, 0);
      });
      test(
        'close and last release wait for internal optional leases',
        () async {
          await service.configureCache(
            ArchiveCachePolicy(
              directory: service.cachePolicy.directory,
              persistent: false,
            ),
          );
          final session = await service.open(source);
          final lease = await session.acquireFile(session.entries[31]);
          final privateRoot = lease.file.parent;
          await Future.wait([session.close(), lease.release()]);
          expect(await privateRoot.exists(), isFalse);
          expect((await service.cacheStats()).files, 0);
        },
      );
    },
    skip: missingTool
        ? 'Build archive helper and install the 7-Zip fixture encoder.'
        : false,
  );
}

class _CancelOnAttachRequest extends DecodeRequest {
  void Function()? onAttached;

  @override
  void addCancelListener(void Function() listener) {
    super.addCancelListener(listener);
    final callback = onAttached;
    onAttached = null;
    callback?.call();
  }
}
