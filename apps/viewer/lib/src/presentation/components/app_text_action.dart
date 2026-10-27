import 'package:flutter/material.dart';

import '../theme/app_styles.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// An inline action aligned with surrounding text, without a hover surface.
class AppTextAction extends StatelessWidget {
  const AppTextAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.maxLines,
    this.semanticsLabel,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final int? maxLines;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    final typography = Theme.of(context).textTheme.bodyMedium!
        .merge(AppTextStyles.control);
    Color foreground(Set<WidgetState> states) =>
        states.contains(WidgetState.disabled)
        ? tokens.textDisabled
        : states.any(
            {
              WidgetState.hovered,
              WidgetState.focused,
              WidgetState.pressed,
            }.contains,
          )
        ? tokens.accentStrong
        : tokens.textPrimary;
    return TextButton(
      onPressed: onPressed,
      style: ButtonStyle(
        alignment: Alignment.centerLeft,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 8),
        ),
        minimumSize: const WidgetStatePropertyAll(
          Size(0, AppTokens.controlHeight),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(foreground),
        iconColor: WidgetStateProperty.resolveWith(foreground),
        mouseCursor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
        ),
        textStyle: WidgetStateProperty.resolveWith((states) {
          final emphasized =
              !states.contains(WidgetState.disabled) &&
              states.any(
                {
                  WidgetState.hovered,
                  WidgetState.focused,
                  WidgetState.pressed,
                }.contains,
              );
          return typography.copyWith(
            decoration: emphasized
                ? TextDecoration.underline
                : TextDecoration.none,
            decorationColor: foreground(states),
            decorationThickness: states.contains(WidgetState.focused) ? 2 : 1,
          );
        }),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: maxLines,
              overflow: maxLines == null ? null : TextOverflow.ellipsis,
              semanticsLabel: semanticsLabel,
            ),
          ),
        ],
      ),
    );
  }
}
