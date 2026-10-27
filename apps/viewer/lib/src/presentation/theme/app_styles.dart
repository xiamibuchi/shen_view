import 'package:flutter/material.dart';

import '../../domain/picked_color.dart';

/// Image data colors are independent of application surface/theme colors.
abstract final class AppImageColors {
  static Color sampled(PickedColor value) =>
      Color.fromARGB(value.alpha, value.red, value.green, value.blue);
}

/// Shared typography; each caller supplies its semantic foreground color.
class AppTextStyles {
  const AppTextStyles._();

  static const compactTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  static const control = TextStyle(fontSize: 14, height: 20 / 14);
  static const caption = TextStyle(fontSize: 12, height: 1.4);
  static const body = TextStyle(fontSize: 14);
  static const bodySmall = TextStyle(fontSize: 13);
  static const code = TextStyle(fontSize: 12.5);
  static const bodyLarge = TextStyle(fontSize: 15);
  static const label = TextStyle(fontSize: 12);
  static const finePrint = TextStyle(fontSize: 11);
  static const thumbnailText = TextStyle(fontSize: 10);
  static const shortcut = TextStyle(fontSize: 9);
  static const subtitle = TextStyle(fontSize: 16);
  static const sectionTitle = TextStyle(fontSize: 18);
  static const dialogTitle = TextStyle(
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w600,
  );
  static const pageTitle = TextStyle(fontSize: 22);

  /// Subtitle-style labels remain legible over both bright and dark images.
  static final thumbnailCaption = TextStyle(
    color: Colors.white,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    shadows: [
      Shadow(
        color: Colors.black.withValues(alpha: 0.72),
        blurRadius: 1.5,
        offset: const Offset(0, 1),
      ),
      Shadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 3),
    ],
  );
}

/// Theme-independent compositing colors, shared by surfaces and painters.
abstract final class AppColors {
  static const transparent = Colors.transparent;
  static const shadow = Colors.black;
}

class AppDecorations {
  const AppDecorations._();

  /// Printed paper remains white in both themes, independently of app surfaces.
  static final printPaper = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(2),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.22),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ],
  );
}
