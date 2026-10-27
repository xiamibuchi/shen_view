import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as paths;
import 'package:shen_view/src/application/development_codec_paths.dart';

void main() {
  late Directory repository;
  setUp(() {
    repository = Directory.systemTemp.createTempSync('shenview-codec-layout-');
    File(paths.join(repository.path, 'third_party', 'dependencies.lock.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{}');
  });
  tearDown(() => repository.deleteSync(recursive: true));

  test('Flutter project finds helpers built at repository level', () {
    final viewer = Directory(paths.join(repository.path, 'apps', 'viewer'));
    expect(
      developmentCodecCandidates(
        'avif-codecs/bin/helper',
        workingDirectory: viewer,
      ),
      [
        paths.join(viewer.path, 'build', 'avif-codecs/bin/helper'),
        paths.join(repository.path, 'build', 'avif-codecs/bin/helper'),
      ],
    );
  });

  test('repository and unrelated directories do not search parent caches', () {
    for (final directory in [
      repository,
      Directory(paths.join(repository.path, 'unrelated', 'viewer')),
    ]) {
      expect(
        developmentCodecCandidates(
          'archive-helper/bin/helper',
          workingDirectory: directory,
        ),
        [paths.join(directory.path, 'build', 'archive-helper/bin/helper')],
      );
    }
  });
}
