import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as paths;
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/reading_state_store.dart';
import 'package:shen_view/src/application/viewer_session.dart';
import 'package:shen_view/src/domain/comic_layout_direction.dart';
import 'package:shen_view/src/domain/reading_state.dart';
import 'package:shen_view/src/domain/view_scale_mode.dart';
import 'package:shen_view/src/domain/viewer_mode.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';

void main() {
  test('history and global defaults survive reload without changing unrelated config', () async {
    final root = await Directory.systemTemp.createTemp('reading-state');
    addTearDown(() => root.delete(recursive: true));
    final config = AppConfigStore(
      filePath: paths.join(root.path, 'config.json'),
    );
    await config.write({
      'session': {'recentFile': 'untouched'},
      'futureField': 42,
    });
    const settings = ViewerSettings(
      defaultViewerMode: ViewerMode.longImage,
      defaultScaleModes: {
        ViewerMode.single: ViewScaleMode.originalSize,
        ViewerMode.longImage: ViewScaleMode.fitHeight,
      },
    );
    await settings.save(store: config);
    final history = ReadingStateStore(config);
    await history.load();
    final folder = ReadingStateStore.folderKey(root.path);
    final book = ReadingStateStore.archiveKey(
      paths.join(root.path, 'comic.cbz'),
    );
    await history.save(
      folder,
      const ReadingState(
        mode: ViewerMode.comic,
        scales: {ViewerMode.comic: ViewScaleMode.fitWidth},
        layoutDirection: ComicLayoutDirection.horizontalRightToLeft,
        entryPath: 'chapter/003.png',
        pageFraction: 0.61,
        crossFraction: 0.5,
      ),
    );
    await history.save(
      book,
      const ReadingState(mode: ViewerMode.doublePage, entryPath: '002.png'),
    );
    final restored = ReadingStateStore(config);
    await restored.load();
    expect(restored[folder]!.mode, ViewerMode.comic);
    expect(restored[folder]!.entryPath, 'chapter/003.png');
    expect(restored[folder]!.pageFraction, 0.61);
    expect(
      restored[folder]!.layoutDirection,
      ComicLayoutDirection.horizontalRightToLeft,
    );
    expect(restored[book]!.mode, ViewerMode.doublePage);
    expect((await ViewerSettings.load(store: config)), settings);
    final json = await config.read();
    expect(json['futureField'], 42);
    expect((json['session'] as Map)['recentFile'], 'untouched');
    expect(restored[folder]!.toJson().containsKey('zoom'), isFalse);
  });

  test(
    'switching locations restores preferences without leaking zoom or defaults',
    () {
      final session = ViewerSession();
      addTearDown(session.dispose);
      session.applySettings(
        const ViewerSettings(defaultViewerMode: ViewerMode.longImage),
      );
      session.restoreReadingState(null);
      expect(session.mode, ViewerMode.longImage);
      expect(session.scaleMode, ViewScaleMode.fitWidth);
      session.setMode(ViewerMode.doublePage);
      session.setScaleMode(ViewScaleMode.originalSize);
      session.setReadingDirection(ReadingDirection.rightToLeft);
      final a = session.readingState(entryPath: '002.png');
      session.setZoomed(true);
      session.rotateDisplay();
      session.restoreReadingState(null);
      expect(session.mode, ViewerMode.longImage);
      expect(session.scaleMode, ViewScaleMode.fitWidth);
      expect(session.readingDirection, ReadingDirection.leftToRight);
      expect(session.isZoomed, isFalse);
      expect(session.rotationQuarterTurns, 0);
      session.restoreReadingState(a);
      expect(session.mode, ViewerMode.doublePage);
      expect(session.scaleMode, ViewScaleMode.originalSize);
      expect(session.readingDirection, ReadingDirection.rightToLeft);
      expect(session.settings.defaultViewerMode, ViewerMode.longImage);
      expect(session.settings.readingDirection, ReadingDirection.leftToRight);
      session.applySettings(
        session.settings.copyWith(
          defaultViewerMode: ViewerMode.comic,
          defaultScaleModes: {ViewerMode.doublePage: ViewScaleMode.fitWidth},
          comicLayoutDirection: ComicLayoutDirection.horizontalLeftToRight,
        ),
      );
      expect(session.mode, ViewerMode.doublePage);
      expect(session.scaleMode, ViewScaleMode.originalSize);
      expect(session.readingDirection, ReadingDirection.rightToLeft);
      expect(session.layoutDirection, ComicLayoutDirection.vertical);
      session.restoreReadingState(null);
      expect(session.mode, ViewerMode.comic);
      expect(
        session.layoutDirection,
        ComicLayoutDirection.horizontalLeftToRight,
      );
    },
  );

  test('malformed history and unsafe entry paths fall back safely', () {
    final state = ReadingState.fromJson({
      'mode': 'removedMode',
      'scales': {'single': 'removedScale', 'comic': 'fitHeight'},
      'entryPath': '../outside.png',
      'pageFraction': double.nan,
      'crossFraction': 2,
    });
    expect(state.mode, ViewerMode.single);
    expect(state.scales, {ViewerMode.comic: ViewScaleMode.fitHeight});
    expect(state.entryPath, isNull);
    expect(state.pageFraction, isNull);
    expect(state.crossFraction, 1);
    expect(
      ReadingState.safeEntryPath(
        paths.join(Directory.systemTemp.path, 'image.png'),
      ),
      isNull,
    );
    expect(ReadingState.safeEntryPath(r'\image.png'), isNull);
    expect(
      ReadingState.safeEntryPath(r'chapter\image.png'),
      'chapter/image.png',
    );
  });

  test('history keys normalize aliases and keep nested books separate', () {
    final root = Directory.systemTemp.path;
    expect(
      ReadingStateStore.folderKey(paths.join(root, 'a', '..', 'b')),
      ReadingStateStore.folderKey(paths.join(root, 'b')),
    );
    if (Platform.isWindows) {
      expect(
        ReadingStateStore.folderKey(root.toUpperCase()),
        ReadingStateStore.folderKey(root.toLowerCase()),
      );
    }
    final archive = paths.join(root, 'book.cbz');
    expect(
      ReadingStateStore.archiveKey(archive),
      isNot(
        ReadingStateStore.archiveKey(archive, innerPath: 'book.cbz/inner.cbz'),
      ),
    );
  });
}
