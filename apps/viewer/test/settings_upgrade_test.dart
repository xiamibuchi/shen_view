import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/decoder_registry.dart';
import 'package:shen_view/src/domain/image_format.dart';
import 'package:shen_view/src/domain/viewer_mode.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/components/app_button.dart';
import 'package:shen_view/src/presentation/components/app_icon_button.dart';
import 'package:shen_view/src/presentation/components/app_select.dart';
import 'package:shen_view/src/presentation/components/app_switch.dart';
import 'package:shen_view/src/presentation/settings_page.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

import 'support/style_review_fonts.dart';

const _captureKey = ValueKey('settings.upgrade.capture');

Widget _host({
  ViewerSettings settings = const ViewerSettings(),
  ValueChanged<ViewerSettings>? onChanged,
  ValueChanged<ViewerSettings>? onResetAll,
  DecoderRegistry? registry,
  String language = 'zh',
  bool dark = true,
  double textScale = 1,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: Locale(language),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: dark
      ? AppTheme.dark(platform: TargetPlatform.windows)
      : AppTheme.light(platform: TargetPlatform.windows),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: RepaintBoundary(key: _captureKey, child: child!),
  ),
  home: SettingsPage(
    key: UniqueKey(),
    settings: settings,
    onChanged: onChanged ?? (_) {},
    onResetAll: onResetAll,
    decoderRegistry: registry ?? DecoderRegistry(),
  ),
);

Future<void> _open(WidgetTester tester, String section) async {
  final nav = find.byKey(ValueKey('settings.nav.$section'));
  if (nav.evaluate().isEmpty) {
    final navigation = find.descendant(
      of: find.byType(ListView).first,
      matching: find.byType(Scrollable),
    );
    tester.state<ScrollableState>(navigation).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(nav, 100, scrollable: navigation);
  }
  await tester.ensureVisible(nav);
  await tester.tap(nav);
  await tester.pumpAndSettle();
}

