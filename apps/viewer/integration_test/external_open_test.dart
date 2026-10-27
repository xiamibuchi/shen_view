import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as paths;
import 'package:shen_view/src/application/external_open_service.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real system application enumeration and launch failure recover',
    (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final root = await Directory.systemTemp.createTemp(
        'shenview-native-open-',
      );
      final file = File('${root.path}/原图 空格.png');
      await file.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
      addTearDown(() => root.delete(recursive: true));
      final entry = ImageEntry(
        file: file,
        format: ImageFormat.png,
        width: 1,
        height: 1,
        byteLength: await file.length(),
        modifiedAt: DateTime(2026),
      );
      const service = ExternalOpenService();
      final apps = await service
          .applications(entry)
          .timeout(const Duration(seconds: 15));
      expect(apps.length, lessThanOrEqualTo(8));
      expect(apps.map((app) => app.id).toSet().length, apps.length);
      for (final app in apps) {
        expect(app.id, isNotEmpty);
        expect(app.name, isNotEmpty);
        expect(app.name.toLowerCase(), isNot('shenview'));
        expect(app.name, isNot('神羊看图'));
        if (app.icon != null) {
          final codec = await ui.instantiateImageCodec(app.icon!);
          final frame = await codec.getNextFrame();
          expect(frame.image.width, greaterThan(0));
          frame.image.dispose();
          codec.dispose();
        }
      }
      await expectLater(
        service.open(
          entry,
          application: const ExternalApplication(
            id: 'missing-application-for-shenview-test',
            name: 'Missing',
          ),
          saveCopy: (_) async => null,
        ),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        ExternalOpenService.channel.invokeMethod<bool>('choose', {
          'path': '${root.path}/missing.png',
        }),
        throwsA(isA<PlatformException>()),
      );
      final recovered = await service
          .applications(entry)
          .timeout(const Duration(seconds: 15));
      expect(recovered.map((app) => app.id), apps.map((app) => app.id));
      binding.reportData = {
        'platform': Platform.operatingSystem,
        'applications': [for (final app in apps) app.name],
        'icons': apps.where((app) => app.icon != null).length,
        'recoveredAfterLaunchFailure': true,
      };
      // Keep the native result next to the widget review captures.
      const output = String.fromEnvironment('EXTERNAL_OPEN_REPORT');
      if (output.isNotEmpty) {
        await File(output).writeAsString(
          const JsonEncoder.withIndent('  ').convert(binding.reportData),
        );
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'selected Windows application receives the exact file without changing its default',
    (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final root = await Directory.systemTemp.createTemp('shenview-open-test-');
      final suffix =
          'shenview-open-test-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
      addTearDown(() async {
        await _associationFixture('cleanup', root, suffix);
        await root.delete(recursive: true);
      });
      await _associationFixture('setup', root, suffix);
      final file = File(paths.join(root.path, '原图 空格 & (source).$suffix'));
      await file.writeAsString('external application launch fixture');
      final entry = ImageEntry(
        file: file,
        format: ImageFormat.png,
        width: 1,
        height: 1,
        byteLength: await file.length(),
        modifiedAt: DateTime(2026),
      );
      const service = ExternalOpenService();
      final apps = await service.applications(entry);
      final selected = apps.singleWhere(
        (app) => paths.basename(app.id).toLowerCase() == 'powershell.exe',
      );
      expect(
        await service.open(
          entry,
          application: selected,
          saveCopy: (_) async => null,
        ),
        isTrue,
      );
      final received = File(paths.join(root.path, 'received.txt'));
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      String? actual;
      while (DateTime.now().isBefore(deadline)) {
        if (await received.exists()) actual = await received.readAsString();
        if (actual == file.absolute.path) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(actual, file.absolute.path);
      await _associationFixture('verify', root, suffix);
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Future<void> _associationFixture(
  String mode,
  Directory root,
  String suffix,
) async {
  final shell = paths.join(
    Platform.environment['WINDIR']!,
    'System32',
    'WindowsPowerShell',
    'v1.0',
    'powershell.exe',
  );
  final script = File('integration_test/support/external_open_registration.ps1')
      .absolute
      .path;
  final result = await Process.run(shell, [
    '-NoLogo',
    '-NoProfile',
    '-NonInteractive',
    '-WindowStyle',
    'Hidden',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    script,
    '-Mode',
    mode,
    '-Root',
    root.path,
    '-Suffix',
    suffix,
  ]);
  expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
}
