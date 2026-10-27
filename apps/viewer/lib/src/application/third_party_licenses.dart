import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'license_exclusions.g.dart';

class LicenseDocument {
  const LicenseDocument({required this.paragraphs, this.title});

  final List<LicenseParagraph> paragraphs;
  final String? title;
}

class LicenseComponent {
  const LicenseComponent({required this.name, required this.documents});

  final String name;
  final List<LicenseDocument> documents;
}

/// One row per component. Multiple distinct notices remain intact in its detail.
Future<List<LicenseComponent>> collectLicenseComponents(
  Stream<LicenseEntry> source,
) async {
  final components = <String, List<LicenseDocument>>{};
  final displayNames = <String, String>{};
  final seen = <String, Set<String>>{};
  await for (final entry in source) {
    final paragraphs = entry.paragraphs.toList(growable: false);
    final identity = paragraphs
        .map(
          (paragraph) => [
            paragraph.indent,
            paragraph.text.length,
            paragraph.text,
          ].join(':'),
        )
        .join('\n');
    final names = entry.packages.toSet();
    if (names.isEmpty) names.add('');
    for (final name in names) {
      final key = name.toLowerCase();
      displayNames.putIfAbsent(key, () => name);
      if (!(seen[key] ??= <String>{}).add(identity)) continue;
      (components[key] ??= []).add(
        LicenseDocument(
          paragraphs: paragraphs,
          title: entry is _NativeLicenseEntry ? entry.title : null,
        ),
      );
    }
  }
  final result = [
    for (final entry in components.entries)
      LicenseComponent(name: displayNames[entry.key]!, documents: entry.value),
  ];
  result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return result;
}

/// Uses shipped notices, without requiring network access or a source checkout.
Stream<LicenseEntry> appLicenseEntries({
  Stream<LicenseEntry>? flutterEntries,
  Directory? nativeLicenseDirectory,
}) async* {
  await for (final entry in flutterEntries ?? LicenseRegistry.licenses) {
    final names = entry.packages
        .where((name) => !developmentOnlyLicenseNames.contains(name))
        .toList(growable: false);
    if (names.isEmpty && entry.packages.isNotEmpty) continue;
    yield _FilteredLicenseEntry(names, entry);
  }
  final directory =
      nativeLicenseDirectory ??
      Directory(
        p.join(p.dirname(Platform.resolvedExecutable), 'codecs', 'licenses'),
      );
  if (!directory.existsSync()) return;
  final files = await directory
      .list(recursive: true, followLinks: false)
      .where((entity) => entity is File)
      .cast<File>()
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final relative = p.relative(file.path, from: directory.path);
    final parts = p.split(relative);
    // The top-level README is a directory index, not a component notice.
    if (parts.length < 2) continue;
    final folder = parts.first;
    if (folder == 'ffmpeg' && parts.contains('build-recipe')) continue;
    final filename = p.basename(file.path);
    final name = switch (folder.toLowerCase()) {
      '7zip' => '7-Zip',
      'imagemagick' => 'ImageMagick',
      'resvg' => 'resvg',
      'hdr' => _hdrComponent(filename),
      'ffmpeg' =>
        parts.length > 3 && parts[1] == 'dependencies'
            ? switch (parts[2]) {
                'vulkan-headers' => 'vulkan-loader',
                'spirv-headers' => 'shaderc',
                _ => parts[2],
              }
            : 'FFmpeg',
      _ => folder,
    };
    final text = await file.readAsString();
    if (name == 'ImageMagick' && filename == 'NOTICE.txt') {
      yield* Stream.fromIterable(_imageMagickNotices(text));
    } else {
      yield _NativeLicenseEntry(name, filename, text);
    }
  }
}

/// ImageMagick ships its delegate licenses in one file with section headings.
/// Keep every section, including any preamble, while making delegates searchable.
Iterable<LicenseEntry> _imageMagickNotices(String text) sync* {
  final headings = RegExp(
    r'^\[ ([^\r\n]+) \]\r?$',
    multiLine: true,
  ).allMatches(text).toList();
  if (headings.isEmpty) {
    yield _NativeLicenseEntry('ImageMagick', 'NOTICE.txt', text);
    return;
  }
  if (headings.first.start > 0) {
    yield _NativeLicenseEntry(
      'ImageMagick',
      'NOTICE.txt',
      text.substring(0, headings.first.start),
    );
  }
  for (var index = 0; index < headings.length; index++) {
    final heading = headings[index];
    final label = heading.group(1)!;
    final name = label.split(RegExp(r'\s+')).first;
    final end = index + 1 < headings.length
        ? headings[index + 1].start
        : text.length;
    yield _NativeLicenseEntry(
      name,
      'NOTICE.txt · $label',
      text.substring(heading.start, end),
    );
  }
}

String _hdrComponent(String filename) {
  for (final name in [
    'libjpeg-turbo',
    'libultrahdr',
    'libavif',
    'lcms2',
    'libheif',
    'libaom',
    'LibRaw',
  ]) {
    if (filename.toLowerCase().startsWith(name.toLowerCase())) return name;
  }
  if (filename.startsWith('Adobe-')) return 'Adobe Gain Map';
  return 'HDR codecs';
}

class _FilteredLicenseEntry extends LicenseEntry {
  const _FilteredLicenseEntry(this.packages, this.source);

  @override
  final List<String> packages;
  final LicenseEntry source;

  @override
  Iterable<LicenseParagraph> get paragraphs => source.paragraphs;
}

class _NativeLicenseEntry extends LicenseEntryWithLineBreaks {
  _NativeLicenseEntry(String name, this.title, String text)
    : super([name], text);

  final String title;
}
