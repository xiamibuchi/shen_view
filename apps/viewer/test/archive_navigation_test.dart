import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as paths;
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/archive_service.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/viewer_controller.dart';
import 'package:shen_view/src/domain/folder_browse_mode.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';

void main() {
  late Directory directory;
  late ViewerController controller;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('archive-navigation-');
    controller = ViewerController(
      configStore: AppConfigStore(filePath: '${directory.path}/config.json'),
      archiveService: ArchiveService(
        cachePolicy: ArchiveCachePolicy(
          directory: Directory('${directory.path}/cache'),
        ),
      ),
    );
  });
  tearDown(() async {
    controller.dispose();
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        await directory.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    }
    await directory.delete(recursive: true);
  });

  test('archive filename rules reorder chapters and pages while preserving selection', () async {
    final archive = _writeArchive(directory, 'sorting.cbz', {
      for (final name in [
        '10.png',
        '2.png',
        '01.png',
        '01.jpg',
        '001.png',
        '0001.png',
      ])
        name: [0],
      '第10章/1.png': [0],
      '第2章/1.png': [0],
    });
    await controller.openArchive(archive);
    expect(controller.entries.map((e) => e.relativePath), [
      '01.jpg',
      '01.png',
      '001.png',
      '0001.png',
      '2.png',
      '10.png',
      '第2章/1.png',
      '第10章/1.png',
    ]);
    controller.select(4);
    final selected = controller.currentEntry!.id;
    final session = controller.archiveContext!.session;
    await controller.setOptions(
      fileNameSortMode: FileNameSortMode.lexicographic,
    );
    expect(controller.entries.map((e) => e.relativePath), [
      '0001.png',
      '001.png',
      '01.jpg',
      '01.png',
      '10.png',
      '2.png',
      '第10章/1.png',
      '第2章/1.png',
    ]);
    expect(controller.currentEntry!.id, selected);
    expect(controller.archiveContext!.session, same(session));
    final index = await controller.listNavigationDirectory(
      controller.folderPath!,
    );
    expect(index.childFolders.map((e) => e.name), ['第10章', '第2章']);
    controller.configureArchive(
      const ViewerSettings(archiveSortOrder: SortOrder.nameDescending),
    );
    expect(controller.entries.take(6).map((e) => e.name), [
      '10.png',
      '2.png',
      '0001.png',
      '001.png',
      '01.png',
      '01.jpg',
    ]);
    expect(controller.currentEntry!.id, selected);
    expect(controller.fileNameSortMode, FileNameSortMode.natural);
  });

  test('folder sibling entries survive three successive archives and reverse navigation', () async {
    final books = [
      for (var volume = 1; volume <= 3; volume++)
        _writeArchive(directory, '第0$volume卷.cbz', {
          '001.png': [volume],
        }),
    ];
    controller.configureOptions(
      sortOrder: SortOrder.nameAscending,
      browseMode: FolderBrowseMode.recursiveFolders,
      scanUnknownExtensions: false,
    );
    await controller.openFolder(directory.path);
    expect(controller.containers.map((entry) => entry.name), [
      '第01卷.cbz',
      '第02卷.cbz',
      '第03卷.cbz',
    ]);
    expect(
      await controller.openArchiveEntry(controller.containers.first),
      ArchiveOpenOutcome.opened,
    );
    expect(controller.adjacentArchive(-1), isNull);
    for (var volume = 1; volume <= 2; volume++) {
      final next = controller.adjacentArchive(1);
      expect(next?.file.path, paths.normalize(books[volume].path));
      expect(
        await controller.openArchiveEntry(next!),
        ArchiveOpenOutcome.opened,
      );
      expect(
        controller.archiveContext!.archiveFile.path,
        paths.normalize(books[volume].path),
      );
      expect(controller.directoryRoot!.path, paths.normalize(directory.path));
    }
    expect(controller.adjacentArchive(1), isNull);
    for (var volume = 1; volume >= 0; volume--) {
      final previous = controller.adjacentArchive(-1);
      expect(previous?.file.path, paths.normalize(books[volume].path));
      expect(
        await controller.openArchiveEntry(previous!),
        ArchiveOpenOutcome.opened,
      );
    }
    // Direct opening starts an independent root even after browsing a folder.
    expect(await controller.openArchive(books[1]), ArchiveOpenOutcome.opened);
    expect(controller.adjacentArchive(-1), isNull);
    expect(controller.adjacentArchive(1), isNull);
  });

  test('nested archive does not inherit outer folder siblings', () async {
    final inner = _writeArchive(directory, '第01卷.cbz', {
      '001.png': [1],
    });
    _writeArchive(directory, '合集.cbz', {'内嵌.cbz': inner.readAsBytesSync()});
    controller.configureOptions(
      sortOrder: SortOrder.nameAscending,
      browseMode: FolderBrowseMode.recursiveFolders,
      scanUnknownExtensions: false,
    );
    await controller.openFolder(directory.path);
    final outerEntry = controller.containers.firstWhere(
      (entry) => entry.name == '合集.cbz',
    );
    expect(
      await controller.openArchiveEntry(outerEntry),
      ArchiveOpenOutcome.opened,
    );
    expect(
      await controller.openArchiveEntry(controller.navigationContainers.single),
      ArchiveOpenOutcome.opened,
    );
    expect(controller.archiveContext!.parent, isNotNull);
    expect(controller.adjacentArchive(-1), isNull);
    expect(controller.adjacentArchive(1), isNull);
  });

  test(
    'folder root retains archive chapters and can switch outer peers',
    () async {
      final book = _writeArchive(directory, 'chapters.cbz', {
        '第01章/001.png': [1],
        '第02章/001.png': [2],
      });
      final peer = _writeArchive(directory, 'peer.cbz', {
        '001.png': [3],
      });
      controller.configureOptions(
        sortOrder: SortOrder.nameAscending,
        browseMode: FolderBrowseMode.recursiveFolders,
        scanUnknownExtensions: false,
      );
      await controller.openFolder(directory.path);
      await controller.openArchiveEntry(
        controller.containers.firstWhere(
          (entry) => paths.equals(entry.id, book.path),
        ),
      );
      expect(controller.directoryRoot!.path, directory.path);
      expect(controller.chapterChoices.map((choice) => choice.name), [
        '第01章',
        '第02章',
      ]);
      final second = controller.chapterChoices.last.path;
      await controller.openChapter(second);
      expect(controller.selectedChapterPath, second);
      final origin = await controller.listNavigationDirectory(directory.path);
      await controller.openArchiveEntry(
        origin.containers.firstWhere(
          (entry) => paths.equals(entry.id, peer.path),
        ),
      );
      expect(controller.selectedChapterPath, paths.normalize(peer.path));
      expect(controller.directoryRoot!.path, directory.path);
      expect(
        controller.chapterChoices.where((choice) => choice.isArchive).length,
        2,
      );
      await expectLater(
        controller.listNavigationDirectory(directory.parent.path),
        throwsArgumentError,
      );
    },
  );

  test('switching nested peers retains their owner and folder root', () async {
    final archive = _writeArchive(directory, 'outer.cbz', {
      'first.cbz': _zip({
        '001.png': [1],
      }),
      'second.cbz': _zip({
        '001.png': [2],
      }),
    });
    controller.configureOptions(
      sortOrder: SortOrder.nameAscending,
      browseMode: FolderBrowseMode.recursiveFolders,
      scanUnknownExtensions: false,
    );
    await controller.openFolder(directory.path);
    await controller.openArchiveEntry(
      controller.containers.singleWhere(
        (entry) => paths.equals(entry.id, archive.path),
      ),
    );
    final outer = controller.archiveContext!;
    final peers = controller.navigationContainers;
    await controller.openArchiveEntry(peers.first);
    final first = controller.archiveContext!;
    await controller.openArchiveEntry(peers.last);
    expect(controller.archiveContext!.parent, same(outer));
    expect(controller.archiveContext!.entryId, peers.last.id);
    expect(controller.directoryRoot!.path, directory.path);
    expect(controller.adjacentArchive(1), isNull);
    expect(controller.archiveContext, isNot(same(first)));
    await controller.navigateToFolder(outer.extractionRoot);
    expect(controller.archiveContext, same(outer));
    expect(controller.navigationContainers.length, 2);
    await controller.navigateToFolder(directory.path);
    expect(controller.isArchiveView, isFalse);
  });

  test('folder navigation stays within the explicitly opened root', () async {
    final root = Directory(paths.join(directory.path, 'library'))..createSync();
    final chapter = Directory('${root.path}/chapter')..createSync();
    File('${chapter.path}/001.png').writeAsBytesSync([1]);
    final peer = Directory('${root.path}/chapter2')..createSync();
    File('${peer.path}/001.png').writeAsBytesSync([2]);
    controller.configureOptions(
      sortOrder: SortOrder.nameAscending,
      browseMode: FolderBrowseMode.recursiveFolders,
      scanUnknownExtensions: false,
    );
    await controller.openFolder(root.path);
    expect(controller.directoryRoot!.path, paths.normalize(root.path));
    expect(controller.parentFolderPath, paths.normalize(root.path));
    await controller.navigateToFolder(chapter.path);
    expect(controller.parentFolderPath, root.path);
    expect(controller.navigationFolders.map((folder) => folder.name), [
      'chapter',
      'chapter2',
    ]);
    expect(controller.isNavigationFolderSelected(chapter.path), isTrue);
    await controller.setOptions(sortOrder: SortOrder.nameDescending);
    expect(controller.parentFolderPath, root.path);
    await controller.navigateToFolder(root.path);
    await controller.navigateToFolder(directory.path);
    expect(controller.folderPath, root.path);
    expect(controller.parentFolderPath, isNull);
  });

  for (final continuous in [false, true]) {
    test(
      'recursive folders keep directory choices across continuous toggles ($continuous)',
      () async {
        final root = Directory(paths.join(directory.path, 'library'))
          ..createSync();
        final first = Directory(paths.join(root.path, '卷1', '第01章'))
          ..createSync(recursive: true);
        final second = Directory(paths.join(root.path, '卷1', '第02章'))
          ..createSync();
        final other = Directory(paths.join(root.path, '卷2', '第01章'))
          ..createSync(recursive: true);
        File(paths.join(root.path, 'cover.png')).writeAsBytesSync([0]);
        for (final folder in [first, second, other]) {
          File(paths.join(folder.path, '001.png')).writeAsBytesSync([1]);
        }
        controller.configureOptions(
          sortOrder: SortOrder.nameAscending,
          browseMode: continuous
              ? FolderBrowseMode.recursiveFlat
              : FolderBrowseMode.recursiveFolders,
          scanUnknownExtensions: false,
        );
        await controller.openFolder(root.path);
        expect(controller.entries.length, continuous ? 4 : 1);
        await controller.openChapter(second.path);
        expect(paths.dirname(controller.currentEntry!.id), second.path);
        expect(controller.entries.length, continuous ? 4 : 1);
        expect(controller.chapterChoices.map((chapter) => chapter.name), [
          '第01章',
          '第02章',
        ]);
        expect(controller.selectedChapterPath, second.path);
        final selected = controller.currentEntry!.id;
        for (final mode in [
          FolderBrowseMode.recursiveFlat,
          FolderBrowseMode.recursiveFolders,
          FolderBrowseMode.recursiveFlat,
        ]) {
          await controller.setOptions(browseMode: mode);
          expect(controller.currentEntry!.id, selected);
          expect(controller.entries.length, mode.isFlat ? 4 : 1);
          expect(controller.selectedChapterPath, second.path);
          expect(controller.chapterChoices.length, 2);
          expect(controller.directoryRoot!.path, paths.normalize(root.path));
        }
        controller.select(
          controller.entries.indexWhere(
            (entry) => paths.equals(paths.dirname(entry.id), other.path),
          ),
        );
        for (
          var attempt = 0;
          attempt < 100 &&
              !paths.equals(controller.selectedChapterPath ?? '', other.path);
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(controller.selectedChapterPath, other.path);
        await controller.openChapter(root.path);
        expect(controller.currentEntry!.name, 'cover.png');
        await controller.navigateToFolder(directory.path);
        expect(controller.directoryRoot!.path, paths.normalize(root.path));
      },
    );

    test(
      'chapter siblings survive navigation and reading toggles (continuous=$continuous)',
      () async {
        final archive = _writeArchive(directory, '章节.zip', {
          '第01章/001.png': [1],
          '第01章/002.png': [2],
          '第02章/001.png': [3],
          '第03章/001.png': [4],
        });
        controller.configureArchive(
          ViewerSettings(archiveContinuousReading: continuous),
        );
        expect(
          await controller.openArchive(archive),
          ArchiveOpenOutcome.opened,
        );
        final root = controller.archiveContext!.extractionRoot;
        final second = paths.join(root, '第02章');
        await controller.navigateToFolder(second);
        expect(controller.currentEntry!.relativePath, '第02章/001.png');
        expect(controller.entries.length, continuous ? 4 : 1);
        expect(controller.navigationFolders.map((folder) => folder.name), [
          '第01章',
          '第02章',
          '第03章',
        ]);
        expect(controller.isNavigationFolderSelected(second), isTrue);
        final selected = controller.currentEntry!.id;
        for (final enabled in [!continuous, continuous]) {
          controller.configureArchive(
            ViewerSettings(archiveContinuousReading: enabled),
          );
          expect(controller.currentEntry!.id, selected);
          expect(controller.entries.length, enabled ? 4 : 1);
          expect(controller.navigationFolders.length, 3);
          expect(controller.isNavigationFolderSelected(second), isTrue);
        }
        await controller.navigateToFolder(paths.join(root, '第03章'));
        expect(controller.currentEntry!.relativePath, '第03章/001.png');
      },
    );
  }

  test('multilevel archive preserves hierarchy, direct images and natural chapter order', () async {
    final archive = _writeArchive(directory, '多级目录.cbz', {
      'cover.png': [0],
      '第1卷/cover.png': [1],
      '第1卷/第01章/001.png': [2],
      '第1卷/第02章/001.png': [3],
      '第1卷/第10章/001.png': [4],
      '第2卷/上篇/第01章/001.png': [5],
      'empty/readme.txt': [6],
    });
    await controller.openArchive(archive);
    final root = controller.archiveContext!.extractionRoot;
    expect(controller.navigationFolders.map((folder) => folder.name), [
      '第1卷',
      '第2卷',
    ]);
    expect(controller.navigationImageDirectory, root);
    expect(controller.navigationDirectorySelected, isTrue);
    final volume = paths.join(root, '第1卷');
    await controller.navigateToFolder(volume);
    expect(controller.navigationFolders.map((folder) => folder.name), [
      '第01章',
      '第02章',
      '第10章',
    ]);
    expect(controller.navigationLocations.map((location) => location.name), [
      '多级目录.cbz',
      '第1卷',
    ]);
    expect(controller.navigationImageDirectory, volume);
    await controller.navigateToFolder(paths.join(volume, '第02章'));
    expect(controller.navigationFolders.length, 3);
    expect(controller.currentEntry!.relativePath, '第1卷/第02章/001.png');
    controller.configureArchive(
      const ViewerSettings(archiveContinuousReading: false),
    );
    expect(controller.entries.map((entry) => entry.relativePath), [
      '第1卷/第02章/001.png',
    ]);
    expect(controller.navigationFolders.length, 3);
    await controller.navigateToFolder(volume);
    expect(controller.currentEntry!.relativePath, '第1卷/cover.png');
    expect(controller.navigationDirectorySelected, isTrue);
    await controller.navigateToFolder(root);
    expect(controller.currentEntry!.relativePath, 'cover.png');
    expect(controller.parentFolderPath, isNull);
    controller.configureArchive(const ViewerSettings());
    controller.select(
      controller.entries.indexWhere(
        (entry) => entry.relativePath.startsWith('第2卷/'),
      ),
    );
    expect(controller.navigationLocations.map((location) => location.name), [
      '多级目录.cbz',
      '第2卷',
      '上篇',
    ]);
    expect(controller.navigationFolders.single.name, '第01章');
    final selected = controller.currentEntry!.id;
    await controller.openFolder(
      controller.folderPath!,
      preferredFilePath: selected,
      keepArchiveContext: true,
      persistRecent: false,
    );
    expect(controller.currentEntry!.id, selected);
    expect(controller.navigationLocations.map((location) => location.name), [
      '多级目录.cbz',
      '第2卷',
      '上篇',
    ]);
    expect(controller.navigationFolders.single.name, '第01章');
  });

  test(
    'nested archives remain lazy and return across multiple container levels',
    () async {
      final innermost = _zip({
        'deep/001.png': [9],
      });
      final inner = _zip({
        'cover.png': [4],
        '章节/deeper.cbz': innermost,
      });
      final archive = _writeArchive(directory, '合集.zip', {
        '卷1/第01章/001.png': [1],
        '卷1/第01章/002.png': [2],
        '卷1/第02章/001.png': [3],
        '卷1/单行本.cbz': inner,
      });
      await controller.openArchive(archive);
      final outer = controller.archiveContext!;
      expect(
        controller.entries.length,
        3,
        reason: 'Inner archives must not be flattened or extracted.',
      );
      expect((await controller.archiveCacheStats()).files, 1);
      final chapter = paths.join(outer.extractionRoot, '卷1', '第01章');
      await controller.navigateToFolder(chapter);
      controller.select(1);
      final selection = controller.currentEntry!.id;
      final nested = controller.navigationContainers.single;
      expect(
        await controller.openArchiveEntry(nested),
        ArchiveOpenOutcome.opened,
      );
      final middle = controller.archiveContext!;
      expect(middle.parent, same(outer));
      expect(controller.navigationLocations.map((location) => location.name), [
        '合集.zip',
        '卷1',
        '单行本.cbz',
      ]);
      await controller.navigateToFolder(
        paths.join(middle.extractionRoot, '章节'),
      );
      final deeper = controller.navigationContainers.single;
      expect(
        await controller.openArchiveEntry(deeper),
        ArchiveOpenOutcome.opened,
      );
      expect(controller.currentEntry!.relativePath, 'deep/001.png');
      expect(controller.archiveContext!.parent, same(middle));
      // A tree entry may return across several containers without losing the page.
      await controller.openChapter(chapter);
      expect(controller.archiveContext, same(outer));
      expect(controller.currentEntry!.id, selection);
      expect(controller.navigationContainers.single.id, nested.id);
      expect(controller.navigationFolders.map((folder) => folder.name), [
        '第01章',
        '第02章',
      ]);
      await controller.navigateToFolder(outer.extractionRoot);
      expect(controller.parentFolderPath, isNull);
      await controller.navigateToFolder(directory.path);
      expect(controller.archiveContext, same(outer));
      await controller.clearArchiveCache();
      expect(
        (await controller.archiveCacheStats()).files,
        0,
        reason: 'Returning must release nested container leases.',
      );
    },
  );

  test(
    'directory metadata browsing stays lazy, bounded and normalized',
    () async {
      final archive = _writeArchive(directory, '目录树.zip', {
        'cover.png': [0],
        '卷1/上篇/第01章/001.png': [1],
        '卷1/上篇/第02章/001.png': [2],
        '卷1/单行本.cbz': _zip({
          '001.png': [3],
        }),
      });
      await controller.openArchive(archive);
      final root = controller.archiveContext!.extractionRoot;
      final selected = controller.currentEntry!.id;
      final initialFiles = (await controller.archiveCacheStats()).files;
      final volume = paths.join(root, '卷1');
      final part = paths.join(volume, '上篇');
      final chapter = paths.join(part, '第02章');
      expect(controller.directoryRoot!.path, root);
      final volumeIndex = await controller.listNavigationDirectory(volume);
      expect(volumeIndex.containers.single.name, '单行本.cbz');
      expect(
        controller.openedArchiveFor(volumeIndex.containers.single),
        isNull,
      );
      final index = await controller.listNavigationDirectory(part);
      expect(index.childFolders.map((folder) => folder.directory.path), [
        paths.join(part, '第01章'),
        chapter,
      ]);
      expect(controller.currentEntry!.id, selected);
      expect((await controller.archiveCacheStats()).files, initialFiles);
      final cancelled = DecodeRequest()..cancel();
      await expectLater(
        controller.listNavigationDirectory(part, request: cancelled),
        throwsA(isA<DecodeCancelled>()),
      );
      await expectLater(
        controller.listNavigationDirectory(directory.path),
        throwsArgumentError,
      );
      await controller.openChapter(chapter);
      expect(controller.currentDirectoryPath, chapter);
      expect(controller.selectedChapterPath, chapter);
      expect(controller.chapterChoices.map((choice) => choice.name), [
        '第01章',
        '第02章',
      ]);
      await controller.openChapter(root);
      expect(controller.currentEntry!.relativePath, 'cover.png');
    },
  );

  test('failed inner archive keeps the outer chapter and navigation', () async {
    final archive = _writeArchive(directory, 'outer.cbz', {
      '第01章/001.png': [1],
      '第02章/001.png': [2],
      'broken.cbz': [3],
    });
    await controller.openArchive(archive);
    final outer = controller.archiveContext;
    final entry = controller.currentEntry;
    expect(
      await controller.openArchiveEntry(controller.navigationContainers.single),
      ArchiveOpenOutcome.failed,
    );
    expect(controller.archiveContext, same(outer));
    expect(controller.currentEntry, same(entry));
    expect(controller.navigationFolders.length, 2);
  });

  test('archive entered from a folder preserves its folder navigation root and peers', () async {
    final archive = _writeArchive(directory, 'inner.cbz', {
      '001.png': [1],
    });
    final peer = _writeArchive(directory, 'peer.cbz', {
      '001.png': [2],
    });
    File(paths.join(directory.path, 'cover.png')).writeAsBytesSync([0]);
    controller.configureOptions(
      sortOrder: SortOrder.nameAscending,
      browseMode: FolderBrowseMode.recursiveFolders,
      scanUnknownExtensions: false,
    );
    await controller.openFolder(directory.path);
    final source = controller.containers.singleWhere(
      (entry) => paths.equals(entry.file.path, archive.path),
    );
    await controller.openArchiveEntry(source);
    expect(controller.parentFolderPath, isNull);
    expect(controller.directoryRoot!.path, directory.path);
    expect(controller.directoryRoot!.isArchive, isFalse);
    expect(controller.navigationLocations.first.path, directory.path);
    expect(controller.hasFolderNavigation, isTrue);
    expect(controller.chapterChoices.map((choice) => choice.name), [
      '',
      'inner.cbz',
      'peer.cbz',
    ]);
    expect(controller.selectedChapterPath, paths.normalize(archive.path));
    final index = await controller.listNavigationDirectory(directory.path);
    expect(index.containers.length, 2);
    await controller.openChapter(paths.normalize(peer.path));
    expect(
      controller.archiveContext!.archiveFile.path,
      paths.normalize(peer.path),
    );
    expect(controller.selectedChapterPath, paths.normalize(peer.path));
    await controller.openChapter(directory.path);
    expect(controller.isArchiveView, isFalse);
    expect(controller.currentEntry!.name, 'cover.png');
    expect(controller.directoryRoot!.path, directory.path);
    expect(controller.parentFolderPath, isNull);
  });
}

List<int> _zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  return ZipEncoder().encodeBytes(archive);
}

File _writeArchive(
  Directory directory,
  String name,
  Map<String, List<int>> files,
) => File('${directory.path}/$name')..writeAsBytesSync(_zip(files));
