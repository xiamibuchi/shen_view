import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_styles.dart';
import '../theme/app_tokens.dart';
import 'app_search_text.dart';

class AppSwitch extends StatelessWidget {
  const AppSwitch({
    required this.value,
    required this.onChanged,
    this.label,
    this.description,
    this.enabled = true,
    this.focusNode,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final String? description;
  final bool enabled;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    final active = enabled && onChanged != null;
    final labelWidget = label == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSearchText(
                label!,
                style: AppTextStyles.body.copyWith(
                  color: active ? tokens.textPrimary : tokens.textDisabled,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 2),
                AppSearchText(
                  description!,
                  style: AppTextStyles.label.copyWith(
                    color: active ? tokens.textTertiary : tokens.textDisabled,
                  ),
                ),
              ],
            ],
          );
    return MergeSemantics(
      child: Row(
        mainAxisSize: label == null ? MainAxisSize.min : MainAxisSize.max,
        children: [
          if (labelWidget != null) Expanded(child: labelWidget),
          if (labelWidget != null) const SizedBox(width: AppTokens.space5),
          SizedBox(
            width: AppTokens.switchWidth,
            height: AppTokens.controlHeight,
            child: FittedBox(
              child: Switch(
                // Retain a 36px hit target while reducing the 52x32 M3 track.
                padding: const EdgeInsets.symmetric(vertical: 4),
                value: value,
                focusNode: focusNode,
                onChanged: active ? onChanged : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                thumbColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return tokens.textDisabled;
                  }
                  return states.contains(WidgetState.selected)
                      ? tokens.onAccent
                      : tokens.textSecondary;
                }),
                trackColor: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  if (states.contains(WidgetState.disabled)) {
                    return selected
                        ? Color.alphaBlend(
                            tokens.accent.withValues(alpha: 0.28),
                            tokens.surfaceSubtle,
                          )
                        : tokens.surfaceSubtle;
                  }
                  if (selected) {
                    final tint = states.contains(WidgetState.pressed)
                        ? 0.16
                        : states.contains(WidgetState.hovered)
                        ? 0.08
                        : 0.0;
                    return Color.alphaBlend(
                      tokens.textPrimary.withValues(alpha: tint),
                      tokens.accent,
                    );
                  }
                  if (states.contains(WidgetState.pressed)) {
                    return tokens.surfacePressed;
                  }
                  if (states.contains(WidgetState.hovered)) {
                    return tokens.surfaceHover;
                  }
                  return tokens.surfaceSubtle;
                }),
                trackOutlineColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return tokens.border;
                  }
                  if (states.contains(WidgetState.focused)) {
                    return tokens.focusRing;
                  }
                  return states.contains(WidgetState.selected)
                      ? Colors.transparent
                      : tokens.borderStrong;
                }),
                trackOutlineWidth: WidgetStateProperty.resolveWith(
                  (states) =>
                      !states.contains(WidgetState.disabled) &&
                          states.contains(WidgetState.focused)
                      ? 2
                      : 1,
                ),
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                mouseCursor: active
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
