import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/third_party_licenses.dart';

import '../tool/generate_license_exclusions.dart';

void main() {
  test('FFmpeg notices list shipped libraries without build recipes', () async {
    final root = await Directory.systemTemp.createTemp('ffmpeg-notices-');
    addTearDown(() => root.delete(recursive: true));
    for (final entry in {
      'ffmpeg/COPYING.LGPLv2.1': 'FFmpeg terms',
      'ffmpeg/dependencies/zimg/COPYING': 'zimg terms',
      'ffmpeg/build-recipe/windows-packages.lock.json':
          'build tooling metadata',
    }.entries) {
      final file = File.fromUri(root.uri.resolve(entry.key));
      await file.parent.create(recursive: true);
      await file.writeAsString(entry.value);
    }
    final components = await collectLicenseComponents(
      appLicenseEntries(
        nativeLicenseDirectory: root,
        flutterEntries: const Stream.empty(),
      ),
    );
    expect(components.map((c) => c.name), ['FFmpeg', 'zimg']);
    expect(components.first.documents, hasLength(1));
  });
  test(
    'groups by component, deduplicates text and retains all distinct notices',
    () async {
      final components = await collectLicenseComponents(
        Stream.fromIterable([
          const LicenseEntryWithLineBreaks(['beta', 'alpha'], 'Shared license'),
          const LicenseEntryWithLineBreaks(['alpha'], 'Additional terms'),
          const LicenseEntryWithLineBreaks(['alpha'], 'Shared license'),
        ]),
      );
      expect(components.map((item) => item.name), ['alpha', 'beta']);
      expect(components.first.documents.length, 2);
      expect(
        components.first.documents
            .expand((doc) => doc.paragraphs)
            .map((paragraph) => paragraph.text),
        ['Shared license', 'Additional terms'],
      );
    },
  );

  test(
    'loads bundled native notices and filters only exclusive dev notices',
    () async {
      final root = await Directory.systemTemp.createTemp('shenview-licenses-');
      addTearDown(() => root.delete(recursive: true));
      for (final entry in {
        'README.txt': 'Directory index',
        '7zip/License.txt': '7-Zip license',
        '7zip/LGPL-2.1.txt': 'LGPL full text',
        'hdr/libavif-LICENSE': 'AVIF terms',
        'hdr/LibRaw-COPYRIGHT': 'Raw copyright',
        'imagemagick/NOTICE.txt': 'Delegate preamble\n[ libheif 1.2.3 ]\n\nHEIF terms\n[ libde265 1.0 ]\n\nHEVC terms',
        'resvg/LICENSE-MIT': 'SVG terms',
      }.entries) {
        final file = File.fromUri(root.uri.resolve(entry.key));
        await file.parent.create(recursive: true);
        await file.writeAsString(entry.value);
      }
      final components = await collectLicenseComponents(
        appLicenseEntries(
          nativeLicenseDirectory: root,
          flutterEntries: Stream.fromIterable([
            const LicenseEntryWithLineBreaks([
              'analyzer',
              'archive',
            ], 'Shared terms'),
            const LicenseEntryWithLineBreaks([
              'flutter_test',
            ], 'Test-only terms'),
            const LicenseEntryWithLineBreaks([
              'custom_lint',
            ], 'Lint-only terms'),
            const LicenseEntryWithLineBreaks(['flutter'], 'Flutter terms'),
          ]),
        ),
      );
      expect(components.map((item) => item.name), [
        '7-Zip',
        'archive',
        'flutter',
        'ImageMagick',
        'libavif',
        'libde265',
        'libheif',
        'LibRaw',
        'resvg',
      ]);
      expect(components.first.documents.length, 2);
      expect(components.first.documents.map((doc) => doc.title), [
        'LGPL-2.1.txt',
        'License.txt',
      ]);
    },
  );

  test(
    'missing optional native directory still returns Flutter notices',
    () async {
      final root = await Directory.systemTemp.createTemp('shenview-licenses-');
      addTearDown(() => root.delete(recursive: true));
      final entries = await appLicenseEntries(
        nativeLicenseDirectory: Directory.fromUri(root.uri.resolve('absent/')),
        flutterEntries: Stream.value(
          const LicenseEntryWithLineBreaks(['flutter'], 'Flutter terms'),
        ),
      ).toList();
      expect(entries.single.packages, ['flutter']);
    },
  );

  test('generated exclusions match the resolved dependency graph', () async {
    final generated = await generateLicenseExclusions(Directory.current);
    expect(
      await File('lib/src/application/license_exclusions.g.dart')
          .readAsString(),
      generated,
      reason:
          'Run dart run tool/generate_license_exclusions.dart after pub get.',
    );
  });

  test('generator preserves runtime notices with non-package names', () async {
    final root = await Directory.systemTemp.createTemp(
      'shenview-license-graph-',
    );
    addTearDown(() => root.delete(recursive: true));
    final graph = {
      'roots': ['app'],
      'packages': [
        {
          'name': 'app',
          'dependencies': ['shared'],
          'devDependencies': ['dev'],
        },
        {'name': 'shared', 'dependencies': <String>[]},
        {
          'name': 'dev',
          'dependencies': ['shared'],
        },
      ],
    };
    final config = {
      'packages': [
        for (final name in ['app', 'shared', 'dev'])
          {'name': name, 'rootUri': '../packages/$name'},
      ],
    };
    for (final entry in {
      '.dart_tool/package_graph.json': jsonEncode(graph),
      '.dart_tool/package_config.json': jsonEncode(config),
      'packages/shared/NOTICES':
          'engine-shared\n\nRuntime terms\n${'-' * 80}\nshared\n\nOther terms',
      'packages/dev/NOTICES':
          'engine-shared\n\nShared terms\n${'-' * 80}\ndev-embedded\n\nDev terms',
    }.entries) {
      final file = File.fromUri(root.uri.resolve(entry.key));
      await file.parent.create(recursive: true);
      await file.writeAsString(entry.value);
    }
    final generated = await generateLicenseExclusions(root);
    expect(generated, contains("'dev'"));
    expect(generated, contains("'dev-embedded'"));
    expect(generated, isNot(contains("'engine-shared'")));
    expect(generated, isNot(contains("'shared'")));
  });
}
