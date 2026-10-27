import 'dart:math' as math;

/// ITU-R BT.2100 signal conversion. Working RGB is linear, D65, white=203 nits.
class HdrTransfer {
  static const referenceWhite = 203.0;
  static const rec2020 = [
    0.708,
    0.292,
    0.170,
    0.797,
    0.131,
    0.046,
    0.3127,
    0.329,
  ];
  static const displayP3 = [
    0.680,
    0.320,
    0.265,
    0.690,
    0.150,
    0.060,
    0.3127,
    0.329,
  ];

  /// ST 2084 EOTF, absolute cd/m².
  static double pqToNits(double signal) {
    if (!signal.isFinite) return 0;
    const m1 = 2610 / 16384, m2 = 2523 / 32;
    const c1 = 3424 / 4096, c2 = 2413 / 128, c3 = 2392 / 128;
    final v = math.pow(signal.clamp(0, 1), 1 / m2).toDouble();
    return 10000 *
        math.pow(math.max(v - c1, 0) / (c2 - c3 * v), 1 / m1).toDouble();
  }

  static double nitsToPq(double nits) {
    if (!nits.isFinite) return 0;
    const m1 = 2610 / 16384, m2 = 2523 / 32;
    const c1 = 3424 / 4096, c2 = 2413 / 128, c3 = 2392 / 128;
    final v = math.pow((nits / 10000).clamp(0, 1), m1).toDouble();
    return math.pow((c1 + c2 * v) / (1 + c3 * v), m2).toDouble();
  }

  /// HLG inverse OETF, scene linear (not yet display light).
  static double hlgToScene(double signal) {
    if (!signal.isFinite) return 0;
    final e = signal.clamp(0.0, 1.0);
    const a = 0.17883277, b = 0.28466892, c = 0.55991073;
    return e <= 0.5 ? e * e / 3 : (math.exp((e - c) / a) + b) / 12;
  }

  /// BT.2100 OOTF, reference display peak 1000 cd/m², system gamma 1.2.
  /// Apply the gain from luminance to all channels, never gamma each channel.
  static List<double> hlgToDisplayLinear2020(List<double> signal) {
    final rgb = signal.map(hlgToScene).toList();
    final y = 0.2627 * rgb[0] + 0.6780 * rgb[1] + 0.0593 * rgb[2];
    final gain = y <= 0 ? 0.0 : 1000 / referenceWhite * math.pow(y, 0.2);
    return rgb.map((v) => v * gain).toList();
  }

  static double linearToSrgb(double v) =>
      v <= 0.0031308 ? 12.92 * v : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
}
