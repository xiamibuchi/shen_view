import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as imaging;

import '../domain/animation_timeline.dart';
import '../domain/image_format.dart';
import 'avif_codec.dart';
import 'format_detector.dart';
import 'ico_file.dart';
import 'native_decoder.dart';
import 'platform_image_decoder.dart';
import 'hdr_input_metadata.dart';
import 'raw_developer.dart';
import 'photo_media_info.dart';
import 'photo_metadata_reader.dart';

class ImageMetadata {
  const ImageMetadata({
    required this.width,
    required this.height,
    required this.values,
    this.orientation = 1,
    this.readable = true,
    this.bitDepth,
    this.hasAlpha,
    this.colorSpace,
    this.codec,
    this.animation,
    this.media,
    this.mayContainPhotoVideo = false,
    this.icoVariants = const [],
    this.icoIndex,
    this.hdrEncoding = HdrEncoding.sdr,
  });
  final int width;
  final int height;
  final int orientation;
  final Map<String, String> values;
  final bool readable;
  final int? bitDepth;
  final bool? hasAlpha;
  final String? colorSpace;
  final String? codec;
  final ImageAnimationMetadata? animation;
  final PhotoMediaInfo? media;
  final bool mayContainPhotoVideo;
  final List<IcoVariant> icoVariants;
  final int? icoIndex;

  ImageMetadata selectIco(int index) {
    final variant = icoVariants[index];
    return ImageMetadata(
      width: variant.width,
      height: variant.height,
      values: values,
      bitDepth: variant.bitDepth,
      hasAlpha: variant.hasAlpha,
      codec: variant.codec,
      icoVariants: icoVariants,
      icoIndex: index,
    );
  }

  final HdrEncoding hdrEncoding;
  bool get isHdr => hdrEncoding != HdrEncoding.sdr;
}

class ImageAnimationMetadata {
  const ImageAnimationMetadata({
    required this.frameCount,
    this.fps,
    this.durationMs,
    this.loopCount,
    this.durationsMs,
    this.sourcePixelCount,
  });

  final int frameCount;
  final double? fps;
  final int? durationMs;

  /// `0` means infinite looping for GIF/APNG/WebP.
  final int? loopCount;
  final List<int>? durationsMs;
  final int? sourcePixelCount;
}

class MetadataService {
  Future<ImageMetadata> read(String path, {DecodeRequest? request}) async {
    ImageMetadata? basic;
    if (FormatDetector.formatForPath(path) == ImageFormat.jpeg) {
      basic = await _read(path, request: request);
    }
    PhotoMediaInfo? media;
    Object? mediaFailure;
    try {
      // Reuse the existing bounded metadata read for ordinary JPEGs. Most photos
      // have no video; extra serial file probes would delay foreground metadata.
      if (basic == null || basic.mayContainPhotoVideo) {
        media = await PhotoMediaInfo.inspect(path, request: request);
      }
    } on DecodeCancelled {
      rethrow;
    } on Object catch (failure) {
      mediaFailure = failure;
    }
    if (media != null) {
      basic ??= await _read(path, request: request);
      final timeline = media.timeline;
      return ImageMetadata(
        width: media.width,
        height: media.height,
        values: {
          ...basic.values,
          'photoMedia': media.location.kind.name,
          'videoCodec': media.codec,
          if (media.audioTracks.isNotEmpty)
            'audioCodecs': media.audioTracks.map((a) => a.codec).join(', '),
          if (media.hdr) 'playbackColor': 'HDR → sRGB',
        },
        codec: media.codec,
        colorSpace: basic.colorSpace,
        bitDepth: basic.bitDepth,
        hdrEncoding: basic.hdrEncoding,
        hasAlpha: media.alphaIndex != null,
        media: media,
        animation: media.animated
            ? ImageAnimationMetadata(
                frameCount: timeline.durations.length,
                durationMs: timeline.durationMs,
                fps: timeline.durations.length * 1000 / timeline.durationMs,
                loopCount: timeline.totalPlays,
                durationsMs: timeline.durations,
                sourcePixelCount: media.width * media.height,
              )
            : null,
      );
    }
    basic ??= await _read(path, request: request);
    if (mediaFailure != null) {
      basic = basic.copyWith(
        values: {...basic.values, 'photoMediaError': mediaFailure.toString()},
      );
    }
    if (basic.codec != 'AV1' &&
        !{'avif', 'avis'}.contains(FormatDetector.extensionOf(path))) {
      return basic;
    }
    try {
      final info = await AvifCodec.inspect(path, request: request);
      final timeline = info.timeline;
      return ImageMetadata(
        width: basic.width > 0 ? basic.width : info.width,
        height: basic.height > 0 ? basic.height : info.height,
        orientation: basic.orientation,
        values: basic.values,
        bitDepth: info.depth,
        hasAlpha: info.hasAlpha,
        colorSpace: basic.colorSpace,
        codec: 'AV1',
        hdrEncoding: basic.hdrEncoding,
        animation: info.animated
            ? ImageAnimationMetadata(
                frameCount: timeline.durations.length,
                durationMs: timeline.durationMs,
                fps: timeline.durations.length * 1000 / timeline.durationMs,
                loopCount: timeline.totalPlays,
                durationsMs: timeline.durations,
                sourcePixelCount: info.width * info.height,
              )
            : null,
      );
    } on DecodeCancelled {
      rethrow;
    } on Object {
      // Static AVIF remains available when the optional animation helper is absent.
      return basic;
    }
  }

