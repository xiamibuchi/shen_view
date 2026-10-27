import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/presentation/theme/app_control_styles.dart';
import 'package:shen_view/src/presentation/components/app_notification.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

import 'support/style_review_fonts.dart';

void main() {
  testWidgets(
    'notification fade uses the panel curve without changing layout',
    (tester) async {
      final controller = AppNotificationController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(controller));
      controller.show('打开失败', type: AppNotificationType.error);
      await tester.pump();
      final card = find.byType(AppNotificationCard);
      final fade = find.descendant(of: card, matching: find.byType(Opacity));
      final before = tester.getRect(card);
      expect(tester.widget<Opacity>(fade).opacity, 0);
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: card,
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(8));
      final material = tester.widget<Material>(
        find.descendant(of: card, matching: find.byType(Material)).first,
      );
      expect(material.borderRadius, BorderRadius.circular(8));
      await tester.pump(const Duration(milliseconds: 90));
      expect(
        tester.widget<Opacity>(fade).opacity,
        closeTo(Curves.easeOutCubic.transform(0.5), 0.001),
      );
      expect(tester.getRect(card), before);
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.widget<Opacity>(fade).opacity, 1);
      expect(tester.getRect(card), before);
    },
  );

  testWidgets('reduced motion shows notifications immediately', (tester) async {
    final controller = AppNotificationController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, disableAnimations: true));
    controller.show('打开失败', type: AppNotificationType.error);
    await tester.pump();
    final fade = find.descendant(
      of: find.byType(AppNotificationCard),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(fade).opacity, 1);
  });

  for (final dark in [true, false]) {
    testWidgets(
      'close button has a stable active keyboard focus background dark=$dark',
      (tester) async {
        await _loadFonts(tester);
        final controller = AppNotificationController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _host(
            controller,
            dark: dark,
            child: Center(
              child: TextButton(onPressed: () {}, child: const Text('其他操作')),
            ),
          ),
        );
        controller.show('压缩包内没有可浏览的图片', type: AppNotificationType.error);
        await tester.pumpAndSettle();
        final close = find.byType(IconButton);
        final before = tester.getRect(close);
        expect(before.size, const Size.square(32));
        expect(_closeShape(tester).side, BorderSide.none);
        expect(_closeFocused(tester), isFalse);
        for (var i = 0; i < 4 && !_closeFocused(tester); i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
        }
        expect(_closeFocused(tester), isTrue);
        expect(_closeShape(tester).side, BorderSide.none);
        expect(tester.getRect(close), before);
        await _capture(tester, 'notification-focus-${dark ? 'dark' : 'light'}');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(_closeShape(tester).side, BorderSide.none);
        expect(_closeFocused(tester), isFalse);
        expect(tester.getRect(close), before);
        for (var i = 0; i < 4 && !_closeFocused(tester); i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(AppNotificationCard), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('close button hover and press use theme surfaces dark=$dark', (
      tester,
    ) async {
      final controller = AppNotificationController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(controller, dark: dark));
      controller.show('打开失败', type: AppNotificationType.error);
      await tester.pumpAndSettle();
      final close = find.byType(IconButton);
      final before = tester.getRect(close);
      final tokens = ViewerThemeTokens.of(tester.element(close));
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(before.center);
      await tester.pumpAndSettle();
      expect(_closeMaterial(tester).color, tokens.surfaceHover);
      expect(tester.getRect(close), before);
      await mouse.down(before.center);
      await tester.pumpAndSettle();
      expect(_closeMaterial(tester).color, tokens.surfacePressed);
      expect(tester.getRect(close), before);
      await mouse.up();
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(find.byType(AppNotificationCard), findsNothing);
    });
  }

  testWidgets('notifications expire independently; errors require closing', (
    tester,
  ) async {
    final controller = AppNotificationController();
    addTearDown(controller.dispose);
    var underlyingTaps = 0;
    await tester.pumpWidget(
      _host(
        controller,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => underlyingTaps++,
          child: const SizedBox.expand(),
        ),
      ),
    );
    for (final type in AppNotificationType.values) {
      controller.show(type.name, type: type);
    }
    await tester.pumpAndSettle();
    expect(find.byType(AppNotificationCard), findsNWidgets(4));
    await tester.tapAt(const Offset(30, 300));
    await tester.pump();
    expect(underlyingTaps, 1);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('success'), findsNothing);
    expect(find.text('info'), findsNothing);
    expect(find.text('warning'), findsOneWidget);
    expect(find.text('error'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('warning'), findsNothing);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('error'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(controller.isNotEmpty, isFalse);
  });

  testWidgets('actions and progress completion keep unrelated errors visible', (
    tester,
  ) async {
    await _loadFonts(tester);
    final controller = AppNotificationController();
    await tester.pumpWidget(_host(controller));
    var actions = 0;
    controller.show(
      '压缩包内没有可浏览的图片',
      type: AppNotificationType.error,
      actionLabel: '在资源管理器中显示',
      onAction: () => actions++,
    );
    final progress = controller.show('正在准备页面');
    await tester.pumpAndSettle();
    final action = find.text('在资源管理器中显示');
    final message = find.text('压缩包内没有可浏览的图片');
    final actionRect = tester.getRect(action);
    expect(actionRect.left, tester.getRect(message).left);
    final button = find.ancestor(of: action, matching: find.byType(TextButton));
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(action));
    await tester.pumpAndSettle();
    final richText = find.descendant(
      of: action,
      matching: find.byType(RichText),
    );
    expect(
      tester.widget<RichText>(richText).text.style!.decoration,
      TextDecoration.underline,
    );
    expect(tester.getRect(action), actionRect);
    expect(
      tester
          .widget<Material>(
            find.descendant(of: button, matching: find.byType(Material)).first,
          )
          .color,
      Colors.transparent,
    );
    await _capture(tester, 'notification-action-hover');
    await mouse.removePointer();
    await tester.tap(find.text('在资源管理器中显示'));
    await tester.pump();
    expect(actions, 1);
    for (var i = 0; i < 4 && !Focus.of(tester.element(action)).hasFocus; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    expect(Focus.of(tester.element(action)).hasFocus, isTrue);
    expect(
      tester.widget<RichText>(richText).text.style!.decorationThickness,
      2,
    );
    await _capture(tester, 'notification-action-focus');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(actions, 2);
    expect(find.text('压缩包内没有可浏览的图片'), findsOneWidget);
    progress.close();
    await tester.pump();
    expect(find.text('正在准备页面'), findsNothing);
    expect(find.text('压缩包内没有可浏览的图片'), findsOneWidget);
    final lateProgress = controller.show('新页面');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    lateProgress.close();
    // This test explicitly disposes the controller before asynchronous cleanup.
    // No timers or listener notifications may survive disposal.
    await tester.pump(const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
  });

  for (final dark in [true, false]) {
    for (final width in [1039.0, 440.0]) {
      testWidgets('notification visuals dark=$dark width=$width', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 655);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await _loadFonts(tester);
        final controller = AppNotificationController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(_host(controller, dark: dark));
        controller.show('图片已保存', type: AppNotificationType.success);
        controller.show('正在准备压缩包中的下一页', type: AppNotificationType.info);
        controller.show('压缩包中的图片为只读，无法重命名', type: AppNotificationType.warning);
        controller.show(
          '压缩包内没有可浏览的图片',
          type: AppNotificationType.error,
          actionLabel: '在资源管理器中显示',
          onAction: () {},
        );
        await tester.pumpAndSettle();
        final cards = find.byType(AppNotificationCard);
        expect(cards, findsNWidgets(4));
        final first = tester.getRect(cards.first);
        expect(first.top, 60);
        expect(first.right, width - 16);
        expect(first.width, width < 500 ? width - 32 : 420);
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          'notifications-${dark ? 'dark' : 'light'}-${width.toInt()}',
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 7));
      });
    }
  }

  testWidgets('long errors and many notifications scroll in a small window', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(440, 460);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = AppNotificationController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, textScale: 2));
    final longMessage = List.filled(50, '打开压缩包失败，文件内容已损坏。').join();
    controller.show(longMessage, type: AppNotificationType.error);
    for (var i = 0; i < 8; i++) {
      controller.show('错误 $i', type: AppNotificationType.error);
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭').first);
    await tester.pumpAndSettle();
    expect(find.text(longMessage), findsNothing);
    final list = find.byType(ListView);
    await tester.drag(list, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('错误 7').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Widget _host(
  AppNotificationController controller, {
  bool dark = true,
  double textScale = 1,
  bool disableAnimations = false,
  Widget child = const SizedBox.expand(),
}) => RepaintBoundary(
  key: const ValueKey('notification.capture'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark
        ? AppTheme.dark(
            platform: Platform.environment['NOTIFICATION_CAPTURE_DIR'] != null
                ? TargetPlatform.windows
                : null,
          )
        : AppTheme.light(
            platform: Platform.environment['NOTIFICATION_CAPTURE_DIR'] != null
                ? TargetPlatform.windows
                : null,
          ),
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: AppNotificationHost(
        controller: controller,
        child: Scaffold(body: child),
      ),
    ),
  ),
);

Material _closeMaterial(WidgetTester tester) => tester
    .widgetList<Material>(
      find.descendant(
        of: find.byType(IconButton),
        matching: find.byType(Material),
      ),
    )
    .firstWhere((material) => material.shape is RoundedRectangleBorder);

RoundedRectangleBorder _closeShape(WidgetTester tester) =>
    _closeMaterial(tester).shape! as RoundedRectangleBorder;

bool _closeFocused(WidgetTester tester) =>
    _closeMaterial(tester).color ==
    AppControlStyles.focusFill(
      ViewerThemeTokens.of(tester.element(find.byType(IconButton))),
    );

Future<void> _loadFonts(WidgetTester tester) async {
  if (Platform.environment['NOTIFICATION_CAPTURE_DIR'] == null) return;
  await loadStyleReviewFonts(tester);
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['NOTIFICATION_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('notification.capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
