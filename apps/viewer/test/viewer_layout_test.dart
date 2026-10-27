import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_bottom_bar.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';

import 'support/style_review_fonts.dart';

const _captureKey = ValueKey('viewer-layout-capture');

void main() {
  testWidgets('toolbar mode does not move the thumbnail strip', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const windowManagerChannel = MethodChannel('window_manager');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(windowManagerChannel, (call) async {
      if (call.method == 'isFullScreen' ||
          call.method == 'isMaximized' ||
          call.method == 'isAlwaysOnTop') {
        return false;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(windowManagerChannel, null),
    );

    final captureDir = Platform.environment['VIEWER_LAYOUT_CAPTURE_DIR'];
    if (captureDir != null) {
      await loadStyleReviewFonts(tester);
    }

    final directory = Directory.systemTemp.createTempSync('viewer-layout-test');
    addTearDown(() {
      // The image decoder can keep the copied file open briefly on Windows.
      try {
        directory.deleteSync(recursive: true);
      } on FileSystemException {
        // The temp directory is safe to leave behind if the OS still holds it.
      }
    });
    File('testdata/formats/format_static.png')
        .copySync('${directory.path}/sample.png');

    Future<Rect> pump(ToolbarMode mode, Key key) async {
      final theme = AppTheme.dark(
        platform: captureDir == null ? null : TargetPlatform.windows,
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: _captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            locale: const Locale('zh'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: ViewerPage(
              key: key,
              configStore: AppConfigStore(
                filePath: '${directory.path}/${mode.name}.json',
              ),
              initialPath: '${directory.path}/sample.png',
              initialSettings: ViewerSettings(
                showDirectoryPanel: false,
                toolbarMode: mode,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 40; attempt++) {
        if (find.text('sample.png').evaluate().isNotEmpty) break;
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        });
        await tester.pump();
      }
      expect(find.text('sample.png'), findsWidgets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (captureDir != null) {
        await _capture(tester, '$captureDir/${mode.name}.png');
      }
      final rect = tester.getRect(find.byType(ViewerBottomBar));
      expect(rect.height, 88);
      return rect;
    }

    final normal = await pump(ToolbarMode.normal, const ValueKey('normal'));
    final floating = await pump(
      ToolbarMode.floating,
      const ValueKey('floating'),
    );

    expect(floating, normal);
    expect(normal.left, 0);
    expect(normal.right, 1280);
    expect(normal.bottom, 760);

    final directoryToggle = find.byKey(const ValueKey('navigation.directory'));
    final directoryRect = tester.getRect(directoryToggle);
    final thumbnails = find.byKey(const ValueKey('navigation.thumbnails'));
    final thumbnailRect = tester.getRect(thumbnails);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pumpAndSettle();
    expect(tester.getRect(directoryToggle), directoryRect);
    expect(tester.getRect(thumbnails), thumbnailRect);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pumpAndSettle();
    expect(find.byType(ViewerBottomBar), findsNothing);
    await tester.tap(directoryToggle);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('directory.panel')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _capture(WidgetTester tester, String filePath) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