  Future<ImageMetadata> _read(String path, {DecodeRequest? request}) async {
    request?.throwIfCancelled();
    if (RawDeveloper.candidate(path)) {
      try {
        // A TIFF container's first IFD may describe only its 160 px thumbnail.
        // Inspect sensor geometry without unpacking or developing sensor pixels.
        final info = await RawDeveloper().inspect(path, request: request);
        final width = (info['width'] as num).toInt();
        final height = (info['height'] as num).toInt();
        if (width > 0 && height > 0) {
          final photo = await Isolate.run(() => PhotoMetadataReader.read(path));
          request?.throwIfCancelled();
          return ImageMetadata(
            width: width,
            height: height,
            codec: 'LibRaw',
            orientation: int.tryParse(photo['orientation'] ?? '') ?? 1,
            colorSpace: photo['colorSpace'],
            hdrEncoding: HdrEncoding.sceneLinear,
            values: {
              for (final entry in info.entries) entry.key: '${entry.value}',
              ...photo,
            },
          );
        }
      } on DecodeCancelled {
        rethrow;
      } catch (_) {
        // Optional/missing helper retains the existing metadata fallbacks.
      }
    }
    if (path.toLowerCase().endsWith('.hevc') ||
        path.toLowerCase().endsWith('.h265')) {
      try {
        final info = await HdrInputMetadata.readVideo(path, request: request);
        request?.throwIfCancelled();
        return ImageMetadata(
          width: info.width ?? 0,
          height: info.height ?? 0,
          bitDepth: 10,
          colorSpace: info.encoding == HdrEncoding.dolbyVision
              ? 'Dolby Vision'
              : info.encoding.name.toUpperCase(),
          values: const {},
          hdrEncoding: info.encoding,
        );
      } on DecodeCancelled {
        rethrow;
      } catch (_) {
        return const ImageMetadata(
          width: 0,
          height: 0,
          values: {},
          readable: false,
        );
      }
    }
    var basic = await Isolate.run(() => _readBasic(path));
    request?.throwIfCancelled();
    if ({
      'heic',
      'heif',
      'hif',
      'avif',
    }.contains(FormatDetector.extensionOf(path))) {
      try {
        final photo = await PhotoMetadataReader.readHeif(
          path,
          request: request,
        );
        final values = {...basic.values, ...photo};
        for (final key in PhotoMetadataReader.descriptiveKeys) {
          if (basic.values[key] case final String value) values[key] = value;
        }
        basic = basic.copyWith(
          values: values,
          colorSpace: values['colorSpace'],
        );
      } on DecodeCancelled {
        rethrow;
      } on Object {
        // The metadata helper is optional, just like the HEIF HDR helper.
      }
    }
    if (HdrInputMetadata.candidate(path)) {
      try {
        final hdr = await HdrInputMetadata.read(path, request: request);
        basic = basic.copyWith(hdrEncoding: hdr.encoding);
      } on DecodeCancelled {
        rethrow;
      } catch (_) {
        // Optional HDR metadata never prevents normal image metadata/display.
      }
    }
    if (basic.width > 0 && basic.height > 0) return basic;
    try {
      final extension = path.split('.').last.toLowerCase();
      // WIC metadata probing is unreliable for Radiance HDR and OpenEXR
      // codecs on older Windows builds. Use ImageMagick's metadata reader
      // for those formats; it is already the guarded decode fallback.
      final platformData = extension == 'hdr' || extension == 'exr'
          ? null
          : await PlatformImageDecoder().metadata(path, request: request);
      final data =
          platformData ??
          await NativeDecoder().metadata(path, request: request);
      request?.throwIfCancelled();
      final orientation = (data['orientation'] as num?)?.toInt() ?? 1;
      final width = (data['width'] as num?)?.toInt() ?? 0;
      final height = (data['height'] as num?)?.toInt() ?? 0;
      return ImageMetadata(
        width: orientation >= 5 && orientation <= 8 ? height : width,
        height: orientation >= 5 && orientation <= 8 ? width : height,
        orientation: orientation,
        readable: width > 0 && height > 0,
        bitDepth: int.tryParse(data['bitDepth']?.toString() ?? ''),
        hasAlpha: _parseBool(data['hasAlpha']),
        colorSpace: basic.colorSpace ?? _nonEmpty(data['colorSpace']),
        codec: basic.codec ?? _nonEmpty(data['codec']) ?? _codecForPath(path),
        animation: _animationFrom(data),
        values: {
          for (final item in data.entries)
            if (item.value is String && (item.value as String).isNotEmpty)
              item.key: item.value as String,
          ...basic.values,
        },
        hdrEncoding: basic.hdrEncoding,
      );
    } on DecodeCancelled {
      rethrow;
    } on Object {
      return basic.copyWith(readable: basic.width > 0 && basic.height > 0);
    }
  }
}

