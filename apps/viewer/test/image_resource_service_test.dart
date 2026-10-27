import 'package:flutter_test/flutter_test.dart';

import 'package:shen_view/src/application/decoder_registry.dart';
import 'package:shen_view/src/domain/image_format.dart';

void main() {
  test('keeps JPEG XL on the ImageMagick path', () {
    expect(decodeRouteFor(ImageFormat.jxl), ImageDecodeRoute.imageMagick);
    expect(
      DecoderRegistry()
          .capabilities()
          .singleWhere((capability) => capability.format == ImageFormat.jxl)
          .sourceKind,
      DecoderSource.imageMagickJxl,
    );
  });

  test('keeps platform decoding available for other native formats', () {
    expect(
      decodeRouteFor(ImageFormat.avif),
      ImageDecodeRoute.platformThenImageMagick,
    );
    expect(
      decodeRouteFor(ImageFormat.heic),
      ImageDecodeRoute.platformThenImageMagick,
    );
  });

  test('uses Flutter codec only for full-frame Flutter formats', () {
    expect(decodeRouteFor(ImageFormat.png), ImageDecodeRoute.flutter);
    expect(decodeRouteFor(ImageFormat.apng), ImageDecodeRoute.flutter);
    expect(
      decodeRouteFor(ImageFormat.png, hasRegion: true),
      ImageDecodeRoute.platformThenImageMagick,
    );
  });
}
