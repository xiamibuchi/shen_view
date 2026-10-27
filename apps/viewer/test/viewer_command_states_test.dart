import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';
import 'package:window_manager/window_manager.dart';

import 'support/style_review_fonts.dart';

const _captureKey = ValueKey('viewer-command-states.capture');

void main() {
  if (Platform.environment['STATE_AUDIT_CAPTURE_DIR'] != null) {
    StyleReviewBinding();
  }
  for (final dark in [true, false]) {
    testWidgets(
      'sort and context command states across window layouts dark=$dark',
      (tester) async {
        if (Platform.environment['STATE_AUDIT_CAPTURE_DIR'] != null) {
          await loadStyleReviewFonts(tester);
        }
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        const channel = MethodChannel('window_manager');
        var pinned = false;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'isAlwaysOnTop') return pinned;
            if (call.method == 'setAlwaysOnTop') {
              pinned = (call.arguments as Map)['isAlwaysOnTop'] as bool;
            }
            if (call.method == 'isFullScreen' || call.method == 'isMaximized') {
              return false;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final directory = Directory.systemTemp.createTempSync(
          'command-states-',
        );
        addTearDown(() {
          try {
            directory.deleteSync(recursive: true);
          } on FileSystemException {
            /* Pending config writes can retain the temporary file on Windows. */
          }
        });
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        for (final mode in ToolbarMode.values) {
          for (final width in [1280.0, 760.0, 440.0]) {
            pinned = false;
            final height = width == 440 ? 460.0 : 800.0;
            tester.view.physicalSize = Size(width, height);
            final prefix =
                'viewer-${dark ? 'dark' : 'light'}-${mode.name}-${width.toInt()}';
            await mouse.moveTo(Offset.zero);
            await tester.pumpWidget(
              RepaintBoundary(
                key: _captureKey,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: dark
                      ? AppTheme.dark(platform: TargetPlatform.windows)
                      : AppTheme.light(platform: TargetPlatform.windows),
                  locale: const Locale('zh'),
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  home: ViewerPage(
                    key: ValueKey(prefix),
                    configStore: AppConfigStore(
                      filePath: '${directory.path}/$prefix.json',
                    ),
                    initialSettings: ViewerSettings(
                      showDirectoryPanel: false,
                      toolbarMode: mode,
                      openRecentOnNewWindow: true,
                    ),
                  ),
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 200));
            for (
              var attempt = 0;
              attempt < 40 &&
                  (find.text('开始').evaluate().isEmpty ||
                      find
                          .byType(CircularProgressIndicator)
                          .evaluate()
                          .isNotEmpty);
              attempt++
            ) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 25)),
              );
              await tester.pump(const Duration(milliseconds: 100));
            }
            expect(find.text('开始'), findsOneWidget);
            final listener =
                tester.state(find.byType(ViewerPage)) as WindowListener;
            listener.onWindowFocus();
            await tester.pumpAndSettle();
            await mouse.moveTo(Offset(width / 2, 100));
            await tester.pump();
            await mouse.moveTo(Offset(width / 2, 20));
            await tester.pumpAndSettle();
            final trigger = _sortTrigger();
            final rect = tester.getRect(trigger);
            final normal = _surface(tester, trigger).color;
            await _capture(tester, '$prefix-default');
            await mouse.moveTo(rect.center);
            await tester.pumpAndSettle();
            final hovered = _surface(tester, trigger).color;
            expect(hovered, isNot(normal));
            await _capture(tester, '$prefix-hover');
            await mouse.down(rect.center);
            await tester.pumpAndSettle();
            expect(_surface(tester, trigger).color, isNot(hovered));
            await _capture(tester, '$prefix-pressed');
            await mouse.up();
            await mouse.moveTo(Offset(width / 2, height - 70));
            await tester.pumpAndSettle();
            expect(find.text('文件名升序'), findsOneWidget);
            final opened = _surface(tester, trigger).color!;
            expect(
              opened.r,
              opened.b,
              reason: 'Expanded trigger stays neutral',
            );
            final foreground = tester.widget(trigger) is TextButton
                ? tester.widget<TextButton>(trigger).style!.foregroundColor
                : tester.widget<IconButton>(trigger).style!.foregroundColor;
            final tokens = ViewerThemeTokens.of(tester.element(trigger));
            expect(foreground!.resolve({}), tokens.textPrimary);
            expect(tester.getRect(trigger), rect);
            final menu = tester.getRect(
              find
                  .ancestor(
                    of: find.text('文件名升序'),
                    matching: find.byType(Material),
                  )
                  .first,
            );
            expect(menu.left, greaterThanOrEqualTo(0));
            expect(menu.right, lessThanOrEqualTo(width));
            expect(menu.bottom, lessThanOrEqualTo(height));
            await _capture(tester, '$prefix-open');
            final selected = find.ancestor(
              of: find.text('文件名升序'),
              matching: find.byType(MenuItemButton),
            );
            await mouse.moveTo(tester.getCenter(selected));
            await tester.pumpAndSettle();
            await _capture(tester, '$prefix-selected-hover');
            await mouse.down(tester.getCenter(selected));
            await tester.pumpAndSettle();
            final selectedFill = _surface(tester, selected).color!;
            expect(selectedFill.b, greaterThan(selectedFill.r));
            await _capture(tester, '$prefix-selected-pressed');
            await mouse.up();
            await tester.pumpAndSettle();
            expect(find.text('文件名升序'), findsNothing);
            await mouse.moveTo(rect.center);
            await tester.tap(trigger);
            await tester.pumpAndSettle();
            listener.onWindowBlur();
            await tester.pumpAndSettle();
            expect(find.text('文件名升序'), findsNothing);
            await mouse.moveTo(Offset(width / 2, height - 70));
            await tester.pumpAndSettle();
            await _capture(tester, '$prefix-inactive');
            listener.onWindowFocus();
            await tester.pumpAndSettle();
            await tester.tapAt(
              tester.getBottomRight(
                    find.byKey(const ValueKey('recent.welcome')),
                  ) -
                  const Offset(8, 8),
              buttons: kSecondaryMouseButton,
            );
            await tester.pumpAndSettle();
            for (final label in ['复制文件', '删除', '打印', '另存为']) {
              final item = find.ancestor(
                of: find.text(label),
                matching: find.byType(MenuItemButton),
              );
              expect(tester.widget<MenuItemButton>(item).onPressed, isNull);
              final before = _surface(tester, item).color;
              await mouse.moveTo(tester.getCenter(item));
              await mouse.down(tester.getCenter(item));
              await tester.pumpAndSettle();
              expect(_surface(tester, item).color, before);
              await mouse.up();
            }
            await _capture(tester, '$prefix-context-disabled');
            expect(find.text('置顶'), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
          }
        }
        await mouse.removePointer();
      },
    );
  }
}

Finder _sortTrigger() {
  final text = find.text('查看顺序');
  if (text.evaluate().isNotEmpty) {
    return find.ancestor(of: text, matching: find.byType(TextButton)).first;
  }
  return find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == '查看顺序',
  );
}

Material _surface(WidgetTester tester, Finder control) =>
    tester.widget<Material>(
      find.descendant(of: control, matching: find.byType(Material)).first,
    );

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['STATE_AUDIT_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
