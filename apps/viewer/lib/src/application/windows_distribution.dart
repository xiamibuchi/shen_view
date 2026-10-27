import 'dart:io';

import 'package:path/path.dart' as paths;

class WindowsDistribution {
  static String dataDirectory({
    required String executable,
    required String mode,
    required String localAppData,
  }) {
    final directory = paths.dirname(executable);
    return switch (mode.trim()) {
      'installed' || 'installed-system' => paths.join(localAppData, 'ShenView'),
      'msix' => paths.join(localAppData, 'ShenView', 'MSIX'),
      'portable' || 'scoop' => paths.join(directory, 'user-data'),
      _ => directory,
    };
  }

  static String currentDataDirectory() {
    final executable = Platform.resolvedExecutable;
    final marker = File(
      paths.join(paths.dirname(executable), 'installation-mode'),
    );
    final mode = marker.existsSync() ? marker.readAsStringSync().trim() : '';
    return dataDirectory(
      executable: executable,
      mode: mode,
      localAppData:
          Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path,
    );
  }
}
