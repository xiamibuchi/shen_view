import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/format_detector.dart';
import 'package:shen_view/src/domain/image_format.dart';

void main() {
  test(
    'fixture inventory distinguishes RAW, HDR and format compatibility',
    () async {
      const fixtures = <ImageFormat, List<String>>{
        ImageFormat.jpeg: ['format_static.jpg', 'hdr_gain_map.jpg'],
        ImageFormat.png: [
          'format_static.png',
          'format_srgb_icc.png',
          'format_long.png',
          'hdr_pq.png',
          'hdr_pq_alpha.png',
          'hdr_hlg.png',
        ],
        ImageFormat.apng: [
          'format_animated.apng',
          'format_animated_small.apng',
        ],
        ImageFormat.gif: ['format_animated.gif'],
        ImageFormat.webp: ['format_static.webp', 'format_animated.webp'],
        ImageFormat.bmp: ['format_static.bmp'],
        ImageFormat.ico: [
          'format_multisize.ico',
          'format_bitmap.ico',
          'format_single.ico',
        ],
        ImageFormat.tiff: ['format_static.tiff'],
        ImageFormat.dds: ['format_static.dds'],
        ImageFormat.psd: ['format_static.psd'],
        ImageFormat.jxl: ['format_static.jxl'],
        ImageFormat.svg: ['format_color_patches.svg'],
        ImageFormat.heic: ['format_alpha.heic', 'hdr_gain_map.heic'],
        ImageFormat.heif: ['format_alpha.heif', 'hdr_gain_map.heif'],
        ImageFormat.avif: [
          'format_static.avif',
          'format_animated.avif',
          'format_animated_finite.avif',
          'format_animated_pq.avif',
          'format_animated_hlg.avif',
          'format_animated_icc.avif',
          'format_single_frame.avif',
          'format_progressive.avif',
          'hdr_pq.avif',
          'hdr_hlg.avif',
          'hdr_gain_map.avif',
        ],
        ImageFormat.raw: [
          'raw_canon_white_paper.cr2',
          'raw_nikon_d2h.nef',
          'raw_sony_a7s.arw',
          'raw_bayer_no_preview.dng',
          'raw_bayer_rotated.dng',
          'raw_bayer_underexposed.dng',
          'raw_bayer_black.dng',
        ],
        ImageFormat.hdr: ['hdr_highlights.hdr', 'hdr_gradient.hdr'],
        ImageFormat.exr: [
          'hdr_highlights.exr',
          'hdr_rec2020.exr',
          'hdr_transparent.exr',
          'hdr_gradient.exr',
        ],
        ImageFormat.hdrVideo: ['hdr_dovi_p81.hevc'],
        ImageFormat.archive: [
          'format_comic.cbz',
          'format_comic_zip.cbr',
          'format_comic_rar.cbr',
        ],
      };
      final root = Directory('testdata/formats');
      final names = root
          .listSync()
          .whereType<File>()
          .where((file) => !file.path.endsWith('.md'))
          .map((file) => file.uri.pathSegments.last)
          .toSet();
      final expected = fixtures.values.expand((value) => value).toSet();
      expect(
        names,
        expected,
        reason: 'New images need a category and documented test intent',
      );
      expect(
        fixtures.keys.toSet(),
        ImageFormat.values
            .where((format) => format != ImageFormat.unknown)
            .toSet(),
      );
      final detector = FormatDetector();
      for (final group in fixtures.entries) {
        for (final name in group.value) {
          expect(
            name,
            matches(RegExp(r'^(format|raw|hdr)_[a-z0-9_]+[.][a-z0-9]+$')),
          );
          final file = File('${root.path}/$name');
          expect(file.lengthSync(), greaterThan(0), reason: name);
          expect(await detector.detect(file), group.key, reason: name);
          if (group.key == ImageFormat.raw) {
            expect(name.startsWith('raw_'), isTrue);
          }
          if ([
            ImageFormat.hdr,
            ImageFormat.exr,
            ImageFormat.hdrVideo,
          ].contains(group.key)) {
            expect(name.startsWith('hdr_'), isTrue);
          }
        }
      }
    },
  );
}
