import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/archive_service.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/folder_index_service.dart';
import 'package:shen_view/src/application/folder_order_provider.dart';
import 'package:shen_view/src/application/viewer_controller.dart';
import 'package:shen_view/src/application/reading_state_store.dart';
import 'package:shen_view/src/domain/reading_state.dart';
import 'package:shen_view/src/domain/archive_failure.dart';
import 'package:shen_view/src/domain/archive_open_state.dart';
import 'package:shen_view/src/domain/folder_browse_mode.dart';
import 'package:shen_view/src/domain/folder_index_result.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';

void main() {
  test('book reading history restores a chapter', () async {
    final root = await Directory.systemTemp.createTemp('viewer-chapter-resume');
    _tempDirectoryTeardown(root);
    final source = File(_path(root, 'book.cbz'))
      ..writeAsBytesSync(
        _zipBytes({
          'cover.png': [1],
          'chapter/2.png': [2],
        }),
      );
    final config = await _configStore();
    final history = ReadingStateStore(config);
    await history.load();
    await history.save(
      ReadingStateStore.archiveKey(source.path),
      const ReadingState(entryPath: 'chapter/2.png'),
    );
    final controller = ViewerController(configStore: config);
    addTearDown(controller.dispose);
    controller.configureArchive(
      const ViewerSettings(archiveContinuousReading: false),
    );
    expect(await controller.openArchive(source), ArchiveOpenOutcome.opened);
    expect(controller.currentEntry!.relativePath, 'chapter/2.png');
    expect(controller.entries, hasLength(1));
  });

  test(
    'folder progress resumes by path while explicit file selection wins',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'viewer-folder-resume',
      );
      _tempDirectoryTeardown(root);
      for (final name in ['1.png', '2.png', '3.png']) {
        await _writePng(File(_path(root, name)));
      }
      final config = await _configStore();
      final history = ReadingStateStore(config);
      await history.load();
      await history.save(
        ReadingStateStore.folderKey(root.path),
        const ReadingState(entryPath: '2.png'),
      );
      final controller = ViewerController(configStore: config);
      addTearDown(controller.dispose);
      await controller.openFolder(root.path);
      expect(controller.currentEntry!.name, '2.png');
      await controller.openFolder(
        root.path,
        preferredFilePath: _path(root, '3.png'),
      );
      expect(controller.currentEntry!.name, '3.png');
      await File(_path(root, '2.png')).delete();
      await controller.openFolder(root.path);
      expect(controller.currentEntry!.name, '1.png');
    },
  );

  test(
    'startup resumes the last ordinary archive rather than its parent folder',
    () async {
      final root = await Directory.systemTemp.createTemp('viewer-book-startup');
      _tempDirectoryTeardown(root);
      final source = File(_path(root, 'book.cbz'))
        ..writeAsBytesSync(
          _zipBytes({
            '1.png': [1],
            '2.png': [2],
          }),
        );
      final config = await _configStore();
      final first = ViewerController(configStore: config);
      await first.openArchive(source);
      first.select(1);
      await first.flushPersistence();
      first.dispose();
      final second = ViewerController(configStore: config);
      addTearDown(second.dispose);
      expect(await second.restoreRecentFolder(), isTrue);
      expect(second.isArchiveView, isTrue);
      expect(second.currentEntry!.name, '2.png');
      expect(second.archiveContext!.archiveFile.path, source.path);
    },
  );

  test('file name rule reorders cached images and folders without moving selection', () async {
    final root = await Directory.systemTemp.createTemp('viewer-name-rule');
    _tempDirectoryTeardown(root);
    for (final name in [
      '10.png',
      '2.png',
      '01.png',
      '01.jpg',
      '001.png',
      '0001.png',
    ]) {
      await _writePng(File(_path(root, name)));
    }
    for (final name in ['第10章', '第2章']) {
      final chapter = await Directory(_path(root, name)).create();
      await _writePng(File(_path(chapter, '1.png')));
    }
    final service = _CountingIndexService();
    final store = await _configStore();
    final controller = ViewerController(
      indexService: service,
      configStore: store,
    );
    addTearDown(controller.dispose);
    controller.configureOptions(
      sortOrder: SortOrder.nameAscending,
      browseMode: FolderBrowseMode.recursiveFolders,
      scanUnknownExtensions: false,
    );
    await controller.openFolder(root.path);
    expect(controller.entries.map((e) => e.name), [
      '01.jpg',
      '01.png',
      '001.png',
      '0001.png',
      '2.png',
      '10.png',
    ]);
    expect(controller.childFolders.map((e) => e.name), ['第2章', '第10章']);
    controller.select(4);
    final selected = controller.currentEntry!.id;
    final scans = service.calls;
    await controller.setOptions(
      fileNameSortMode: FileNameSortMode.lexicographic,
    );
    expect(controller.entries.map((e) => e.name), [
      '0001.png',
      '001.png',
      '01.jpg',
      '01.png',
      '10.png',
      '2.png',
    ]);
    expect(controller.childFolders.map((e) => e.name), ['第10章', '第2章']);
    expect(controller.currentEntry!.id, selected);
    expect(service.calls, scans);
    expect(
      (await ViewerSettings.load(store: store)).fileNameSortMode,
      FileNameSortMode.lexicographic,
    );
    await controller.setOptions(sortOrder: SortOrder.nameDescending);
    expect(controller.entries.map((e) => e.name), [
      '2.png',
      '10.png',
      '01.png',
      '01.jpg',
      '001.png',
      '0001.png',
    ]);
    expect(controller.currentEntry!.id, selected);
    expect(service.calls, scans);
  });

  test('sort changes reuse the cached folder scan', () async {
    final root = await Directory.systemTemp.createTemp('viewer-sort-cache');
    _tempDirectoryTeardown(root);
    await _writePng(File(_path(root, 'b.png')));
    await _writePng(File(_path(root, 'a.png')));
    final service = _CountingIndexService();
    final controller = ViewerController(
      indexService: service,
      configStore: await _configStore(),
    );
    addTearDown(controller.dispose);
    controller.configureOptions(
      sortOrder: SortOrder.fileSystem,
      browseMode: FolderBrowseMode.currentFolder,
      scanUnknownExtensions: false,
    );

    await controller.openFolder(root.path);
    expect(service.calls, 1);
    await controller.setOptions(sortOrder: SortOrder.nameAscending);
    expect(service.calls, 1);
    expect(controller.entries.map((entry) => entry.name), ['a.png', 'b.png']);
  });

  test(
    'flat mode retains directory metadata alongside the flattened images',
    () async {
      final root = await Directory.systemTemp.createTemp('viewer-flat-cache');
      _tempDirectoryTeardown(root);
      final child = await Directory(_path(root, 'chapter')).create();
      await _writePng(File(_path(root, 'b.png')));
      await _writePng(File(_path(child, 'a.png')));
      final controller = ViewerController(
        indexService: _CountingIndexService(),
        configStore: await _configStore(),
      );
      addTearDown(controller.dispose);

      await controller.openFolder(root.path);
      await controller.setOptions(browseMode: FolderBrowseMode.recursiveFlat);

      expect(controller.entries.map((entry) => entry.relativePath), [
        'b.png',
        'chapter/a.png',
      ]);
      expect(controller.childFolders.single.name, 'chapter');
      expect(controller.activeBrowseMode.isFlat, isTrue);
    },
  );

  test('opens an archive with its own root boundary', () async {
    final root = await Directory.systemTemp.createTemp('viewer-archive-open');
    _tempDirectoryTeardown(root);
    final source = File(_path(root, 'book.cbz'))
      ..writeAsBytesSync(
        _zipBytes({
          '001.png': [0x89, 0x50, 0x4E, 0x47],
        }),
      );
    final config = await _configStore();
    final controller = ViewerController(configStore: config);
    addTearDown(controller.dispose);

    final outcome = await controller.openArchive(source);

    expect(outcome, ArchiveOpenOutcome.opened);
    expect(controller.isArchiveView, isTrue);
    expect(controller.isReadOnlyArchive, isTrue);
    expect(controller.archiveContext?.displayName, 'book.cbz');
    expect(controller.entries.map((entry) => entry.name), ['001.png']);
    expect(controller.parentFolderPath, isNull);
    expect(controller.archiveStateFor(source).phase, ArchiveOpenPhase.ready);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    final session = (await config.read())['session'] as Map?;
    expect(session?['recentFolder'], root.path);
    final recentFile = session?['recentFile'] as String?;
    expect(recentFile, isNull);
  });

  test('archive navigation cannot leave the explicitly opened root', () async {
    final root = await Directory.systemTemp.createTemp('viewer-archive-back');
    _tempDirectoryTeardown(root);
    final source = File(_path(root, 'book.cbz'))
      ..writeAsBytesSync(
        _zipBytes({
          '001.png': [0x89, 0x50, 0x4E, 0x47],
        }),
      );
    final controller = ViewerController(configStore: await _configStore());
    addTearDown(controller.dispose);

    await controller.openArchive(source);
    final extractionRoot = controller.archiveContext!.extractionRoot;
    expect(controller.parentFolderPath, isNull);

    await controller.navigateToFolder(extractionRoot);
    expect(controller.isArchiveView, isTrue);
    expect(controller.folderPath, extractionRoot);

    await controller.navigateToFolder(root.path);
    expect(controller.isArchiveView, isTrue);
    expect(controller.folderPath, extractionRoot);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await Directory(extractionRoot).exists(), isFalse);
  });

  test('reports an archive without images as empty', () async {
    final root = await Directory.systemTemp.createTemp('viewer-archive-empty');
    _tempDirectoryTeardown(root);
    final source = File(_path(root, 'empty.cbz'))
      ..writeAsBytesSync(_zipBytes({'readme.txt': 'hello'.codeUnits}));
    final controller = ViewerController(configStore: await _configStore());
    addTearDown(controller.dispose);

    final outcome = await controller.openArchive(source);

    expect(outcome, ArchiveOpenOutcome.empty);
    expect(controller.isArchiveView, isFalse);
    expect(controller.folderPath, isNull);
    expect(controller.lastArchiveFailure, ArchiveFailureKind.empty);
    expect(controller.archiveStateFor(source).isEmpty, isTrue);
  });

  test(
    'reports a damaged archive as failed and keeps the current view',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'viewer-archive-broken',
      );
      _tempDirectoryTeardown(root);
      await _writePng(File(_path(root, 'cover.png')));
      final source = File(_path(root, 'broken.cbz'))
        ..writeAsBytesSync([0x50, 0x4B, 0x03, 0x04, 1, 2, 3, 4]);
      final controller = ViewerController(configStore: await _configStore());
      addTearDown(controller.dispose);
      await controller.openFolder(root.path);

      final outcome = await controller.openArchive(source);

      expect(outcome, ArchiveOpenOutcome.failed);
      expect(controller.lastArchiveFailure, ArchiveFailureKind.corrupt);
      expect(controller.archiveStateFor(source).hasFailed, isTrue);
      expect(controller.folderPath, root.path);
      expect(controller.entries.map((entry) => entry.name), ['cover.png']);
    },
  );

  test(
    'opens nested archives by source entry and returns to the parent selection',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'viewer-archive-nested',
      );
      _tempDirectoryTeardown(root);
      final nested = _zipBytes({
        '002.png': [0x89, 0x50, 0x4E, 0x47],
      });
      final source = File(_path(root, 'book.cbz'))
        ..writeAsBytesSync(
          _zipBytes({
            '001.png': [0x89, 0x50, 0x4E, 0x47],
            'nested.cbz': nested,
          }),
        );
      final controller = ViewerController(configStore: await _configStore());
      addTearDown(controller.dispose);
      await controller.openArchive(source);
      final parent = controller.archiveContext!;
      final parentEntryId = controller.currentEntry!.id;
      final nestedEntry = controller.containers.single;
      expect(nestedEntry.isMaterialized, isFalse);

      final outcome = await controller.openArchiveEntry(nestedEntry);

      expect(outcome, ArchiveOpenOutcome.opened);
      expect(controller.archiveContext!.parent, same(parent));
      expect(controller.archiveContext!.archiveFile.path, source.path);
      expect(controller.archiveContext!.displayName, 'book.cbz/nested.cbz');
      expect(controller.entries.map((entry) => entry.name), ['002.png']);
      expect(controller.parentFolderPath, parent.extractionRoot);
      await controller.navigateToFolder(controller.parentFolderPath!);
      expect(controller.archiveContext, same(parent));
      expect(controller.currentEntry!.id, parentEntryId);
      expect(controller.isArchiveView, isTrue);
      expect(
        controller.entries.every((entry) => !entry.name.endsWith('.cbz')),
        isTrue,
      );
    },
  );

  test('archive first screen acquires only its target and releases the preparation lease', () async {
    final root = await Directory.systemTemp.createTemp('viewer-lazy-first');
    _tempDirectoryTeardown(root);
    final source = File(_path(root, 'book.cbz'))
      ..writeAsBytesSync(
        _zipBytes({
          '3.png': [3],
          '1.png': [1],
          '2.png': [2],
        }),
      );
    final service = ArchiveService(
      cachePolicy: ArchiveCachePolicy(
        directory: Directory(_path(root, 'cache')),
      ),
    );
    final controller = ViewerController(
      configStore: await _configStore(),
      archiveService: service,
    );
    addTearDown(controller.dispose);
    var prepared = 0;
    controller.prepareArchiveEntry = (entry, request) async {
      prepared++;
      expect(entry.isMaterialized, isTrue);
      expect(entry.name, '1.png');
      expect(await entry.file.readAsBytes(), [1]);
    };
    expect(await controller.openArchive(source), ArchiveOpenOutcome.opened);
    expect(prepared, 1);
    expect(controller.entries.every((entry) => !entry.isMaterialized), isTrue);
    expect(controller.entries.map((entry) => entry.id).toSet().length, 3);
    expect((await service.cacheStats()).files, 1);
    await service.clearCache();
    expect(
      (await service.cacheStats()).files,
      0,
      reason: 'The first-screen preparation lease must already be released.',
    );
  });

  test(
    'first-page decode failure keeps archive navigation and releases its lease',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'viewer-bad-first-page',
      );
      _tempDirectoryTeardown(root);
      final source = File(_path(root, 'book.cbz'))
        ..writeAsBytesSync(
          _zipBytes({
            '第01章/001.png': [1],
            '第02章/002.png': [2],
          }),
        );
      final service = ArchiveService(
        cachePolicy: ArchiveCachePolicy(
          directory: Directory(_path(root, 'cache')),
        ),
      );
      final controller = ViewerController(
        configStore: await _configStore(),
        archiveService: service,
      );
      addTearDown(controller.dispose);
      controller.prepareArchiveEntry = (_, _) async {
        throw StateError('Image codec failed');
      };

      expect(await controller.openArchive(source), ArchiveOpenOutcome.opened);
      expect(controller.lastArchiveFailure, isNull);
      expect(controller.entries.length, 2);
      expect(controller.childFolders.map((folder) => folder.name), [
        '第01章',
        '第02章',
      ]);
      controller.select(1);
      expect(controller.currentEntry!.relativePath, '第02章/002.png');
      await service.clearCache();
      expect((await service.cacheStats()).files, 0);
    },
  );

  test(
    'archive failures during first-page preparation still abort opening',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'viewer-prepare-archive-error',
      );
      _tempDirectoryTeardown(root);
      final source = File(_path(root, 'book.cbz'))
        ..writeAsBytesSync(
          _zipBytes({
            '001.png': [1],
          }),
        );
      final controller = ViewerController(configStore: await _configStore());
      addTearDown(controller.dispose);
      controller.prepareArchiveEntry = (_, _) async {
        throw const ArchiveOpenException(ArchiveFailureKind.io);
      };

      expect(await controller.openArchive(source), ArchiveOpenOutcome.failed);
      expect(controller.lastArchiveFailure, ArchiveFailureKind.io);
      expect(controller.archiveContext, isNull);
    },
  );

  test('archive chapters use natural continuous order and isolated chapter browsing', () async {
    final root = await Directory.systemTemp.createTemp(
      'viewer-archive-chapters',
    );
    _tempDirectoryTeardown(root);
    final source = File(_path(root, 'book.cbz'))
      ..writeAsBytesSync(
        _zipBytes({
          'chapter10/10.png': [10],
          'chapter2/10.png': [20],
          'root10.png': [30],
          'chapter2/2.png': [40],
          'chapter2/sub/1.png': [41],
          'chapter2-extra/1.png': [42],
          'root2.png': [50],
        }),
      );
    final controller = ViewerController(configStore: await _configStore());
    addTearDown(controller.dispose);
    expect(await controller.openArchive(source), ArchiveOpenOutcome.opened);
    expect(controller.entries.map((entry) => entry.relativePath), [
      'root2.png',
      'root10.png',
      'chapter2/2.png',
      'chapter2/10.png',
      'chapter2/sub/1.png',
      'chapter2-extra/1.png',
      'chapter10/10.png',
    ]);
    final chapter = controller.childFolders.first;
    expect(chapter.name, 'chapter2');
    await controller.navigateToFolder(chapter.directory.path);
    expect(controller.currentEntry!.relativePath, 'chapter2/2.png');
    expect(controller.entries.length, 7);
    expect(controller.folderPath, controller.archiveContext!.extractionRoot);
    controller.select(
      controller.entries.indexWhere(
        (entry) => entry.relativePath == 'chapter2/10.png',
      ),
    );
    final selected = controller.currentEntry!.id;
    controller.configureArchive(
      const ViewerSettings(archiveContinuousReading: false),
    );
    expect(controller.entries.map((entry) => entry.relativePath), [
      'chapter2/2.png',
      'chapter2/10.png',
    ]);
    expect(controller.currentEntry!.id, selected);
    await controller.navigateToFolder(
      controller.archiveContext!.extractionRoot,
    );
    expect(controller.entries.map((entry) => entry.name), [
      'root2.png',
      'root10.png',
    ]);
    expect(controller.childFolders.map((folder) => folder.name), [
      'chapter2',
      'chapter2-extra',
      'chapter10',
    ]);
  });

  test('folder sort changes do not override archive page order', () async {
    final root = await Directory.systemTemp.createTemp(
      'viewer-archive-sort-independent',
    );
    _tempDirectoryTeardown(root);
    final source = File(_path(root, 'book.cbz'))
      ..writeAsBytesSync(
        _zipBytes({
          '10.png': [10],
          '2.png': [2],
          '1.png': [1],
        }),
      );
    final controller = ViewerController(configStore: await _configStore());
    addTearDown(controller.dispose);
    await controller.openArchive(source);
    final before = controller.entries.map((entry) => entry.id).toList();
    await controller.setOptions(sortOrder: SortOrder.nameDescending);
    expect(controller.entries.map((entry) => entry.id), before);
    expect(controller.archiveSortOrder, SortOrder.nameAscending);
  });

  test(
    'canceling archive preparation preserves the previous committed view',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'viewer-archive-cancel-replace',
      );
      _tempDirectoryTeardown(root);
      final original = File(_path(root, 'original.cbz'))
        ..writeAsBytesSync(
          _zipBytes({
            'original.png': [1],
          }),
        );
      final replacement = File(_path(root, 'replacement.cbz'))
        ..writeAsBytesSync(
          _zipBytes({
            'replacement.png': [2],
          }),
        );
      final controller = ViewerController(configStore: await _configStore());
      addTearDown(controller.dispose);
      await controller.openArchive(original);
      final oldContext = controller.archiveContext;
      final oldEntry = controller.currentEntry;
      final entered = Completer<void>();
      final release = Completer<void>();
      controller.prepareArchiveEntry = (_, request) async {
        entered.complete();
        await release.future;
      };
      final opening = controller.openArchive(replacement);
      await entered.future;
      expect(controller.isOpeningArchive, isTrue);
      expect(controller.archiveContext, same(oldContext));
      expect(controller.currentEntry, same(oldEntry));
      controller.cancelArchiveOpen();
      release.complete();
      expect(await opening, ArchiveOpenOutcome.cancelled);
      expect(controller.archiveContext, same(oldContext));
      expect(controller.currentEntry, same(oldEntry));
      expect(controller.isOpeningArchive, isFalse);
      expect(controller.lastArchiveFailure, isNull);
    },
  );

  test(
    'an archive containing only a nested archive remains navigable',
    () async {
      final root = await Directory.systemTemp.createTemp('viewer-nested-only');
      _tempDirectoryTeardown(root);
      final source = File(_path(root, 'outer.cbz'))
        ..writeAsBytesSync(
          _zipBytes({
            'inner.cbz': _zipBytes({
              '1.png': [1],
            }),
          }),
        );
      final controller = ViewerController(configStore: await _configStore());
      addTearDown(controller.dispose);
      expect(await controller.openArchive(source), ArchiveOpenOutcome.opened);
      expect(controller.entries, isEmpty);
      expect(controller.containers.single.name, 'inner.cbz');
      final parent = controller.archiveContext;
      expect(
        await controller.openArchiveEntry(controller.containers.single),
        ArchiveOpenOutcome.opened,
      );
      expect(controller.currentEntry!.name, '1.png');
      await controller.navigateToFolder(controller.parentFolderPath!);
      expect(controller.archiveContext, same(parent));
      expect(controller.entries, isEmpty);
      expect(controller.containers.single.name, 'inner.cbz');
    },
  );

  test(
    'a superseded archive result cannot replace the latest successful open',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'viewer-archive-superseded',
      );
      _tempDirectoryTeardown(root);
      final older = File(_path(root, 'older.cbz'))
        ..writeAsBytesSync(
          _zipBytes({
            'older.png': [1],
          }),
        );
      final latest = File(_path(root, 'latest.cbz'))
        ..writeAsBytesSync(
          _zipBytes({
            'latest.png': [2],
          }),
        );
      final controller = ViewerController(configStore: await _configStore());
      addTearDown(controller.dispose);
      final entered = Completer<void>();
      final release = Completer<void>();
      controller.prepareArchiveEntry = (entry, request) async {
        if (entry.name == 'older.png') {
          entered.complete();
          await release.future;
        }
      };
      final obsolete = controller.openArchive(older);
      await entered.future;
      expect(await controller.openArchive(latest), ArchiveOpenOutcome.opened);
      final latestId = controller.currentEntry!.id;
      release.complete();
      expect(await obsolete, ArchiveOpenOutcome.cancelled);
      expect(controller.currentEntry!.id, latestId);
      expect(controller.archiveContext!.archiveFile.path, latest.path);
      expect(controller.archiveStateFor(older).phase, ArchiveOpenPhase.idle);
      expect(controller.isOpeningArchive, isFalse);
      expect(controller.lastArchiveFailure, isNull);
    },
  );

  test(
    'ordinary archive restores latest selection after an immediate switch',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'viewer-archive-resume',
      );
      _tempDirectoryTeardown(root);
      final source = File(_path(root, 'book.cbz'))
        ..writeAsBytesSync(
          _zipBytes({
            '1.png': [1],
            '2.png': [2],
          }),
        );
      final config = await _configStore();
      final controller = ViewerController(configStore: config);
      addTearDown(controller.dispose);
      await controller.openArchive(source);
      await controller.readingStates.save(
        ReadingStateStore.archiveKey(source.path),
        const ReadingState(
          entryPath: '1.png',
          readingDirection: ReadingDirection.rightToLeft,
        ),
      );
      controller.select(1);
      final selectedId = controller.currentEntry!.id;
      await controller.openFolder(root.path);
      expect(await controller.openArchive(source), ArchiveOpenOutcome.opened);
      expect(controller.currentEntry!.id, selectedId);
      final session = (await config.read())['session'] as Map;
      expect(session, isNot(contains('archiveHistory')));
      final saved = (await config.read())['readingHistory'] as Map;
      final state = saved[ReadingStateStore.archiveKey(source.path)] as Map;
      expect(state['entryPath'], '2.png');
      expect(state['readingDirection'], 'rightToLeft');
      expect(
        jsonEncode(session),
        isNot(contains(controller.archiveContext!.extractionRoot)),
      );
    },
  );

  test(
    'password archives do not persist credentials or internal history',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'viewer-password-history',
      );
      _tempDirectoryTeardown(root);
      final source = File(_path(root, 'private.cbz'))
        ..writeAsBytesSync(
          _zipBytes({
            'sensitive-page-1.png': [1],
            'sensitive-page-2.png': [2],
          }, password: 'do-not-save'),
        );
      final config = await _configStore();
      final controller = ViewerController(configStore: config);
      addTearDown(controller.dispose);
      expect(
        await controller.openArchive(source, password: 'do-not-save'),
        ArchiveOpenOutcome.opened,
      );
      expect(controller.archiveContext!.session!.encrypted, isTrue);
      controller.select(1);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      final serialized = jsonEncode(await config.read());
      expect(serialized, isNot(contains('do-not-save')));
      expect(serialized, isNot(contains('sensitive-page')));
      expect(serialized, isNot(contains(controller.currentEntry!.id)));
      expect(
        serialized,
        isNot(contains(controller.archiveContext!.extractionRoot)),
      );
      await controller.openFolder(root.path);
      expect(await controller.openArchive(source), ArchiveOpenOutcome.failed);
      expect(controller.lastArchiveFailure, ArchiveFailureKind.encrypted);
    },
  );
}

