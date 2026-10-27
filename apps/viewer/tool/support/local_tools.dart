import 'dart:io';

import 'package:path/path.dart' as paths;

/// Resolve the fixture encoder without assuming an installation drive.
String? findSevenZip() {
  final override = Platform.environment['SHENVIEW_7ZIP'];
  if (override != null && override.isNotEmpty) {
    return File(override).existsSync() ? override : null;
  }
  final names = Platform.isWindows ? ['7z.exe', '7zz.exe'] : ['7zz', '7z'];
  final directories = [
    ...?Platform.environment['PATH']?.split(Platform.isWindows ? ';' : ':'),
    if (Platform.isWindows)
      for (final variable in ['ProgramW6432', 'ProgramFiles'])
        if (Platform.environment[variable] case final String directory)
          paths.join(directory, '7-Zip'),
  ];
  for (final directory in directories) {
    if (directory.isEmpty) continue;
    for (final name in names) {
      final candidate = paths.join(directory.replaceAll('"', ''), name);
      if (File(candidate).existsSync()) return candidate;
    }
  }
  return null;
}
