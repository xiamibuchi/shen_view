import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// EXR/RGBE chromaticities -> linear Rec.709 with Bradford white adaptation.
/// This handles source primaries only. DWM / ColorSync handles the output
/// display transform from the explicitly tagged native surface.
class HdrSourceProfile {
  static const rec709 = [0.64, 0.33, 0.30, 0.60, 0.15, 0.06, 0.3127, 0.3290];

  static Future<List<double>?> read(String path) async {
    final file = await File(path).open();
    late Uint8List bytes;
    try {
      bytes = await file.read(256 * 1024);
    } finally {
      await file.close();
    }
    List<double>? primaries;
    if (path.toLowerCase().endsWith('.exr')) {
      primaries = exrChromaticities(bytes);
    } else {
      final header = latin1.decode(
        bytes.sublist(0, bytes.length.clamp(0, 8192)),
      );
      final match = RegExp(
        r'^PRIMARIES=\s*([^\r\n]+)',
        multiLine: true,
      ).firstMatch(header);
      if (match != null) {
        primaries = match
            .group(1)!
            .trim()
            .split(RegExp(r'\s+'))
            .map(double.parse)
            .toList();
      }
    }
    if (primaries == null) {
      return null; // Explicit untagged-input policy: Rec.709.
    }
    return toLinear709(primaries);
  }

  static List<double>? exrChromaticities(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (bytes.length < 8 || data.getUint32(0, Endian.little) != 20000630) {
      throw const FormatException('EXR header');
    }
    var offset = 8;
    String string() {
      final start = offset;
      while (offset < bytes.length &&
          bytes[offset] != 0 &&
          offset - start < 256) {
        offset++;
      }
      if (offset >= bytes.length || offset - start >= 256) {
        throw const FormatException('EXR attribute name');
      }
      return latin1.decode(bytes.sublist(start, offset++));
    }

    while (offset < bytes.length) {
      final name = string();
      if (name.isEmpty) return null;
      final type = string();
      if (offset + 4 > bytes.length) {
        throw const FormatException('EXR attribute');
      }
      final size = data.getUint32(offset, Endian.little);
      offset += 4;
      if (offset + size > bytes.length) {
        throw const FormatException('EXR header budget');
      }
      if (name == 'chromaticities') {
        if (type != 'chromaticities' || size != 32) {
          throw const FormatException('EXR chromaticities');
        }
        return [
          for (var i = 0; i < 8; i++)
            data.getFloat32(offset + i * 4, Endian.little),
        ];
      }
      offset += size;
    }
    throw const FormatException('EXR header budget');
  }

  static List<double> toLinear709(List<double> p) {
    if (p.length != 8 ||
        p.any((v) => !v.isFinite) ||
        [1, 3, 5, 7].any((i) => p[i] <= 0 || p[i] > 1)) {
      throw const FormatException('HDR chromaticities');
    }
    List<double> xyz(double x, double y) => [x / y, 1, (1 - x - y) / y];
    List<double> rgbToXyz(List<double> p) {
      final r = xyz(p[0], p[1]), g = xyz(p[2], p[3]), b = xyz(p[4], p[5]);
      final basis = [
        for (var i = 0; i < 3; i++) ...[r[i], g[i], b[i]],
      ];
      final scale = _vector(_inverse(basis), xyz(p[6], p[7]));
      return [
        for (var row = 0; row < 3; row++)
          for (var col = 0; col < 3; col++) basis[row * 3 + col] * scale[col],
      ];
    }

    const bradford = [
      0.8951,
      0.2664,
      -0.1614,
      -0.7502,
      1.7135,
      0.0367,
      0.0389,
      -0.0685,
      1.0296,
    ];
    final from = _vector(bradford, xyz(p[6], p[7]));
    final to = _vector(bradford, xyz(rec709[6], rec709[7]));
    if (from.any((v) => v.abs() < 1e-10)) {
      throw const FormatException('HDR white point');
    }
    final diagonal = [
      for (var r = 0; r < 3; r++)
        for (var c = 0; c < 3; c++) r == c ? to[r] / from[r] : 0.0,
    ];
    final adaptation = _multiply(
      _inverse(bradford),
      _multiply(diagonal, bradford),
    );
    final result = _multiply(
      _inverse(rgbToXyz(rec709)),
      _multiply(adaptation, rgbToXyz(p)),
    );
    if (result.any((v) => !v.isFinite || v.abs() > 100)) {
      throw const FormatException('HDR color matrix');
    }
    return result;
  }
}

List<double> _vector(List<double> m, List<double> v) => [
  for (var r = 0; r < 3; r++)
    m[r * 3] * v[0] + m[r * 3 + 1] * v[1] + m[r * 3 + 2] * v[2],
];
List<double> _multiply(List<double> a, List<double> b) => [
  for (var r = 0; r < 3; r++)
    for (var c = 0; c < 3; c++)
      a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c],
];
List<double> _inverse(List<double> m) {
  final a = m[0],
      b = m[1],
      c = m[2],
      d = m[3],
      e = m[4],
      f = m[5],
      g = m[6],
      h = m[7],
      i = m[8];
  final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
  if (!det.isFinite || det.abs() < 1e-12) {
    throw const FormatException('Singular HDR primaries');
  }
  return [
    e * i - f * h,
    c * h - b * i,
    b * f - c * e,
    f * g - d * i,
    a * i - c * g,
    c * d - a * f,
    d * h - e * g,
    b * g - a * h,
    a * e - b * d,
  ].map((v) => v / det).toList();
}
