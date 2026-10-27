import 'dart:typed_data';

/// 256 display-referred bins. Alpha weights exclude invisible RGB and keep
/// translucent edges from dominating an otherwise opaque image.
class ImageHistogram {
  ImageHistogram._(
    this.luminance,
    this.red,
    this.green,
    this.blue,
    this.samples,
  );

  final List<int> luminance;
  final List<int> red;
  final List<int> green;
  final List<int> blue;
  final int samples;

  static ImageHistogram fromRgba(Uint8List rgba) {
    if (rgba.length % 4 != 0) {
      throw ArgumentError('Expected straight RGBA pixels');
    }
    final luminance = List.filled(256, 0);
    final red = List.filled(256, 0);
    final green = List.filled(256, 0);
    final blue = List.filled(256, 0);
    var samples = 0;
    for (var i = 0; i < rgba.length; i += 4) {
      final alpha = rgba[i + 3];
      if (alpha == 0) continue;
      final r = rgba[i];
      final g = rgba[i + 1];
      final b = rgba[i + 2];
      final luma = (r * 2126 + g * 7152 + b * 722 + 5000) ~/ 10000;
      luminance[luma] += alpha;
      red[r] += alpha;
      green[g] += alpha;
      blue[b] += alpha;
      samples++;
    }
    return ImageHistogram._(luminance, red, green, blue, samples);
  }
}
