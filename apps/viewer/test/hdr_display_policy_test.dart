import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/hdr_display_policy.dart';
import 'package:shen_view/src/application/hdr_input_metadata.dart';
import 'package:shen_view/src/domain/image_format.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';

void main() {
  const cases = [
    (ImageFormat.hdr, HdrEncoding.sceneLinear, 'linear'),
    (ImageFormat.exr, HdrEncoding.sceneLinear, 'linear'),
    (ImageFormat.raw, HdrEncoding.sceneLinear, 'raw'),
    (ImageFormat.png, HdrEncoding.pq, 'pqHlg'),
    (ImageFormat.avif, HdrEncoding.hlg, 'pqHlg'),
    (ImageFormat.avif, HdrEncoding.gainMap, 'gainMap'),
    (ImageFormat.heif, HdrEncoding.gainMap, 'gainMap'),
    (ImageFormat.jpeg, HdrEncoding.gainMap, 'gainMap'),
    (ImageFormat.hdrVideo, HdrEncoding.dolbyVision, 'dolbyVision'),
  ];

  test('default HDR policy allows supported inputs, never ordinary SDR', () {
    for (final input in cases) {
      expect(
        shouldUseHdrDisplay(const ViewerSettings(), input.$1, input.$2),
        isTrue,
      );
      expect(
        shouldUseHdrDisplay(const ViewerSettings(), input.$1, HdrEncoding.sdr),
        isFalse,
      );
    }
  });

  test('each type switch disables only its own HDR inputs', () {
    const disabled = {
      'linear': ViewerSettings(hdrLinear: false),
      'pqHlg': ViewerSettings(hdrPqHlg: false),
      'gainMap': ViewerSettings(hdrGainMap: false),
      'raw': ViewerSettings(hdrRaw: false),
      'dolbyVision': ViewerSettings(hdrDolbyVision: false),
    };
    for (final setting in disabled.entries) {
      for (final input in cases) {
        expect(
          shouldUseHdrDisplay(setting.value, input.$1, input.$2),
          input.$3 != setting.key,
          reason: 'disabled=${setting.key}, input=$input',
        );
      }
    }
  });

  test('global off overrides every type without erasing the choices', () {
    const selected = ViewerSettings(hdrRaw: false, hdrGainMap: false);
    final off = selected.copyWith(autoHdr: false);
    for (final input in cases) {
      expect(shouldUseHdrDisplay(off, input.$1, input.$2), isFalse);
    }
    expect(off.copyWith(autoHdr: true), selected);
  });
}