bool? _parseBool(Object? value) {
  if (value is bool) return value;
  if (value is! String) return null;
  if (value.toLowerCase() == 'true' || value == '1') return true;
  if (value.toLowerCase() == 'false' || value == '0') return false;
  return null;
}

String? _nonEmpty(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

ImageAnimationMetadata? _animationFrom(Map<String, dynamic> data) {
  final count = int.tryParse(data['frameCount']?.toString() ?? '') ?? 0;
  if (count <= 1) return null;
  return ImageAnimationMetadata(
    frameCount: count,
    fps: double.tryParse(data['fps']?.toString() ?? ''),
    durationMs: int.tryParse(data['durationMs']?.toString() ?? ''),
    loopCount: int.tryParse(data['loopCount']?.toString() ?? ''),
  );
}

extension on ImageMetadata {
  ImageMetadata copyWith({
    bool? readable,
    HdrEncoding? hdrEncoding,
    Map<String, String>? values,
    String? colorSpace,
  }) => ImageMetadata(
    width: width,
    height: height,
    orientation: orientation,
    values: values ?? this.values,
    readable: readable ?? this.readable,
    bitDepth: bitDepth,
    hasAlpha: hasAlpha,
    colorSpace: colorSpace ?? this.colorSpace,
    codec: codec,
    animation: animation,
    media: media,
    mayContainPhotoVideo: mayContainPhotoVideo,
    icoVariants: icoVariants,
    icoIndex: icoIndex,
    hdrEncoding: hdrEncoding ?? this.hdrEncoding,
  );
}

FutureOr<ImageMetadata> _readBasic(String path) {
  final input = File(path).openSync();
  late final Uint8List bytes;
  var photoVideoHint = false;
  try {
    bytes = input.readSync(2 * 1024 * 1024);
    if (bytes.length > 2 && bytes[0] == 255 && bytes[1] == 216) {
      final prefix = String.fromCharCodes(bytes);
      photoVideoHint =
          prefix.contains('MotionPhoto') || prefix.contains('MicroVideo');
      if (!photoVideoHint) {
        final size = input.lengthSync();
        input.setPositionSync((size - 256).clamp(0, size));
        final footer = String.fromCharCodes(input.readSync(256));
        photoVideoHint =
            footer.contains('SEFT') || footer.contains('MotionPhoto');
      }
    }
  } finally {
    input.closeSync();
  }
  if (IcoFile.matches(bytes)) {
    return IcoFile.inspect(path).then(
      (variants) => ImageMetadata(
        width: 0,
        height: 0,
        values: const {},
        icoVariants: variants,
      ).selectIco(IcoFile.largest(variants)),
    );
  }
  var width = 0;
  var height = 0;
  var orientation = 1;
  final values = <String, String>{};
  int? bitDepth;
  bool? hasAlpha;
  ImageAnimationMetadata? animation;
  final data = ByteData.sublistView(bytes);
  if (bytes.length >= 24 && bytes[0] == 0x89 && bytes[1] == 0x50) {
    width = data.getUint32(16);
    height = data.getUint32(20);
    if (_containsBytes(bytes, const [0x69, 0x43, 0x43, 0x50])) {
      values['colorSpace'] = 'ICC';
    }
    if (bytes.length > 25) {
      bitDepth = bytes[24];
      hasAlpha = bytes[25] == 4 || bytes[25] == 6;
    }
  } else if (bytes.length >= 10 &&
      String.fromCharCodes(bytes.take(3)) == 'GIF') {
    width = data.getUint16(6, Endian.little);
    height = data.getUint16(8, Endian.little);
  } else if (bytes.length >= 26 && bytes[0] == 0x42 && bytes[1] == 0x4d) {
    final headerSize = data.getUint32(14, Endian.little);
    width = headerSize == 12
        ? data.getUint16(18, Endian.little)
        : data.getInt32(18, Endian.little).abs();
    height = headerSize == 12
        ? data.getUint16(20, Endian.little)
        : data.getInt32(22, Endian.little).abs();
  } else if (bytes.length > 3 && bytes[0] == 0xff && bytes[1] == 0xd8) {
    var offset = 2;
    while (offset + 3 < bytes.length) {
      if (bytes[offset++] != 0xff) continue;
      while (offset < bytes.length && bytes[offset] == 0xff) {
        offset++;
      }
      if (offset >= bytes.length) break;
      final marker = bytes[offset++];
      if (marker == 0xda || marker == 0xd9) break;
      if (marker == 0x01 || marker >= 0xd0 && marker <= 0xd7) continue;
      if (offset + 2 > bytes.length) break;
      final length = data.getUint16(offset);
      if (length < 2 || offset + length > bytes.length) break;
      if ({
            0xc0,
            0xc1,
            0xc2,
            0xc3,
            0xc5,
            0xc6,
            0xc7,
            0xc9,
            0xca,
            0xcb,
            0xcd,
            0xce,
            0xcf,
          }.contains(marker) &&
          length >= 7) {
        height = data.getUint16(offset + 3);
        width = data.getUint16(offset + 5);
      }
      offset += length;
    }
  } else if (bytes.length >= 30 &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    final kind = String.fromCharCodes(bytes.sublist(12, 16));
    if (kind == 'VP8X') {
      width = 1 + bytes[24] + (bytes[25] << 8) + (bytes[26] << 16);
      height = 1 + bytes[27] + (bytes[28] << 8) + (bytes[29] << 16);
      hasAlpha = (bytes[20] & 0x10) != 0;
    } else if (kind == 'VP8 ') {
      width = data.getUint16(26, Endian.little) & 0x3fff;
      height = data.getUint16(28, Endian.little) & 0x3fff;
    } else if (kind == 'VP8L') {
      final dimensions = data.getUint32(21, Endian.little);
      width = 1 + (dimensions & 0x3fff);
      height = 1 + ((dimensions >> 14) & 0x3fff);
    }
  } else if (_looksLikeSvg(bytes)) {
    final source = String.fromCharCodes(bytes);
    final root = RegExp(
      r'<svg\b[^>]*>',
      caseSensitive: false,
    ).firstMatch(source);
    final rootText = root?.group(0) ?? '';
    final widthText = _svgAttribute(rootText, 'width');
    final heightText = _svgAttribute(rootText, 'height');
    final viewBox = _svgAttribute(rootText, 'viewBox');
    final viewBoxParts = viewBox
        ?.split(RegExp(r'[,\s]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final viewBoxWidth = viewBoxParts != null && viewBoxParts.length >= 4
        ? double.tryParse(viewBoxParts[2])
        : null;
    final viewBoxHeight = viewBoxParts != null && viewBoxParts.length >= 4
        ? double.tryParse(viewBoxParts[3])
        : null;
    width = _svgDimension(widthText) ?? viewBoxWidth?.round() ?? 0;
    height = _svgDimension(heightText) ?? viewBoxHeight?.round() ?? 0;
    if (widthText != null || heightText != null) {
      values['svgPhysicalSize'] = [
        widthText,
        heightText,
      ].whereType<String>().join(' × ');
    }
    if (viewBox != null) values['svgViewBox'] = viewBox;
    values['svgNodeCount'] = RegExp(
      r'<(path|rect|circle|ellipse|line|polyline|polygon|g|text)\b',
      caseSensitive: false,
    ).allMatches(source).length.toString();
  } else {
    try {
      final info = imaging.findDecoderForData(bytes)?.startDecode(bytes);
      width = info?.width ?? 0;
      height = info?.height ?? 0;
    } on Object {
      width = 0;
      height = 0;
    }
  }
  try {
    final timeline = AnimationTimeline.parse(bytes);
    if (timeline != null && timeline.durations.length > 1) {
      animation = ImageAnimationMetadata(
        frameCount: timeline.durations.length,
        fps: timeline.durations.length * 1000 / timeline.durationMs,
        durationMs: timeline.durationMs,
        loopCount: timeline.totalPlays,
      );
    }
  } on Object {
    // Dimensions are still useful when an animation's optional metadata is malformed.
  }
  var readable = width > 0 && height > 0;
  if (readable && !_looksLikeSvg(bytes)) {
    try {
      final decoder = imaging.findDecoderForData(bytes);
      readable = decoder != null && decoder.startDecode(bytes) != null;
    } on Object {
      readable = false;
    }
  }
  values.addAll(PhotoMetadataReader.read(path));
  final photoOrientation = int.tryParse(values['orientation'] ?? '');
  if (photoOrientation != null &&
      photoOrientation >= 1 &&
      photoOrientation <= 8) {
    orientation = photoOrientation;
  }
  return ImageMetadata(
    width: orientation >= 5 && orientation <= 8 ? height : width,
    height: orientation >= 5 && orientation <= 8 ? width : height,
    orientation: orientation,
    readable: readable,
    bitDepth: bitDepth,
    hasAlpha: hasAlpha,
    animation: animation,
    mayContainPhotoVideo: photoVideoHint,
    codec: FormatDetector().fromSignature(bytes) == ImageFormat.avif
        ? 'AV1'
        : _codecForPath(path),
    colorSpace: _nonEmpty(values['colorSpace']),
    values: values,
  );
}

String? _codecForPath(String path) {
  final extension = path.split('.').last.toLowerCase();
  return switch (extension) {
    'avif' || 'avis' => 'AV1',
    'heic' || 'heif' => 'HEVC',
    _ => null,
  };
}

bool _looksLikeSvg(Uint8List bytes) {
  final source = String.fromCharCodes(bytes.take(4096));
  return RegExp(r'<svg\b', caseSensitive: false).hasMatch(source);
}

bool _containsBytes(Uint8List bytes, List<int> needle) {
  for (var index = 0; index <= bytes.length - needle.length; index++) {
    var matches = true;
    for (var offset = 0; offset < needle.length; offset++) {
      if (bytes[index + offset] != needle[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}

String? _svgAttribute(String source, String name) => RegExp(
  '\\b$name\\s*=\\s*["\\x27]([^"\\x27]+)',
  caseSensitive: false,
).firstMatch(source)?.group(1);

int? _svgDimension(String? value) {
  if (value == null) return null;
  return double.tryParse(
    RegExp(r'-?\d+(?:\.\d+)?').firstMatch(value)?.group(0) ?? '',
  )?.round();
}
