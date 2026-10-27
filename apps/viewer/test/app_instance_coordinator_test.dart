import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/app_instance_coordinator.dart';
import 'package:path/path.dart' as paths;

void main() {
  late Directory root;
  late AppConfigStore config;
  final instances = <AppInstanceCoordinator>[];
  final workers = <Process>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('viewer-instances-');
    config = AppConfigStore(filePath: paths.join(root.path, 'config.json'));
  });
  tearDown(() async {
    for (final worker in workers) {
      worker.kill();
      await worker.exitCode;
    }
    workers.clear();
    for (final instance in instances) {
      await instance.close();
    }
    instances.clear();
    await root.delete(recursive: true);
  });

  Future<AppInstanceCoordinator?> start([List<String> files = const []]) async {
    final instance = await AppInstanceCoordinator.start(
      config: config,
      request: AppLaunchRequest(paths: files),
    );
    if (instance != null) instances.add(instance);
    return instance;
  }

  test('arguments separate options and preserve Unicode, spaces and option-like filenames', () {
    final request = AppLaunchRequest.fromArguments([
      '--new-window',
      '图片 one.png',
      '--',
      '--photo.png',
    ]);
    expect(request.paths, [
      paths.absolute('图片 one.png'),
      paths.absolute('--photo.png'),
    ]);
  });

  test(
    'single-process startup queues paths until the viewer is ready',
    () async {
      final first = (await start())!;
      final file = paths.join(root.path, '中文 image.png');
      expect(await start([file]), isNull);
      final received = <AppLaunchRequest>[];
      first.attach(received.add);
      expect(received.single.paths, [file]);
      expect(await start(), isNull);
      expect(received.last.paths, isEmpty);
    },
  );

  test('multi-process windows survive one closing; switching back reuses a survivor', () async {
    await config.write({
      'settings': {'instanceMode': 'multiProcess'},
    });
    final first = (await start())!;
    final second = (await start())!;
    expect(second, isNot(same(first)));
    await first.close();
    final received = <AppLaunchRequest>[];
    second.attach(received.add);
    await config.write({
      'settings': {'instanceMode': 'singleProcess'},
    });
    expect(await start(), isNull);
    expect(received, hasLength(1));
  });

  test('simultaneous cold launches elect one viewer', () async {
    final results = await Future.wait(List.generate(8, (_) => start()));
    expect(results.whereType<AppInstanceCoordinator>(), hasLength(1));
    final received = <AppLaunchRequest>[];
    results.whereType<AppInstanceCoordinator>().single.attach(received.add);
    expect(received, hasLength(7));
  });

  test('invalid local clients cannot inject file opens', () async {
    final first = (await start())!;
    final received = <AppLaunchRequest>[];
    first.attach(received.add);
    final file = await Directory('${config.filePath}.instances')
        .list()
        .where((file) => file.path.endsWith('.json'))
        .first;
    final endpoint = jsonDecode(await File(file.path).readAsString()) as Map;
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      endpoint['port'] as int,
    );
    socket.writeln(
      jsonEncode({
        'protocol': 1,
        'token': 'wrong',
        'paths': [paths.join(root.path, 'injected.png')],
      }),
    );
    await socket.flush();
    await socket.drain<void>();
    socket.destroy();
    expect(received, isEmpty);
    expect(await start(), isNull);
  });

  Future<Process> worker(
    String command, [
    List<String> arguments = const [],
  ]) async {
    final packageConfig = jsonDecode(
      await File('.dart_tool/package_config.json').readAsString(),
    ) as Map;
    final packages = packageConfig['packages'] as List;
    final flutter = packages.cast<Map<String, dynamic>>().singleWhere(
      (entry) => entry['name'] == 'flutter',
    );
    final flutterPackage = Uri.parse('${flutter['rootUri']}/');
    final dart = flutterPackage
        .resolve(
          '../../bin/cache/dart-sdk/bin/${Platform.isWindows ? 'dart.exe' : 'dart'}',
        )
        .toFilePath();
    final process = await Process.start(dart, [
      'run',
      'test/support/instance_worker.dart',
      command,
      config.filePath,
      ...arguments,
    ]);
    workers.add(process);
    return process;
  }

  test(
    'configuration transactions do not lose updates across real OS processes',
    () async {
      final processes = await Future.wait(
        List.generate(4, (_) => worker('increment')),
      );
      for (final process in processes) {
        final errors = process.stderr.transform(utf8.decoder).join();
        unawaited(process.stdout.drain<void>());
        expect(await process.exitCode, 0, reason: await errors);
      }
      expect((await config.read())['count'], 120);
    },
  );

  test(
    'real processes forward requests and recover after an owner crashes',
    () async {
      final first = await worker('start');
      final lines = StreamIterator(
        first.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      final errors = first.stderr.transform(utf8.decoder).join();
      expect(
        await lines.moveNext().timeout(const Duration(seconds: 20)),
        isTrue,
      );
      expect((jsonDecode(lines.current) as Map)['forwarded'], isFalse);
      final image = paths.join(root.path, '中文 image.png');
      final second = await worker('start', [image]);
      final reply = await second.stdout.transform(utf8.decoder).join();
      final secondErrors = await second.stderr.transform(utf8.decoder).join();
      expect(await second.exitCode, 0, reason: secondErrors);
      expect((jsonDecode(reply) as Map)['forwarded'], isTrue);
      expect(
        await lines.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect((jsonDecode(lines.current) as Map)['paths'], [image]);
      first.kill();
      await first.exitCode;
      await errors;
      await lines.cancel();
      expect(await start(), isNotNull);
    },
  );
}
