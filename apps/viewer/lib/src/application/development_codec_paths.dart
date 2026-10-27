import 'dart:io';

import 'package:path/path.dart' as paths;

/// Native helpers are built at repository level, outside the Flutter project.
Iterable<String> developmentCodecCandidates(
  String relativePath, {
  Directory? workingDirectory,
}) sync* {
  final current = (workingDirectory ?? Directory.current).absolute;
  yield paths.join(current.path, 'build', relativePath);
  final repository = current.parent.parent;
  if (paths.equals(
        current.path,
        paths.join(repository.path, 'apps', 'viewer'),
      ) &&
      File(paths.join(repository.path, 'third_party', 'dependencies.lock.json'))
          .existsSync()) {
    yield paths.join(repository.path, 'build', relativePath);
  }
}
