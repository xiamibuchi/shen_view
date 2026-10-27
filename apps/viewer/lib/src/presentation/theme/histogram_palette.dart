import 'package:flutter/material.dart';

/// Data colors stay distinct from command/status colors in both themes.
abstract final class HistogramPalette {
  static const tonalRange = [Color(0xFF000000), Color(0xFFFFFFFF)];

  static List<Color> channels(Brightness brightness) =>
      brightness == Brightness.dark
      ? const [Color(0xFFFF7E89), Color(0xFF73CF92), Color(0xFF7EAFFF)]
      : const [Color(0xFFBD3348), Color(0xFF24834A), Color(0xFF3166C5)];
}
