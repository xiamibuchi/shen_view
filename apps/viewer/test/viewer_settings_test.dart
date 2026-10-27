import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/domain/comic_layout_direction.dart';
import 'package:shen_view/src/domain/folder_browse_mode.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';

void main() {
  for (final field in ['sortOrder', 'comicPageGap', 'both']) {
    test(
      'invalid $field types fall back without discarding valid settings',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'invalid-settings-types-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final store = AppConfigStore(
          filePath: '${directory.path}/settings.json',
        );
        const valid = ViewerSettings(
          localeCode: 'en',
          themeMode: ViewerThemeMode.light,
          sortOrder: SortOrder.nameDescending,
          comicPageGap: 12.5,
          autoHdr: false,
        );
        for (final invalid in <Object?>[null, false, 'invalid', [], {}]) {
          final config = {
            'settings': {
              ...valid.toJson(),
              if (field != 'comicPageGap') 'sortOrder': invalid ?? 42,
              if (field != 'sortOrder') 'comicPageGap': invalid,
            },
            'session': {'recentFile': 'keep.png'},
          };
          await store.write(config);
          final loaded = await ViewerSettings.load(store: store);
          expect(
            loaded,
            valid.copyWith(
              sortOrder: field == 'comicPageGap'
                  ? SortOrder.nameDescending
                  : SortOrder.nameAscending,
              comicPageGap: field == 'sortOrder' ? 12.5 : 8,
            ),
            reason: '$field: $invalid',
          );
          expect(await store.read(), config);
        }
      },
    );
  }

  test(
    'resetting every setting preserves reading recent and cache records',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'reset-settings-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = AppConfigStore(filePath: '${directory.path}/config.json');
      const changed = ViewerSettings(
        localeCode: 'en',
        autoHdr: false,
        directoryPanelWidth: 560,
        showDirectoryPanel: false,
        pinDirectoryPanel: true,
        archiveDiskBudgetMiB: 4096,
      );
      await changed.save(store: store);
      final records = {
        'readingHistory': {
          'chapter': {'index': 4},
        },
        'recentOpen': [
          {'path': 'keep.png'},
        ],
        'session': {'recentFile': 'keep.png'},
        'archiveCache': {'keep': true},
      };
      await store.update((config) => {...config, ...records});
      await const ViewerSettings().save(store: store, previous: changed);
      expect(await ViewerSettings.load(store: store), const ViewerSettings());
      final restored = await store.read();
      for (final entry in records.entries) {
        expect(restored[entry.key], entry.value);
      }
    },
  );

  test('directory width sanitizes and persists with pin preference', () async {
    final directory = await Directory.systemTemp.createTemp('directory-width-');
    addTearDown(() => directory.delete(recursive: true));
    final store = AppConfigStore(filePath: '${directory.path}/config.json');
    expect((await ViewerSettings.load(store: store)).directoryPanelWidth, 360);
    for (final entry in <Object?, double>{
      null: 360,
      'invalid': 360,
      -1: 240,
      9999: 600,
      475.5: 475.5,
    }.entries) {
      await store.write({
        'settings': {
          'directoryPanelWidth': entry.key,
          'pinDirectoryPanel': true,
        },
      });
      final loaded = await ViewerSettings.load(store: store);
      expect(loaded.directoryPanelWidth, entry.value);
      expect(loaded.pinDirectoryPanel, isTrue);
    }
    expect(ViewerSettings.normalizeDirectoryPanelWidth(double.nan), 360);
    expect(ViewerSettings.normalizeDirectoryPanelWidth(double.infinity), 360);
    const original = ViewerSettings(pinDirectoryPanel: true);
    final changed = original.copyWith(directoryPanelWidth: 480);
    expect(changed, isNot(original));
    await changed.save(store: store);
    final restored = await ViewerSettings.load(store: store);
    expect(restored, changed);
    expect(restored.hashCode, changed.hashCode);
    await restored.copyWith(pinDirectoryPanel: false).save(store: store);
    expect((await ViewerSettings.load(store: store)).directoryPanelWidth, 480);
  });

  test('wide-image defaults and both preferences round trip', () async {
    final directory = await Directory.systemTemp.createTemp('wide-settings-');
    addTearDown(() => directory.delete(recursive: true));
    final store = AppConfigStore(filePath: '${directory.path}/config.json');
    await store.write({
      'settings': {'doublePageFirstAlone': false},
    });
    final defaults = await ViewerSettings.load(store: store);
    expect(defaults.doublePageWideAlone, isTrue);
    expect(defaults.doublePageSplitWide, isFalse);
    for (final alone in [false, true]) {
      for (final split in [false, true]) {
        final changed = defaults.copyWith(
          doublePageWideAlone: alone,
          doublePageSplitWide: split,
        );
        await changed.save(store: store);
        final loaded = await ViewerSettings.load(store: store);
        expect(loaded, changed);
        expect(loaded.hashCode, changed.hashCode);
        expect(loaded.doublePageWideAlone, alone);
        expect(loaded.doublePageSplitWide, split);
      }
    }
  });

  test('filename sorting defaults, validation and persistence', () async {
    final directory = await Directory.systemTemp.createTemp(
      'filename-settings-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = AppConfigStore(filePath: '${directory.path}/config.json');
    final defaults = await ViewerSettings.load(store: store);
    expect(defaults.sortOrder, SortOrder.nameAscending);
    expect(defaults.fileNameSortMode, FileNameSortMode.natural);
    await store.write({
      'settings': {
        'sortOrder': 'fileSystem',
        'archiveSortOrder': 'fileSystem',
        'fileNameSortMode': 'invalid',
      },
    });
    final validated = await ViewerSettings.load(store: store);
    expect(validated.sortOrder, SortOrder.fileSystem);
    expect(validated.archiveSortOrder, SortOrder.nameAscending);
    expect(validated.fileNameSortMode, FileNameSortMode.natural);
    final changed = validated.copyWith(
      fileNameSortMode: FileNameSortMode.lexicographic,
    );
    expect(changed, isNot(validated));
    await changed.save(store: store);
    final loaded = await ViewerSettings.load(store: store);
    expect(loaded, changed);
    expect(loaded.hashCode, changed.hashCode);
    expect(
      const ViewerSettings(archiveSortOrder: SortOrder.fileSystem)
          .archiveSortOrder,
      SortOrder.nameAscending,
    );
  });
  test('folder continuous preference matches current modes and survives recursion off', () async {
    final directory = await Directory.systemTemp.createTemp(
      'folder-reading-settings-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = AppConfigStore(filePath: '${directory.path}/config.json');
    for (final mode in FolderBrowseMode.values) {
      await store.write({
        'settings': {'folderBrowseMode': mode.name},
      });
      final loaded = await ViewerSettings.load(store: store);
      expect(loaded.browseMode, mode);
      expect(loaded.folderContinuousReading, mode.isFlat);
    }
    const flat = ViewerSettings(browseMode: FolderBrowseMode.recursiveFlat);
    final disabled = flat.copyWith(browseMode: FolderBrowseMode.currentFolder);
    await disabled.save(store: store);
    final restored = await ViewerSettings.load(store: store);
    expect(restored, disabled);
    expect(restored.folderContinuousReading, isTrue);
    expect(restored.browseMode.isRecursive, isFalse);
    expect(
      restored
          .copyWith(browseMode: FolderBrowseMode.recursiveFolders)
          .folderContinuousReading,
      isFalse,
    );
    expect(restored.hashCode, disabled.hashCode);
  });

  test('directory visibility defaults and pin persist independently', () async {
    final directory = await Directory.systemTemp.createTemp(
      'directory-settings-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = AppConfigStore(filePath: '${directory.path}/config.json');
    const original = ViewerSettings(archiveContinuousReading: false);
    expect(original.showDirectoryPanel, isTrue);
    expect(original.pinDirectoryPanel, isFalse);
    expect(
      (await ViewerSettings.load(store: store)).showDirectoryPanel,
      isTrue,
    );
    await store.update(
      (config) => {
        ...config,
        'settings': {'pinDirectoryPanel': true},
      },
    );
    final loaded = await ViewerSettings.load(store: store);
    expect(loaded.showDirectoryPanel, isTrue);
    expect(loaded.pinDirectoryPanel, isTrue);
    await original.save(store: store);
    expect(
      (await ViewerSettings.load(store: store)).pinDirectoryPanel,
      isFalse,
    );
    final pinned = original.copyWith(pinDirectoryPanel: true);
    await pinned.save(store: store);
    expect(await ViewerSettings.load(store: store), pinned);
    expect((await ViewerSettings.load(store: store)).hashCode, pinned.hashCode);
    await pinned.copyWith(pinDirectoryPanel: false).save(store: store);
    expect(await ViewerSettings.load(store: store), original);
    final hidden = pinned.copyWith(showDirectoryPanel: false);
    expect(hidden, isNot(pinned));
    await hidden.save(store: store);
    final restored = await ViewerSettings.load(store: store);
    expect(restored, hidden);
    expect(restored.hashCode, hidden.hashCode);
    expect(restored.showDirectoryPanel, isFalse);
    expect(restored.pinDirectoryPanel, isTrue);
  });

  test('input settings persist, preserve unrelated preferences and sanitize config', () async {
    final directory = await Directory.systemTemp.createTemp(
      'interaction-settings',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = AppConfigStore(filePath: '${directory.path}/config.json');
    final defaults = await ViewerSettings.load(store: store);
    expect(defaults.interaction, const ViewerInteractionSettings());
    const value = ViewerInteractionSettings(
      wheelAction: WheelAction.zoom,
      wheelIntervalMs: 350,
      reverseWheel: true,
      scrollSpeed: 1.5,
      zoomSpeed: 0.5,
      keepZoom: true,
      keepZoomPosition: true,
      zoomCenter: ZoomCenter.viewport,
      holdNavigation: false,
      holdDelayMs: 600,
      holdIntervalMs: 250,
      transition: ImageTransition.slide,
      transitionDurationMs: 220,
    );
    final changed = defaults.copyWith(
      interaction: value,
      showBottomBar: false,
      comicUniformSize: false,
    );
    await changed.save(store: store);
    expect(await ViewerSettings.load(store: store), changed);
    expect(
      changed.hashCode,
      (await ViewerSettings.load(store: store)).hashCode,
    );
    await store.update((config) {
      (config['settings'] as Map)['interaction'] = {
        'wheelIntervalMs': -1,
        'holdDelayMs': 'invalid',
        'scrollSpeed': 999,
        'zoomSpeed': 'invalid',
        'transition': 'unknown',
        'wheelAction': 3,
        'holdIntervalMs': -10,
        'transitionDurationMs': 999,
      };
      return config;
    });
    final loaded = await ViewerSettings.load(store: store);
    expect(loaded.showBottomBar, isFalse);
    expect(loaded.interaction.wheelIntervalMs, 80);
    expect(loaded.interaction.holdDelayMs, 400);
    expect(loaded.interaction.scrollSpeed, 3);
    expect(loaded.interaction.zoomSpeed, 1);
    expect(loaded.interaction.transition, ImageTransition.fade);
    expect(loaded.interaction.wheelAction, WheelAction.navigate);
    expect(loaded.interaction.holdIntervalMs, 80);
    expect(loaded.interaction.transitionDurationMs, 500);
    expect(
      ViewerInteractionSettings.fromJson([]),
      const ViewerInteractionSettings(),
    );
    expect(
      ViewerInteractionSettings.fromJson({'scrollSpeed': double.nan})
          .scrollSpeed,
      1,
    );
  });

  test(
    'archive defaults, limits and independent settings survive reload',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'archive-settings',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = AppConfigStore(filePath: '${directory.path}/config.json');
      final defaults = await ViewerSettings.load(store: store);
      expect(defaults.archiveContinuousReading, isTrue);
      expect(defaults.archiveAutoAdvance, isFalse);
      expect(defaults.archiveSortOrder, SortOrder.nameAscending);
      expect(defaults.archiveMemoryBudgetMiB, 0);
      expect(defaults.archiveDiskBudgetMiB, 2048);
      expect(defaults.archiveCacheRetentionDays, 7);
      final changed = defaults.copyWith(
        archiveContinuousReading: false,
        archiveAutoAdvance: true,
        archiveSortOrder: SortOrder.modifiedNewest,
        archivePrefetchMode: ArchivePrefetchMode.conservative,
        archivePersistCache: false,
        archiveMemoryBudgetMiB: 123,
        archiveDiskBudgetMiB: 512,
        archiveCacheRetentionDays: 3,
      );
      expect(changed, isNot(defaults));
      await changed.save(store: store);
      expect(await ViewerSettings.load(store: store), changed);
      expect(changed.sortOrder, defaults.sortOrder);
      await store.update((config) {
        final settings = config['settings'] as Map;
        settings['archiveMemoryBudgetMiB'] = 1;
        settings['archiveDiskBudgetMiB'] = 999999;
        settings['archiveCacheRetentionDays'] = -1;
        settings['archivePrefetchMode'] = 'unknown';
        return config;
      });
      final bounded = await ViewerSettings.load(store: store);
      expect(bounded.archiveMemoryBudgetMiB, 32);
      expect(bounded.archiveDiskBudgetMiB, 8192);
      expect(bounded.archiveCacheRetentionDays, 1);
      expect(bounded.archivePrefetchMode, ArchivePrefetchMode.automatic);
    },
  );

  test('persists settings as named JSON values', () async {
    final directory = await Directory.systemTemp.createTemp(
      'shen_view-settings-json',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = AppConfigStore(filePath: '${directory.path}/settings.json');

    const expected = ViewerSettings(
      themeMode: ViewerThemeMode.light,
      comicLayoutDirection: ComicLayoutDirection.horizontalRightToLeft,
      browseMode: FolderBrowseMode.recursiveFlat,
      scanUnknownExtensions: true,
      alwaysOnTop: true,
      comicPageGap: 12,
      showThumbnailFileNames: false,
      showBottomBar: false,
      autoHdr: false,
    );
    await expected.save(store: store);
    final loaded = await ViewerSettings.load(store: store);
    final json = await store.read();

    expect(loaded.comicLayoutDirection, expected.comicLayoutDirection);
    expect(loaded.themeMode, ViewerThemeMode.light);
    expect(loaded.browseMode, FolderBrowseMode.recursiveFlat);
    expect(loaded.scanUnknownExtensions, isTrue);
    expect(loaded.alwaysOnTop, isTrue);
    expect(loaded.comicPageGap, 12);
    expect(loaded.showThumbnailFileNames, isFalse);
    expect(loaded.showBottomBar, isFalse);
    expect(loaded.autoHdr, isFalse);
    expect(
      (json['settings'] as Map)['comicLayoutDirection'],
      'horizontalRightToLeft',
    );
    expect((json['settings'] as Map)['themeMode'], 'light');
    expect((json['settings'] as Map)['folderBrowseMode'], 'recursiveFlat');
    expect((json['settings'] as Map)['scanUnknownExtensions'], isTrue);
    expect((json['settings'] as Map)['alwaysOnTop'], isTrue);
    expect((json['settings'] as Map)['showBottomBar'], isFalse);
  });

  test('keeps defaults and explicit zero gap across reloads', () async {
    final directory = await Directory.systemTemp.createTemp(
      'shen_view-settings-reload',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = AppConfigStore(filePath: '${directory.path}/settings.json');

    expect(
      (await ViewerSettings.load(store: store)).comicPageGap,
      ViewerSettings.defaultComicPageGap,
    );
    expect((await ViewerSettings.load(store: store)).autoHdr, isTrue);
    await const ViewerSettings(comicPageGap: 0).save(store: store);
    expect((await ViewerSettings.load(store: store)).comicPageGap, 0);
  });

  test('clamps the comic page gap into the supported range', () async {
    final directory = await Directory.systemTemp.createTemp(
      'shen_view-settings-gap-clamp',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = AppConfigStore(filePath: '${directory.path}/settings.json');

    await const ViewerSettings(comicPageGap: -6).save(store: store);
    expect(
      (await ViewerSettings.load(store: store)).comicPageGap,
      ViewerSettings.minComicPageGap,
    );
    await const ViewerSettings(comicPageGap: 400).save(store: store);
    expect(
      (await ViewerSettings.load(store: store)).comicPageGap,
      ViewerSettings.maxComicPageGap,
    );
  });

  test('compares settings by value so page resets can detect changes', () {
    expect(const ViewerSettings(), const ViewerSettings());
    expect(
      const ViewerSettings(localeCode: 'en'),
      isNot(const ViewerSettings()),
    );
    expect(
      const ViewerSettings(
        localeCode: 'en',
        toolbarMode: ToolbarMode.floating,
      ).copyWith(localeCode: 'system', toolbarMode: ToolbarMode.normal),
      const ViewerSettings(),
    );
    expect(
      const ViewerSettings(comicPageGap: 12).hashCode,
      const ViewerSettings(comicPageGap: 12).hashCode,
    );
  });

  test(
    'HDR type choices survive saving and missing fields default on',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'hdr-type-settings',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = AppConfigStore(filePath: '${directory.path}/settings.json');
      await store.update(
        (config) => {
          'settings': {'autoHdr': true},
        },
      );
      expect(await ViewerSettings.load(store: store), const ViewerSettings());

      const chosen = ViewerSettings(
        hdrLinear: false,
        hdrPqHlg: false,
        hdrGainMap: false,
        hdrRaw: false,
        hdrDolbyVision: false,
      );
      await chosen.save(store: store);
      expect(await ViewerSettings.load(store: store), chosen);
      expect(chosen.copyWith(autoHdr: false).copyWith(autoHdr: true), chosen);
      for (final changed in [
        chosen.copyWith(hdrLinear: true),
        chosen.copyWith(hdrPqHlg: true),
        chosen.copyWith(hdrGainMap: true),
        chosen.copyWith(hdrRaw: true),
        chosen.copyWith(hdrDolbyVision: true),
      ]) {
        expect(changed, isNot(chosen));
        await changed.save(store: store);
        final loaded = await ViewerSettings.load(store: store);
        expect(loaded, changed);
        expect(loaded.hashCode, changed.hashCode);
      }
    },
  );

  test('folder watching defaults on and round trips', () async {
    final directory = await Directory.systemTemp.createTemp('watch-settings-');
    addTearDown(() => directory.delete(recursive: true));
    final store = AppConfigStore(filePath: '${directory.path}/config.json');
    expect(
      (await ViewerSettings.load(store: store)).watchFolderChanges,
      isTrue,
    );
    await store.write({
      'settings': {'watchFolderChanges': false},
    });
    final off = await ViewerSettings.load(store: store);
    expect(off.watchFolderChanges, isFalse);
    final on = off.copyWith(watchFolderChanges: true);
    await on.save(store: store);
    final restored = await ViewerSettings.load(store: store);
    expect(restored.watchFolderChanges, isTrue);
    expect(restored, on);
    expect(restored.hashCode, on.hashCode);
  });
}
