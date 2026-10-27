import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'app_tokens.dart';

@immutable
class ViewerThemeTokens extends ThemeExtension<ViewerThemeTokens> {
  const ViewerThemeTokens({
    required this.appBackground,
    required this.shellSurface,
    required this.canvasBackground,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceSubtle,
    required this.controlFill,
    required this.fieldFill,
    required this.navigationSurface,
    required this.navigationOverlay,
    required this.navigationBorder,
    required this.surfaceHover,
    required this.surfacePressed,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.accent,
    required this.accentStrong,
    required this.onAccent,
    required this.danger,
    required this.dangerFill,
    required this.onDanger,
    required this.warning,
    required this.success,
    required this.focusRing,
  });

  final Color appBackground;
  final Color shellSurface;
  final Color canvasBackground;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceSubtle;
  final Color controlFill;
  final Color fieldFill;
  final Color navigationSurface;
  final Color navigationOverlay;
  final Color navigationBorder;
  final Color surfaceHover;
  final Color surfacePressed;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;
  final Color accent;
  final Color accentStrong;
  final Color onAccent;
  final Color danger;
  final Color dangerFill;
  final Color onDanger;
  final Color warning;
  final Color success;
  final Color focusRing;

  static ViewerThemeTokens of(BuildContext context) {
    return Theme.of(context).extension<ViewerThemeTokens>()!;
  }

  @override
  ViewerThemeTokens copyWith({
    Color? appBackground,
    Color? shellSurface,
    Color? canvasBackground,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceSubtle,
    Color? controlFill,
    Color? fieldFill,
    Color? navigationSurface,
    Color? navigationOverlay,
    Color? navigationBorder,
    Color? surfaceHover,
    Color? surfacePressed,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? accent,
    Color? accentStrong,
    Color? onAccent,
    Color? danger,
    Color? dangerFill,
    Color? onDanger,
    Color? warning,
    Color? success,
    Color? focusRing,
  }) {
    return ViewerThemeTokens(
      appBackground: appBackground ?? this.appBackground,
      shellSurface: shellSurface ?? this.shellSurface,
      canvasBackground: canvasBackground ?? this.canvasBackground,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      controlFill: controlFill ?? this.controlFill,
      fieldFill: fieldFill ?? this.fieldFill,
      navigationSurface: navigationSurface ?? this.navigationSurface,
      navigationOverlay: navigationOverlay ?? this.navigationOverlay,
      navigationBorder: navigationBorder ?? this.navigationBorder,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      surfacePressed: surfacePressed ?? this.surfacePressed,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textDisabled: textDisabled ?? this.textDisabled,
      accent: accent ?? this.accent,
      accentStrong: accentStrong ?? this.accentStrong,
      onAccent: onAccent ?? this.onAccent,
      danger: danger ?? this.danger,
      dangerFill: dangerFill ?? this.dangerFill,
      onDanger: onDanger ?? this.onDanger,
      warning: warning ?? this.warning,
      success: success ?? this.success,
      focusRing: focusRing ?? this.focusRing,
    );
  }

  @override
  ViewerThemeTokens lerp(covariant ViewerThemeTokens? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return ViewerThemeTokens(
      appBackground: mix(appBackground, other.appBackground),
      shellSurface: mix(shellSurface, other.shellSurface),
      canvasBackground: mix(canvasBackground, other.canvasBackground),
      surface: mix(surface, other.surface),
      surfaceElevated: mix(surfaceElevated, other.surfaceElevated),
      surfaceSubtle: mix(surfaceSubtle, other.surfaceSubtle),
      controlFill: mix(controlFill, other.controlFill),
      fieldFill: mix(fieldFill, other.fieldFill),
      navigationSurface: mix(navigationSurface, other.navigationSurface),
      navigationOverlay: mix(navigationOverlay, other.navigationOverlay),
      navigationBorder: mix(navigationBorder, other.navigationBorder),
      surfaceHover: mix(surfaceHover, other.surfaceHover),
      surfacePressed: mix(surfacePressed, other.surfacePressed),
      border: mix(border, other.border),
      borderStrong: mix(borderStrong, other.borderStrong),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      textDisabled: mix(textDisabled, other.textDisabled),
      accent: mix(accent, other.accent),
      accentStrong: mix(accentStrong, other.accentStrong),
      onAccent: mix(onAccent, other.onAccent),
      danger: mix(danger, other.danger),
      dangerFill: mix(dangerFill, other.dangerFill),
      onDanger: mix(onDanger, other.onDanger),
      warning: mix(warning, other.warning),
      success: mix(success, other.success),
      focusRing: mix(focusRing, other.focusRing),
    );
  }
}

class AppTheme {
  const AppTheme._();

  static ThemeData light({TargetPlatform? platform}) => _build(
    Brightness.light,
    const ViewerThemeTokens(
      appBackground: Color(0xFFF3F3F3),
      shellSurface: Color(0xFFF3F3F3),
      canvasBackground: Color(0xFFF3F3F3),
      surface: Color(0xFFF3F3F3),
      surfaceElevated: Color(0xFFFFFFFF),
      surfaceSubtle: Color(0xFFF3F3F3),
      controlFill: Color(0xFFFAFAFA),
      fieldFill: Color(0xFFFAFAFA),
      navigationSurface: Color(0xFFF3F3F3),
      navigationOverlay: Color(0xFFFFFFFF),
      navigationBorder: Color(0xFFD6D6D6),
      surfaceHover: Color(0xFFEEEEEE),
      surfacePressed: Color(0xFFE5E5E5),
      border: Color(0xFFD6D6D6),
      borderStrong: Color(0xFF8A8A8A),
      textPrimary: Color(0xFF1A1A1A),
      textSecondary: Color(0xFF525252),
      textTertiary: Color(0xFF707070),
      textDisabled: Color(0xFFA0A0A0),
      accent: Color(0xFF0F6FEF),
      accentStrong: Color(0xFF0754BF),
      onAccent: Color(0xFFFFFFFF),
      danger: Color(0xFFC93636),
      dangerFill: Color(0xFFC93636),
      onDanger: Color(0xFFFFFFFF),
      warning: Color(0xFFB7791F),
      success: Color(0xFF2F855A),
      focusRing: Color(0xFF333333),
    ),
    platform: platform,
  );

