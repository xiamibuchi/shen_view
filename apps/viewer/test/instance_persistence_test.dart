import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/reading_state_store.dart';
import 'package:shen_view/src/domain/reading_state.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';

void main() {
  late Directory root;
  late AppConfigStore config;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('instance-persistence-');
    config = AppConfigStore(filePath: '${root.path}/config.json');
    await const ViewerSettings().save(store: config);
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'mode defaults to single and roundtrips; invalid values fall back',
    () async {
      final defaults = await ViewerSettings.load(store: config);
      expect(defaults.instanceMode, InstanceMode.singleProcess);
      final multi = defaults.copyWith(instanceMode: InstanceMode.multiProcess);
      expect(multi, isNot(defaults));
      await multi.save(store: config, previous: defaults);
      final loaded = await ViewerSettings.load(store: config);
      expect(loaded, multi);
      expect(loaded.hashCode, multi.hashCode);
      await config.write({
        'settings': {'instanceMode': 'unknown'},
      });
      expect(
        (await ViewerSettings.load(store: config)).instanceMode,
        InstanceMode.singleProcess,
      );
    },
  );

  test('stale windows preserve unrelated settings and future fields', () async {
    final a = await ViewerSettings.load(store: config);
    final b = await ViewerSettings.load(store: config);
    await config.update((value) {
      (value['settings'] as Map)['futureSetting'] = 42;
      return value;
    });
    await a
        .copyWith(
          instanceMode: InstanceMode.multiProcess,
          themeMode: ViewerThemeMode.light,
        )
        .save(store: config, previous: a);
    await b.copyWith(localeCode: 'en').save(store: config, previous: b);
    final loaded = await ViewerSettings.load(store: config);
    expect(loaded.instanceMode, InstanceMode.multiProcess);
    expect(loaded.themeMode, ViewerThemeMode.light);
    expect(loaded.localeCode, 'en');
    expect(((await config.read())['settings'] as Map)['futureSetting'], 42);
  });

  test('reading histories merge per location; an unchanged old window cannot roll back progress', () async {
    final a = ReadingStateStore(config);
    final b = ReadingStateStore(config);
    await Future.wait([a.load(), b.load()]);
    await a.save('book-a', const ReadingState(entryPath: '001.png'));
    await b.save('book-b', const ReadingState(entryPath: '005.png'));
    await b.save('book-a', const ReadingState(entryPath: '020.png'));
    // Closing the untouched older window must not re-publish its old page.
    await a.save('book-a', const ReadingState(entryPath: '001.png'));
    final restored = ReadingStateStore(config);
    await restored.load();
    expect(restored['book-a']!.entryPath, '020.png');
    expect(restored['book-b']!.entryPath, '005.png');
  });
}
