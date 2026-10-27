import 'dart:convert';
import 'dart:io';

import 'package:shen_view/src/application/native_decoder.dart';

Future<int?> workingSet() async {
  if (!Platform.isWindows) return null;
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    '(Get-Process -Id $pid).WorkingSet64',
  ]);
  return int.tryParse(result.stdout.toString().trim());
}

Future<void> main(List<String> arguments) async {
  final root = Directory(
    arguments.isEmpty ? 'testdata/formats' : arguments.first,
  );
  final files = root
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.png'))
      .toList();
  final targets = files
      .where(
        (file) =>
            file.path.endsWith('format_static.png') ||
            file.path.endsWith('format_long.png'),
      )
      .toList();
  final decoder = NativeDecoder();
  final samples = <Map<String, Object?>>[];
  var peak = 0;
  for (final file in targets) {
    final first = Stopwatch()..start();
    await decoder.decode(file.path, targetWidth: 4096);
    first.stop();
    final turnTimes = <int>[];
    for (var index = 0; index < 3; index++) {
      final stopwatch = Stopwatch()..start();
      await decoder.decode(file.path, targetWidth: 4096);
      stopwatch.stop();
      turnTimes.add(stopwatch.elapsedMilliseconds);
      peak = [peak, await workingSet() ?? 0].reduce((a, b) => a > b ? a : b);
    }
    turnTimes.sort();
    samples.add({
      'file': file.uri.pathSegments.last,
      'firstFrameMs': first.elapsedMilliseconds,
      'pageTurnMs': turnTimes,
      'pageTurnP50Ms': turnTimes[turnTimes.length ~/ 2],
      'pageTurnP95Ms': turnTimes.last,
    });
  }
  final report = {
    'generatedAt': DateTime.now().toIso8601String(),
    'decoder': 'ImageMagick fallback baseline',
    'processPeakWorkingSetBytes': peak,
    'samples': samples,
  };
  final output = const JsonEncoder.withIndent('  ').convert(report);
  final file = File('../../artifacts/performance-probe.json');
  await file.parent.create(recursive: true);
  await file.writeAsString(output);
  stdout.writeln(output);
}
