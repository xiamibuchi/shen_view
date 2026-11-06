import 'package:path/path.dart' as paths;

Map<String, String> nativeDecoderEnvironment(
  String executable, {
  required Map<String, String> inherited,
  required bool isWindows,
}) {
  final path = paths.Context(
    style: isWindows ? paths.Style.windows : paths.Style.posix,
  );
  final directory = path.dirname(executable);
  if (!isWindows) {
    return {...inherited, 'MAGICK_CONFIGURE_PATH': directory};
  }
  final searchPath = inherited.entries
      .where((entry) => entry.key.toUpperCase() == 'PATH')
      .map((entry) => entry.value)
      .firstOrNull;
  return {
    for (final entry in inherited.entries)
      if (entry.key.toUpperCase() != 'PATH') entry.key: entry.value,
    // ImageMagick loads coder DLLs with LOAD_WITH_ALTERED_SEARCH_PATH, so
    // dependencies beside magick.exe must also be on the child's search path.
    'PATH': [
      directory,
      if (searchPath != null && searchPath.isNotEmpty) searchPath,
    ].join(';'),
    'MAGICK_CONFIGURE_PATH': directory,
    'MAGICK_CODER_MODULE_PATH': path.join(directory, 'modules', 'coders'),
    'MAGICK_FILTER_MODULE_PATH': path.join(directory, 'modules', 'filters'),
  };
}
