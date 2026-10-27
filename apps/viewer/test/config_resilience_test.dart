import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/reading_state_store.dart';
import 'package:shen_view/src/application/recent_color_store.dart';
import 'package:shen_view/src/application/recent_open_store.dart';
import 'package:shen_view/src/application/viewer_controller.dart';
import 'package:shen_view/src/application/window_placement_store.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';

class _UnavailableStore extends AppConfigStore {
  _UnavailableStore(this.failure);
  final Object failure;

  @override
  Future<Map<String, dynamic>> read() => Future.error(failure);
}

class _StalledStore extends AppConfigStore {
  final pending = Completer<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>> read() => pending.future;
}

void main() {
  late Directory directory;
  late AppConfigStore store;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('settings-resilience-');
    file = File('${directory.path}/settings.json');
    store = AppConfigStore(filePath: file.path);
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'missing, malformed, invalid UTF-8 and non-object files use defaults',
    () async {
      expect(await ViewerSettings.load(store: store), const ViewerSettings());
      for (final bytes in [
        utf8.encode(''),
        utf8.encode('{"settings":'),
        utf8.encode('null'),
        utf8.encode('[1, 2, 3]'),
        utf8.encode(jsonEncode('settings')),
        [255, 254, 0],
      ]) {
        await file.writeAsBytes(bytes);
        expect(await ViewerSettings.load(store: store), const ViewerSettings());
        expect(await file.readAsBytes(), bytes);
      }
    },
  );

  test(
    'every preference tolerates arbitrary JSON field types independently',
    () async {
      const valid = ViewerSettings(localeCode: 'en', autoHdr: false);
      for (final field in valid.toJson().keys) {
        for (final value in <Object?>[null, true, 42, 'invalid', [], {}]) {
          await store.write({
            'settings': {...valid.toJson(), field: value},
          });
          final loaded = await ViewerSettings.load(store: store);
          if (field != 'localeCode') {
            expect(loaded.localeCode, 'en', reason: '$field: $value');
          }
          if (field != 'autoHdr') {
            expect(loaded.autoHdr, isFalse, reason: '$field: $value');
          }
        }
      }
    },
  );

  test('unavailable config defaults every startup reader without hiding strict errors', () async {
    final unavailable = _UnavailableStore(
      const FileSystemException('Access denied'),
    );
    expect(
      await ViewerSettings.load(store: unavailable),
      const ViewerSettings(),
    );
    await ReadingStateStore(unavailable).load();
    expect(await RecentOpenStore(unavailable).load(), isEmpty);
    expect(await RecentColorStore(unavailable).load(), isEmpty);
    expect(await WindowPlacementStore(unavailable).load(), isNull);
    final controller = ViewerController(configStore: unavailable);
    addTearDown(controller.dispose);
    expect(await controller.restoreRecentFolder(), isFalse);
    await expectLater(unavailable.read(), throwsA(isA<FileSystemException>()));
  });

  test(
    'read timeouts return defaults instead of holding startup indefinitely',
    () async {
      final stalled = _StalledStore();
      expect(await ViewerSettings.load(store: stalled), const ViewerSettings());
      stalled.pending.complete({});
    },
  );

  test(
    'a directory in place of config cannot block startup or be overwritten',
    () async {
      await Directory(file.path).create();
      expect(await ViewerSettings.load(store: store), const ViewerSettings());
      await expectLater(
        const ViewerSettings(localeCode: 'en').save(store: store),
        throwsA(isA<FileSystemException>()),
      );
      expect(await Directory(file.path).exists(), isTrue);
    },
  );

  test('oversized files are bounded and protected from replacement', () async {
    await file.writeAsBytes(Uint8List(AppConfigStore.maxFileBytes + 1));
    expect(await ViewerSettings.load(store: store), const ViewerSettings());
    await expectLater(
      const ViewerSettings().save(store: store),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.length(), AppConfigStore.maxFileBytes + 1);
  });

  test(
    'nesting limits ignore brackets and escaped quotes within strings',
    () async {
      final depth = AppConfigStore.maxNestingDepth + 1;
      final text = '[' * depth + ']' * depth;
      await file.writeAsString(text);
      expect(await ViewerSettings.load(store: store), const ViewerSettings());
      expect(await file.readAsString(), text);
      await store.write({
        'settings': {'localeCode': 'en'},
        'unknown': String.fromCharCodes([91, 123, 34, 92]) * 100,
      });
      expect((await ViewerSettings.load(store: store)).localeCode, 'en');
    },
  );

  test('corrupt optional records do not prevent opening the viewer', () async {
    await store.write({
      'settings': {'localeCode': 'en'},
      'session': {
        'recentFolder': 42,
        'recentFile': <Object?>[],
        'recentReadingPath': <String, Object?>{},
      },
      'readingHistory': {
        'bad': 42,
        'empty': {'entryPath': <Object?>[]},
      },
      'recentOpen': [
        null,
        42,
        {'path': <Object?>[]},
      ],
      'recentColors': [
        null,
        [999, 'bad', 0, 255],
      ],
      'windowPlacement': {'width': <Object?>[], 'x': 'bad'},
    });
    final controller = ViewerController(configStore: store);
    addTearDown(controller.dispose);
    expect(await controller.restoreRecentFolder(), isFalse);
    await ReadingStateStore(store).load();
    expect(await RecentOpenStore(store).load(), isEmpty);
    expect(await RecentColorStore(store).load(), isEmpty);
    expect(await WindowPlacementStore(store).load(), isNull);
    expect((await ViewerSettings.load(store: store)).localeCode, 'en');
  });
}
