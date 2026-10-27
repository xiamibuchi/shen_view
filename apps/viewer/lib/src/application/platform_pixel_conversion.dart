import 'dart:math' as math;
import 'dart:typed_data';

/// Pure pixel work; run in a short-lived isolate, never on the UI isolate.
Uint8List toneMapPlatformFloatPixels((Uint8List, int, int) input) {
  final (pixels, width, height) = input;
  if (width < 1 || height < 1 || pixels.length != width * height * 16) {
    throw const FormatException('Invalid platform float pixels');
  }
  final floats = ByteData.sublistView(pixels);
  final output = Uint8List(width * height * 4);
  for (var pixel = 0; pixel < width * height; pixel++) {
    for (var channel = 0; channel < 3; channel++) {
      var value = floats.getFloat32(pixel * 16 + channel * 4, Endian.little);
      if (!value.isFinite || value < 0) value = 0;
      value = value / (1 + value);
      value = math.pow(value, 1 / 2.2).toDouble();
      output[pixel * 4 + channel] = (value * 255).round().clamp(0, 255);
    }
    var alpha = floats.getFloat32(pixel * 16 + 12, Endian.little);
    if (!alpha.isFinite) alpha = 1;
    output[pixel * 4 + 3] = (alpha.clamp(0, 1) * 255).round();
  }
  return output;
}