ScrollController _scroll(WidgetTester tester, String section) => tester
    .widget<SingleChildScrollView>(
      find.byKey(PageStorageKey('settings.content.$section')),
    )
    .controller!;

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['SETTINGS_UPGRADE_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('each settings category keeps its own scroll position', (
    tester,
  ) async {
    _size(tester, const Size(1280, 600));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const PageStorageKey('settings.content.general')),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    final general = _scroll(tester, 'general').offset;
    // General is shorter without the global-reset card. Verify a nonzero
    // position is remembered rather than assuming a particular content height.
    expect(general, greaterThan(0));
    await _open(tester, 'playback');
    expect(_scroll(tester, 'playback').offset, 0);
    await tester.drag(
      find.byKey(const PageStorageKey('settings.content.playback')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    final playback = _scroll(tester, 'playback').offset;
    expect(playback, greaterThan(200));
    await _open(tester, 'general');
    expect(_scroll(tester, 'general').offset, closeTo(general, 1));
    await _open(tester, 'image');
    expect(_scroll(tester, 'image').offset, 0);
    await _open(tester, 'playback');
    expect(_scroll(tester, 'playback').offset, closeTo(playback, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset all requires confirmation and includes every category', (
    tester,
  ) async {
    _size(tester, const Size(1280, 800));
    var settings = const ViewerSettings(
      localeCode: 'en',
      toolbarMode: ToolbarMode.floating,
      defaultViewerMode: ViewerMode.doublePage,
      autoHdr: false,
      showDirectoryPanel: false,
      pinDirectoryPanel: true,
      directoryPanelWidth: 500,
      archiveDiskBudgetMiB: 4096,
      animationAutoPlay: false,
    );
    final original = settings;
    var changes = 0;
    await tester.pumpWidget(
      _host(
        settings: settings,
        onChanged: (value) {
          settings = value;
          changes++;
        },
      ),
    );
    await tester.pumpAndSettle();
    final action = find.byKey(const ValueKey('settings.resetAll'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.textContaining('不会清除阅读进度'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(settings, original);
    expect(changes, 0);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复所有设置').last);
    await tester.pumpAndSettle();
    expect(settings, const ViewerSettings());
    expect(changes, 1);
    expect(tester.widget<AppButton>(action).onPressed, isNull);
    await _open(tester, 'image');
    expect(
      tester
          .widget<AppSwitch>(
            find.byWidgetPredicate(
              (w) => w is AppSwitch && w.label == '自动 HDR 显示',
            ),
          )
          .value,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in [1280.0, 440.0]) {
    for (final language in ['zh', 'en']) {
      testWidgets('global reset stays reachable at $width in $language', (
        tester,
      ) async {
        _size(tester, Size(width, 800));
        if (Platform.environment['SETTINGS_UPGRADE_CAPTURE_DIR'] != null) {
          await loadStyleReviewFonts(tester);
        }
        var settings = const ViewerSettings(
          defaultViewerMode: ViewerMode.doublePage,
          autoHdr: false,
          directoryPanelWidth: 500,
          archiveDiskBudgetMiB: 4096,
          animationAutoPlay: false,
        );
        final original = settings;
        var resets = 0;
        var changes = 0;
        final zh = language == 'zh';
        await tester.pumpWidget(
          _host(
            settings: settings,
            language: language,
            dark: zh,
            textScale: width == 440 ? 1.5 : 1,
            onChanged: (_) => changes++,
            onResetAll: (value) {
              settings = value;
              resets++;
            },
          ),
        );
        await tester.pumpAndSettle();
        final reset = find.byKey(const ValueKey('settings.resetAll'));
        final position = tester.getRect(reset);
        for (final section in [
          'general',
          'appearance',
          'browsing',
          'reading',
          'interaction',
          'playback',
          'archives',
          'image',
          'shortcuts',
          'about',
        ]) {
          await _open(tester, section);
          expect(reset.hitTestable(), findsOneWidget, reason: section);
          expect(tester.getRect(reset), position, reason: section);
        }
        await _capture(tester, '$language-$width-global-reset-about');
        final search = find.descendant(
          of: find.byKey(const ValueKey('settings.search')),
          matching: find.byType(TextField),
        );
        await tester.enterText(search, 'unmatched-settings-query');
        await tester.pumpAndSettle();
        expect(
          find.text(zh ? '没有匹配的设置' : 'No matching settings'),
          findsOneWidget,
        );
        expect(reset.hitTestable(), findsOneWidget);
        await _capture(tester, '$language-$width-global-reset-empty');
        await tester.tap(reset);
        await tester.pumpAndSettle();
        expect(
          find.text(zh ? '恢复所有设置？' : 'Reset all settings?'),
          findsOneWidget,
        );
        await _capture(tester, '$language-$width-global-reset-confirm');
        await tester.tap(find.text(zh ? '取消' : 'Cancel'));
        await tester.pumpAndSettle();
        expect(settings, original);
        expect(resets, 0);
        await tester.tap(reset);
        await tester.pumpAndSettle();
        await tester.tap(find.text(zh ? '恢复所有设置' : 'Reset all').last);
        await tester.pumpAndSettle();
        expect(settings, const ViewerSettings());
        expect(resets, 1);
        expect(changes, 0);
        final button = tester.widget(reset);
        expect(switch (button) {
          AppButton(:final onPressed) => onPressed,
          AppIconButton(:final onPressed) => onPressed,
          _ => throw StateError('Unexpected reset control'),
        }, isNull);
        await tester.tap(find.byKey(const ValueKey('appInput.clearButton')));
        await tester.pumpAndSettle();
        await _open(tester, 'image');
        expect(
          tester
              .widget<AppSwitch>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is AppSwitch &&
                      widget.label ==
                          (zh ? '自动 HDR 显示' : 'Automatic HDR display'),
                ),
              )
              .value,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('format catalog groups supported formats and adapts columns', (
    tester,
  ) async {
    _size(tester, const Size(1280, 800));
    await tester.pumpWidget(_host(registry: _FormatRegistry()));
    await tester.pumpAndSettle();
    await _open(tester, 'image');
    final toggle = find.byKey(const ValueKey('settings.toggleFormats'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final jpeg = find.byKey(const ValueKey('settings.format.jpeg'));
    final gif = find.byKey(const ValueKey('settings.format.gif'));
    expect(jpeg, findsOneWidget);
    expect(gif, findsOneWidget);
    expect(find.byKey(const ValueKey('settings.format.png')), findsNothing);
    expect(find.text('可用'), findsNothing);
    expect(find.text('不可用'), findsNothing);
    expect(find.text('Flutter 编解码器'), findsOneWidget);
    expect(find.textContaining('支持 2 种格式'), findsOneWidget);
    expect(tester.getTopLeft(jpeg).dy, tester.getTopLeft(gif).dy);
    expect(tester.getTopLeft(gif).dx, greaterThan(tester.getTopLeft(jpeg).dx));
    tester.view.physicalSize = const Size(440, 800);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(jpeg).dx, tester.getTopLeft(gif).dx);
    expect(tester.getTopLeft(gif).dy, greaterThan(tester.getTopLeft(jpeg).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('select menus only show tooltips that add information', (
    tester,
  ) async {
    _size(tester, const Size(800, 600));
    var selected = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              child: AppSelect<int>(
                value: selected,
                options: const [
                  AppSelectOption(value: 1, label: '最新', tooltip: '最新'),
                  AppSelectOption(value: 2, label: '最早'),
                  AppSelectOption(value: 3, label: '名称', tooltip: '按文件名自然排序'),
                ],
                onChanged: (value) => selected = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(AppSelect<int>));
    await tester.pumpAndSettle();
    // The selected trigger keeps its tooltip; the menu adds no duplicate.
    expect(find.byTooltip('最新'), findsOneWidget);
    expect(find.byTooltip('最早'), findsNothing);
    expect(find.byTooltip('按文件名自然排序'), findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.text('名称')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('按文件名自然排序'), findsOneWidget);
    await mouse.removePointer();
    await tester.tap(find.text('最早'));
    await tester.pumpAndSettle();
    expect(selected, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HDR and formats render across locales themes and text scaling', (
    tester,
  ) async {
    _size(tester, const Size(1280, 800));
    if (Platform.environment['SETTINGS_UPGRADE_CAPTURE_DIR'] != null) {
      await loadStyleReviewFonts(tester);
    }
    for (final language in ['zh', 'en']) {
      for (final dark in [false, true]) {
        for (final width in [1280.0, 440.0]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pumpWidget(
            _host(
              language: language,
              dark: dark,
              textScale: width == 440 ? 1.5 : 1,
            ),
          );
          await tester.pumpAndSettle();
          await _open(tester, 'image');
          await _capture(tester, '$language-$dark-$width-hdr-on');
          final master = find.byWidgetPredicate(
            (w) =>
                w is AppSwitch &&
                w.label ==
                    (language == 'zh' ? '自动 HDR 显示' : 'Automatic HDR display'),
          );
          await tester.ensureVisible(master);
          await tester.tap(
            find.descendant(of: master, matching: find.byType(Switch)),
          );
          await tester.pumpAndSettle();
          expect(tester.widget<AppSwitch>(master).value, isFalse);
          await tester.pumpAndSettle();
          await _capture(tester, '$language-$dark-$width-hdr-off');
          final toggle = find.byKey(const ValueKey('settings.toggleFormats'));
          await tester.ensureVisible(toggle);
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          await Scrollable.ensureVisible(tester.element(toggle), alignment: 0);
          await tester.pumpAndSettle();
          await _capture(tester, '$language-$dark-$width-formats');
          await _open(tester, 'general');
          final reset = find.byKey(const ValueKey('settings.resetAll'));
          await tester.ensureVisible(reset);
          await tester.pumpAndSettle();
          await _capture(tester, '$language-$dark-$width-reset-entry');
          await tester.tap(reset);
          await tester.pumpAndSettle();
          expect(
            find.text(language == 'zh' ? '恢复所有设置？' : 'Reset all settings?'),
            findsOneWidget,
          );
          await _capture(tester, '$language-$dark-$width-reset-dialog');
          await tester.tap(find.text(language == 'zh' ? '取消' : 'Cancel'));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$language $dark $width',
          );
        }
      }
    }
  });
}

class _FormatRegistry extends DecoderRegistry {
  @override
  List<DecoderCapability> capabilities() => const [
    DecoderCapability(
      format: ImageFormat.jpeg,
      available: true,
      animated: false,
      metadata: true,
      sourceKind: DecoderSource.flutterCodec,
    ),
    DecoderCapability(
      format: ImageFormat.png,
      available: false,
      animated: false,
      metadata: false,
      sourceKind: DecoderSource.unavailable,
    ),
    DecoderCapability(
      format: ImageFormat.gif,
      available: true,
      animated: true,
      metadata: false,
      sourceKind: DecoderSource.flutterCodec,
    ),
  ];
}
