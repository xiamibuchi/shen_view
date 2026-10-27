import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

final _dependencyLock = jsonDecode(
  File.fromUri(
    Platform.script.resolve('../../../third_party/dependencies.lock.json'),
  ).readAsStringSync(),
) as Map<String, dynamic>;
final _artifacts = _dependencyLock['artifacts'] as Map<String, dynamic>;
final _resvg = _artifacts['resvg'] as Map<String, dynamic>;
final version = _resvg['version'] as String;
final assets = Map<String, String>.from(_resvg['sha256'] as Map);

Future<void> main(List<String> args) async {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i += 2) {
    options[args[i]] = args[i + 1];
  }
  final root = Directory(
    p.absolute(
      options['--output'] ??
          File.fromUri(Platform.script.resolve('../../../build/svg-codecs'))
              .path,
    ),
  );
  if (Platform.isWindows) await _ensureNuget(root);
  final platform = Platform.isWindows ? 'win' : 'macos';
  final architectures =
      (options['--arch'] ??
              (Platform.version.contains('arm64') ? 'arm64' : 'x64'))
          .split(',');
  final suffix = Platform.isWindows ? '.exe' : '';
  final target = File(p.join(root.path, 'bin', 'resvg$suffix'));
  final marker = File(p.join(root.path, 'version'));
  final identity = '$version:$platform:${architectures.join(',')}';
  if (await target.exists() &&
      await marker.exists() &&
      await marker.readAsString() == identity) {
    return;
  }
  await target.parent.create(recursive: true);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final binaries = <String>[];
    for (final arch in architectures) {
      final normalized = arch == 'arm64'
          ? 'aarch64'
          : arch == 'x64'
          ? 'x86_64'
          : arch;
      final key = '$platform-$normalized';
      final expected =
          assets[key] ??
          (throw ArgumentError('Unsupported SVG codec platform: $key'));
      final archiveFile = File(p.join(root.path, 'resvg-$key.zip'));
      if (!await archiveFile.exists() ||
          sha256.convert(await archiveFile.readAsBytes()).toString() !=
              expected) {
        await _download(
          client,
          (_resvg['urlTemplate'] as String)
              .replaceAll('{version}', version)
              .replaceAll('{platform}', key),
          archiveFile,
        );
      }
      final bytes = await archiveFile.readAsBytes();
      if (sha256.convert(bytes).toString() != expected) {
        throw StateError('resvg archive SHA256 verification failed');
      }
      final archive = ZipDecoder().decodeBytes(bytes);
      final entry = archive.files.singleWhere(
        (file) => p.posix.basename(file.name) == 'resvg$suffix',
      );
      final binary = File(p.join(root.path, 'resvg-$key$suffix'));
      await binary.writeAsBytes(entry.content);
      binaries.add(binary.path);
    }
    if (binaries.length == 1) {
      await File(binaries.single).copy(target.path);
    } else {
      final result = await Process.run('lipo', [
        '-create',
        ...binaries,
        '-output',
        target.path,
      ]);
      if (result.exitCode != 0) {
        throw StateError('resvg universal binary failed: ${result.stderr}');
      }
    }
    final licenses = Directory(p.join(root.path, 'licenses', 'resvg'));
    await licenses.create(recursive: true);
    for (final name in ['LICENSE-MIT', 'LICENSE-APACHE']) {
      await _download(
        client,
        'https://raw.githubusercontent.com/linebender/resvg/v$version/$name',
        File(p.join(licenses.path, name)),
      );
    }
    if (!Platform.isWindows) {
      final result = await Process.run('chmod', ['+x', target.path]);
      if (result.exitCode != 0) {
        throw StateError('Could not make resvg executable');
      }
    }
    await marker.writeAsString(identity);
    stdout.writeln('Installed pinned resvg $version: ${target.path}');
  } finally {
    client.close(force: true);
  }
}

Future<void> _download(HttpClient client, String url, File target) async {
  final request = await client.getUrl(Uri.parse(url));
  final response = await request.close();
  if (response.statusCode != 200) {
    throw HttpException(
      'Download failed: ${response.statusCode}',
      uri: Uri.parse(url),
    );
  }
  final sink = target.openWrite();
  try {
    await sink.addStream(response);
  } finally {
    await sink.close();
  }
}

Future<void> _ensureNuget(Directory root) async {
  final nuget = _artifacts['nuget'] as Map<String, dynamic>;
  final expected = nuget['sha256'] as String;
  final target = File(p.join(root.path, 'tools', 'nuget.exe'));
  if (await target.exists() &&
      sha256.convert(await target.readAsBytes()).toString() == expected) {
    return;
  }
  await target.parent.create(recursive: true);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    await _download(client, nuget['url'] as String, target);
  } finally {
    client.close(force: true);
  }
  if (sha256.convert(await target.readAsBytes()).toString() != expected) {
    throw StateError('NuGet SHA256 verification failed');
  }
}
