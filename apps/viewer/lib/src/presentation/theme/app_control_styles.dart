import 'package:flutter/material.dart';

import 'app_styles.dart';
import 'app_theme.dart';
import 'app_tokens.dart';

class AppControlStyles {
  const AppControlStyles._();

  /// Normal desktop density with room for enlarged system text.
  static double controlHeight(
    BuildContext context, {
    double minimum = AppTokens.controlHeight,
  }) {
    final lineHeight =
        MediaQuery.textScalerOf(context)
            .scale(AppTextStyles.control.fontSize!) *
        AppTextStyles.control.height!;
    final height =
        ((lineHeight + AppTokens.space3) / AppTokens.space1).ceil() *
        AppTokens.space1;
    return height < minimum ? minimum : height;
  }

  static Color selectionFill(
    ViewerThemeTokens tokens, {
    bool hovered = false,
    bool pressed = false,
    bool enabled = true,
  }) => tokens.accent.withValues(
    alpha: !enabled
        ? 0.06
        : pressed
        ? 0.24
        : hovered
        ? 0.18
        : 0.12,
  );

  /// Background activation for neutral actions, without an extra focus outline.
  static Color focusFill(ViewerThemeTokens tokens) => Color.alphaBlend(
    tokens.textPrimary.withValues(alpha: 0.10),
    tokens.controlFill,
  );

  /// Transient feedback is independent of an action's toggled state.
  static Color actionFill(
    ViewerThemeTokens tokens,
    Set<WidgetState> states, {
    Color? idle,
  }) {
    if (states.contains(WidgetState.disabled)) return Colors.transparent;
    if (states.contains(WidgetState.pressed)) return tokens.surfacePressed;
    if (states.contains(WidgetState.focused)) return focusFill(tokens);
    if (states.contains(WidgetState.hovered)) return tokens.surfaceHover;
    return idle ?? Colors.transparent;
  }

