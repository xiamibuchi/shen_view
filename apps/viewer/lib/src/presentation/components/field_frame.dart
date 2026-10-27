import 'package:flutter/material.dart';

import '../theme/app_styles.dart';
import '../theme/app_control_styles.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// Shared label and feedback placement. Feedback never changes control height.
class FieldFrame extends StatelessWidget {
  const FieldFrame({
    required this.child,
    this.label,
    this.helperText,
    this.errorText,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final String? label;
  final String? helperText;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    final feedback = errorText ?? helperText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: AppTextStyles.caption.copyWith(
              color: enabled ? tokens.textSecondary : tokens.textDisabled,
            ),
          ),
          const SizedBox(height: 6),
        ],
        child,
        if (feedback != null) ...[
          const SizedBox(height: AppTokens.space1),
          Semantics(
            liveRegion: errorText != null,
            child: Text(
              feedback,
              style: AppTextStyles.caption.copyWith(
                color: errorText != null ? tokens.danger : tokens.textTertiary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class FieldSurface extends StatelessWidget {
  const FieldSurface({
    required this.child,
    this.focused = false,
    this.hovered = false,
    this.pressed = false,
    this.enabled = true,
    this.hasError = false,
    this.borderless = false,
    super.key,
  });

  final Widget child;
  final bool focused;
  final bool hovered;
  final bool pressed;
  final bool enabled;
  final bool hasError;
  final bool borderless;

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    return SizedBox(
      height: AppControlStyles.controlHeight(context),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: !enabled
              ? tokens.surfaceSubtle
              : pressed
              ? Color.alphaBlend(
                  tokens.surfacePressed.withValues(alpha: 0.65),
                  tokens.fieldFill,
                )
              : hovered
              ? Color.alphaBlend(
                  tokens.surfaceHover.withValues(alpha: 0.45),
                  tokens.fieldFill,
                )
              : borderless
              ? AppColors.transparent
              : tokens.fieldFill,
          borderRadius: BorderRadius.circular(AppTokens.controlRadius),
          border: Border.all(
            color: !enabled
                ? tokens.border
                : hasError
                ? tokens.danger
                : focused
                ? tokens.accentStrong
                : borderless
                ? tokens.border.withValues(alpha: 0)
                : tokens.border,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.space3),
          child: child,
        ),
      ),
    );
  }
}
