import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/archive_service.dart';
import 'package:shen_view/src/application/recent_open_store.dart';
import 'package:shen_view/src/application/viewer_controller.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';

void main() {
  late Directory root;
  late AppConfigStore config;
  late RecentOpenStore store;

  ViewerController createController() => ViewerController(
    configStore: config,
    archiveService: ArchiveService(
      cachePolicy: ArchiveCachePolicy(
        directory: Directory('${root.path}/cache'),
      ),
    ),
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('recent-open-');
    config = AppConfigStore(filePath: '${root.path}/config.json');
    store = RecentOpenStore(config);
  });
  tearDown(() async {
    // AppConfigStore's queue drains before deleting the fixture.
    await config.update((value) => value);
    await root.delete(recursive: true);
  });

  test('settings default, roundtrip, copy and invalid fields', () async {
    const defaults = ViewerSettings();
    expect(defaults.recentOpenEnabled, isTrue);
    expect(defaults.recentOpenLimit, 20);
    expect(defaults.openRecentOnNewWindow, isFalse);
    final settings = defaults.copyWith(
      recentOpenEnabled: false,
      recentOpenLimit: 50,
      openRecentOnNewWindow: true,
    );
    await settings.save(store: config);
    final loaded = await ViewerSettings.load(store: config);
    expect(loaded, settings);
    expect(loaded.hashCode, settings.hashCode);
    await config.write({
      'settings': {'recentOpenLimit': -2},
    });
    expect((await ViewerSettings.load(store: config)).recentOpenLimit, 5);
    await config.write({
      'settings': {'recentOpenLimit': 'invalid'},
    });
    expect((await ViewerSettings.load(store: config)).recentOpenLimit, 20);
  });

  test(
    'mixed records are bounded, deduplicated and persisted newest first',
    () async {
      for (var i = 0; i < 6; i++) {
        await store.record(
          '${root.path}/$i.png',
          RecentOpenKind.image,
          limit: 5,
        );
      }
      await store.record('${root.path}/3.png', RecentOpenKind.image, limit: 5);
      var entries = await RecentOpenStore(config).load();
      expect(entries, hasLength(5));
      expect(entries.first.name, '3.png');
      expect(entries.where((entry) => entry.name == '0.png'), isEmpty);
      if (Platform.isWindows) {
        await store.record(
          '${root.path}/3.PNG',
          RecentOpenKind.image,
          limit: 5,
        );
        expect(await store.load(), hasLength(5));
      }
      await store.remove((await store.load()).first.path);
      expect(await store.load(), hasLength(4));
      await store.trim(2);
      entries = await store.load();
      expect(entries, hasLength(2));
      expect(entries.first.openedAt.isUtc, isTrue);
    },
  );

  test(
    'clear preserves reading progress and stops legacy startup restore',
    () async {
      final controller = createController();
      await controller.openFolder(root.path);
      await controller.flushPersistence();
      await config.update((value) {
        value['readingHistory'] = {
          'example': {'entryPath': '2.png'},
        };
        return value;
      });
      await controller.clearRecentOpen();
      expect(await controller.restoreRecentFolder(), isFalse);
      final saved = await config.read();
      expect(await store.load(), isEmpty);
      expect(saved['readingHistory'], isNotEmpty);
      controller.dispose();
    },
  );

  test(
    'disabled recording prevents both list and last-location writes',
    () async {
      final controller = createController()..recentOpenEnabled = false;
      await controller.openFolder(root.path);
      await controller.recordRecentImage('${root.path}/1.png');
      await controller.flushPersistence();
      expect(await store.load(), isEmpty);
      expect((await config.read())['session'], isNull);
      controller.dispose();
      await const ViewerSettings(recentOpenEnabled: false).save(store: config);
      await store.record(root.path, RecentOpenKind.folder);
      expect(await store.load(), isEmpty);
    },
  );

  test(
    'only opens add records; selection and refresh keep list stable',
    () async {
      final image = File('${root.path}/1.png')
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==',
          ),
        );
      final controller = createController();
      await controller.openFolder(
        root.path,
        preferredFilePath: image.path,
        recordRecentOpen: false,
      );
      await controller.recordRecentImage(image.path);
      controller.select(0);
      await controller.openFolder(root.path, persistRecent: false);
      await controller.flushPersistence();
      var entries = await store.load();
      expect(entries, hasLength(1));
      expect(entries.single.kind, RecentOpenKind.image);
      await controller.openFolder(root.path);
      final archive = Archive()..addFile(ArchiveFile('page.png', 1, [1]));
      final book = File('${root.path}/book.cbz')
        ..writeAsBytesSync(ZipEncoder().encode(archive));
      expect(await controller.openArchive(book), ArchiveOpenOutcome.opened);
      await controller.flushPersistence();
      entries = await store.load();
      expect(entries.map((entry) => entry.kind), [
        RecentOpenKind.archive,
        RecentOpenKind.folder,
        RecentOpenKind.image,
      ]);
      final before = entries.length;
      expect(
        await controller.openArchive(File('${root.path}/missing.cbz')),
        ArchiveOpenOutcome.failed,
      );
      await controller.flushPersistence();
      expect(await store.load(), hasLength(before));
      await controller.flushPersistence();
      controller.dispose();
    },
  );

  test('malformed entries are ignored without losing valid records', () async {
    await config.write({
      'recentOpen': [
        {
          'path': root.path,
          'kind': 'folder',
          'openedAt': '2026-10-22T01:00:00Z',
        },
        {'path': root.path, 'kind': 'folder', 'openedAt': 3},
        {'path': 3},
        {'path': root.path, 'kind': 'invalid', 'openedAt': 'bad'},
        null,
      ],
    });
    expect(await store.load(), hasLength(1));
    await store.record('${root.path}/new.png', RecentOpenKind.image);
    expect(await store.load(), hasLength(2));
  });
}
