import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as paths;
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/file_association_service.dart';
import 'package:shen_view/src/application/format_detector.dart';
import 'package:shen_view/src/application/windows_distribution.dart';
import 'package:shen_view/src/application/decoder_registry.dart';
import 'package:shen_view/src/domain/image_format.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/settings_page.dart';
import 'package:shen_view/src/presentation/components/app_switch.dart';
import 'package:shen_view/src/presentation/components/app_button.dart';
import 'package:shen_view/src/presentation/file_associations_dialog.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

import 'support/style_review_fonts.dart';

void main() {
  StyleReviewBinding();

  test('association formats follow decoder formats, excluding video', () {
    expect(FileAssociationFormats.archives, FormatDetector.archiveExtensions);
    expect(
      FileAssociationFormats.images.intersection(
        FileAssociationFormats.archives,
      ),
      isEmpty,
    );
    expect(FileAssociationFormats.all, {
      for (final entry in FormatDetector.extensionMap.entries)
        if (entry.value != ImageFormat.hdrVideo) entry.key,
    });
    expect(FileAssociationFormats.all, isNot(contains('exe')));
  });

  test(
    'Windows data directories separate installed, packaged and portable modes',
    () {
      final root = paths.join(
        Directory.systemTemp.path,
        'distribution-fixture',
      );
      final appDirectory = paths.join(root, 'app');
      final localAppData = paths.join(root, 'local-data');
      final normalizedRoot = root.replaceAll('\\', '/');
      String resolve(String mode) => WindowsDistribution.dataDirectory(
        executable: paths.join(appDirectory, 'ShenView.exe'),
        mode: mode,
        localAppData: localAppData,
      ).replaceAll('\\', '/');
      expect(resolve('installed'), '$normalizedRoot/local-data/ShenView');
      expect(resolve('installed-system'), resolve('installed'));
      expect(resolve('msix'), '$normalizedRoot/local-data/ShenView/MSIX');
      expect(resolve('portable'), '$normalizedRoot/app/user-data');
      expect(resolve('scoop'), resolve('portable'));
      expect(resolve(''), '$normalizedRoot/app');
    },
  );

  final binding = TestDefaultBinaryMessengerBinding.instance;
  const service = FileAssociationService();
  final calls = <MethodCall>[];
  var mode = 'portable';
  var registered = <String>{'jpg', 'png'};
  var failRead = false;
  var failUpdate = false;
  var failOpen = false;

  setUp(() {
    calls.clear();
    mode = 'portable';
    registered = {'jpg', 'png'};
    failRead = false;
    failUpdate = false;
    failOpen = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      FileAssociationService.channel,
      (call) async {
        calls.add(call);
        if (call.method == 'read') {
          if (failRead) throw PlatformException(code: 'denied');
          return {
            'mode': mode,
            'extensions': {
              for (final ext in FileAssociationFormats.all)
                ext: {
                  'registered': mode == 'msix' || registered.contains(ext),
                  'isDefault': ext == 'jpg',
                },
            },
          };
        }
        if (call.method == 'update') {
          if (failUpdate) throw PlatformException(code: 'denied');
          registered = Set<String>.from(call.arguments as List);
        }
        if (call.method == 'openSettings' && failOpen) {
          throw PlatformException(code: 'denied');
        }
        return null;
      },
    );
  });
  tearDown(
    () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
      FileAssociationService.channel,
      null,
    ),
  );

  test('reads actual defaults separately from registered candidates', () async {
    final state = await service.read();
    expect(state.registered, {'jpg', 'png'});
    expect(state.defaults, {'jpg'});
    expect(state.isPackaged, isFalse);
    await expectLater(service.update({'exe'}), throwsArgumentError);
    expect(calls.where((call) => call.method == 'update'), isEmpty);
  });

  Widget host({bool dark = false, double scale = 1, Widget? home}) =>
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: dark
            ? AppTheme.dark(platform: TargetPlatform.windows)
            : AppTheme.light(platform: TargetPlatform.windows),
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home:
            home ??
            const Scaffold(
              body: RepaintBoundary(
                key: ValueKey('capture'),
                child: FileAssociationsDialog(),
              ),
            ),
      );

  testWidgets(
    'settings search opens the association manager without changing preferences',
    (tester) async {
      var changes = 0;
      await tester.pumpWidget(
        host(
          home: SettingsPage(
            settings: const ViewerSettings(),
            onChanged: (_) => changes++,
            decoderRegistry: DecoderRegistry(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.descendant(
        of: find.byKey(const ValueKey('settings.search')),
        matching: find.byType(EditableText),
      );
      await tester.enterText(search, '关联');
      await tester.pumpAndSettle();
      final manager = find.byKey(const ValueKey('settings.fileAssociations'));
      await tester.ensureVisible(manager);
      await tester.tap(manager);
      await tester.pumpAndSettle();
      expect(find.byType(FileAssociationsDialog), findsOneWidget);
      expect(calls.where((call) => call.method == 'read'), isNotEmpty);
      expect(changes, 0);
    },
  );

  testWidgets(
    'archive registration is explicit; apply persists candidate selection',
    (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(calls.where((call) => call.method == 'update'), isEmpty);
      final zip = find.byKey(const ValueKey('association.zip'));
      await tester.scrollUntilVisible(
        zip,
        220,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(tester.widget<AppSwitch>(zip).value, isFalse);
      tester.widget<AppSwitch>(zip).onChanged!(true);
      await tester.pump();
      final apply = find.byKey(const ValueKey('associations.apply'));
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(registered, {'jpg', 'png', 'zip'});
      expect(calls.where((call) => call.method == 'openSettings'), isEmpty);
      expect(find.text('已更新打开方式候选。默认应用请在 Windows 中选择。'), findsOneWidget);
    },
  );

  testWidgets('MSIX offers Windows defaults without registry updates', (
    tester,
  ) async {
    mode = 'msix';
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('associations.apply')), findsNothing);
    expect(
      tester
          .widget<AppSwitch>(find.byKey(const ValueKey('association.apng')))
          .enabled,
      isFalse,
    );
    final open = find.text('在 Windows 中选择默认应用');
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(calls.last.method, 'openSettings');
    expect(calls.where((call) => call.method == 'update'), isEmpty);
  });

  testWidgets('machine installation explains administrator approval', (
    tester,
  ) async {
    mode = 'installed-system';
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.textContaining('修改安装版的打开方式候选需要管理员权限'), findsOneWidget);
    expect(find.byKey(const ValueKey('associations.apply')), findsOneWidget);
  });

  testWidgets('read, save and system settings failures are actionable', (
    tester,
  ) async {
    failRead = true;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('读取文件关联失败，请重试。'), findsOneWidget);
    failRead = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    failUpdate = true;
    final apply = find.byKey(const ValueKey('associations.apply'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(find.text('更新文件关联失败，请重试。'), findsOneWidget);
    failOpen = true;
    final open = find.text('在 Windows 中选择默认应用');
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.text('无法打开系统设置，请前往 Windows 设置 → 应用 → 默认应用。'), findsOneWidget);
  });

  for (final size in [
    const Size(440, 800),
    const Size(600, 460),
    const Size(1000, 800),
  ]) {
    final width = size.width;
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.25, 1.5]) {
        testWidgets('association layout size=$size dark=$dark scale=$scale', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          if (Platform.environment['ASSOCIATION_REVIEW'] == '1') {
            await loadStyleReviewFonts(tester);
          }
          await tester.pumpWidget(host(dark: dark, scale: scale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final switches = tester
              .widgetList<AppSwitch>(find.byType(AppSwitch))
              .toList();
          expect(switches, isNotEmpty);
          final apply = find.byKey(const ValueKey('associations.apply'));
          final close = find.ancestor(
            of: find.text('关闭'),
            matching: find.byType(AppButton),
          );
          await tester.ensureVisible(apply);
          await tester.pumpAndSettle();
          final applyRect = tester.getRect(apply);
          final closeRect = tester.getRect(close);
          expect(applyRect.left, greaterThanOrEqualTo(0));
          expect(applyRect.right, lessThanOrEqualTo(width));
          expect(applyRect.overlaps(closeRect), isFalse);
          expect(applyRect.top, greaterThanOrEqualTo(0));
          expect(applyRect.bottom, lessThanOrEqualTo(size.height));
          expect(applyRect.left - closeRect.right, greaterThanOrEqualTo(8));
          if (Platform.environment['ASSOCIATION_REVIEW'] == '1') {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('capture')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              try {
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File(
                  'build/association-review/$width-$dark-$scale.png',
                );
                await file.parent.create(recursive: true);
                await file.writeAsBytes(bytes!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
          }
        });
      }
    }
  }
}
