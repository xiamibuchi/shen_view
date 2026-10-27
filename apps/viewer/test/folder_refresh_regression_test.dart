import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/folder_change_watcher.dart';
import 'package:shen_view/src/application/folder_index_service.dart';
import 'package:shen_view/src/application/viewer_controller.dart';
import 'package:shen_view/src/domain/folder_browse_mode.dart';
import 'package:shen_view/src/domain/folder_index_result.dart';
import 'package:shen_view/src/domain/sort_order.dart';
import 'package:path/path.dart' as paths;

const _pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

void main() {
  late _Harness harness;
  setUp(() async {
    harness = await _Harness.create();
  });
  tearDown(() => harness.dispose());

  test(
    'a pending destination lookup cannot cancel a newer directory open',
    () async {
      harness.image('a.png');
      harness.image('second/b.png');
      await harness.open();
      // onChanged starts the refresh synchronously up to its first disk await.
      harness.watcher.onChanged!(
        FolderChangeBatch(paths: {harness.path('a.png')}, overflowed: false),
      );
      await harness.controller.openFolder(harness.path('second'));
      await _settle();
      expect(harness.controller.folderPath, harness.path('second'));
      expect(harness.controller.currentEntry?.name, 'b.png');
      expect(harness.controller.isIndexing, isFalse);
    },
  );

  test('selection made during a refresh survives its completion', () async {
    for (final name in ['a.png', 'b.png', 'c.png']) {
      harness.image(name);
    }
    await harness.open();
    final previous = harness.controller.entries;
    File(harness.path('a.png')).writeAsBytesSync([..._pngHeader, 1]);
    final gate = harness.index.holdNext();
    await harness.change('a.png');
    await gate.entered.future;
    harness.controller.select(2);
    gate.release.complete();
    await _until(() => !identical(previous, harness.controller.entries));
    expect(harness.controller.currentEntry?.name, 'c.png');
    expect(harness.controller.isIndexing, isFalse);
  });

  test(
    'unchanged notifications preserve the list used by reading layouts',
    () async {
      harness.image('a.png');
      final openedPath = harness.root.path.replaceAll(
        Platform.pathSeparator,
        '/',
      );
      await harness.controller.openFolder(openedPath);
      final entries = harness.controller.entries;
      final finished = Completer<void>();
      harness.controller.addListener(() {
        if (!finished.isCompleted) finished.complete();
      });
      await harness.change('a.png');
      await finished.future.timeout(const Duration(seconds: 10));
      expect(harness.index.calls, 2);
      expect(identical(harness.controller.entries, entries), isTrue);
      expect(harness.controller.folderPath, openedPath);
    },
  );

  test('a case-only rename updates the displayed filename', () async {
    final image = harness.image('a.png');
    await harness.open();
    image.renameSync(harness.path('A.png'));
    harness.events.add(
      FileSystemMoveEvent(image.path, false, harness.path('A.png')),
    );
    await _until(() => harness.controller.currentEntry?.name == 'A.png');
  });

  test('an in-flight refresh cannot overwrite a newer folder scan', () async {
    harness.image('a.png');
    harness.image('second/b.png');
    await harness.open();
    final gate = harness.index.holdNext();
    await harness.change('a.png');
    await gate.entered.future;
    await harness.controller.openFolder(harness.path('second'));
    gate.release.complete();
    await _settle();
    expect(harness.controller.folderPath, harness.path('second'));
    expect(harness.controller.currentEntry?.name, 'b.png');
    expect(harness.controller.isIndexing, isFalse);
  });

  test(
    'a queued retry waits for focus and resumes without new events',
    () async {
      harness.image('a.png');
      await harness.open();
      final gate = harness.index.holdNext();
      final foreground = harness.controller.openFolder(harness.root.path);
      await gate.entered.future;
      harness.image('b.png');
      await harness.change('b.png');
      harness.controller.setWindowFocused(false);
      final scans = harness.index.calls;
      gate.release.complete();
      await foreground;
      await _settle(700);
      expect(harness.index.calls, scans);
      expect(harness.controller.entries, hasLength(1));
      harness.controller.setWindowFocused(true);
      await _until(() => harness.controller.entries.length == 2);
    },
  );

  test(
    'a scan finishing after blur defers its result until focus returns',
    () async {
      harness.image('a.png');
      await harness.open();
      harness.image('b.png');
      final gate = harness.index.holdNext();
      await harness.change('b.png');
      await gate.entered.future;
      harness.controller.setWindowFocused(false);
      gate.release.complete();
      await _settle();
      expect(harness.controller.entries, hasLength(1));
      harness.controller.setWindowFocused(true);
      await _until(() => harness.controller.entries.length == 2);
    },
  );

  test(
    'disabling watching discards in-flight results and queued work',
    () async {
      harness.image('a.png');
      await harness.open();
      harness.image('b.png');
      final gate = harness.index.holdNext();
      await harness.change('b.png');
      await gate.entered.future;
      await harness.controller.setOptions(watchFolderChanges: false);
      final scans = harness.index.calls;
      gate.release.complete();
      harness.controller.setWindowFocused(false);
      harness.controller.setWindowFocused(true);
      await _settle(700);
      expect(harness.index.calls, scans);
      expect(harness.controller.entries, hasLength(1));
      expect(harness.controller.isWatchingFolder, isFalse);
    },
  );

  test(
    'focus fallback finds descendant changes without root mtime changes',
    () async {
      harness.configure(FolderBrowseMode.recursiveFlat);
      harness.available = false;
      harness.image('chapter/a.png');
      await harness.open();
      await harness.controller.flushPersistence();
      final modified = harness.root.statSync().modified;
      harness.controller.setWindowFocused(false);
      harness.image('chapter/b.png');
      expect(harness.root.statSync().modified, modified);
      harness.controller.setWindowFocused(true);
      await _until(() => harness.controller.entries.length == 2);
      expect(harness.controller.isWatchingFolder, isFalse);
    },
  );

  test(
    'focus fallback finds an overwritten file without root mtime changes',
    () async {
      harness.available = false;
      final image = harness.image('a.png');
      await harness.open();
      await harness.controller.flushPersistence();
      final modified = harness.root.statSync().modified;
      harness.controller.setWindowFocused(false);
      image.writeAsBytesSync([..._pngHeader, 1, 2, 3]);
      expect(harness.root.statSync().modified, modified);
      harness.controller.setWindowFocused(true);
      await _until(() => harness.controller.currentEntry?.byteLength == 11);
    },
  );

  test('a completed stream becomes inactive and recovers on focus', () async {
    harness.image('a.png');
    await harness.open();
    await harness.events.close();
    expect(harness.controller.isWatchingFolder, isFalse);
    harness.image('b.png');
    harness.controller.setWindowFocused(false);
    harness.controller.setWindowFocused(true);
    await _until(() => harness.controller.entries.length == 2);
    expect(harness.controller.isWatchingFolder, isTrue);
    expect(harness.subscriptions, 2);
  });

  test(
    'changes after initial enumeration are retained before its commit',
    () async {
      harness.image('a.png');
      final gate = harness.index.holdNext();
      final initial = harness.open();
      await gate.entered.future;
      expect(harness.controller.isWatchingFolder, isTrue);
      harness.image('b.png');
      await harness.change('b.png');
      gate.release.complete();
      await initial;
      await _until(() => harness.controller.entries.length == 2);
    },
  );

  test(
    'deleted dotted folders are recognized when isDirectory is false',
    () async {
      harness.configure(FolderBrowseMode.recursiveFlat);
      harness.image('chapter.v1/nested/a.png');
      harness.image('cover.png');
      await harness.open();
      final nested = harness.path('chapter.v1/nested');
      expect(
        (await harness.controller.listNavigationDirectory(nested)).images,
        hasLength(1),
      );
      Directory(harness.path('chapter.v1')).deleteSync(recursive: true);
      harness.events.add(
        FileSystemDeleteEvent(harness.path('chapter.v1'), false),
      );
      await _until(() => harness.controller.entries.length == 1);
      expect(harness.controller.currentEntry?.name, 'cover.png');
      expect(
        (await harness.controller.listNavigationDirectory(nested)).images,
        isEmpty,
      );
    },
  );
}

