import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_control_styles.dart';
import '../theme/app_tokens.dart';

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    this.icon,
    this.iconWidget,
    required this.tooltip,
    required this.onPressed,
    this.size = AppTokens.iconButtonSize,
    this.iconSize = 20,
    this.color,
    this.autofocus = false,
    this.style,
    super.key,
  });

  final IconData? icon;
  final Widget? iconWidget;
  final ButtonStyle? style;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? color;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    final defaults = AppControlStyles.icon(tokens, size: size, color: color);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      autofocus: autofocus,
      // Keep bar geometry and express focus through the action background.
      style: style == null
          ? defaults
          : style!.copyWith(
              side: defaults.side,
              mouseCursor: style!.mouseCursor ?? defaults.mouseCursor,
            ),
      icon: iconWidget ?? Icon(icon, size: iconSize),
    );
  }
}
