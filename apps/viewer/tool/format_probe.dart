import 'dart:convert';
import 'dart:io';

import 'package:shen_view/src/application/native_decoder.dart';
import 'package:shen_view/src/application/format_detector.dart';
import 'package:image/image.dart' as imaging;

Future<void> main(List<String> arguments) async {
  final root = Directory(
    arguments.isEmpty ? 'testdata/formats' : arguments.first,
  );
  final decoder = NativeDecoder();
  final rows = <Map<String, Object?>>[];
  for (final file in root.listSync().whereType<File>().where((file) {
    final extension = file.path.split('.').last.toLowerCase();
    return FormatDetector.extensionMap.containsKey(extension) &&
        !{'zip', 'cbz', 'cbr', 'rar'}.contains(extension);
  })) {
    final stopwatch = Stopwatch()..start();
    try {
      final bytes = await decoder.decode(file.path, targetWidth: 4096);
      stopwatch.stop();
      final frameCount = await decoder.frameCount(file.path);
      final decoded = file.path.toLowerCase().endsWith('.apng')
          ? imaging.decodePng(await file.readAsBytes())
          : null;
      rows.add({
        'file': file.uri.pathSegments.last,
        'status': 'pass',
        'decodeMs': stopwatch.elapsedMilliseconds,
        'pngBytes': bytes.length,
        'frameCount': frameCount,
        if (decoded != null) 'packageFrameCount': decoded.frames.length,
      });
    } catch (error) {
      stopwatch.stop();
      rows.add({
        'file': file.uri.pathSegments.last,
        'status': 'fail',
        'decodeMs': stopwatch.elapsedMilliseconds,
        'error': error.toString(),
      });
    }
  }
  final output = const JsonEncoder.withIndent('  ').convert({
    'generatedAt': DateTime.now().toIso8601String(),
    'decoder': 'ImageMagick fallback baseline',
    'validation': 'decode-smoke-only',
    'colorCorrectness': 'not-checked; run flutter test for pixel assertions',
    'rows': rows,
  });
  final report = File('../../artifacts/format-probe.json');
  await report.parent.create(recursive: true);
  await report.writeAsString(output);
  stdout.writeln(output);
}
