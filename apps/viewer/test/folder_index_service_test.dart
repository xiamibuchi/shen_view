import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shen_view/src/application/folder_index_service.dart';
import 'package:shen_view/src/application/folder_order_provider.dart';
import 'package:shen_view/src/domain/folder_browse_mode.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/domain/image_format.dart';

void main() {
  test(
    'folder indexing preserves camera RAW routes for TIFF containers',
    () async {
      final root = await Directory.systemTemp.createTemp('shen_view-raw-index');
      addTearDown(() => root.delete(recursive: true));
      for (final extension in ['cr2', 'dng', 'nef', 'arw', 'tiff']) {
        await File(_join(root.path, 'sample.$extension'))
            .writeAsBytes([0x49, 0x49, 0x2a, 0x00, 0x08, 0x00, 0x00, 0x00]);
      }
      final entries = await FolderIndexService().index(
        root.path,
        sortOrder: SortOrder.nameAscending,
      );
      for (final entry in entries) {
        expect(
          entry.format,
          entry.name.endsWith('.tiff') ? ImageFormat.tiff : ImageFormat.raw,
          reason: entry.name,
        );
      }
      expect(entries, hasLength(5));
      expect(
        (await FolderIndexService().indexResult(root.path)).headerProbeCount,
        0,
      );
    },
  );

  test(
    'current folder mode exposes direct images and unopened archives',
    () async {
      final root = await Directory.systemTemp.createTemp('shen_view-folder');
      addTearDown(() => root.delete(recursive: true));
      final child = await Directory(_join(root.path, 'chapter-01')).create();
      await _writePng(File(_join(root.path, 'cover.png')));
      await _writePng(File(_join(child.path, '001.png')));
      await File(_join(root.path, 'book.cbz')).writeAsBytes([0]);

      final result = await FolderIndexService().indexResult(root.path);

      expect(result.images.map((entry) => entry.name), ['cover.png']);
      expect(result.containers.map((entry) => entry.name), ['book.cbz']);
      expect(result.childFolders, isEmpty);
      expect(result.truncated, isFalse);
    },
  );

  test(
    'recursive folder mode exposes child folders with subtree counts',
    () async {
      final root = await Directory.systemTemp.createTemp('shen_view-folder');
      addTearDown(() => root.delete(recursive: true));
      final child = await Directory(_join(root.path, 'chapter-01')).create();
      await Directory(_join(child.path, 'nested')).create();
      await _writePng(File(_join(child.path, '001.png')));
      await File(_join(root.path, 'book.cbz')).writeAsBytes([0]);

      final result = await FolderIndexService().indexResult(
        root.path,
        browseMode: FolderBrowseMode.recursiveFolders,
      );

      expect(result.images.map((entry) => entry.name), ['001.png']);
      expect(result.containers.map((entry) => entry.name), ['book.cbz']);
      expect(result.childFolders, hasLength(1));
      expect(result.childFolders.single.name, 'chapter-01');
      expect(result.childFolders.single.imageCount, 1);
      // Empty nested folders are hidden; this is still a visible leaf.
      expect(result.childFolders.single.hasNavigableChildren, isFalse);
      expect(result.truncated, isFalse);
    },
  );

  test(
    'recursive flat mode appends subfolder images after root images',
    () async {
      final root = await Directory.systemTemp.createTemp('shen_view-flat');
      addTearDown(() => root.delete(recursive: true));
      final first = await Directory(_join(root.path, 'chapter-01')).create();
      final second = await Directory(_join(root.path, 'chapter-02')).create();
      await _writePng(File(_join(root.path, 'cover.png')));
      await _writePng(File(_join(first.path, 'b.png')));
      await _writePng(File(_join(first.path, 'a.png')));
      await _writePng(File(_join(second.path, 'c.png')));
      await File(_join(root.path, 'book.cbz')).writeAsBytes([0]);

      final result = await FolderIndexService().indexResult(
        root.path,
        browseMode: FolderBrowseMode.recursiveFlat,
        sortOrder: SortOrder.nameAscending,
      );

      expect(result.images.first.relativePath, 'cover.png');
      final subfolderPaths = result.images
          .skip(1)
          .map((entry) => entry.relativePath)
          .toList();
      expect(subfolderPaths.toSet(), {
        'chapter-01/a.png',
        'chapter-01/b.png',
        'chapter-02/c.png',
      });
      // Each folder group keeps its internal order; the order between
      // chapter-01 and chapter-02 follows directory enumeration.
      expect(
        subfolderPaths.indexOf('chapter-01/a.png'),
        lessThan(subfolderPaths.indexOf('chapter-01/b.png')),
      );
      expect(result.images.first.relativeFolder, isNull);
      expect(result.images[1].relativeFolder, isNotNull);
      expect(result.childFolders.map((folder) => folder.name), [
        'chapter-01',
        'chapter-02',
      ]);
      expect(result.containers.map((entry) => entry.name), ['book.cbz']);
    },
  );

  test('recursive modes hide folders without images or archives', () async {
    final root = await Directory.systemTemp.createTemp('shen_view-empty');
    addTearDown(() => root.delete(recursive: true));
    await Directory(_join(root.path, 'empty')).create();
    final nestedEmpty = await Directory(_join(root.path, 'nested-empty'))
        .create();
    await Directory(_join(nestedEmpty.path, 'deeper')).create();
    final archiveOnly = await Directory(_join(root.path, 'archive-only'))
        .create();
    await File(_join(archiveOnly.path, 'book.cbz')).writeAsBytes([0]);
    final withImage = await Directory(_join(root.path, 'with-image')).create();
    await _writePng(File(_join(withImage.path, '001.png')));

    final result = await FolderIndexService().indexResult(
      root.path,
      browseMode: FolderBrowseMode.recursiveFolders,
    );

    expect(
      result.childFolders.map((folder) => folder.name),
      unorderedEquals(['archive-only', 'with-image']),
    );
    final archiveFolder = result.childFolders.firstWhere(
      (folder) => folder.name == 'archive-only',
    );
    expect(archiveFolder.imageCount, 0);
    expect(archiveFolder.archiveCount, 1);
  });

  test(
    'extension-first scanning skips non-image files without reading headers',
    () async {
      final root = await Directory.systemTemp.createTemp('shen_view-ext');
      addTearDown(() => root.delete(recursive: true));
      await File(_join(root.path, 'notes.txt')).writeAsString('not an image');
      await File(_join(root.path, 'data.bin')).writeAsBytes([1, 2, 3, 4]);
      await _writePng(File(_join(root.path, 'cover.png')));

      final result = await FolderIndexService().indexResult(root.path);

      expect(result.images.map((entry) => entry.name), ['cover.png']);
      expect(result.headerProbeCount, 1);
    },
  );

  test(
    'unknown extension scanning reads headers for unidentified files',
    () async {
      final root = await Directory.systemTemp.createTemp('shen_view-unknown');
      addTearDown(() => root.delete(recursive: true));
      await File(_join(root.path, 'notes.txt')).writeAsString('not an image');
      await _writePng(File(_join(root.path, 'hidden.dat')));
      await _writePng(File(_join(root.path, 'cover.png')));

      final result = await FolderIndexService().indexResult(
        root.path,
        scanUnknownExtensions: true,
      );

      expect(
        result.images.map((entry) => entry.name),
        unorderedEquals(['hidden.dat', 'cover.png']),
      );
      expect(result.headerProbeCount, 3);
    },
  );

  test('uses the platform folder view order for folder order', () async {
    final root = await Directory.systemTemp.createTemp('shen_view-order');
    addTearDown(() => root.delete(recursive: true));
    for (final name in ['zeta.png', 'alpha.png', 'middle.png']) {
      await _writePng(File(_join(root.path, name)));
    }

    final result = await FolderIndexService(
      folderOrderProvider: _FakeFolderOrderProvider([
        _slash(_join(root.path, 'middle.png')),
        _slash(_join(root.path, 'alpha.png')),
        _slash(_join(root.path, 'zeta.png')),
      ]),
    ).indexResult(root.path, sortOrder: SortOrder.fileSystem);

    expect(result.images.map((entry) => entry.name), [
      'middle.png',
      'alpha.png',
      'zeta.png',
    ]);
  });

  test(
    'falls back to directory enumeration when no folder view is available',
    () async {
      final root = await Directory.systemTemp.createTemp('shen_view-order');
      addTearDown(() => root.delete(recursive: true));
      for (final name in ['zeta.png', 'alpha.png', 'middle.png']) {
        await _writePng(File(_join(root.path, name)));
      }

      final filesystemOrder = <String>[];
      await for (final entity in root.list(followLinks: false)) {
        if (entity is File) filesystemOrder.add(entity.uri.pathSegments.last);
      }
      final result = await FolderIndexService(
        folderOrderProvider: const _EmptyFolderOrderProvider(),
      ).indexResult(root.path, sortOrder: SortOrder.fileSystem);

      expect(result.images.map((entry) => entry.name), filesystemOrder);
    },
  );

  test('limits recursive indexing by depth and image count', () async {
    final root = await Directory.systemTemp.createTemp('shen_view-depth');
    addTearDown(() => root.delete(recursive: true));
    final levelOne = await Directory(_join(root.path, 'level-1')).create();
    final levelTwo = await Directory(_join(levelOne.path, 'level-2')).create();
    await _writePng(File(_join(root.path, 'root.png')));
    await _writePng(File(_join(levelOne.path, 'level-1.png')));
    await _writePng(File(_join(levelTwo.path, 'level-2.png')));

    final result = await FolderIndexService().indexResult(
      root.path,
      browseMode: FolderBrowseMode.recursiveFolders,
      maxDepth: 1,
      maxImages: 2,
    );

    expect(result.images, hasLength(2));
    expect(result.truncated, isTrue);
  });

  test('sorts images and containers by size in both directions', () async {
    final root = await Directory.systemTemp.createTemp('shen_view-size');
    addTearDown(() => root.delete(recursive: true));
    await _writePng(File(_join(root.path, 'small.png')), padding: 1);
    await _writePng(File(_join(root.path, 'large.png')), padding: 20);
    await File(_join(root.path, 'small.cbz')).writeAsBytes([0]);
    await File(_join(root.path, 'large.cbz')).writeAsBytes(List.filled(20, 0));

    final service = FolderIndexService();
    final ascending = await service.indexResult(
      root.path,
      browseMode: FolderBrowseMode.recursiveFolders,
      sortOrder: SortOrder.sizeAscending,
    );
    final descending = await service.indexResult(
      root.path,
      browseMode: FolderBrowseMode.recursiveFolders,
      sortOrder: SortOrder.sizeDescending,
    );

    expect(ascending.images.map((entry) => entry.name), [
      'small.png',
      'large.png',
    ]);
    expect(ascending.containers.map((entry) => entry.name), [
      'small.cbz',
      'large.cbz',
    ]);
    expect(descending.images.map((entry) => entry.name), [
      'large.png',
      'small.png',
    ]);
    expect(descending.containers.map((entry) => entry.name), [
      'large.cbz',
      'small.cbz',
    ]);
  });

  test('sorting a cached flat result keeps folder groups together', () async {
    final root = await Directory.systemTemp.createTemp('shen_view-sort');
    addTearDown(() => root.delete(recursive: true));
    final child = await Directory(_join(root.path, 'chapter')).create();
    await _writePng(File(_join(root.path, 'b.png')));
    await _writePng(File(_join(root.path, 'a.png')));
    await _writePng(File(_join(child.path, 'z.png')));
    await _writePng(File(_join(child.path, 'y.png')));

    final service = FolderIndexService();
    final result = await service.indexResult(
      root.path,
      browseMode: FolderBrowseMode.recursiveFlat,
      sortOrder: SortOrder.fileSystem,
    );
    final sorted = service.sortResult(
      result,
      SortOrder.nameAscending,
      FolderBrowseMode.recursiveFlat,
    );

    expect(sorted.images.map((entry) => entry.relativePath), [
      'a.png',
      'b.png',
      'chapter/y.png',
      'chapter/z.png',
    ]);
  });
}

Future<void> _writePng(File file, {int padding = 0}) async {
  await file.writeAsBytes([
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    ...List.filled(padding, 0),
  ]);
}

String _join(String base, String child) =>
    Directory(base).uri.resolve(child).toFilePath();

String _slash(String path) => path.replaceAll(String.fromCharCode(92), '/');

class _FakeFolderOrderProvider implements FolderOrderProvider {
  const _FakeFolderOrderProvider(this.paths);

  final List<String> paths;

  @override
  Future<List<String>?> orderFor(String folderPath) async => paths;
}

class _EmptyFolderOrderProvider implements FolderOrderProvider {
  const _EmptyFolderOrderProvider();

  @override
  Future<List<String>?> orderFor(String folderPath) async => null;
}
