import 'dart:convert';
import 'dart:io';

import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/app_instance_coordinator.dart';

/// Runs in a real OS process, so static queues cannot mask broken file locks.
Future<void> main(List<String> arguments) async {
  final config = AppConfigStore(filePath: arguments[1]);
  if (arguments[0] == 'increment') {
    for (var i = 0; i < 30; i++) {
      await config.update((value) {
        value['count'] = (value['count'] as int? ?? 0) + 1;
        return value;
      });
    }
    return;
  }
  final instance = await AppInstanceCoordinator.start(
    config: config,
    request: AppLaunchRequest.fromArguments(arguments.skip(2).toList()),
  );
  stdout.writeln(jsonEncode({'forwarded': instance == null, 'pid': pid}));
  if (instance == null) return;
  instance.attach(
    (request) => stdout.writeln(jsonEncode({'paths': request.paths})),
  );
  await stdin.first;
  await instance.close();
}
