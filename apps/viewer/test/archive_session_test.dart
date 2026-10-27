import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/archive_service.dart';
import 'package:shen_view/src/application/archive_index.dart';
import 'package:shen_view/src/application/archive_image_source.dart';
import 'package:shen_view/src/domain/sort_order.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/domain/archive_failure.dart';
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
  group(
    'indexed archive session',
    () {
      late Directory directory;
      late ArchiveService service;
      setUp(() async {
        directory = await Directory.systemTemp.createTemp(
          'viewer-archive-session-',
        );
        service = ArchiveService(
          helperExecutable: helper.absolute.path,
          cachePolicy: ArchiveCachePolicy(
            directory: Directory(paths.join(directory.path, 'cache')),
          ),
        );
      });
      tearDown(() => directory.delete(recursive: true));
      File zip(List<(String, List<int>)> entries, {String? password}) {
        final archive = Archive();
        for (final (name, bytes) in entries) {
          archive.addFile(ArchiveFile.bytes(name, bytes));
        }
        return File(paths.join(directory.path, 'sample.cbz'))..writeAsBytesSync(
          ZipEncoder(password: password).encodeBytes(archive),
        );
      }

      Matcher failure(ArchiveFailureKind kind) => throwsA(
        isA<ArchiveOpenException>().having((error) => error.kind, 'kind', kind),
      );

      test(
        'identifies ZIP content despite a misleading RAR extension',
        () async {
          final source = zip([
            ('001.png', [1, 2, 3]),
          ]);
          final renamed = await source.rename(
            paths.join(directory.path, 'sample.cbr'),
          );
          final session = await service.open(renamed);
          addTearDown(session.close);
          expect(session.format, 'zip');
          final lease = await session.acquireFile(session.entries.single);
          addTearDown(lease.release);
          expect(await lease.file.readAsBytes(), [1, 2, 3]);
        },
      );
      test('indexes an empty ZIP without materializing files', () async {
        final session = await service.open(zip([]));
        addTearDown(session.close);
        expect(session.format, 'zip');
        expect(session.entries, isEmpty);
        expect((await service.cacheStats()).files, 0);
      });
      test('classifies a truncated ZIP as corrupt', () async {
        final source = File(paths.join(directory.path, 'broken.cbz'))
          ..writeAsBytesSync([0x50, 0x4B, 0x03, 0x04, 1, 2, 3, 4]);
        await expectLater(
          service.open(source),
          failure(ArchiveFailureKind.corrupt),
        );
        expect((await service.cacheStats()).files, 0);
      });
      test(
        'rejects an oversized entry without committing cache output',
        () async {
          final limited = ArchiveService(
            helperExecutable: helper.absolute.path,
            limits: const ArchiveLimits(maxFileBytes: 1),
            cachePolicy: service.cachePolicy,
          );
          final session = await limited.open(
            zip([
              ('001.png', [1, 2, 3]),
            ]),
          );
          addTearDown(session.close);
          await expectLater(
            session.acquireFile(session.entries.single),
            failure(ArchiveFailureKind.limit),
          );
          expect((await limited.cacheStats()).files, 0);
        },
      );
      test('indexes without materializing; selected page only, reused across sessions', () async {
        final source = zip([
          ('chapter/001.png', [1, 2, 3]),
          ('chapter/002.png', [4, 5, 6]),
        ]);
        final session = await service.open(source);
        expect(session.entries.length, 2);
        expect((await service.cacheStats()).bytes, 0);
        final lease = await session.acquireFile(session.entries[1]);
        expect(await lease.file.readAsBytes(), [4, 5, 6]);
        expect((await service.cacheStats()).files, 1);
        final location = lease.file.path;
        await service.clearCache();
        expect(await lease.file.exists(), isTrue);
        await lease.release();
        await session.close();
        final reopened = await service.open(source);
        final again = await reopened.acquireFile(reopened.entries[1]);
        expect(again.file.path, location);
        await again.release();
        await reopened.close();
        await service.clearCache();
        expect((await service.cacheStats()).files, 0);
      });
      test(
        'encrypted data uses private directory and leases survive close',
        () async {
          final source = zip([
            ('001.png', [9, 8, 7]),
          ], password: 'test-credential');
          await expectLater(
            service.open(source),
            failure(ArchiveFailureKind.encrypted),
          );
          final session = await service.open(
            source,
            password: 'test-credential',
          );
          expect(session.encrypted, isTrue);
          final lease = await session.acquireFile(session.entries.single);
          expect(await lease.file.readAsBytes(), [9, 8, 7]);
          await session.close();
          expect(await lease.file.exists(), isTrue);
          await lease.release();
          expect(await lease.file.exists(), isFalse);
          expect((await service.cacheStats()).files, 0);
        },
      );
      test(
        'duplicate names retain indexed identity and cannot overwrite',
        () async {
          final source = zip([
            ('a.png', [1]),
            ('b.png', [2]),
          ]);
          final bytes = source.readAsBytesSync();
          final marker = utf8.encode('b.png');
          for (var i = 0; i <= bytes.length - marker.length; i++) {
            if (List.generate(marker.length, (j) => bytes[i + j]).join(',') ==
                marker.join(',')) {
              bytes[i] = 97;
            }
          }
          source.writeAsBytesSync(bytes);
          final session = await service.open(source);
          final first = await session.acquireFile(session.entries.first);
          final second = await session.acquireFile(session.entries.last);
          expect(session.entries.map((entry) => entry.name), [
            'a.png',
            'a.png',
          ]);
          for (final mode in FileNameSortMode.values) {
            for (final sort in [
              SortOrder.nameAscending,
              SortOrder.nameDescending,
            ]) {
              final index = archiveIndex(
                session,
                root: directory.path,
                sort: sort,
                fileNameSortMode: mode,
              );
              expect(
                index.images.map(
                  (image) => (image.source! as ArchiveImageSource).entry.index,
                ),
                [0, 1],
              );
              expect(index.images.map((image) => image.id).toSet().length, 2);
            }
          }
          expect(first.file.path, isNot(second.file.path));
          expect(await first.file.readAsBytes(), [1]);
          expect(await second.file.readAsBytes(), [2]);
          await first.release();
          await second.release();
          await session.close();
        },
      );
      test('wrong credentials never commit plaintext files', () async {
        final source = zip([
          ('001.png', [9, 8, 7]),
        ], password: 'test-credential');
        final session = await service.open(source, password: 'incorrect');
        addTearDown(session.close);
        await expectLater(
          session.acquireFile(session.entries.single),
          throwsA(
            isA<ArchiveOpenException>().having(
              (error) => error.kind,
              'kind',
              isIn([
                ArchiveFailureKind.wrongPassword,
                ArchiveFailureKind.passwordUnverifiable,
              ]),
            ),
          ),
        );
        expect((await service.cacheStats()).files, 0);
      });
      test('Unicode names preserve non-BMP characters', () async {
        final source = zip([
          ('中文/漫画📚.png', [3]),
        ]);
        final session = await service.open(source);
        expect(session.entries.single.name, '中文/漫画📚.png');
        final image = await session.acquireFile(session.entries.single);
        expect(await image.file.readAsBytes(), [3]);
        await image.release();
        await session.close();
      });
      test('TAR exposes indexed entries without whole-book output', () async {
        final archive = Archive()
          ..addFile(ArchiveFile.bytes('chapter/001.png', [1, 2]))
          ..addFile(ArchiveFile.bytes('chapter/002.png', [3]));
        final source = File(paths.join(directory.path, 'sample.cbt'))
          ..writeAsBytesSync(TarEncoder().encodeBytes(archive));
        final session = await service.open(source);
        expect(session.format, 'tar');
        expect((await service.cacheStats()).files, 0);
        final image = await session.acquireFile(session.entries.last);
        expect(await image.file.readAsBytes(), [3]);
        await image.release();
        await session.close();
      });
      test(
        'solid 7Z retains a bounded prior window without whole-book output',
        () async {
          final tool = findSevenZip();
          if (tool == null) {
            markTestSkipped('需要 7-Zip，请将 7z/7zz 加入 PATH 或设置 SHENVIEW_7ZIP。');
            return;
          }
          final inputs = Directory(paths.join(directory.path, 'inputs'))
            ..createSync();
          File(paths.join(inputs.path, '001.png')).writeAsBytesSync([1, 2]);
          File(paths.join(inputs.path, '002.png')).writeAsBytesSync([3, 4]);
          for (var page = 3; page <= 8; page++) {
            File(paths.join(inputs.path, '00$page.png'))
                .writeAsBytesSync([page]);
          }
          final source = File(paths.join(directory.path, 'sample.cb7'));
          final encoded = await Process.run(tool, [
            'a',
            '-t7z',
            '-ms=on',
            source.path,
            paths.join(inputs.path, '*'),
          ]);
          expect(encoded.exitCode, 0);
          final session = await service.open(source);
          expect(session.format, '7z');
          expect(session.solid, isTrue);
          final image = await session.acquireFile(session.entries[1]);
          expect(await image.file.readAsBytes(), [3, 4]);
          expect((await service.cacheStats()).files, 2);
          await image.release();
          await session.close();
        },
      );
      test(
        'RAR and RAR5, including solid blocks, read indexed entries',
        () async {
          for (final (path, format, count, solid) in [
            ('testdata/formats/format_comic_rar.cbr', 'rar', 2, false),
            ('testdata/archives/rar5-compressed.rar', 'rar5', 1, false),
            ('testdata/archives/rar5-solid.rar', 'rar5', 7, true),
          ]) {
            final session = await service.open(File(path));
            expect(session.format, format);
            expect(session.entries.length, count);
            expect(session.solid, solid);
            final target = session.entries.last;
            final image = await session.acquireFile(target);
            expect(await image.file.length(), target.size);
            expect(await image.file.readAsBytes(), isNotEmpty);
            await image.release();
            await session.close();
          }
        },
      );
      test('source replacement invalidates cache', () async {
        final source = zip([
          ('001.png', [1, 2, 3]),
        ]);
        final session = await service.open(source);
        addTearDown(session.close);
        final lease = await session.acquireFile(session.entries.single);
        await lease.release();
        source.writeAsBytesSync([1, 2, 3]);
        await expectLater(
          session.acquireFile(session.entries.single),
          failure(ArchiveFailureKind.sourceChanged),
        );
      });
      test('rejects unsafe paths before data is written', () async {
        final source = zip([
          ('../outside.png', [1]),
        ]);
        await expectLater(
          service.open(source),
          failure(ArchiveFailureKind.unsafePath),
        );
        expect((await service.cacheStats()).files, 0);
      });
      test('one cancelled reader does not cancel another', () async {
        final source = zip([('001.png', List.filled(1024 * 1024, 42))]);
        final session = await service.open(source);
        addTearDown(session.close);
        final request = DecodeRequest();
        final first = session.acquireFile(
          session.entries.single,
          request: request,
        );
        final second = session.acquireFile(session.entries.single);
        final firstError = expectLater(first, throwsA(isA<DecodeCancelled>()));
        request.cancel();
        await firstError;
        final lease = await second;
        expect(await lease.file.length(), 1024 * 1024);
        await lease.release();
        expect((await service.cacheStats()).files, 1);
      });
      test('cancelling one entry preserves a queued different entry', () async {
        final source = zip([
          ('001.png', List.filled(1024 * 1024, 42)),
          ('002.png', [4, 5, 6]),
        ]);
        final session = await service.open(source);
        addTearDown(session.close);
        final request = DecodeRequest();
        final first = session.acquireFile(
          session.entries.first,
          request: request,
        );
        final cancelled = expectLater(first, throwsA(isA<DecodeCancelled>()));
        final second = session.acquireFile(session.entries.last);
        request.cancel();
        await cancelled;
        final lease = await second.timeout(const Duration(seconds: 10));
        expect(await lease.file.readAsBytes(), [4, 5, 6]);
        await lease.release();
      });
      test('budget protects active entries and admits after release', () async {
        service.configureCache(
          ArchiveCachePolicy(
            directory: Directory(paths.join(directory.path, 'cache')),
            maxBytes: 4,
          ),
        );
        final source = zip([
          ('001.png', [1, 2, 3]),
          ('002.png', [4, 5, 6]),
        ]);
        final session = await service.open(source);
        addTearDown(session.close);
        final first = await session.acquireFile(session.entries.first);
        await expectLater(
          session.acquireFile(session.entries.last),
          failure(ArchiveFailureKind.resource),
        );
        await first.release();
        final second = await session.acquireFile(session.entries.last);
        expect(await second.file.readAsBytes(), [4, 5, 6]);
        await second.release();
        expect((await service.cacheStats()).bytes, 3);
      });
      test(
        'lowered live budgets reclaim immediately and after lease release',
        () async {
          final source = zip([
            ('001.png', [1, 2, 3]),
            ('002.png', [4, 5, 6]),
          ]);
          final session = await service.open(source);
          addTearDown(session.close);
          final active = await session.acquireFile(session.entries.first);
          final idle = await session.acquireFile(session.entries.last);
          await idle.release();
          await service.configureCache(
            ArchiveCachePolicy(
              directory: service.cachePolicy.directory,
              maxBytes: 3,
              maxFiles: 1,
            ),
          );
          expect(await active.file.exists(), isTrue);
          expect(await idle.file.exists(), isFalse);
          expect((await service.cacheStats()).files, 1);
          // Reapplying the same limit must not reserve a fictitious extra slot.
          await service.configureCache(
            ArchiveCachePolicy(
              directory: service.cachePolicy.directory,
              maxBytes: 3,
              maxFiles: 1,
            ),
          );
          expect(await active.file.exists(), isTrue);
          await service.configureCache(
            ArchiveCachePolicy(
              directory: service.cachePolicy.directory,
              maxBytes: 0,
              maxFiles: 0,
            ),
          );
          expect(await active.file.exists(), isTrue);
          await active.release();
          expect((await service.cacheStats()).bytes, 0);
        },
      );
      test(
        'shorter retention reclaims idle and protected entries on release',
        () async {
          final session = await service.open(
            zip([
              ('001.png', [1]),
              ('002.png', [2]),
            ]),
          );
          addTearDown(session.close);
          final active = await session.acquireFile(session.entries.first);
          final idle = await session.acquireFile(session.entries.last);
          await idle.release();
          final old = DateTime.now().subtract(const Duration(days: 2));
          await active.file.setLastModified(old);
          await idle.file.setLastModified(old);
          await service.configureCache(
            ArchiveCachePolicy(
              directory: service.cachePolicy.directory,
              maxAge: const Duration(days: 1),
            ),
          );
          expect(await active.file.exists(), isTrue);
          expect(await idle.file.exists(), isFalse);
          await active.release();
          expect((await service.cacheStats()).files, 0);
        },
      );
      test(
        'disabling persistence switches an open session to private storage',
        () async {
          final session = await service.open(
            zip([
              ('001.png', [1]),
              ('002.png', [2]),
              ('003.png', [3]),
            ]),
          );
          final active = await session.acquireFile(session.entries[0]);
          final idle = await session.acquireFile(session.entries[1]);
          await idle.release();
          await service.configureCache(
            ArchiveCachePolicy(
              directory: service.cachePolicy.directory,
              persistent: false,
            ),
          );
          expect(await active.file.exists(), isTrue);
          expect(await idle.file.exists(), isFalse);
          final private = await session.acquireFile(session.entries[2]);
          expect(private.file.parent.path, isNot(active.file.parent.path));
          expect(
            paths.basename(private.file.parent.path),
            startsWith('private-'),
          );
          await active.release();
          expect(await active.file.exists(), isFalse);
          await session.close();
          expect(await private.file.exists(), isTrue);
          await private.release();
          expect(await private.file.exists(), isFalse);
          expect((await service.cacheStats()).files, 0);
        },
      );
      test('nested entries inherit sensitive lifetime and depth', () async {
        final inner = Archive()..addFile(ArchiveFile.bytes('001.png', [7]));
        final source = zip([
          ('inner.cbz', ZipEncoder().encodeBytes(inner)),
        ], password: 'test-credential');
        final outer = await service.open(source, password: 'test-credential');
        final container = await outer.acquireFile(outer.entries.single);
        final nested = await service.open(
          container.file,
          parent: outer,
          parentLease: container,
        );
        expect(nested.depth, 1);
        expect(nested.encrypted, isTrue);
        final image = await nested.acquireFile(nested.entries.single);
        expect(await image.file.readAsBytes(), [7]);
        await outer.close();
        expect(await container.file.exists(), isTrue);
        await image.release();
        await nested.close();
        expect(await container.file.exists(), isFalse);
        expect((await service.cacheStats()).files, 0);
      });
    },
    skip: !helper.existsSync()
        ? 'Build the archive helper before native contract tests.'
        : false,
  );
}
