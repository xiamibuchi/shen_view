import 'dart:io';

import 'package:path/path.dart' as p;

import 'install_svg_codecs.dart' as codecs;

/// Pre-rasterize fixed UI artwork with the same pinned resvg as image decoding.
/// Flutter selects density variants; monochrome artwork is tinted at draw time.
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.path;
  final output = p.join(root, 'assets', 'ui');
  final codecRoot = p.normalize(p.join(root, '../../build/svg-codecs'));
  await codecs.main(['--output', codecRoot]);
  final executable = p.join(
    codecRoot,
    'bin',
    Platform.isWindows ? 'resvg.exe' : 'resvg',
  );
  for (final (source, name, size) in [
    ('../../branding/app-icon.svg', 'app-icon', 52),
    ('assets/ui/info.svg', 'info', 18),
  ]) {
    for (final density in [1, 2, 3, 4]) {
      final directory = Directory(
        density == 1 ? output : p.join(output, '$density.0x'),
      );
      await directory.create(recursive: true);
      final result = await Process.run(executable, [
        '--width',
        '${size * density}',
        p.join(root, source),
        p.join(directory.path, '$name.png'),
      ]);
      if (result.exitCode != 0) {
        throw ProcessException(
          executable,
          [],
          'resvg failed for $source: ${result.stderr}',
          result.exitCode,
        );
      }
    }
  }
  stdout.writeln('UI icons generated with resvg ${codecs.version} (1x–4x).');
}
