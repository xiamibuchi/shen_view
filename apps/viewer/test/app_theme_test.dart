import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/presentation/components/app_button.dart';
import 'package:shen_view/src/presentation/theme/app_control_styles.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

void main() {
  test(
    'desktop typography covers UI and Chinese without bundled platform fonts',
    () {
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        final theme = AppTheme.light(platform: platform);
        expect(theme.platform, platform);
        expect(theme.textTheme.bodyMedium!.fontFamily, isNotEmpty);
        expect(theme.textTheme.bodyMedium!.fontFamilyFallback, isNotEmpty);
        expect(
          theme.tooltipTheme.textStyle!.fontFamily,
          theme.textTheme.bodyMedium!.fontFamily,
        );
        expect(
          theme.dialogTheme.contentTextStyle!.fontFamilyFallback,
          theme.textTheme.bodyMedium!.fontFamilyFallback,
        );
      }
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'filled actions and error text retain readable contrast dark=$dark',
      (tester) async {
        final theme = dark ? AppTheme.dark() : AppTheme.light();
        final tokens = theme.extension<ViewerThemeTokens>()!;
        for (final surface in [
          tokens.surface,
          tokens.surfaceSubtle,
          tokens.surfaceElevated,
        ]) {
          for (final (hovered, pressed) in [
            (false, false),
            (true, false),
            (false, true),
          ]) {
            final background = Color.alphaBlend(
              AppControlStyles.selectionFill(
                tokens,
                hovered: hovered,
                pressed: pressed,
              ),
              surface,
            );
            expect(
              _contrast(tokens.accentStrong, background),
              greaterThanOrEqualTo(4.5),
            );
          }
        }
        expect(
          _contrast(tokens.danger, tokens.surfaceElevated),
          greaterThanOrEqualTo(4.5),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Column(
                children: [
                  AppButton(label: '保存', onPressed: () {}),
                  AppButton(
                    label: '删除',
                    variant: AppButtonVariant.danger,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        for (final button in tester.widgetList<FilledButton>(
          find.byType(FilledButton),
        )) {
          final fill = button.style!.backgroundColor!;
          expect(fill.resolve({WidgetState.focused}), isNot(fill.resolve({})));
          expect(
            fill.resolve({WidgetState.focused}),
            isNot(fill.resolve({WidgetState.hovered})),
          );
          expect(
            fill.resolve({WidgetState.focused}),
            isNot(fill.resolve({WidgetState.pressed})),
          );
          for (final states in [
            <WidgetState>{},
            {WidgetState.hovered},
            {WidgetState.focused},
            {WidgetState.focused, WidgetState.hovered},
            {WidgetState.pressed},
          ]) {
            final background = button.style!.backgroundColor!.resolve(states)!;
            final foreground = button.style!.foregroundColor!.resolve(states)!;
            expect(
              _contrast(foreground, background),
              greaterThanOrEqualTo(4.5),
            );
          }
        }
      },
    );
  }
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}
