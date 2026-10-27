// Independent fixture verifier. Does not use the viewer's HDR decoder,
// transfer functions, color matrix, tone mapper, or ImageMagick.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as imaging;
import 'package:shen_view/src/application/codec_process.dart';

const _levels = [0.0, 100.0, 203.0, 400.0, 700.0, 1000.0];
const _rows = [
  [1.0, 1.0, 1.0],
  [1.0, 0.25, 0.05],
  [0.05, 0.4, 1.0],
];
const _to2020 = [
  0.6274039,
  0.3292830,
  0.0433131,
  0.0690973,
  0.9195404,
  0.0113623,
  0.0163914,
  0.0880133,
  0.8955953,
];
const _to709 = [
  1.660491,
  -0.587641,
  -0.072850,
  -0.124550,
  1.132900,
  -0.008349,
  -0.018151,
  -0.100579,
  1.118730,
];

List<double> _matrix(List<double> m, List<double> rgb) => [
  for (var row = 0; row < 3; row++)
    m[row * 3] * rgb[0] + m[row * 3 + 1] * rgb[1] + m[row * 3 + 2] * rgb[2],
];

double _pq(double nits) {
  final p = math.pow(nits.clamp(0, 10000) / 10000, 2610 / 16384);
  return math
      .pow((3424 / 4096 + 2413 / 128 * p) / (1 + 2392 / 128 * p), 2523 / 32)
      .toDouble();
}

List<double> _signal(int row, int patch, bool hlg) {
  final rgb = _rows[row].map((c) => c * _levels[patch]).toList();
  if (!hlg) return _matrix(_to2020, rgb).map(_pq).toList();
  final display = rgb.map((c) => c / 1000).toList();
  final luminance =
      display[0] * 0.2627 + display[1] * 0.6780 + display[2] * 0.0593;
  final gain = luminance == 0 ? 0.0 : math.pow(luminance, -1 / 6);
  return display.map((c) {
    final scene = c * gain;
    final signal = scene <= 1 / 12
        ? math.sqrt(3 * scene)
        : 0.17883277 * math.log(12 * scene - 0.28466892) + 0.55991073;
    return signal.clamp(0.0, 1.0);
  }).toList();
}

List<double> _hlgDisplay(List<double> signal) {
  final scene = signal
      .map(
        (v) => v <= 0.5
            ? v * v / 3
            : (math.exp((v - 0.55991073) / 0.17883277) + 0.28466892) / 12,
      )
      .toList();
  final luminance = 0.2627 * scene[0] + 0.6780 * scene[1] + 0.0593 * scene[2];
  final gain = 1000 / 203 * math.pow(luminance, 0.2);
  return scene.map((v) => v * gain).toList();
}

int _sdr(double linear) {
  final v = math.max(0.0, linear);
  final mapped = v / (1 + v);
  final encoded = mapped <= 0.0031308
      ? 12.92 * mapped
      : 1.055 * math.pow(mapped, 1 / 2.4) - 0.055;
  return (encoded * 255).round().clamp(0, 255);
}

