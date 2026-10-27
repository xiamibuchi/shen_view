import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/decoder_registry.dart';
import 'package:shen_view/src/domain/auto_play_settings.dart';
import 'package:shen_view/src/domain/viewer_mode.dart';
import 'package:shen_view/src/domain/view_scale_mode.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/settings_page.dart';
import 'package:shen_view/src/presentation/components/app_switch.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

import 'support/style_review_fonts.dart';

const _captureKey = ValueKey('settings.review');

Widget _host({
  ViewerSettings settings = const ViewerSettings(),
  ValueChanged<ViewerSettings>? onChanged,
  Locale locale = const Locale('zh'),
  bool dark = true,
  double textScale = 1,
}) => MaterialApp(
  locale: locale,
  debugShowCheckedModeBanner: false,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  theme: dark
      ? AppTheme.dark(platform: TargetPlatform.windows)
      : AppTheme.light(platform: TargetPlatform.windows),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: RepaintBoundary(
    key: _captureKey,
    child: SettingsPage(
      key: ValueKey('${locale.languageCode}-$dark-$textScale'),
      settings: settings,
      onChanged: onChanged ?? (_) {},
      decoderRegistry: DecoderRegistry(),
    ),
  ),
);

Finder _nav(String name) => find.byKey(ValueKey('settings.nav.$name'));
Finder _input(String name) => find.descendant(
  of: find.byKey(ValueKey('settings.autoPlay.$name')),
  matching: find.byType(TextField),
);

Future<void> _open(WidgetTester tester, String page) async {
  await tester.ensureVisible(_nav(page));
  await tester.tap(_nav(page));
  await tester.pumpAndSettle();
}

