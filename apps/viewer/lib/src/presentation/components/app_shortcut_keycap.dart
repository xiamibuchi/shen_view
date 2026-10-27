import 'package:flutter/material.dart';

import '../theme/app_styles.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'app_interactive_surface.dart';
import 'app_search_text.dart';

class AppShortcutKeycap extends StatelessWidget {
  const AppShortcutKeycap({
    required this.label,
    required this.tooltip,
    this.onPressed,
    super.key,
  });

  final String label;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    final content = Container(
      constraints: const BoxConstraints(
        minWidth: AppTokens.iconButtonSize,
        minHeight: AppTokens.iconButtonSize,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space2,
        vertical: AppTokens.space1,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.controlRadius),
        border: Border.all(color: tokens.border),
      ),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: AppSearchText(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: onPressed == null
                ? tokens.textSecondary
                : tokens.textPrimary,
            height: 1.4,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaceSubtle,
          borderRadius: BorderRadius.circular(AppTokens.controlRadius),
        ),
        child: onPressed == null
            ? content
            : AppInteractiveSurface(onTap: onPressed, child: content),
      ),
    );
  }
}
