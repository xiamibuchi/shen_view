import 'dart:convert';
import 'dart:io';

import 'package:shen_view/src/application/folder_index_service.dart';
import 'package:shen_view/src/application/folder_order_provider.dart';
import 'package:shen_view/src/domain/folder_browse_mode.dart';
import 'package:shen_view/src/domain/sort_order.dart';

/// Measures folder indexing without the Explorer-order lookup so scanner
/// changes can be compared on the same machine and directory.
///
/// Usage:
///   dart run tool/folder_scan_probe.dart [folder]
///   dart run tool/folder_scan_probe.dart --synthetic
Future<void> main(List<String> arguments) async {
  final synthetic = arguments.contains('--synthetic');
  final root = synthetic
      ? await _createSyntheticTree()
      : Directory(arguments.isEmpty ? 'testdata/formats' : arguments.first);
  if (!await root.exists()) {
    stderr.writeln('Folder not found: ${root.path}');
    exitCode = 2;
    return;
  }
  try {
    final service = FolderIndexService(
      folderOrderProvider: const _NoFolderOrderProvider(),
    );
    final samples = <Map<String, Object?>>[];
    for (final mode in FolderBrowseMode.values) {
      for (final scanUnknownExtensions in [false, true]) {
        final stopwatch = Stopwatch()..start();
        final result = await service.indexResult(
          root.path,
          sortOrder: SortOrder.fileSystem,
          browseMode: mode,
          scanUnknownExtensions: scanUnknownExtensions,
          resolveFolderOrder: false,
        );
        stopwatch.stop();
        samples.add(<String, Object?>{
          'mode': mode.name,
          'scanUnknownExtensions': scanUnknownExtensions,
          'elapsedMs': stopwatch.elapsedMilliseconds,
          'images': result.images.length,
          'containers': result.containers.length,
          'childFolders': result.childFolders.length,
          'scannedDirectories': result.scannedDirectoryCount,
          'headerProbes': result.headerProbeCount,
          'truncated': result.truncated,
        });
      }
    }
    final report = <String, Object?>{
      'generatedAt': DateTime.now().toIso8601String(),
      'root': root.absolute.path,
      'synthetic': synthetic,
      'samples': samples,
    };
    final output = const JsonEncoder.withIndent('  ').convert(report);
    final file = File('../../artifacts/folder-scan-probe.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(output);
    stdout.writeln(output);
  } finally {
    if (synthetic) {
      try {
        await root.delete(recursive: true);
      } catch (_) {
        // The OS temp cleaner will remove a locked fixture later.
      }
    }
  }
}

Future<Directory> _createSyntheticTree() async {
  final root = await Directory.systemTemp.createTemp('shen_view-scan-probe');
  final pngHeader = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var index = 0; index < 10; index++) {
    await File('${root.path}/root-$index.png').writeAsBytes(pngHeader);
  }
  await File('${root.path}/notes.txt').writeAsString('not an image');
  for (var directory = 0; directory < 30; directory++) {
    final child = await Directory('${root.path}/chapter-$directory').create();
    await File('${child.path}/001.png').writeAsBytes(pngHeader);
    for (var file = 0; file < 39; file++) {
      await File('${child.path}/note-$file.txt').writeAsString('text');
    }
  }
  return root;
}

class _NoFolderOrderProvider implements FolderOrderProvider {
  const _NoFolderOrderProvider();

  @override
  Future<List<String>?> orderFor(String folderPath) async => null;
}
