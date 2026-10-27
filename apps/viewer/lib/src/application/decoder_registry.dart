import 'dart:io';

import '../domain/image_format.dart';
import 'native_decoder.dart';

class DecoderCapability {
  const DecoderCapability({
    required this.format,
    required this.available,
    required this.animated,
    required this.metadata,
    required this.sourceKind,
  });
  final ImageFormat format;
  final bool available;
  final bool animated;
  final bool metadata;
  final DecoderSource sourceKind;
}

enum DecoderSource {
  flutterCodec,
  dartImageSvg,
  archive,
  imageMagickJxl,
  windowsWic,
  macImageIo,
  imageMagickFallback,
  hdrVideo,
  unavailable,
}

enum ImageDecodeRoute { flutter, platformThenImageMagick, imageMagick }

ImageDecodeRoute decodeRouteFor(ImageFormat format, {bool hasRegion = false}) {
  if (format == ImageFormat.jxl) return ImageDecodeRoute.imageMagick;
  if (hasRegion || !isFlutterCodecFormat(format)) {
    return ImageDecodeRoute.platformThenImageMagick;
  }
  return ImageDecodeRoute.flutter;
}

bool isFlutterCodecFormat(ImageFormat format) => const {
  ImageFormat.jpeg,
  ImageFormat.png,
  ImageFormat.gif,
  ImageFormat.webp,
  ImageFormat.bmp,
  ImageFormat.apng,
}.contains(format);

class DecoderRegistry {
  List<DecoderCapability> capabilities() => ImageFormat.values
      .where((format) => format != ImageFormat.unknown)
      .map((format) {
        final core = _isCore(format);
        final extended = _isDartExtension(format);
        final native = _isNative(format);
        final archive = format == ImageFormat.archive;
        final nativeAvailable =
            Platform.isWindows ||
            Platform.isMacOS ||
            NativeDecoder.isLikelyAvailable;
        final windowsHdrUsesFallback =
            Platform.isWindows &&
            (format == ImageFormat.hdr || format == ImageFormat.exr);
        return DecoderCapability(
          format: format,
          available:
              core ||
              extended ||
              archive ||
              format == ImageFormat.hdrVideo ||
              native && nativeAvailable,
          animated:
              format == ImageFormat.gif ||
              format == ImageFormat.webp ||
              format == ImageFormat.avif ||
              format == ImageFormat.apng,
          metadata:
              format == ImageFormat.ico ||
              format == ImageFormat.jpeg ||
              format == ImageFormat.hdrVideo ||
              _isNative(format),
          sourceKind: format == ImageFormat.hdrVideo
              ? DecoderSource.hdrVideo
              : core
              ? DecoderSource.flutterCodec
              : extended
              ? DecoderSource.dartImageSvg
              : archive
              ? DecoderSource.archive
              : format == ImageFormat.jxl
              ? DecoderSource.imageMagickJxl
              : native
              ? windowsHdrUsesFallback
                    ? DecoderSource.imageMagickFallback
                    : Platform.isWindows
                    ? DecoderSource.windowsWic
                    : Platform.isMacOS
                    ? DecoderSource.macImageIo
                    : DecoderSource.imageMagickFallback
              : DecoderSource.unavailable,
        );
      })
      .toList();

  bool _isCore(ImageFormat format) => const {
    ImageFormat.jpeg,
    ImageFormat.png,
    ImageFormat.gif,
    ImageFormat.webp,
    ImageFormat.bmp,
  }.contains(format);

  bool _isDartExtension(ImageFormat format) => const {
    ImageFormat.apng,
    ImageFormat.svg,
    ImageFormat.ico,
  }.contains(format);

  bool _isNative(ImageFormat format) => const {
    ImageFormat.tiff,
    ImageFormat.psd,
    ImageFormat.exr,
    ImageFormat.hdr,
    ImageFormat.heic,
    ImageFormat.heif,
    ImageFormat.avif,
    ImageFormat.jxl,
    ImageFormat.raw,
    ImageFormat.dds,
  }.contains(format);
}