/// Checks these authored charts, not arbitrary AVIF pictures. Reference PNGs
/// intentionally use the viewer's chosen per-channel Reinhard SDR policy.
/// Other correct tone mappers need not produce the same 8-bit RGB.
Future<Map<String, Object?>> verifyHdrAvif(
  File file, {
  required bool hlg,
  required Directory output,
}) async {
  final probe = await CodecProcess.locate('ffprobe', 'SHENVIEW_FFPROBE');
  final ffmpeg = await CodecProcess.locate('ffmpeg', 'SHENVIEW_FFMPEG');
  final info = jsonDecode(
    utf8.decode(
      await CodecProcess.run(probe, [
        '-v',
        'error',
        '-show_entries',
        'stream=width,height,pix_fmt,color_primaries,color_transfer,color_space,color_range',
        '-of',
        'json',
        file.absolute.path,
      ]),
    ),
  ) as Map<String, dynamic>;
  final stream = (info['streams'] as List).single as Map<String, dynamic>;
  if (stream['width'] != 384 || stream['height'] != 192) {
    throw const FormatException('Expected the authored 384x192 HDR chart');
  }
  final bytes = await CodecProcess.run(ffmpeg, [
    '-hide_banner', '-loglevel', 'error', '-nostdin', '-threads', '2',
    '-i', file.absolute.path,
    // Honor source matrix/range. Request planar RGB explicitly for zscale;
    // then repack to RGB48, preserving PQ/HLG signals (no tone mapping).
    '-vf', 'zscale=matrix=0:range=full,format=gbrp16le,format=rgb48le',
    '-frames:v', '1', '-pix_fmt', 'rgb48le', '-f', 'rawvideo', 'pipe:1',
  ]);
  if (bytes.length != 384 * 192 * 6) {
    throw const FormatException('Unexpected decoded AVIF byte count');
  }
  final data = ByteData.sublistView(bytes);
  final patches = <Map<String, Object?>>[];
  var maxError = 0.0;
  for (var row = 0; row < 3; row++) {
    for (var patch = 0; patch < 6; patch++) {
      final offset = ((row * 64 + 32) * 384 + patch * 64 + 32) * 6;
      final actual = [
        for (var c = 0; c < 3; c++)
          data.getUint16(offset + c * 2, Endian.little) / 65535,
      ];
      final expected = _signal(row, patch, hlg);
      for (var c = 0; c < 3; c++) {
        maxError = math.max(maxError, (actual[c] - expected[c]).abs());
      }
      patches.add({
        'row': row,
        'patch': patch,
        'nitsScale': _levels[patch],
        'expectedSignal': expected,
        'actualSignal': actual,
      });
    }
  }
  final reference = imaging.Image(width: 384, height: 192);
  for (var y = 0; y < 192; y++) {
    for (var x = 0; x < 384; x++) {
      final source = _rows[y ~/ 64]
          .map((c) => c * _levels[x ~/ 64] / 203)
          .toList();
      // HLG's 1000-nit saturated patches can exceed signal 1 in one
      // component. Respect the authored nominal-range clipping, rather than
      // inventing an unrepresentable reference from the original RGB alone.
      final rgb = hlg
          ? _matrix(_to709, _hlgDisplay(_signal(y ~/ 64, x ~/ 64, true)))
          : source;
      reference.setPixelRgb(x, y, _sdr(rgb[0]), _sdr(rgb[1]), _sdr(rgb[2]));
    }
  }
  await output.create(recursive: true);
  final name = hlg ? 'hdr_hlg' : 'hdr_pq';
  final referencePath = '${output.path}/$name-reference-sdr.png';
  await File(referencePath).writeAsBytes(imaging.encodePng(reference));
  final tagsMatch =
      stream['color_primaries'] == 'bt2020' &&
      stream['color_transfer'] == (hlg ? 'arib-std-b67' : 'smpte2084') &&
      stream['color_space'] == 'bt2020nc' &&
      stream['color_range'] == 'pc' &&
      stream['pix_fmt'] == 'yuv420p10le';
  return {
    'file': file.path,
    'metadata': stream,
    'expectedTagsMatch': tagsMatch,
    'maxSignalError': maxError,
    'signalTolerance': 0.004,
    'passed': tagsMatch && maxError <= 0.004,
    'patches': patches,
    'sdrReference': referencePath,
    'referencePolicy': 'linear Rec.709 per-channel Reinhard then sRGB; not a universal HDR screenshot reference',
  };
}

Future<void> main() async {
  final output = Directory('../../artifacts/hdr-color-check');
  final results = <Map<String, Object?>>[];
  for (final hlg in [false, true]) {
    results.add(
      await verifyHdrAvif(
        File('testdata/formats/hdr_${hlg ? 'hlg' : 'pq'}.avif'),
        hlg: hlg,
        output: output,
      ),
    );
  }
  final report = const JsonEncoder.withIndent('  ').convert(results);
  await File('${output.path}/verification.json').writeAsString(report);
  for (final row in results) {
    stdout.writeln(
      '${row['file']}: ${row['passed'] == true ? 'PASS' : 'FAIL'}, max signal error=${row['maxSignalError']}',
    );
    stdout.writeln('  SDR reference: ${row['sdrReference']}');
  }
  if (results.any((r) => r['passed'] != true)) exitCode = 1;
}