  static ButtonStyle icon(
    ViewerThemeTokens tokens, {
    required double size,
    Color? color,
  }) => ButtonStyle(
    fixedSize: WidgetStatePropertyAll(Size.square(size)),
    minimumSize: WidgetStatePropertyAll(Size.square(size)),
    maximumSize: WidgetStatePropertyAll(Size.square(size)),
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? tokens.textDisabled
          : color ?? tokens.textSecondary,
    ),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return Colors.transparent;
      if (states.contains(WidgetState.pressed)) return tokens.surfacePressed;
      if (states.contains(WidgetState.focused)) return focusFill(tokens);
      if (states.contains(WidgetState.hovered)) return tokens.surfaceHover;
      return Colors.transparent;
    }),
    side: const WidgetStatePropertyAll(BorderSide.none),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.controlRadius),
      ),
    ),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    mouseCursor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
    ),
  );
  static ButtonStyle menuItem(BuildContext context, {bool selected = false}) {
    final tokens = ViewerThemeTokens.of(context);
    return ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(
          double.infinity,
          controlHeight(context, minimum: AppTokens.menuItemHeight),
        ),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: AppTokens.space3),
      ),
      alignment: AlignmentDirectional.centerStart,
      visualDensity: VisualDensity.standard,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.menuItemRadius),
        ),
      ),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return tokens.textDisabled;
        return selected ? tokens.accentStrong : tokens.textPrimary;
      }),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return selected
              ? selectionFill(tokens, enabled: false)
              : Colors.transparent;
        }
        if (selected) {
          return selectionFill(
            tokens,
            hovered:
                states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused),
            pressed: states.contains(WidgetState.pressed),
          );
        }
        if (states.contains(WidgetState.pressed)) {
          return tokens.surfacePressed;
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return tokens.surfaceHover;
        }
        return Colors.transparent;
      }),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      side: const WidgetStatePropertyAll(BorderSide.none),
      textStyle: WidgetStatePropertyAll(
        Theme.of(context).textTheme.bodyMedium!.merge(AppTextStyles.control),
      ),
    );
  }

  static ButtonStyle submenu(BuildContext context) => menuItem(context);

  static ButtonStyle toolbarIcon(
    ViewerThemeTokens tokens, {
    required double size,
    bool selected = false,
  }) => ButtonStyle(
    fixedSize: WidgetStatePropertyAll(Size(size, size)),
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.controlRadius),
      ),
    ),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return tokens.textDisabled;
      return selected ? tokens.accentStrong : tokens.textPrimary;
    }),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => actionFill(tokens, states),
    ),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  );

  static ButtonStyle notificationClose(ViewerThemeTokens tokens) =>
      toolbarIcon(tokens, size: AppTokens.iconButtonSize).copyWith(
        minimumSize: const WidgetStatePropertyAll(
          Size.square(AppTokens.iconButtonSize),
        ),
        maximumSize: const WidgetStatePropertyAll(
          Size.square(AppTokens.iconButtonSize),
        ),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? tokens.textDisabled
              : tokens.textSecondary,
        ),
        side: const WidgetStatePropertyAll(BorderSide.none),
      );

  static ButtonStyle bottomIcon(
    ViewerThemeTokens tokens, {
    required double size,
    bool selected = false,
  }) => ButtonStyle(
    fixedSize: WidgetStatePropertyAll(Size(size, size)),
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return tokens.textDisabled;
      return selected ? tokens.accentStrong : tokens.textPrimary;
    }),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => actionFill(tokens, states),
    ),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  );

  static ButtonStyle statusZoom(ViewerThemeTokens tokens) =>
      bottomIcon(tokens, size: 28).copyWith(
        fixedSize: const WidgetStatePropertyAll(Size(72, 28)),
        minimumSize: const WidgetStatePropertyAll(Size(72, 28)),
      );

  static ButtonStyle windowIcon(
    ViewerThemeTokens tokens, {
    required double size,
    required Color chromeColor,
    bool flushSquare = false,
    bool closeButton = false,
    bool selected = false,
  }) => ButtonStyle(
    fixedSize: WidgetStatePropertyAll(Size(size, size)),
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          flushSquare ? 0 : AppTokens.controlRadius,
        ),
      ),
    ),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return tokens.textDisabled;
      }
      if (closeButton &&
          (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed))) {
        return tokens.onDanger;
      }
      return selected ? tokens.accentStrong : chromeColor;
    }),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return actionFill(tokens, states);
      }
      if (closeButton &&
          (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed))) {
        return states.contains(WidgetState.pressed)
            ? Color.alphaBlend(
                AppColors.shadow.withValues(alpha: 0.20),
                tokens.dangerFill,
              )
            : tokens.dangerFill;
      }
      return actionFill(tokens, states);
    }),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  );

  static ButtonStyle edgeNavigation(
    ViewerThemeTokens tokens, {
    required bool isDark,
  }) => ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size.square(48)),
    maximumSize: const WidgetStatePropertyAll(Size.square(48)),
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    shape: const WidgetStatePropertyAll(CircleBorder()),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return tokens.textDisabled;
      }
      return tokens.textPrimary;
    }),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return tokens.navigationOverlay.withValues(alpha: .28);
      }
      if (states.contains(WidgetState.pressed)) {
        return tokens.surfacePressed;
      }
      if (states.contains(WidgetState.focused)) return focusFill(tokens);
      if (states.contains(WidgetState.hovered)) {
        return tokens.surfaceHover;
      }
      return tokens.navigationOverlay.withValues(alpha: isDark ? .86 : .82);
    }),
    side: const WidgetStatePropertyAll(BorderSide.none),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  );

  static ButtonStyle menuAction(
    ViewerThemeTokens tokens, {
    bool selected = false,
  }) => ButtonStyle(
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
    minimumSize: const WidgetStatePropertyAll(Size(60, 60)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.menuItemRadius),
      ),
    ),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => actionFill(tokens, states),
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? tokens.textDisabled
          : tokens.textPrimary,
    ),
    iconColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? tokens.textDisabled
          : selected
          ? tokens.accentStrong
          : tokens.textPrimary,
    ),
    side: const WidgetStatePropertyAll(BorderSide.none),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  );

  static Color menuShadow(ViewerThemeTokens tokens) => Colors.black.withValues(
    alpha: tokens.surfaceElevated.computeLuminance() < 0.5 ? 0.24 : 0.12,
  );

  static MenuStyle menu(ViewerThemeTokens tokens) => MenuStyle(
    elevation: const WidgetStatePropertyAll(8),
    padding: const WidgetStatePropertyAll(EdgeInsets.all(AppTokens.space1)),
    backgroundColor: WidgetStatePropertyAll(tokens.surfaceElevated),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: WidgetStatePropertyAll(menuShadow(tokens)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.menuRadius),
        side: BorderSide(color: tokens.border),
      ),
    ),
  );
  static ButtonStyle sortTrigger(
    ViewerThemeTokens tokens, {
    required double size,
    Color? foregroundColor,
  }) => ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return tokens.textDisabled;
      return foregroundColor ?? tokens.textPrimary;
    }),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => actionFill(tokens, states, idle: tokens.controlFill),
    ),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
    minimumSize: WidgetStatePropertyAll(Size(0, size)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.controlRadius),
      ),
    ),
    side: const WidgetStatePropertyAll(BorderSide.none),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    mouseCursor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
    ),
  );
}
