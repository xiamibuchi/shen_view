import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../theme/app_styles.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

class AppImageError extends StatelessWidget {
  const AppImageError({required this.title, this.details, super.key});
  final String title;
  final String? details;

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          FluentIcons.image_off_24_regular,
          size: 42,
          color: tokens.textDisabled,
        ),
        const SizedBox(height: AppTokens.space2),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(color: tokens.textPrimary),
        ),
        if (details != null) ...[
          const SizedBox(height: AppTokens.space2),
          Text(
            details!,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: tokens.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class AppImagePlaceholder extends StatelessWidget {
  const AppImagePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    return ColoredBox(
      color: tokens.surfaceSubtle,
      child: Center(
        child: Icon(
          FluentIcons.image_off_24_regular,
          color: tokens.textDisabled,
        ),
      ),
    );
  }
}
