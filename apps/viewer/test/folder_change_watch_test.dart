import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/folder_change_watcher.dart';
import 'package:shen_view/src/application/viewer_controller.dart';
import 'package:shen_view/src/domain/folder_browse_mode.dart';
import 'package:shen_view/src/domain/sort_order.dart';
import 'package:path/path.dart' as paths;

const _pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

void main() {
  test(
    'refreshes the list after images are added or removed externally',
    () async {
      final root = await Directory.systemTemp.createTemp('folder-watch-');
      final controller = _controller(root);
      final first = _writeImage(root, 'a.png');
      _writeImage(root, 'b.png');
      first.deleteSync();
      controller.configureOptions(
        sortOrder: SortOrder.nameAscending,
        browseMode: FolderBrowseMode.currentFolder,
        scanUnknownExtensions: false,
        watchFolderChanges: true,
      );
      await controller.openFolder(root.path);
      expect(controller.entries.map((entry) => entry.name), ['b.png']);
      expect(controller.isWatchingFolder, isTrue);

      _writeImage(root, 'c.png');
      await _until(() => controller.entries.length == 2);
      expect(controller.entries.map((entry) => entry.name), ['b.png', 'c.png']);
      expect(controller.currentEntry?.name, 'b.png');

      File(paths.join(root.path, 'b.png')).deleteSync();
      await _until(() => controller.entries.length == 1);
      expect(controller.entries.single.name, 'c.png');
      // The deleted selection falls back to the nearest remaining image.
      expect(controller.currentEntry?.name, 'c.png');
    },
  );

  test('defers refreshes while the window is unfocused', () async {
    final root = await Directory.systemTemp.createTemp('folder-watch-blur-');
    final controller = _controller(root);
    _writeImage(root, 'a.png');
    controller.configureOptions(
      sortOrder: SortOrder.nameAscending,
      browseMode: FolderBrowseMode.currentFolder,
      scanUnknownExtensions: false,
      watchFolderChanges: true,
    );
    await controller.openFolder(root.path);
    controller.setWindowFocused(false);
    _writeImage(root, 'b.png');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(controller.entries, hasLength(1));

    controller.setWindowFocused(true);
    await _until(() => controller.entries.length == 2);
    expect(controller.entries.map((entry) => entry.name), ['a.png', 'b.png']);
  });

  test(
    'recursive flat browsing picks up images added to a subfolder',
    () async {
      final root = await Directory.systemTemp.createTemp('folder-watch-flat-');
      final controller = _controller(root);
      _writeImage(root, 'a.png');
      final chapter = Directory(paths.join(root.path, 'chapter'))..createSync();
      _writeImage(chapter, 'b.png');
      controller.configureOptions(
        sortOrder: SortOrder.nameAscending,
        browseMode: FolderBrowseMode.recursiveFlat,
        scanUnknownExtensions: false,
        watchFolderChanges: true,
      );
      await controller.openFolder(root.path);
      expect(controller.entries.map((entry) => entry.name), ['a.png', 'b.png']);

      _writeImage(chapter, 'c.png');
      await _until(() => controller.entries.length == 3);
      expect(controller.entries.map((entry) => entry.name), [
        'a.png',
        'b.png',
        'c.png',
      ]);
    },
  );

  test('keeps unrelated file copies from refreshing the list', () async {
    final root = await Directory.systemTemp.createTemp('folder-watch-noise-');
    final controller = _controller(root);
    _writeImage(root, 'a.png');
    controller.configureOptions(
      sortOrder: SortOrder.nameAscending,
      browseMode: FolderBrowseMode.currentFolder,
      scanUnknownExtensions: false,
      watchFolderChanges: true,
    );
    await controller.openFolder(root.path);
    File(paths.join(root.path, 'notes.txt')).writeAsStringSync('hello');
    File(paths.join(root.path, 'build.tmp')).writeAsStringSync('partial');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(controller.entries, hasLength(1));
    expect(controller.isIndexing, isFalse);
  });

  test('refreshes without switching to the indexing state', () async {
    final root = await Directory.systemTemp.createTemp('folder-watch-quiet-');
    final controller = _controller(root);
    _writeImage(root, 'a.png');
    controller.configureOptions(
      sortOrder: SortOrder.nameAscending,
      browseMode: FolderBrowseMode.currentFolder,
      scanUnknownExtensions: false,
      watchFolderChanges: true,
    );
    await controller.openFolder(root.path);
    var sawIndexing = false;
    controller.addListener(() {
      if (controller.isIndexing) sawIndexing = true;
    });
    _writeImage(root, 'b.png');
    await _until(() => controller.entries.length == 2);
    expect(sawIndexing, isFalse);
  });

  test(
    'sibling changes do not rescan the open folder in directory mode',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'folder-watch-sibling-',
      );
      final first = Directory(paths.join(root.path, 'first'))..createSync();
      final second = Directory(paths.join(root.path, 'second'))..createSync();
      final controller = _controller(root);
      _writeImage(first, 'a.png');
      _writeImage(second, 'a.png');
      controller.configureOptions(
        sortOrder: SortOrder.nameAscending,
        browseMode: FolderBrowseMode.recursiveFolders,
        scanUnknownExtensions: false,
        watchFolderChanges: true,
      );
      await controller.openFolder(
        root.path,
        preferredFilePath: paths.join(first.path, 'a.png'),
        establishRoot: true,
      );
      expect(controller.folderPath, first.path);
      expect(controller.directoryRoot?.path, root.path);
      await controller.flushPersistence();
      // Let notifications from setup and initial enumeration reconcile before
      // measuring the effect of the sibling-only change.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final entries = controller.entries;
      _writeImage(second, 'b.png');
      await _until(
        () => controller.navigationFolders.any(
          (folder) =>
              folder.directory.path == second.path && folder.imageCount == 2,
        ),
      );
      expect(identical(controller.entries, entries), isTrue);
    },
  );

  test(
    'native rename from a temporary extension discovers the image',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'folder-watch-rename-',
      );
      final controller = _controller(root);
      _writeImage(root, 'a.png');
      final temporary = _writeImage(root, 'b.tmp');
      controller.configureOptions(
        sortOrder: SortOrder.nameAscending,
        browseMode: FolderBrowseMode.currentFolder,
        scanUnknownExtensions: false,
        watchFolderChanges: true,
      );
      await controller.openFolder(root.path);
      await controller.flushPersistence();
      temporary.renameSync(paths.join(root.path, 'b.png'));
      await _until(() => controller.entries.length == 2);
      expect(controller.entries.map((entry) => entry.name), ['a.png', 'b.png']);
    },
  );

  test(
    'native move of a populated dotted directory discovers its images',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'folder-watch-dotted-',
      );
      final staging = await Directory.systemTemp.createTemp(
        'folder-watch-staging-',
      );
      final controller = _controller(root);
      addTearDown(() async {
        if (staging.existsSync()) await staging.delete(recursive: true);
      });
      _writeImage(root, 'a.png');
      _writeImage(staging, 'b.png');
      controller.configureOptions(
        sortOrder: SortOrder.nameAscending,
        browseMode: FolderBrowseMode.recursiveFlat,
        scanUnknownExtensions: false,
        watchFolderChanges: true,
      );
      await controller.openFolder(root.path);
      await controller.flushPersistence();
      staging.renameSync(paths.join(root.path, 'chapter.v1'));
      await _until(() => controller.entries.length == 2);
      expect(controller.entries.map((entry) => entry.name), ['a.png', 'b.png']);
    },
  );

  test('does not watch the file system when the preference is off', () async {
    final root = await Directory.systemTemp.createTemp('folder-watch-off-');
    final controller = _controller(root);
    _writeImage(root, 'a.png');
    controller.configureOptions(
      sortOrder: SortOrder.nameAscending,
      browseMode: FolderBrowseMode.currentFolder,
      scanUnknownExtensions: false,
      watchFolderChanges: false,
    );
    await controller.openFolder(root.path);
    expect(controller.isWatchingFolder, isFalse);

    _writeImage(root, 'b.png');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(controller.entries, hasLength(1));
  });

  test('turning the preference off stops watching', () async {
    final root = await Directory.systemTemp.createTemp('folder-watch-toggle-');
    final controller = _controller(root);
    _writeImage(root, 'a.png');
    controller.configureOptions(
      sortOrder: SortOrder.nameAscending,
      browseMode: FolderBrowseMode.currentFolder,
      scanUnknownExtensions: false,
      watchFolderChanges: true,
    );
    await controller.openFolder(root.path);
    expect(controller.isWatchingFolder, isTrue);

    await controller.setOptions(watchFolderChanges: false);
    expect(controller.isWatchingFolder, isFalse);
    _writeImage(root, 'b.png');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(controller.entries, hasLength(1));
  });
}

ViewerController _controller(Directory root) {
  final config = AppConfigStore(filePath: paths.join(root.path, 'config.json'));
  final controller = ViewerController(
    configStore: config,
    folderChangeWatcher: FolderChangeWatcher(
      debounce: const Duration(milliseconds: 40),
      maxLatency: const Duration(milliseconds: 120),
    ),
  );
  addTearDown(() async {
    await controller.flushPersistence();
    controller.dispose();
    await root.delete(recursive: true).catchError((_) => root);
  });
  return controller;
}

File _writeImage(Directory directory, String name) {
  final file = File(paths.join(directory.path, name))
    ..writeAsBytesSync(_pngHeader);
  return file;
}

Future<void> _until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
