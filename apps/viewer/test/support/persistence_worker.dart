import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/process_file_lock.dart';
import 'package:shen_view/src/application/recent_open_store.dart';
import 'package:shen_view/src/application/recent_color_store.dart';
import 'package:shen_view/src/domain/picked_color.dart';
import 'package:shen_view/src/application/window_placement_store.dart';

/// A real OS writer/reader, with file barriers for reproducible interleavings.
Future<void> main(List<String> arguments) async {
  final job = Map<String, dynamic>.from(
    jsonDecode(await File(arguments.single).readAsString()) as Map,
  );
  final configPath = job['config'] as String;
  final store = AppConfigStore(filePath: configPath);
  final recent = RecentOpenStore(store);
  final before = await store.read();
  await publish(job['ready'] as String, {
    'pid': pid,
    'settings': before['settings'],
  });
  await waitForFile(job['start'] as String);
  final operation = job['operation'] as String;
  final count = job['count'] as int? ?? 1;
  final actor = job['actor'] as String? ?? 'worker';
  final result = <String, dynamic>{'pid': pid};

  switch (operation) {
    case 'recent-color':
      final rgba = List<int>.from(job['rgba'] as List);
      await RecentColorStore(store).record(
        PickedColor(
          red: rgba[0],
          green: rgba[1],
          blue: rgba[2],
          alpha: rgba[3],
        ),
      );
    case 'window-placement':
      await WindowPlacementStore(store)
          .save(WindowPlacement.fromJson(job['placement'])!);
    case 'increment':
      await publish(job['attempting'] as String, {'pid': pid});
      for (var index = 0; index < count; index++) {
        await store.update((config) {
          final generation = (config['generation'] as int) + 1;
          config['generation'] = generation;
          config['mirror'] = -generation;
          final actors = Map<String, dynamic>.from(config['actors'] as Map);
          actors[actor] = (actors[actor] as int? ?? 0) + 1;
          config['actors'] = actors;
          return config;
        });
      }
    case 'observe':
      var samples = 0;
      var minimum = 1 << 30;
      var maximum = -1;
      var rawSharingConflicts = 0;
      do {
        // Raw reads expose malformed/partial JSON; the store additionally must
        // not silently return its empty fallback during a concurrent rename.
        final snapshots = <Map<dynamic, dynamic>>[];
        try {
          snapshots.add(
            jsonDecode(await File(configPath).readAsString()) as Map,
          );
        } on FileSystemException catch (error) {
          if (!Platform.isWindows ||
              ![5, 32, 33].contains(error.osError?.errorCode)) {
            rethrow;
          }
          // Raw file opens can legitimately conflict with replacement; the
          // application API below must still return a complete snapshot.
          rawSharingConflicts++;
        }
        snapshots.add(await store.read());
        for (final value in snapshots) {
          if (value['sentinel'] != 'preserve' ||
              value['generation'] is! int ||
              value['mirror'] != -(value['generation'] as int) ||
              value['payload'] != job['payload']) {
            throw StateError('Observed an incomplete committed configuration');
          }
          final generation = value['generation'] as int;
          if (generation < minimum) minimum = generation;
          if (generation > maximum) maximum = generation;
          samples++;
        }
        if (!await File(job['observing'] as String).exists()) {
          await publish(job['observing'] as String, {'pid': pid});
        }
        await Future<void>.delayed(const Duration(milliseconds: 1));
      } while (!await File(job['stop'] as String).exists());
      result.addAll({
        'samples': samples,
        'minimum': minimum,
        'maximum': maximum,
        'rawSharingConflicts': rawSharingConflicts,
      });
    case 'settings':
      for (var index = 0; index < count; index++) {
        await store.update((config) {
          final settings = Map<String, dynamic>.from(config['settings'] as Map);
          if (job['settingsEdits'] case final Map<dynamic, dynamic> edits) {
            settings.addAll(Map<String, dynamic>.from(edits));
          }
          settings[actor] = index + 1;
          final autoPlay = Map<String, dynamic>.from(
            settings['autoPlay'] as Map,
          );
          if (job['autoPlayEdits'] case final Map<dynamic, dynamic> edits) {
            autoPlay.addAll(Map<String, dynamic>.from(edits));
          }
          autoPlay['future-$actor'] = index + 1;
          settings['autoPlay'] = autoPlay;
          config['settings'] = settings;
          return config;
        });
      }
    case 'recent':
      final files = List<String>.from(job['paths'] as List);
      final kind = RecentOpenKind.values.byName(
        job['kind'] as String? ?? 'image',
      );
      for (var index = 0; index < count; index++) {
        await recent.record(
          files[index % files.length],
          kind,
          limit: job['limit'] as int? ?? 100,
        );
        if (index + 1 == job['pauseAfter']) {
          await publish(job['paused'] as String, {'pid': pid});
          await waitForFile(job['resume'] as String);
        }
      }
    case 'hold-dirty-temp':
      await ProcessFileLock.run('$configPath.lock', () async {
        final temporary = File('$configPath.tmp-crashed-$pid');
        await temporary.writeAsString('{"generation":', flush: true);
        await publish(job['held'] as String, {'temporary': temporary.path});
        await waitForFile(job['release'] as String);
      });
    case 'expect-replace-failure':
      try {
        await store.update((config) => {...config, 'mustNotCommit': true});
        throw StateError('Replacement unexpectedly succeeded');
      } on FileSystemException catch (error) {
        result['errorCode'] = error.osError?.errorCode;
      }
      await publish(job['failed'] as String, result);
      await waitForFile(job['resume'] as String);
      await store.update((config) => {...config, 'recovered': true});
    case 'timeout-then-retry':
      final stopwatch = Stopwatch()..start();
      try {
        await store.update((config) => {...config, 'mustNotCommit': true});
        throw StateError('Lock acquisition unexpectedly succeeded');
      } on FileSystemException catch (error) {
        result.addAll({
          'errorCode': error.osError?.errorCode,
          'elapsedMs': stopwatch.elapsedMilliseconds,
        });
      }
      await publish(job['failed'] as String, result);
      await waitForFile(job['resume'] as String);
      await store.update((config) => {...config, 'recovered': true});
    default:
      throw ArgumentError.value(operation, 'operation');
  }
  await publish(job['result'] as String, result);
}

Future<void> publish(String path, Map<String, dynamic> value) async {
  final temporary = File('$path.pending-$pid');
  await temporary.writeAsString(jsonEncode(value), flush: true);
  await temporary.rename(path);
}

Future<void> waitForFile(String path) async {
  final deadline = DateTime.now().add(const Duration(seconds: 35));
  while (!await File(path).exists()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Missing process barrier: $path');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