Future<AppConfigStore> _configStore() async {
  final directory = await Directory.systemTemp.createTemp('viewer-config');
  _tempDirectoryTeardown(directory);
  return AppConfigStore(filePath: _path(directory, 'config.json'));
}

void _tempDirectoryTeardown(Directory directory) {
  addTearDown(() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });
}

class _CountingIndexService extends FolderIndexService {
  _CountingIndexService()
    : super(folderOrderProvider: const _EmptyFolderOrderProvider());

  int calls = 0;

  @override
  Future<FolderIndexResult> indexResult(
    String folderPath, {
    SortOrder sortOrder = SortOrder.nameAscending,
    FileNameSortMode fileNameSortMode = FileNameSortMode.natural,
    FolderBrowseMode browseMode = FolderBrowseMode.currentFolder,
    bool scanUnknownExtensions = false,
    int maxDepth = FolderIndexService.defaultMaxDepth,
    int maxImages = FolderIndexService.defaultMaxImages,
    int maxDirectories = FolderIndexService.defaultMaxDirectories,
    bool resolveFolderOrder = true,
    DecodeRequest? request,
    void Function(FolderScanProgress)? onProgress,
  }) {
    calls++;
    return super.indexResult(
      folderPath,
      sortOrder: sortOrder,
      fileNameSortMode: fileNameSortMode,
      browseMode: browseMode,
      scanUnknownExtensions: scanUnknownExtensions,
      maxDepth: maxDepth,
      maxImages: maxImages,
      maxDirectories: maxDirectories,
      resolveFolderOrder: resolveFolderOrder,
      request: request,
      onProgress: onProgress,
    );
  }
}

class _EmptyFolderOrderProvider implements FolderOrderProvider {
  const _EmptyFolderOrderProvider();

  @override
  Future<List<String>?> orderFor(String folderPath) async => null;
}

List<int> _zipBytes(Map<String, List<int>> files, {String? password}) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  return ZipEncoder(password: password).encodeBytes(archive);
}

Future<void> _writePng(File file) async {
  await file.writeAsBytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
}

String _path(Directory directory, String child) =>
    directory.uri.resolve(child).toFilePath();
