import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/color_picker_controller.dart';
import 'package:shen_view/src/application/recent_color_store.dart';
import 'package:shen_view/src/domain/picked_color.dart';

const red = PickedColor(red: 255, green: 0, blue: 0, alpha: 255);
const blue = PickedColor(red: 0, green: 0, blue: 255, alpha: 128);

void main() {
  late Directory directory;
  late AppConfigStore config;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('recent-colors-');
    config = AppConfigStore(filePath: '${directory.path}/config.json');
    await config.write({
      'settings': {'themeMode': 'dark'},
      'foreign': 42,
    });
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'history is color-only, bounded, deduplicated by RGBA and persistent',
    () async {
      final store = RecentColorStore(config);
      for (var index = 0; index < 12; index++) {
        await store.record(
          PickedColor(red: index, green: 0, blue: 0, alpha: 255),
        );
      }
      await store.record(red);
      await store.record(blue);
      await store.record(red);
      final restored = await RecentColorStore(
        AppConfigStore(filePath: config.filePath),
      ).load();
      expect(restored, hasLength(8));
      expect(restored.map((color) => color.hexAlpha).take(2), [
        '#FF0000FF',
        '#0000FF80',
      ]);
      expect(restored.map((color) => color.hexAlpha).toSet(), hasLength(8));
      final saved = await config.read();
      expect(saved['foreign'], 42);
      expect(saved['settings'], {'themeMode': 'dark'});
      expect((saved['recentColors'] as List).first, [255, 0, 0, 255]);
    },
  );

  test('invalid channels and duplicate saved colors are ignored', () async {
    await config.update(
      (value) => {
        ...value,
        'recentColors': [
          null,
          [1, 2],
          [256, 0, 0, 255],
          [-1, 0, 0, 255],
          [1.5, 0, 0, 255],
          ['1', 0, 0, 255],
          [255, 0, 0, 255],
          [255, 0, 0, 255],
          [255, 0, 0, 0],
        ],
      },
    );
    expect((await RecentColorStore(config).load()).map((c) => c.hexAlpha), [
      '#FF0000FF',
      '#FF000000',
    ]);
  });

  test(
    'stale windows merge new colors instead of overwriting history',
    () async {
      final a = RecentColorStore(config);
      final b = RecentColorStore(AppConfigStore(filePath: config.filePath));
      await Future.wait([a.load(), b.load()]);
      await Future.wait([
        a.record(red),
        b.record(blue),
        config.update((value) => {...value, 'anotherPartition': 'preserve'}),
      ]);
      expect((await a.load()).map((c) => c.hexAlpha).toSet(), {
        '#FF0000FF',
        '#0000FF80',
      });
      expect((await config.read())['anotherPartition'], 'preserve');
      await b.record(red);
      expect((await a.load()).first.hexAlpha, red.hexAlpha);
    },
  );

  test(
    'failed saves retain local colors and retry without losing other windows',
    () async {
      final history = _FailOnceStore(config);
      final controller = ColorPickerController(history: history);
      addTearDown(controller.dispose);
      controller.chooseRecent(red);
      await controller.flushHistory();
      expect(controller.historyFailed, isTrue);
      expect(controller.recent.single.hexAlpha, red.hexAlpha);
      await RecentColorStore(config).record(blue);
      await controller.refreshHistory();
      expect(controller.historyFailed, isFalse);
      expect(controller.recent.map((c) => c.hexAlpha), [
        red.hexAlpha,
        blue.hexAlpha,
      ]);
    },
  );

  test(
    'controllers share history and keep chosen colors independent of images',
    () async {
      final a = ColorPickerController(history: RecentColorStore(config));
      final b = ColorPickerController(history: RecentColorStore(config));
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      a.setActive(true);
      b.setActive(true);
      a.chooseRecent(red);
      a.chooseRecent(blue);
      await a.flushHistory();
      await b.refreshHistory();
      expect(b.recent.map((c) => c.hexAlpha), [blue.hexAlpha, red.hexAlpha]);
      b.chooseRecent(b.recent.last);
      expect(b.color!.hexAlpha, red.hexAlpha);
      expect(b.selected, isNull);
      b.resetImage();
      expect(b.color!.hexAlpha, red.hexAlpha);
      await b.flushHistory();
      await a.refreshHistory();
      expect(a.recent.map((c) => c.hexAlpha), [red.hexAlpha, blue.hexAlpha]);
      b.setActive(false);
      b.setActive(true);
      await b.flushHistory();
      expect(b.color!.hexAlpha, red.hexAlpha);
    },
  );
}

class _FailOnceStore extends RecentColorStore {
  _FailOnceStore(super.configStore);
  bool fail = true;
  @override
  Future<List<PickedColor>> record(PickedColor color) {
    if (fail) {
      fail = false;
      throw const FileSystemException('simulated write failure');
    }
    return super.record(color);
  }
}
