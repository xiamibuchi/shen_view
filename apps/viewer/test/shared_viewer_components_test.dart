import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/components/app_dialog.dart';
import 'package:shen_view/src/presentation/components/app_file_name_editor.dart';
import 'package:shen_view/src/presentation/components/app_image_error.dart';
import 'package:shen_view/src/presentation/theme_demo_page.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';
import 'package:shen_view/src/presentation/zoomable_viewport.dart';

import 'support/style_review_fonts.dart';

void main() {
  if (Platform.environment['SHARED_UI_CAPTURE_DIR'] != null) {
    StyleReviewBinding();
  }

  testWidgets(
    'file name editor retains extension, errors, Escape and outside cancellation',
    (tester) async {
      final request = Completer<String?>();
      final names = <String>[];
      await tester.pumpWidget(
        _host(
          Center(
            child: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppFileNameEditor(
                    label: '文件名',
                    fileName: '原始图片.png',
                    canEdit: true,
                    unavailableMessage: '只读',
                    invalidMessage: '请输入文件名',
                    renameTooltip: '重命名',
                    onRename: (name) {
                      names.add(name);
                      return request.future;
                    },
                  ),
                  const Text('外部区域'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('重命名'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '原始图片');
      expect(field.controller!.selection.baseOffset, 0);
      expect(field.controller!.selection.extentOffset, 4);
      expect(find.text('.png'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '新名字');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(names, ['新名字.png']);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      request.complete('同名文件已存在');
      await tester.pumpAndSettle();
      expect(find.text('同名文件已存在'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('原始图片.png'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byTooltip('重命名'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '未保存');
      await tester.tap(find.text('外部区域'));
      await tester.pumpAndSettle();
      expect(find.text('原始图片.png'), findsOneWidget);
      expect(names, ['新名字.png']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'migrated viewer menus, info editor and delete dialog fit both themes',
    (tester) async {
      await _reviewFonts(tester);
      const channel = MethodChannel('window_manager');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (const [
          'isFullScreen',
          'isMaximized',
          'isAlwaysOnTop',
        ].contains(call.method)) {
          return false;
        }
        return null;
      });
      final directory = Directory.systemTemp.createTempSync(
        'shared-viewer-ui-',
      );
      final sample = File('testdata/formats/format_static.png').copySync(
        File.fromUri(
          directory.uri.resolve('旅行相册_山间风景与晚霞_Landscape_2026_10_23.png'),
        ).path,
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        try {
          directory.deleteSync(recursive: true);
        } on FileSystemException {
          /* Decoder may still hold a handle. */
        }
      });
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final dark in [true, false]) {
        final themeName = dark ? 'dark' : 'light';
        await tester.pumpWidget(
          _host(
            ViewerPage(
              key: ValueKey('empty-$themeName'),
              initialSettings: const ViewerSettings(showDirectoryPanel: false),
              configStore: AppConfigStore(
                filePath: '${directory.path}/empty-$themeName-config.json',
              ),
            ),
            dark: dark,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('显示信息 · I'));
        await tester.pumpAndSettle();
        expect(find.text('暂无图片'), findsOneWidget);
        expect(find.byType(AppFileNameEditor), findsNothing);
        await _capture(tester, 'viewer-info-empty-$themeName');
        await tester.pumpWidget(
          _host(
            ViewerPage(
              key: ValueKey(themeName),
              initialPath: sample.path,
              initialSettings: const ViewerSettings(showDirectoryPanel: false),
              configStore: AppConfigStore(
                filePath: '${directory.path}/$themeName-config.json',
              ),
            ),
            dark: dark,
          ),
        );
        for (var attempt = 0; attempt < 80; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
          if (tester
              .widgetList<RawImage>(
                find.descendant(
                  of: find.byType(ZoomableViewport),
                  matching: find.byType(RawImage),
                ),
              )
              .any((n) => n.image != null)) {
            break;
          }
        }
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('显示信息 · I'));
        await tester.pumpAndSettle();
        expect(find.byType(AppFileNameEditor), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('信息')).dx,
          tester.getTopLeft(find.text('文件名')).dx,
        );
        await _capture(tester, 'viewer-info-$themeName');
        tester.view.physicalSize = const Size(560, 640);
        await tester.pumpAndSettle();
        final infoTitle = tester.getRect(find.text('信息'));
        final nameLabel = tester.getRect(find.text('文件名'));
        expect(infoTitle.left, nameLabel.left);
        final nameBounds = tester.getRect(
          find.descendant(
            of: find.byType(AppFileNameEditor),
            matching: find.text(sample.uri.pathSegments.last),
          ),
        );
        expect(
          nameBounds.bottom,
          lessThanOrEqualTo(
            tester.getRect(find.byType(AppFileNameEditor)).bottom,
          ),
        );
        await _capture(tester, 'viewer-info-narrow-$themeName');
        tester.view.physicalSize = const Size(1200, 800);
        await tester.pumpAndSettle();
        final editor = tester.widget<AppFileNameEditor>(
          find.byType(AppFileNameEditor),
        );
        await tester.tap(find.byTooltip(editor.renameTooltip));
        await tester.pumpAndSettle();
        await _capture(tester, 'viewer-rename-$themeName');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('关闭信息面板'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('查看顺序'));
        await tester.pumpAndSettle();
        await _capture(tester, 'viewer-sort-$themeName');
        await tester.tapAt(const Offset(500, 90));
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .descendant(
                of: find.byType(ZoomableViewport),
                matching: find.byType(RawImage),
              )
              .first,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(find.text('删除'), findsOneWidget);
        await _capture(tester, 'viewer-menu-$themeName');
        await tester.tap(find.text('删除'));
        await tester.pumpAndSettle();
        expect(find.byType(AppConfirmDialog), findsOneWidget);
        await _capture(tester, 'viewer-delete-$themeName');
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(sample.existsSync(), isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('theme review controls fit wide and narrow windows', (
    tester,
  ) async {
    await _reviewFonts(tester);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [1600.0, 800.0]) {
      tester.view.physicalSize = Size(width, 1000);
      await tester.pumpWidget(_host(const ThemeDemoPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('双页').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('悬浮').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final widthLabel = width.toInt();
      await _capture(tester, 'theme-demo-$widthLabel');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('image failures are legible in light and dark themes', (
    tester,
  ) async {
    await _reviewFonts(tester);
    for (final dark in [true, false]) {
      await tester.pumpWidget(
        _host(
          Center(
            child: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  AppImageError(title: '无法解析图片', details: '图片数据损坏或格式暂不支持'),
                  SizedBox(height: 24),
                  SizedBox(height: 100, child: AppImagePlaceholder()),
                ],
              ),
            ),
          ),
          dark: dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final themeName = dark ? 'dark' : 'light';
      await _capture(tester, 'image-error-$themeName');
    }
  });
}

Widget _host(Widget child, {bool dark = true}) => RepaintBoundary(
  key: const ValueKey('shared.ui.capture'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark
        ? AppTheme.dark(
            platform: Platform.environment['SHARED_UI_CAPTURE_DIR'] != null
                ? TargetPlatform.windows
                : null,
          )
        : AppTheme.light(
            platform: Platform.environment['SHARED_UI_CAPTURE_DIR'] != null
                ? TargetPlatform.windows
                : null,
          ),
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: child),
  ),
);

Future<void> _reviewFonts(WidgetTester tester) async {
  if (Platform.environment['SHARED_UI_CAPTURE_DIR'] == null) return;
  await loadStyleReviewFonts(tester);
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['SHARED_UI_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shared.ui.capture')),
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
