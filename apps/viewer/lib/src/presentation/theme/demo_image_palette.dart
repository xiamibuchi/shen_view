import 'package:flutter/painting.dart';

/// Illustration pigments for the review fixture, independent of UI surfaces.
class DemoImagePalette {
  const DemoImagePalette({
    required this.sky,
    required this.sun,
    required this.backMountain,
    required this.frontMountain,
    required this.ground,
  });
  final List<Color> sky;
  final Color sun;
  final Color backMountain;
  final Color frontMountain;
  final Color ground;

  static const light = DemoImagePalette(
    sky: [Color(0xFF8DD7F7), Color(0xFFE7F5FA)],
    sun: Color(0xFFFFD36A),
    backMountain: Color(0xFF6D9D8E),
    frontMountain: Color(0xFF315E5A),
    ground: Color(0xFF294C44),
  );
  static const dark = DemoImagePalette(
    sky: [Color(0xFF19344F), Color(0xFF526B78)],
    sun: Color(0xFFE7B55C),
    backMountain: Color(0xFF304D4F),
    frontMountain: Color(0xFF1F3437),
    ground: Color(0xFF152728),
  );
}
