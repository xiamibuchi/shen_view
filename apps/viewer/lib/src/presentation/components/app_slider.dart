import 'package:flutter/material.dart';

import '../theme/app_styles.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

enum AppSliderVariant { zoom, setting, demo }

class AppSlider extends StatelessWidget {
  const AppSlider({
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.onChangeStart,
    this.onChangeEnd,
    this.semanticFormatterCallback,
    this.variant = AppSliderVariant.setting,
    super.key,
  });
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final SemanticFormatterCallback? semanticFormatterCallback;
  final AppSliderVariant variant;

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    final theme = switch (variant) {
      AppSliderVariant.zoom => SliderTheme.of(context).copyWith(
        activeTrackColor: tokens.accentStrong,
        inactiveTrackColor: tokens.borderStrong,
        disabledActiveTrackColor: tokens.textDisabled,
        disabledInactiveTrackColor: tokens.textDisabled,
        thumbColor: tokens.accentStrong,
        overlayColor: tokens.accent.withValues(alpha: 0.16),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.zoomSliderThumbRadius,
        ),
        showValueIndicator: ShowValueIndicator.never,
        trackHeight: 4,
        trackShape: const _EqualHeightSliderTrackShape(),
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: AppTokens.zoomSliderThumbRadius,
        ),
        overlayShape: const RoundSliderOverlayShape(
          overlayRadius: AppTokens.zoomSliderOverlayRadius,
        ),
      ),
      AppSliderVariant.setting => SliderTheme.of(context).copyWith(
        trackHeight: 3,
        activeTrackColor: tokens.accent,
        inactiveTrackColor: tokens.surfaceSubtle,
        thumbColor: tokens.accent,
        overlayColor: tokens.accent.withValues(alpha: 0.12),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        valueIndicatorColor: tokens.surfaceElevated,
        valueIndicatorTextStyle: AppTextStyles.label.copyWith(
          color: tokens.textPrimary,
        ),
      ),
      AppSliderVariant.demo => SliderTheme.of(context).copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
      ),
    };
    return SliderTheme(
      data: theme,
      child: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChanged: onChanged,
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd,
        semanticFormatterCallback: semanticFormatterCallback,
      ),
    );
  }
}

class _EqualHeightSliderTrackShape extends RoundedRectSliderTrackShape {
  const _EqualHeightSliderTrackShape();
  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: 0,
    );
  }
}