  static ThemeData dark({TargetPlatform? platform}) => _build(
    Brightness.dark,
    const ViewerThemeTokens(
      appBackground: Color(0xFF181818),
      shellSurface: Color(0xFF1F1F1F),
      canvasBackground: Color(0xFF1F1F1F),
      surface: Color(0xFF1F1F1F),
      surfaceElevated: Color(0xFF282828),
      surfaceSubtle: Color(0xFF1F1F1F),
      controlFill: Color(0xFF333333),
      fieldFill: Color(0xFF242424),
      navigationSurface: Color(0xFF1F1F1F),
      navigationOverlay: Color(0xFF282828),
      navigationBorder: Color(0xFF3D3D3D),
      surfaceHover: Color(0xFF383838),
      surfacePressed: Color(0xFF2E2E2E),
      border: Color(0xFF3D3D3D),
      borderStrong: Color(0xFF707070),
      textPrimary: Color(0xFFF5F5F5),
      textSecondary: Color(0xFFC6C6C6),
      textTertiary: Color(0xFFA3A3A3),
      textDisabled: Color(0xFF757575),
      accent: Color(0xFF0F6FEF),
      accentStrong: Color(0xFF8ABEFF),
      onAccent: Color(0xFFFFFFFF),
      danger: Color(0xFFFF8A8A),
      dangerFill: Color(0xFFC93636),
      onDanger: Color(0xFFFFFFFF),
      warning: Color(0xFFE0A458),
      success: Color(0xFF66B58A),
      focusRing: Color(0xFFF5F5F5),
    ),
    platform: platform,
  );

  static ThemeData _build(
    Brightness brightness,
    ViewerThemeTokens tokens, {
    TargetPlatform? platform,
  }) {
    final targetPlatform = platform ?? defaultTargetPlatform;
    final (fontFamily, fallbacks) = switch (targetPlatform) {
      TargetPlatform.windows => (
        'Segoe UI Variable',
        ['Segoe UI', 'Microsoft YaHei UI', 'Microsoft YaHei', 'Segoe UI Emoji'],
      ),
      TargetPlatform.macOS || TargetPlatform.iOS => (
        '.AppleSystemUIFont',
        ['PingFang SC', 'Apple Color Emoji'],
      ),
      TargetPlatform.linux => (
        'Noto Sans',
        ['Noto Sans CJK SC', 'Noto Color Emoji'],
      ),
      TargetPlatform.android || TargetPlatform.fuchsia => (
        'Roboto',
        ['Noto Sans CJK SC', 'Noto Color Emoji'],
      ),
    };
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: tokens.accent,
          brightness: brightness,
        ).copyWith(
          primary: tokens.accent,
          onPrimary: tokens.onAccent,
          error: tokens.dangerFill,
          onError: tokens.onDanger,
          surface: tokens.surface,
          onSurface: tokens.textPrimary,
          outline: tokens.border,
          surfaceTint: Colors.transparent,
        );
    return ThemeData(
      useMaterial3: true,
      platform: targetPlatform,
      fontFamily: fontFamily,
      fontFamilyFallback: fallbacks,
      splashFactory: NoSplash.splashFactory,
      brightness: brightness,
      colorScheme: colorScheme,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: tokens.accentStrong,
        selectionColor: tokens.accent.withValues(alpha: 0.24),
        selectionHandleColor: tokens.accentStrong,
      ),
      // The viewer shell stays continuous around the transparent image
      // viewport; appBackground remains available for outer surfaces.
      scaffoldBackgroundColor: tokens.shellSurface,
      canvasColor: tokens.canvasBackground,
      dividerColor: tokens.border,
      tooltipTheme: TooltipThemeData(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.space2,
          vertical: AppTokens.space1,
        ),
        margin: const EdgeInsets.symmetric(horizontal: AppTokens.space2),
        waitDuration: const Duration(milliseconds: 360),
        showDuration: const Duration(seconds: 3),
        verticalOffset: AppTokens.space2,
        preferBelow: false,
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fallbacks,
          color: tokens.textPrimary,
          fontSize: 12,
          height: 1.2,
        ),
        decoration: BoxDecoration(
          color: tokens.surfaceElevated,
          border: Border.all(color: tokens.border),
          borderRadius: BorderRadius.circular(AppTokens.menuItemRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[tokens],
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.surface,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: AppTokens.dialogElevation,
        shadowColor: Colors.black.withValues(alpha: 0.34),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.dialogRadius),
          side: BorderSide(color: tokens.border.withValues(alpha: 0.9)),
        ),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fallbacks,
          color: tokens.textPrimary,
          fontSize: 20,
          height: 1.2,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fallbacks,
          color: tokens.textSecondary,
          fontSize: 14,
          height: 1.4,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        clipBehavior: Clip.antiAlias,
        barrierColor: Colors.black.withValues(alpha: 0.54),
      ),
      iconTheme: IconThemeData(color: tokens.textSecondary),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: tokens.textPrimary),
        bodyMedium: TextStyle(color: tokens.textSecondary),
        bodySmall: TextStyle(color: tokens.textTertiary),
        titleLarge: TextStyle(color: tokens.textPrimary),
        titleMedium: TextStyle(color: tokens.textPrimary),
      ),
    );
  }
}
