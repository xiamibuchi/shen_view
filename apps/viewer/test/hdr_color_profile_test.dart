import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/hdr_source_profile.dart';

void main() {
  test('Rec.2020 converts to extended Rec.709 without gamut clipping', () {
    final matrix = HdrSourceProfile.toLinear709([
      0.708,
      0.292,
      0.170,
      0.797,
      0.131,
      0.046,
      0.3127,
      0.329,
    ]);
    expect(matrix[0], closeTo(1.66049, 0.0001));
    expect(matrix[1], closeTo(-0.58764, 0.0001));
    expect(matrix[4], closeTo(1.13290, 0.0001));
    expect(matrix[7], closeTo(-0.10058, 0.0001));
    for (var r = 0; r < 3; r++) {
      expect(
        matrix[r * 3] + matrix[r * 3 + 1] + matrix[r * 3 + 2],
        closeTo(1, 0.0001),
      );
    }
  });

  test('D60 to D65 white adaptation preserves a neutral highlight', () {
    final matrix = HdrSourceProfile.toLinear709([
      0.713,
      0.293,
      0.165,
      0.830,
      0.128,
      0.044,
      0.32168,
      0.33767,
    ]);
    for (var r = 0; r < 3; r++) {
      expect(
        matrix[r * 3] + matrix[r * 3 + 1] + matrix[r * 3 + 2],
        closeTo(1, 0.0001),
      );
    }
  });

  test('EXR sample header supplies its source chromaticities', () {
    final bytes = File('testdata/formats/hdr_highlights.exr').readAsBytesSync();
    final primaries = HdrSourceProfile.exrChromaticities(bytes);
    expect(primaries, isNotNull);
    final matrix = HdrSourceProfile.toLinear709(primaries!);
    for (var i = 0; i < 9; i++) {
      expect(matrix[i], closeTo(i % 4 == 0 ? 1 : 0, 0.0001));
    }
  });

  test('malformed source color metadata degrades instead of yielding NaN', () {
    expect(
      () => HdrSourceProfile.exrChromaticities(Uint8List(8)),
      throwsFormatException,
    );
    expect(
      () => HdrSourceProfile.toLinear709(List.filled(8, 0.5)),
      throwsFormatException,
    );
    expect(
      () => HdrSourceProfile.toLinear709(List.filled(8, double.nan)),
      throwsFormatException,
    );
  });
}
