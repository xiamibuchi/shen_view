import 'dart:typed_data';
import 'dart:ui' as ui;

import '../domain/picked_color.dart';
export '../domain/picked_color.dart';

class ColorSamplePatch {
  const ColorSamplePatch(this.pixels);
  static const side = 9;
  static const radius = side ~/ 2;
  final List<PickedColor?> pixels;
  PickedColor get color => pixels[radius * side + radius]!;
}

/// Reads only a 9x9 patch of the already decoded frame. No file reads, codecs,
/// full-size CPU buffers, screen capture, interpolation or canvas background.
class ColorPickerService {
  Future<ColorSamplePatch?> capture(ui.Image image, int x, int y) async {
    if (x < 0 || y < 0 || x >= image.width || y >= image.height) return null;
    const side = ColorSamplePatch.side;
    const radius = ColorSamplePatch.radius;
    final left = x - radius, top = y - radius;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.clipRect(const ui.Rect.fromLTWH(0, 0, side * 1.0, side * 1.0));
    canvas.drawImage(
      image,
      ui.Offset(-left.toDouble(), -top.toDouble()),
      ui.Paint()
        ..filterQuality = ui.FilterQuality.none
        ..blendMode = ui.BlendMode.src,
    );
    final picture = recorder.endRecording();
    ui.Image? patch;
    try {
      patch = await picture.toImage(side, side);
      final data = await patch.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (data == null) return null;
      final bytes = Uint8List.sublistView(data);
      return ColorSamplePatch(
        List.generate(side * side, (index) {
          final sx = left + index % side, sy = top + index ~/ side;
          if (sx < 0 || sy < 0 || sx >= image.width || sy >= image.height) {
            return null;
          }
          final offset = index * 4;
          return PickedColor(
            red: bytes[offset],
            green: bytes[offset + 1],
            blue: bytes[offset + 2],
            alpha: bytes[offset + 3],
          );
        }),
      );
    } finally {
      patch?.dispose();
      picture.dispose();
    }
  }
}
