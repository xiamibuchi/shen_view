import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/recent_open_store.dart';
import 'package:shen_view/src/application/recent_color_store.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/domain/viewer_mode.dart';
import 'package:path/path.dart' as paths;

import 'support/windows_replace_guard.dart';

void main() {
  group('Windows real-process persistence', () {
    late Directory root;
    late AppConfigStore config;
    late RecentOpenStore recent;
    late String dartExecutable;
    var nextWorkerId = 0;
    final workers = <_Worker>[];
    final payload = 'snapshot-' * 8192;

    setUpAll(() async {
      final packages = jsonDecode(
        await File('.dart_tool/package_config.json').readAsString(),
      ) as Map;
      final flutter = (packages['packages'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((value) => value['name'] == 'flutter');
      final packageRoot = Uri.directory(
        Uri.parse(flutter['rootUri'] as String).toFilePath(),
      );
      dartExecutable = packageRoot
          .resolve('../../bin/cache/dart-sdk/bin/dart.exe')
          .toFilePath();
    });
    setUp(() async {
      nextWorkerId = 0;
      root = await Directory.systemTemp.createTemp('viewer-win-并发 配置-');
      config = AppConfigStore(filePath: paths.join(root.path, '共享 配置.json'));
      recent = RecentOpenStore(config);
      await const ViewerSettings(recentOpenLimit: 100).save(store: config);
      await config.update(
        (value) => {
          ...value,
          'generation': 0,
          'mirror': 0,
          'actors': <String, dynamic>{},
          'sentinel': 'preserve',
          'payload': payload,
          'futurePartition': {
            'unknown': [1, 2, 3],
          },
          'readingHistory': {
            'book': {'entryPath': '020.png'},
          },
          'session': {
            'recentFile': 'old.png',
            'recentFolder': 'old-folder',
            'recentReadingPath': 'old.cbz',
            'foreign': 42,
          },
        },
      );
    });
    tearDown(() async {
      for (final worker in workers) {
        await worker.kill();
      }
      workers.clear();
      await root.delete(recursive: true);
    });

    String file(String name) => paths.join(root.path, name);
    Future<void> signal(String path) => File(path).writeAsString('go');

    Future<_Worker> start(Map<String, dynamic> options) async {
      final id = nextWorkerId++;
      final prefix = file('worker-$id');
      final job = <String, dynamic>{
        'config': config.filePath,
        'actor': 'actor-$id',
        'start': file('go'),
        'payload': payload,
        for (final name in [
          'ready',
          'result',
          'attempting',
          'observing',
          'paused',
          'resume',
          'held',
          'release',
          'failed',
          'stop',
        ])
          name: '$prefix-$name',
        ...options,
      };
      final jobFile = File('$prefix-job.json');
      await jobFile.writeAsString(jsonEncode(job));
      final process = await Process.start(dartExecutable, [
        '--packages=${paths.absolute('.dart_tool/package_config.json')}',
        paths.absolute('test/support/persistence_worker.dart'),
        jobFile.path,
      ]);
      final worker = _Worker(process, job);
      workers.add(worker);
      await worker.waitFor('ready');
      return worker;
    }

    Future<void> finishAll(Iterable<_Worker> values) async {
      await Future.wait(values.map((worker) => worker.finish()));
    }

    void expectPreserved(Map<String, dynamic> value) {
      expect(value['sentinel'], 'preserve');
      expect(value['payload'], payload);
      expect(value['futurePartition'], {
        'unknown': [1, 2, 3],
      });
      expect(value['readingHistory'], {
        'book': {'entryPath': '020.png'},
      });
    }

    void expectValidRecent(List<RecentOpenEntry> entries, int maximum) {
      expect(entries.length, lessThanOrEqualTo(maximum));
      expect(
        entries
            .map((entry) => paths.normalize(entry.path).toLowerCase())
            .toSet(),
        hasLength(entries.length),
      );
      for (var index = 1; index < entries.length; index++) {
        expect(
          entries[index - 1].openedAt.isBefore(entries[index].openedAt),
          isFalse,
        );
      }
    }

    test('color picks from separate processes merge and duplicate picks move to front', () async {
      final a = await start({
        'operation': 'recent-color',
        'rgba': [255, 0, 0, 255],
      });
      final b = await start({
        'operation': 'recent-color',
        'rgba': [0, 0, 255, 128],
      });
      final settings = await start({'operation': 'settings'});
      await signal(file('go'));
      await finishAll([a, b, settings]);
      final colors = RecentColorStore(config);
      expect((await colors.load()).map((c) => c.hexAlpha).toSet(), {
        '#FF0000FF',
        '#0000FF80',
      });
      final repeats = await Future.wait([
        for (var index = 0; index < 6; index++)
          start({
            'operation': 'recent-color',
            'rgba': [255, 0, 0, 255],
            'start': file('same-color-go'),
          }),
      ]);
      await signal(file('same-color-go'));
      await finishAll(repeats);
      expect((await colors.load()).map((c) => c.hexAlpha), [
        '#FF0000FF',
        '#0000FF80',
      ]);
      expectPreserved(await config.read());
    });

    test('window geometry uses event order across processes and preserves concurrent settings', () async {
      Map<String, dynamic> placement(int stamp) => {
        'x': stamp.toDouble(),
        'y': 80.0,
        'width': 900.0,
        'height': 650.0,
        'updatedAt': stamp,
        'source': 'window-$stamp',
        'scaleFactor': 1.0,
      };
      final stale = await start({
        'operation': 'window-placement',
        'placement': placement(1),
        'start': file('late-window-go'),
      });
      final writers = await Future.wait([
        for (var index = 2; index <= 5; index++)
          start({
            'operation': 'window-placement',
            'placement': placement(index),
          }),
        start({'operation': 'settings', 'count': 10}),
      ]);
      await signal(file('go'));
      await finishAll(writers);
      await signal(file('late-window-go'));
      await stale.finish();
      final value = await config.read();
      expect(value['windowPlacement'], placement(5));
      expect((value['settings'] as Map)['actor-5'], 10);
      expectPreserved(value);
    });

    test('six contending writers and an independent reader observe only complete snapshots', () async {
      final observer = await start({
        'operation': 'observe',
        'start': file('observe-go'),
      });
      await signal(file('observe-go'));
      await observer.waitFor('observing');
      final writers = await Future.wait(
        List.generate(6, (_) => start({'operation': 'increment', 'count': 25})),
      );
      // Each actor has a distinct job id even when process startup overlaps.
      await signal(file('go'));
      await finishAll(writers);
      await signal(observer.path('stop'));
      final observed = await observer.finish();
      final value = await config.read();
      expect(value['generation'], 150);
      expect(value['mirror'], -150);
      expect((value['actors'] as Map).values, everyElement(25));
      expect((value['actors'] as Map).length, 6);
      expect(observed['samples'], greaterThan(2));
      expect(observed['minimum'], 0);
      expectPreserved(value);
    });

    test('real settings and recent writers merge into one shared config without losing foreign fields', () async {
      var local = await ViewerSettings.load(store: config);
      final actors = await Future.wait([
        for (var index = 0; index < 3; index++)
          start({
            'operation': 'settings',
            'actor': 'setting-$index',
            'count': 20,
            if (index == 0) ...{
              'settingsEdits': {
                'alwaysOnTop': true,
                'animationAutoPlay': false,
              },
              'autoPlayEdits': {'loop': true},
            },
          }),
        for (var index = 0; index < 3; index++)
          start({
            'operation': 'recent',
            'kind': RecentOpenKind.values[index].name,
            'count': 20,
            'paths': List.generate(
              20,
              (item) => file('目录 $index/图片 $item.png'),
            ),
          }),
      ]);
      await signal(file('go'));
      for (var index = 0; index < 20; index++) {
        final updated = local.copyWith(
          themeMode: index.isEven
              ? ViewerThemeMode.light
              : ViewerThemeMode.dark,
          localeCode: 'zh',
        );
        await updated.save(store: config, previous: local);
        local = updated;
      }
      await finishAll(actors);
      // The UI snapshot predates the foreign writes. Its last save changes an
      // actual nested setting, and must not revert other known settings or
      // drop unknown nested keys just because those edits finished first.
      await local
          .copyWith(
            themeMode: ViewerThemeMode.light,
            localeCode: 'en',
            autoPlay: local.autoPlay.copyWith(
              intervals: {ViewerMode.single: 7.5},
            ),
          )
          .save(store: config, previous: local);
      final value = await config.read();
      final settings = value['settings'] as Map;
      expect(settings['themeMode'], ViewerThemeMode.light.name);
      expect(settings['localeCode'], 'en');
      expect(settings['alwaysOnTop'], isTrue);
      expect(settings['animationAutoPlay'], isFalse);
      expect((settings['autoPlay'] as Map)['loop'], isTrue);
      expect(
        ((settings['autoPlay'] as Map)['intervals'] as Map)['single'],
        7.5,
      );
      for (var index = 0; index < 3; index++) {
        expect(settings['setting-$index'], 20);
        expect((settings['autoPlay'] as Map)['future-setting-$index'], 20);
      }
      final entries = await recent.load(limit: 100);
      expect(entries, hasLength(60));
      expect(
        entries.map((entry) => entry.kind).toSet(),
        RecentOpenKind.values.toSet(),
      );
      expectValidRecent(entries, 100);
      expectPreserved(value);
    });

    test(
      'case, separators and dot segments identify one Windows recent path',
      () async {
        await Directory(file('sub')).create();
        final image = file('中文 image.png');
        final aliases = [
          image,
          image.toUpperCase(),
          image.split(Platform.pathSeparator).join('/'),
          paths.join(root.path, 'sub', '..', '中文 image.png'),
        ];
        final actors = await Future.wait([
          for (final alias in aliases)
            start({
              'operation': 'recent',
              'paths': [alias],
              'count': 20,
            }),
        ]);
        await signal(file('go'));
        await finishAll(actors);
        final entries = await recent.load(limit: 100);
        expect(entries, hasLength(1));
        expect(
          entries.single.path.toLowerCase(),
          paths.normalize(image).toLowerCase(),
        );
        expectPreserved(await config.read());
      },
    );

    test('stale callers obey a newly reduced shared recent limit', () async {
      final actors = await Future.wait(
        List.generate(
          4,
          (index) => start({
            'operation': 'recent',
            'count': 20,
            'limit': 100,
            'paths': List.generate(20, (item) => file('$index-$item.png')),
          }),
        ),
      );
      final before = await ViewerSettings.load(store: config);
      await before
          .copyWith(recentOpenLimit: 5)
          .save(store: config, previous: before);
      await signal(file('go'));
      await finishAll(actors);
      await recent.record(file('last.png'), RecentOpenKind.image, limit: 100);
      final entries = await recent.load(limit: 100);
      expect(entries, hasLength(5));
      expect(entries.first.path, file('last.png'));
      expectValidRecent(entries, 5);
    });

    test('disabling and clearing records defeats writers that loaded the old enabled policy', () async {
      await recent.record(file('seed.png'), RecentOpenKind.image);
      final actors = await Future.wait(
        List.generate(
          4,
          (index) => start({
            'operation': 'recent',
            'count': 15,
            'paths': [file('stale-$index.png')],
          }),
        ),
      );
      for (final actor in actors) {
        final ready = await actor.read('ready');
        expect((ready['settings'] as Map)['recentOpenEnabled'], isTrue);
      }
      final before = await ViewerSettings.load(store: config);
      await before
          .copyWith(recentOpenEnabled: false)
          .save(store: config, previous: before);
      await recent.clear();
      await signal(file('go'));
      await finishAll(actors);
      expect(await recent.load(limit: 100), isEmpty);
      final value = await config.read();
      expect(value['session'], {'foreign': 42});
      expect((value['settings'] as Map)['recentOpenEnabled'], isFalse);
      expectPreserved(value);
    });

    test('clearing between writer phases never resurrects records committed before the clear', () async {
      final actors = await Future.wait(
        List.generate(
          3,
          (index) => start({
            'operation': 'recent',
            'count': 10,
            'pauseAfter': 5,
            'paths': List.generate(
              10,
              (item) => file('writer-$index-$item.png'),
            ),
          }),
        ),
      );
      await signal(file('go'));
      await Future.wait(actors.map((actor) => actor.waitFor('paused')));
      expect(await recent.load(limit: 100), hasLength(15));
      await recent.clear();
      expect(await recent.load(limit: 100), isEmpty);
      await Future.wait(actors.map((actor) => signal(actor.path('resume'))));
      await finishAll(actors);
      final entries = await recent.load(limit: 100);
      expect(entries.map((entry) => entry.path).toSet(), {
        for (var writer = 0; writer < 3; writer++)
          for (var item = 5; item < 10; item++)
            file('writer-$writer-$item.png'),
      });
      expectValidRecent(entries, 100);
      expect((await config.read())['session'], {'foreign': 42});
      expectPreserved(await config.read());
    });

    test('case-insensitive removal survives unrelated writers resuming from old snapshots', () async {
      final target = file('Remove 中文.png');
      await recent.record(target, RecentOpenKind.image);
      final actors = await Future.wait(
        List.generate(
          3,
          (index) => start({
            'operation': 'recent',
            'count': 6,
            'pauseAfter': 3,
            'paths': List.generate(6, (item) => file('other-$index-$item.png')),
          }),
        ),
      );
      await signal(file('go'));
      await Future.wait(actors.map((actor) => actor.waitFor('paused')));
      await recent.remove(target.toUpperCase());
      await Future.wait(actors.map((actor) => signal(actor.path('resume'))));
      await finishAll(actors);
      final entries = await recent.load(limit: 100);
      expect(
        entries.any(
          (entry) => entry.path.toLowerCase() == target.toLowerCase(),
        ),
        isFalse,
      );
      expect(entries, hasLength(18));
      expectValidRecent(entries, 100);
    });

    test('killing a lock holder with partial temp JSON preserves the old commit and releases waiting writers', () async {
      final holder = await start({'operation': 'hold-dirty-temp'});
      await signal(file('go'));
      final held = await holder.waitFor('held');
      final writers = await Future.wait(
        List.generate(3, (_) => start({'operation': 'increment', 'count': 15})),
      );
      await Future.wait(writers.map((worker) => worker.waitFor('attempting')));
      final before = await config.read().timeout(const Duration(seconds: 2));
      expect(before['generation'], 0);
      expectPreserved(before);
      final temporary = File(held['temporary'] as String);
      expect(
        () => jsonDecode(temporary.readAsStringSync()),
        throwsFormatException,
      );
      await holder.kill();
      await finishAll(writers);
      final after = await config.read();
      expect(after['generation'], 45);
      expect(after['mirror'], -45);
      expectPreserved(after);
      expect(
        await temporary.exists(),
        isTrue,
        reason: 'An uncommitted orphan must never replace the config.',
      );
    });

    test('Windows sharing violation preserves the old config, cleans its temp and permits retry in the same process', () async {
      final guard = WindowsReplaceGuard(config.filePath);
      addTearDown(guard.close);
      final actor = await start({'operation': 'expect-replace-failure'});
      await signal(file('go'));
      final failed = await actor.waitFor('failed');
      expect(failed['errorCode'], isNotNull);
      final before = await config.read();
      expect(before.containsKey('mustNotCommit'), isFalse);
      expectPreserved(before);
      final temporary = await root
          .list()
          .where((entry) => paths.basename(entry.path).contains('.tmp-'))
          .toList();
      expect(temporary, isEmpty);
      guard.close();
      await signal(actor.path('resume'));
      await actor.finish();
      final after = await config.read();
      expect(after['recovered'], isTrue);
      expect(after.containsKey('mustNotCommit'), isFalse);
      expectPreserved(after);
    });

    test('an unreadable existing config cannot be mistaken for defaults during update', () async {
      final actor = await start({'operation': 'expect-replace-failure'});
      final guard = WindowsReplaceGuard(config.filePath, denyRead: true);
      addTearDown(guard.close);
      await signal(file('go'));
      final failed = await actor.waitFor('failed');
      expect(failed['errorCode'], isNotNull);
      await expectLater(config.read(), throwsA(isA<FileSystemException>()));
      guard.close();
      final beforeRetry = await config.read();
      expect(beforeRetry.containsKey('mustNotCommit'), isFalse);
      expectPreserved(beforeRetry);
      await signal(actor.path('resume'));
      await actor.finish();
      final after = await config.read();
      expect(after['recovered'], isTrue);
      expect(after.containsKey('mustNotCommit'), isFalse);
      expectPreserved(after);
    });

    test(
      'a throwing update releases the lock for both local and foreign writers',
      () async {
        final actor = await start({'operation': 'increment', 'count': 1});
        await expectLater(
          config.update((_) => throw StateError('rejected edit')),
          throwsStateError,
        );
        await signal(file('go'));
        await config.update((value) => {...value, 'localRecovered': true});
        await actor.finish();
        final value = await config.read();
        expect(value['generation'], 1);
        expect(value['localRecovered'], isTrue);
        expectPreserved(value);
      },
    );

    test('lock timeout leaves data intact and does not poison the process write queue', () async {
      final holder = await start({'operation': 'hold-dirty-temp'});
      await signal(file('go'));
      await holder.waitFor('held');
      final actor = await start({'operation': 'timeout-then-retry'});
      final failed = await actor.waitFor('failed');
      expect(failed['elapsedMs'] as int, greaterThanOrEqualTo(9500));
      expect(failed['errorCode'], isNotNull);
      final before = await config.read();
      expect(before.containsKey('mustNotCommit'), isFalse);
      expectPreserved(before);
      await holder.kill();
      await signal(actor.path('resume'));
      await actor.finish();
      final after = await config.read();
      expect(after['recovered'], isTrue);
      expect(after.containsKey('mustNotCommit'), isFalse);
      expectPreserved(after);
    }, timeout: const Timeout(Duration(seconds: 45)));
  }, skip: !Platform.isWindows);
}

class _Worker {
  _Worker(this.process, this.job) {
    output = process.stdout.transform(utf8.decoder).join();
    errors = process.stderr.transform(utf8.decoder).join();
    exitCode = process.exitCode.then((value) {
      exited = true;
      return value;
    });
  }

  final Process process;
  final Map<String, dynamic> job;
  late final Future<String> output;
  late final Future<String> errors;
  late final Future<int> exitCode;
  bool exited = false;

  String path(String name) => job[name] as String;

  Future<Map<String, dynamic>> read(String name) async =>
      Map<String, dynamic>.from(
        jsonDecode(await File(path(name)).readAsString()) as Map,
      );

  Future<Map<String, dynamic>> waitFor(String name) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!await File(path(name)).exists()) {
      if (exited) fail('Worker exited before $name: ${await errors}');
      if (DateTime.now().isAfter(deadline)) {
        fail('Worker barrier timed out: $name ($job)');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return read(name);
  }

  Future<Map<String, dynamic>> finish() async {
    final code = await exitCode.timeout(const Duration(seconds: 35));
    expect(code, 0, reason: await errors + await output);
    return read('result');
  }

  Future<void> kill() async {
    if (!exited) process.kill();
    await exitCode.timeout(const Duration(seconds: 10));
    await Future.wait([output, errors]);
  }
}
