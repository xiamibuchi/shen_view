import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/auto_play_controller.dart';
import 'package:shen_view/src/domain/auto_play_settings.dart';
import 'package:shen_view/src/domain/viewer_mode.dart';
import 'package:shen_view/src/presentation/auto_play_status.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

void main() {
  for (final dark in [true, false]) {
    testWidgets(
      'status fades during playback and reveals on hover or pause, dark=$dark',
      (tester) async {
        final controller = AutoPlayController()..start();
        await _mount(tester, controller, dark: dark);
        expect(_opacity(tester), 1);
        // Countdown notifications must not reset the idle timer.
        for (var i = 0; i < 22; i++) {
          controller.tick(const Duration(milliseconds: 100), ready: true);
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(_opacity(tester), 0);
        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: const Offset(10, 10));
        await mouse.moveTo(
          tester.getCenter(find.byType(AutoPlayStatusIndicator)),
        );
        await tester.pump();
        expect(_opacity(tester), 1);
        await tester.pump(const Duration(seconds: 3));
        expect(_opacity(tester), 1);
        await mouse.moveTo(const Offset(10, 10));
        await tester.pump(const Duration(seconds: 3));
        expect(_opacity(tester), 0);
        controller.pause();
        await tester.pump();
        expect(_opacity(tester), 1);
        await tester.pump(const Duration(seconds: 30));
        expect(_opacity(tester), 1);
        controller.start();
        await tester.pump(const Duration(seconds: 3));
        expect(_opacity(tester), 0);
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );
  }

  testWidgets('keyboard focus and an open options panel keep status visible', (
    tester,
  ) async {
    final controller = AutoPlayController()..start();
    final options = Completer<void>();
    await _mount(tester, controller, onOptions: () => options.future);
    await tester.pump(const Duration(seconds: 3));
    expect(_opacity(tester), 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_opacity(tester), 1);
    await tester.pump(const Duration(seconds: 3));
    expect(_opacity(tester), 1);
    await tester.tap(find.byKey(const ValueKey('autoPlay.options')));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(seconds: 3));
    expect(_opacity(tester), 1);
    options.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(_opacity(tester), 0);
    controller.configure(
      controller.settings.copyWith(statusDisplay: AutoPlayStatusDisplay.always),
      ViewerMode.single,
    );
    await tester.pump();
    expect(_opacity(tester), 1);
    await tester.pump(const Duration(seconds: 30));
    expect(_opacity(tester), 1);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

double _opacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.byKey(const ValueKey('autoPlay.statusVisibility')),
    )
    .opacity;

Future<void> _mount(
  WidgetTester tester,
  AutoPlayController controller, {
  bool dark = true,
  FutureOr<void> Function()? onOptions,
}) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('zh'),
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Center(
      child: SizedBox(
        width: 280,
        child: AutoPlayStatusIndicator(
          controller: controller,
          onOptions: onOptions ?? () {},
          position: '1 / 3',
        ),
      ),
    ),
  ),
);