class _Harness {
  _Harness(this.root, this.state) {
    watcher = FolderChangeWatcher(
      debounce: const Duration(milliseconds: 20),
      streamFactory: (_, _) {
        subscriptions++;
        if (!available) throw FileSystemException('watch unavailable');
        if (events.isClosed) {
          events = StreamController<FileSystemEvent>.broadcast();
        }
        return events.stream;
      },
    );
    controller = ViewerController(
      indexService: index,
      folderChangeWatcher: watcher,
      configStore: AppConfigStore(
        filePath: paths.join(state.path, 'config.json'),
      ),
    );
    configure(FolderBrowseMode.currentFolder);
  }

  static Future<_Harness> create() async => _Harness(
    await Directory.systemTemp.createTemp('refresh-regression-'),
    await Directory.systemTemp.createTemp('refresh-regression-state-'),
  );

  final Directory root;
  final Directory state;
  final _GatedIndex index = _GatedIndex();
  StreamController<FileSystemEvent> events =
      StreamController<FileSystemEvent>.broadcast();
  late final FolderChangeWatcher watcher;
  late final ViewerController controller;
  bool available = true;
  int subscriptions = 0;

  void configure(FolderBrowseMode mode) => controller.configureOptions(
    sortOrder: SortOrder.nameAscending,
    browseMode: mode,
    scanUnknownExtensions: false,
    watchFolderChanges: true,
  );
  String path(String relative) => paths.join(root.path, relative);
  File image(String relative) {
    final file = File(path(relative));
    file.parent.createSync(recursive: true);
    return file..writeAsBytesSync(_pngHeader);
  }

  Future<void> open() => controller.openFolder(root.path);
  Future<void> change(String relative) async {
    events.add(FileSystemCreateEvent(path(relative), false));
    await Future<void>.delayed(Duration.zero);
    watcher.flushNow();
  }

  Future<void> dispose() async {
    await controller.flushPersistence();
    controller.dispose();
    await events.close();
    await root.delete(recursive: true);
    await state.delete(recursive: true);
  }
}

class _ScanGate {
  final entered = Completer<void>();
  final release = Completer<void>();
}

class _GatedIndex extends FolderIndexService {
  int calls = 0;
  _ScanGate? _next;
  _ScanGate holdNext() => _next = _ScanGate();

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
  }) async {
    calls++;
    final gate = _next;
    _next = null;
    final result = await super.indexResult(
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
    if (gate != null) {
      gate.entered.complete();
      await gate.release.future;
      request?.throwIfCancelled();
    }
    return result;
  }
}

Future<void> _settle([int milliseconds = 180]) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('refresh did not complete');
    await _settle(20);
  }
}
