import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_styles.dart';
import '../theme/app_tokens.dart';
import '../theme/app_control_styles.dart';

enum AppButtonVariant { accent, neutral, subtle, danger }

enum AppButtonSize { standard, prominent }

class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.accent,
    this.size = AppButtonSize.standard,
    this.leadingIcon,
    this.trailingIcon,
    this.busy = false,
    this.expand = false,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool busy;
  final bool expand;
  final String? tooltip;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    final enabled = onPressed != null && !busy;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (leadingIcon != null)
          Icon(leadingIcon, size: 18),
        if ((busy || leadingIcon != null) && label.isNotEmpty)
          const SizedBox(width: AppTokens.space2),
        if (label.isNotEmpty)
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        if (trailingIcon != null) ...[
          const SizedBox(width: AppTokens.space2),
          Icon(trailingIcon, size: 18),
        ],
      ],
    );
    Widget button = SizedBox(
      width: expand ? double.infinity : null,
      height: AppControlStyles.controlHeight(context, minimum: _height),
      child: FilledButton(
        focusNode: focusNode,
        autofocus: autofocus,
        onPressed: enabled ? onPressed : null,
        style: _style(context, tokens, enabled: enabled),
        child: content,
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }

  double get _height => size == AppButtonSize.prominent
      ? AppTokens.primaryControlHeight
      : AppTokens.controlHeight;

  ButtonStyle _style(
    BuildContext context,
    ViewerThemeTokens tokens, {
    required bool enabled,
  }) {
    Color background(Set<WidgetState> states) {
      if (!enabled) return tokens.surfaceSubtle;
      if (variant == AppButtonVariant.subtle) {
        if (states.contains(WidgetState.pressed)) return tokens.surfacePressed;
        if (states.contains(WidgetState.focused)) {
          return AppControlStyles.focusFill(tokens);
        }
        if (states.contains(WidgetState.hovered)) return tokens.surfaceHover;
        return Colors.transparent;
      }
      if (variant == AppButtonVariant.neutral) {
        if (states.contains(WidgetState.pressed)) return tokens.surfacePressed;
        if (states.contains(WidgetState.focused)) {
          return AppControlStyles.focusFill(tokens);
        }
        if (states.contains(WidgetState.hovered)) return tokens.surfaceHover;
        return tokens.controlFill;
      }
      if (variant == AppButtonVariant.danger) {
        if (states.contains(WidgetState.pressed)) {
          return Color.alphaBlend(
            AppColors.shadow.withValues(alpha: 0.20),
            tokens.dangerFill,
          );
        }
        if (states.contains(WidgetState.focused)) {
          return Color.alphaBlend(
            AppColors.shadow.withValues(alpha: 0.12),
            tokens.dangerFill,
          );
        }
        if (states.contains(WidgetState.hovered)) {
          return Color.alphaBlend(
            AppColors.shadow.withValues(alpha: 0.06),
            tokens.dangerFill,
          );
        }
        return tokens.dangerFill;
      }
      if (states.contains(WidgetState.pressed)) {
        return Color.alphaBlend(
          AppColors.shadow.withValues(alpha: 0.20),
          tokens.accent,
        );
      }
      if (states.contains(WidgetState.focused)) {
        return Color.alphaBlend(
          AppColors.shadow.withValues(alpha: 0.12),
          tokens.accent,
        );
      }
      if (states.contains(WidgetState.hovered)) {
        return Color.alphaBlend(
          AppColors.shadow.withValues(alpha: 0.06),
          tokens.accent,
        );
      }
      return tokens.accent;
    }

    Color foreground(Set<WidgetState> states) {
      if (!enabled) return tokens.textDisabled;
      if (variant == AppButtonVariant.accent ||
          variant == AppButtonVariant.danger) {
        return variant == AppButtonVariant.danger
            ? tokens.onDanger
            : tokens.onAccent;
      }
      return tokens.textPrimary;
    }

    BorderSide side(Set<WidgetState> states) {
      if (variant == AppButtonVariant.neutral) {
        return BorderSide(color: tokens.border);
      }
      return BorderSide.none;
    }

    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
      maximumSize: const WidgetStatePropertyAll(
        Size(double.infinity, double.infinity),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: AppTokens.space4),
      ),
      backgroundColor: WidgetStateProperty.resolveWith(background),
      foregroundColor: WidgetStateProperty.resolveWith(foreground),
      side: WidgetStateProperty.resolveWith(side),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.controlRadius),
        ),
      ),
      elevation: const WidgetStatePropertyAll(0),
      textStyle: WidgetStatePropertyAll(
        Theme.of(context).textTheme.labelLarge?.merge(
          AppTextStyles.control.copyWith(fontWeight: FontWeight.w500),
        ),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      mouseCursor: WidgetStateProperty.resolveWith(
        (states) => enabled && !states.contains(WidgetState.disabled)
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
      ),
    );
  }
}