Future<void> _reset(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('settings.resetSection')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('恢复默认'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('appearance and browsing share directory visibility and pin', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var settings = const ViewerSettings(directoryPanelWidth: 480);
    await tester.pumpWidget(
      _host(settings: settings, onChanged: (value) => settings = value),
    );
    await tester.pumpAndSettle();
    AppSwitch control(String label) => tester
        .widgetList<AppSwitch>(find.byType(AppSwitch))
        .singleWhere((control) => control.label == label);
    await _open(tester, 'appearance');
    expect(control('显示目录导航').value, isTrue);
    expect(control('固定目录栏').value, isFalse);
    final showTitle = tester.getRect(find.text('显示目录导航'));
    final pinTitle = tester.getRect(find.text('固定目录栏'));
    expect((showTitle.left - pinTitle.left).abs(), lessThanOrEqualTo(1));
    for (final label in ['显示目录导航', '固定目录栏']) {
      final toggle = find.descendant(
        of: find.byWidget(control(label)),
        matching: find.byType(Switch),
      );
      expect(
        tester.getRect(toggle).left - tester.getRect(find.text(label)).right,
        greaterThanOrEqualTo(24),
      );
    }
    await tester.ensureVisible(find.text('显示目录导航'));
    await tester.tap(find.text('显示目录导航'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('固定目录栏'));
    await tester.tap(find.text('固定目录栏'));
    await tester.pumpAndSettle();
    expect(settings.showDirectoryPanel, isFalse);
    expect(settings.pinDirectoryPanel, isTrue);
    await _open(tester, 'browsing');
    expect(control('显示目录导航').value, isFalse);
    expect(control('固定目录栏').value, isTrue);
    await _reset(tester);
    expect(settings.showDirectoryPanel, isTrue);
    expect(settings.pinDirectoryPanel, isFalse);
    expect(settings.directoryPanelWidth, 480);
    await _open(tester, 'appearance');
    expect(control('显示目录导航').value, isTrue);
    expect(control('固定目录栏').value, isFalse);
    await tester.ensureVisible(find.text('固定目录栏'));
    await tester.tap(find.text('固定目录栏'));
    await tester.pumpAndSettle();
    await _reset(tester);
    await _open(tester, 'browsing');
    expect(control('显示目录导航').value, isTrue);
    expect(control('固定目录栏').value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reorganized resets preserve other pages and remembered widths', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var settings = const ViewerSettings(
      toolbarMode: ToolbarMode.floating,
      defaultViewerMode: ViewerMode.doublePage,
      defaultScaleModes: {ViewerMode.single: ViewScaleMode.originalSize},
      autoHdr: false,
      animationAutoPlay: false,
      showDirectoryPanel: false,
      pinDirectoryPanel: true,
      directoryPanelWidth: 500,
      autoPlay: AutoPlaySettings(
        loop: true,
        intervals: {ViewerMode.single: 9.2},
      ),
    );
    await tester.pumpWidget(
      _host(settings: settings, onChanged: (value) => settings = value),
    );
    await tester.pumpAndSettle();
    await _open(tester, 'appearance');
    expect(
      find.byKey(const ValueKey('settings.defaultViewerMode')),
      findsNothing,
    );
    await _reset(tester);
    expect(settings.toolbarMode, ToolbarMode.normal);
    expect(settings.showDirectoryPanel, isTrue);
    expect(settings.pinDirectoryPanel, isFalse);
    expect(settings.defaultViewerMode, ViewerMode.doublePage);
    await _open(tester, 'reading');
    final select = find.byKey(const ValueKey('settings.defaultScale.single'));
    final title = find.text('单页尺寸适配');
    expect(
      tester.getRect(select).left - tester.getRect(title).right,
      greaterThanOrEqualTo(24),
    );
    await _reset(tester);
    expect(settings.defaultViewerMode, ViewerMode.single);
    expect(settings.defaultScaleModes, isEmpty);
    expect(settings.autoPlay.loop, isTrue);
    await _open(tester, 'playback');
    await _reset(tester);
    expect(settings.autoPlay, const AutoPlaySettings());
    expect(settings.animationAutoPlay, isTrue);
    expect(settings.autoHdr, isFalse);
    await _open(tester, 'browsing');
    await tester.tap(find.text('显示目录导航'));
    await tester.pumpAndSettle();
    expect(settings.showDirectoryPanel, isFalse);
    await _reset(tester);
    expect(settings.showDirectoryPanel, isTrue);
    expect(settings.pinDirectoryPanel, isFalse);
    expect(settings.directoryPanelWidth, 500);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'playback validates per-mode parameters and saves existing configuration',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var settings = const ViewerSettings(autoHdr: false);
      await tester.pumpWidget(
        _host(settings: settings, onChanged: (value) => settings = value),
      );
      await tester.pumpAndSettle();
      await _open(tester, 'playback');
      final single = _input('interval.single');
      await tester.enterText(single, '0.4');
      await tester.pumpAndSettle();
      expect(find.text('请输入 0.5 到 3600 之间的数字'), findsOneWidget);
      expect(settings.autoPlay.intervalFor(ViewerMode.single), 5);
      await tester.enterText(single, '12.3');
      await tester.pumpAndSettle();
      expect(settings.autoPlay.intervalFor(ViewerMode.single), 12.3);
      expect(settings.autoPlay.intervalFor(ViewerMode.doublePage), 5);
      final speed = _input('speed.comic');
      await tester.ensureVisible(speed);
      await tester.enterText(speed, '1001');
      await tester.pumpAndSettle();
      expect(settings.autoPlay.speedFor(ViewerMode.comic), 60);
      await tester.enterText(speed, '88.5');
      await tester.pumpAndSettle();
      expect(settings.autoPlay.speedFor(ViewerMode.comic), 88.5);
      expect(settings.autoPlay.speedFor(ViewerMode.longImage), 60);
      final dwell = _input('interval.longImage');
      await tester.ensureVisible(dwell);
      await tester.enterText(dwell, '7.1');
      await tester.pumpAndSettle();
      expect(settings.autoPlay.intervalFor(ViewerMode.longImage), 7.1);
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp(
          'shenview-settings-review-',
        );
        try {
          final path = '${dir.path}/config.json';
          await File(path).writeAsString(
            jsonEncode({
              'readingHistory': {
                'sample': {'entryPath': 'page.png'},
              },
            }),
          );
          final store = AppConfigStore(filePath: path);
          await settings.save(store: store);
          final loaded = await ViewerSettings.load(store: store);
          expect(loaded.autoPlay, settings.autoPlay);
          expect(loaded.autoHdr, isFalse);
          expect((await store.read())['readingHistory'], {
            'sample': {'entryPath': 'page.png'},
          });
        } finally {
          await dir.delete(recursive: true);
        }
      });
      final invalidUnchanged = _input('speed.longImage');
      await tester.ensureVisible(invalidUnchanged);
      await tester.enterText(invalidUnchanged, '0');
      await tester.pumpAndSettle();
      await _reset(tester);
      expect(tester.widget<TextField>(single).controller!.text, '5');
      expect(tester.widget<TextField>(invalidUnchanged).controller!.text, '60');
      expect(settings.autoHdr, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'format details expand on demand and through bilingual search without saving',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var changes = 0;
      await tester.pumpWidget(_host(onChanged: (_) => changes++));
      await tester.pumpAndSettle();
      await _open(tester, 'image');
      expect(find.text('JPEG'), findsNothing);
      final toggle = find.byKey(const ValueKey('settings.toggleFormats'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('JPEG'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings.resetSection')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('JPEG'), findsNothing);
      final search = find.descendant(
        of: find.byKey(const ValueKey('settings.search')),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, 'JPEG');
      await tester.pumpAndSettle();
      expect(find.text('JPEG').last.hitTestable(), findsOneWidget);
      await tester.enterText(search, '动图 倍速');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings.animationSpeed')).hitTestable(),
        findsOneWidget,
      );
      await tester.enterText(search, 'Single page interval');
      await tester.pumpAndSettle();
      expect(_input('interval.single').hitTestable(), findsOneWidget);
      await tester.enterText(search, '长图 尺寸适配');
      await tester.pumpAndSettle();
      expect(
        find
            .byKey(const ValueKey('settings.defaultScale.longImage'))
            .hitTestable(),
        findsOneWidget,
      );
      await tester.enterText(search, '颜色拾取');
      await tester.pumpAndSettle();
      expect(find.text('颜色拾取').last.hitTestable(), findsOneWidget);
      expect(changes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reorganized pages render in English and Chinese with enlarged text',
    (tester) async {
      final captureDir =
          Platform.environment['SETTINGS_REORGANIZATION_CAPTURE_DIR'];
      if (captureDir != null) await loadStyleReviewFonts(tester);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final language in ['zh', 'en']) {
        for (final dark in [false, true]) {
          for (final width in [440.0, 1280.0]) {
            tester.view.physicalSize = Size(width, width == 440 ? 560 : 800);
            await tester.pumpWidget(
              _host(
                locale: Locale(language),
                dark: dark,
                textScale: width == 440 ? 1.5 : 1.25,
              ),
            );
            await tester.pumpAndSettle();
            for (final section in [
              if (captureDir != null) ...[
                'general',
                'interaction',
                'archives',
                'about',
              ],
              'appearance',
              'browsing',
              'reading',
              'playback',
              'image',
              'shortcuts',
            ]) {
              await _open(tester, section);
              expect(
                tester.takeException(),
                isNull,
                reason: '$language $width $section',
              );
              if (section == 'reading') {
                final heading = find
                    .text(language == 'zh' ? '查看与阅读' : 'Viewing & reading')
                    .last;
                final group = find.text(
                  language == 'zh' ? '默认查看设置' : 'Viewing defaults',
                );
                expect(
                  (tester.getTopLeft(heading).dx - tester.getTopLeft(group).dx)
                      .abs(),
                  lessThanOrEqualTo(2.1),
                );
              }
              if (captureDir != null) {
                final testedSize = tester.view.physicalSize;
                if (section == 'appearance' || section == 'browsing') {
                  // Review both rows together while keeping the smaller-height
                  // overflow checks above independent of the captured viewport.
                  tester.view.physicalSize = Size(width, 800);
                  await tester.pumpAndSettle();
                  await tester.ensureVisible(
                    find.text(
                      language == 'zh' ? '目录导航' : 'Directory navigation',
                    ),
                  );
                  await tester.pumpAndSettle();
                }
                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  find.byKey(_captureKey),
                );
                await tester.runAsync(() async {
                  final image = await boundary.toImage();
                  try {
                    final bytes = await image.toByteData(
                      format: ui.ImageByteFormat.png,
                    );
                    final file = File(
                      '$captureDir/$language-$dark-${width.toInt()}-$section.png',
                    );
                    await file.parent.create(recursive: true);
                    await file.writeAsBytes(bytes!.buffer.asUint8List());
                  } finally {
                    image.dispose();
                  }
                });
                tester.view.physicalSize = testedSize;
                await tester.pumpAndSettle();
              }
            }
          }
        }
      }
    },
  );
}
