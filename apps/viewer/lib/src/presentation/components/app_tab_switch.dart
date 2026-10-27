import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_styles.dart';
import '../theme/app_control_styles.dart';
import '../theme/app_tokens.dart';

@immutable
class AppTabOption<T> {
  const AppTabOption({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

class AppTabSwitch<T> extends StatelessWidget {
  const AppTabSwitch({
    required this.options,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.expand = false,
    this.showSelectedIcon = true,
    super.key,
  });

  final List<AppTabOption<T>> options;
  final T value;
  final ValueChanged<T>? onChanged;
  final bool enabled;
  final bool expand;
  final bool showSelectedIcon;

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    final active = enabled && onChanged != null;
    return SizedBox(
      width: expand ? double.infinity : null,
      child: SegmentedButton<T>(
        expandedInsets: expand ? EdgeInsets.zero : null,
        segments: [
          for (final option in options)
            ButtonSegment<T>(
              value: option.value,
              label: Text(option.label, overflow: TextOverflow.ellipsis),
              icon: option.icon == null ? null : Icon(option.icon, size: 18),
            ),
        ],
        selected: {value},
        showSelectedIcon: showSelectedIcon,
        onSelectionChanged: active
            ? (selection) {
                if (selection.isNotEmpty) onChanged!(selection.first);
              }
            : null,
        style: ButtonStyle(
          visualDensity: VisualDensity.standard,
          textStyle: WidgetStatePropertyAll(
            Theme.of(context).textTheme.labelLarge!
                .merge(AppTextStyles.control),
          ),
          minimumSize: WidgetStatePropertyAll(
            Size(0, AppControlStyles.controlHeight(context)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppTokens.space3),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (!active) {
              return tokens.textDisabled;
            }
            return states.contains(WidgetState.selected)
                ? tokens.accentStrong
                : tokens.textSecondary;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppControlStyles.selectionFill(
                tokens,
                enabled: active,
                hovered: states.contains(WidgetState.hovered),
                pressed: states.contains(WidgetState.pressed),
              );
            }
            if (!active) return tokens.surfaceSubtle;
            if (states.contains(WidgetState.pressed)) {
              return tokens.surfacePressed;
            }
            if (states.contains(WidgetState.hovered)) {
              return tokens.surfaceHover;
            }
            return Colors.transparent;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (active && states.contains(WidgetState.focused)) {
              return BorderSide(color: tokens.focusRing);
            }
            return BorderSide(color: tokens.border);
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.controlRadius),
            ),
          ),
          mouseCursor: WidgetStatePropertyAll(
            active ? SystemMouseCursors.click : SystemMouseCursors.basic,
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
    );
  }
}
