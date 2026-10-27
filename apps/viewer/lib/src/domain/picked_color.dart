import 'dart:math' as math;

enum ColorCopyFormat {
  hex,
  rgb,
  rgba,
  hsl,
  hsla,
  hsv,
  yuv;

  static ColorCopyFormat fromSetting(Object? value) =>
      values.where((format) => format.name == value).firstOrNull ?? hex;
}

class PickedColor {
  const PickedColor({
    required this.red,
    required this.green,
    required this.blue,
    required this.alpha,
  });
  final int red, green, blue, alpha;
  String get hex => '#${[red, green, blue].map(_hex).join()}';
  String get hexAlpha => '$hex${_hex(alpha)}';
  String get opacity => '${(alpha / 255 * 100).toStringAsFixed(1)}%';
  static String _hex(int value) =>
      value.toRadixString(16).padLeft(2, '0').toUpperCase();
  String format(ColorCopyFormat format) => switch (format) {
    ColorCopyFormat.hex => hex,
    ColorCopyFormat.rgb => 'rgb($red, $green, $blue)',
    ColorCopyFormat.rgba =>
      'rgba($red, $green, $blue, ${_number(alpha / 255, 3)})',
    ColorCopyFormat.hsl => _cylindrical(),
    ColorCopyFormat.hsla => _cylindrical(withAlpha: true),
    ColorCopyFormat.hsv => _cylindrical(hsv: true),
    ColorCopyFormat.yuv => _yuv(),
  };
  String _cylindrical({bool hsv = false, bool withAlpha = false}) {
    final r = red / 255, g = green / 255, b = blue / 255;
    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    final delta = max - min;
    var hue = delta == 0
        ? 0.0
        : max == r
        ? ((g - b) / delta) % 6
        : max == g
        ? (b - r) / delta + 2
        : (r - g) / delta + 4;
    hue = (hue * 60) % 360;
    final light = (max + min) / 2;
    final saturation = delta == 0
        ? 0.0
        : delta / (hsv ? max : (1 - (2 * light - 1).abs()));
    final name = hsv
        ? 'hsv'
        : withAlpha
        ? 'hsla'
        : 'hsl';
    final opacity = withAlpha ? ', ${_number(alpha / 255, 3)}' : '';
    return '$name(${_number(hue, 1)}, ${_number(saturation * 100, 1)}%, ${_number((hsv ? max : light) * 100, 1)}%$opacity)';
  }

  String _yuv() {
    final r = red / 255, g = green / 255, b = blue / 255;
    // BT.601 luma with centered analog U/V, not limited-range video YCbCr.
    // OpenCV's RGB -> YUV uses these coefficients plus a chroma offset;
    // this numeric representation keeps neutral U/V at zero.
    final y = 0.299 * r + 0.587 * g + 0.114 * b;
    final u = 0.492 * (b - y), v = 0.877 * (r - y);
    return 'yuv(${_number(y, 4)}, ${_number(u, 4)}, ${_number(v, 4)})';
  }

  static String _number(double value, int decimals) {
    if (value.abs() < 0.5 * math.pow(10, -decimals)) return '0';
    final fixed = value.toStringAsFixed(decimals);
    return fixed.contains('.')
        ? fixed
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '')
        : fixed;
  }
}
