import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as paths;

import 'decode_request.dart';
import 'platform_image_decoder.dart';
import 'raw_developer.dart';
import 'photo_metadata_reader.dart';

export 'decode_request.dart';

class NativeDecoder {
  NativeDecoder({this.executableOverride, RawDeveloper? rawDeveloper})
    : _rawDeveloper = rawDeveloper ?? RawDeveloper();

  final String? executableOverride;
  final RawDeveloper _rawDeveloper;
  final _platform = PlatformImageDecoder();
  static String? _executable;
  static int _active = 0;
  static const maxOutputBytes = 128 * 1024 * 1024;

  static Iterable<String> _installedWindowsMagick() sync* {
    for (final root in {
      Platform.environment['ProgramW6432'],
      Platform.environment['ProgramFiles'],
    }.whereType<String>()) {
      if (root.isEmpty) continue;
      try {
        for (final directory in Directory(
          root,
        ).listSync().whereType<Directory>()) {
          if (paths.basename(directory.path).startsWith('ImageMagick-')) {
            yield paths.join(directory.path, 'magick.exe');
          }
        }
      } on FileSystemException {
        // An unavailable installation directory must not prevent PATH lookup.
      }
    }
  }

  Future<RawEmbeddedPreview?> rawPreview(
    String path, {
    int? targetWidth,
    int? targetHeight,
    DecodeRequest? request,
  }) => _rawDeveloper.preview(
    path,
    targetWidth: targetWidth,
    targetHeight: targetHeight,
    request: request,
  );

  static bool get isLikelyAvailable {
    if (Platform.isWindows || Platform.isMacOS) return true;
    final override = Platform.environment['SHENVIEW_MAGICK'];
    if (override != null && File(override).existsSync()) return true;
    final bundled = paths.join(
      paths.dirname(Platform.resolvedExecutable),
      'codecs',
      Platform.isWindows ? 'magick.exe' : 'magick',
    );
    if (File(bundled).existsSync()) return true;
    if (Platform.isWindows) {
      return _installedWindowsMagick().any((path) => File(path).existsSync());
    }
    return Platform.isMacOS &&
        (File('/opt/homebrew/bin/magick').existsSync() ||
            File('/usr/local/bin/magick').existsSync());
  }

  Future<String> executable() async {
    if (executableOverride != null) return executableOverride!;
    if (_executable != null) return _executable!;
    final candidates = <String>[
      if (Platform.environment['SHENVIEW_MAGICK'] case final String path) path,
      if (Platform.isWindows)
        paths.join(
          paths.dirname(Platform.resolvedExecutable),
          'codecs',
          'imagemagick',
          'magick.exe',
        ),
      paths.join(
        paths.dirname(Platform.resolvedExecutable),
        'codecs',
        Platform.isWindows ? 'magick.exe' : 'magick',
      ),
      if (Platform.isMacOS) ...[
        '/opt/homebrew/bin/magick',
        '/usr/local/bin/magick',
      ],
      if (Platform.isWindows) ..._installedWindowsMagick(),
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) return _executable = candidate;
    }
    final lookup = await Process.run(
      Platform.isWindows ? 'where.exe' : 'which',
      ['magick'],
    );
    if (lookup.exitCode == 0) {
      return _executable = lookup.stdout
          .toString()
          .trim()
          .split(RegExp(r'[\r\n]+'))
          .first;
    }
    throw StateError('扩展解码器不可用，请重新安装完整发行包，或设置 SHENVIEW_MAGICK。');
  }

  Future<Uint8List> run(
    List<String> arguments, {
    DecodeRequest? request,
  }) async {
    final cancellation = request ?? DecodeRequest();
    while (_active >= 2) {
      if (cancellation.cancelled) throw DecodeCancelled();
      await Future<void>.delayed(const Duration(milliseconds: 12));
    }
    if (cancellation.cancelled) throw DecodeCancelled();
    _active++;
    Process? process;
    Timer? timeout;
    var timedOut = false;
    try {
      final executablePath = await executable();
      if (cancellation.cancelled) throw DecodeCancelled();
      process = await Process.start(
        executablePath,
        [
          '-limit',
          'thread',
          '2',
          '-limit',
          'memory',
          '192MiB',
          '-limit',
          'map',
          '256MiB',
          '-limit',
          'disk',
          '512MiB',
          '-limit',
          'time',
          '30',
          ...arguments,
        ],
        environment: {
          ...Platform.environment,
          'MAGICK_CONFIGURE_PATH': paths.dirname(executablePath),
          if (Platform.isWindows)
            'MAGICK_CODER_MODULE_PATH': paths.join(
              paths.dirname(executablePath),
              'modules',
              'coders',
            ),
          if (Platform.isWindows)
            'MAGICK_FILTER_MODULE_PATH': paths.join(
              paths.dirname(executablePath),
              'modules',
              'filters',
            ),
        },
      );
      cancellation.process = process;
      if (cancellation.cancelled) process.kill();
      timeout = Timer(const Duration(seconds: 35), () {
        timedOut = true;
        process?.kill();
      });
      final output = BytesBuilder(copy: false);
      var overflow = false;
      final stderr = process.stderr.transform(utf8.decoder).join();
      await for (final chunk in process.stdout) {
        if (output.length + chunk.length > maxOutputBytes) {
          overflow = true;
          process.kill();
        } else {
          output.add(chunk);
        }
      }
      final code = await process.exitCode;
      final error = await stderr;
      if (cancellation.cancelled) throw DecodeCancelled();
      if (timedOut) throw DecodeTimedOut('图片解析超时，可以重试或切换下一张。');
      if (overflow) throw DecodeBudgetExceeded('图片超过解码内存预算，请使用适应窗口或长图模式。');
      if (code != 0) throw StateError('解析失败：$error');
      return output.takeBytes();
    } finally {
      timeout?.cancel();
      cancellation.process = null;
      _active--;
    }
  }

  Future<Uint8List> decode(
    String path, {
    int? targetWidth,
    int? targetHeight,
    DecodeRequest? request,
    int frame = 0,
    String? crop,
    bool Function()? allowTimeoutFallback,
  }) async {
    if (RawDeveloper.candidate(path) && crop == null) {
      try {
        return await _rawDeveloper.decode(
          path,
          request: request,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
        );
      } on DecodeCancelled {
        rethrow;
      } on DecodeBudgetExceeded {
        rethrow;
      } on DecodeTimedOut {
        if (!(allowTimeoutFallback?.call() ?? true)) rethrow;
      } catch (_) {
        // A missing/unsupported RAW codec retains the previous fallback.
      }
    }
    var assumeAdobeRgb = false;
    if ({
      '.jpg',
      '.jpeg',
      '.tif',
      '.tiff',
    }.contains(paths.extension(path).toLowerCase())) {
      try {
        final photo = await Isolate.run(
          () => PhotoMetadataReader.read(path, includeSidecars: false),
        );
        assumeAdobeRgb = photo['colorSpace'] == 'Adobe RGB (1998)';
      } on Object {
        /* Optional metadata does not block compatibility decoding. */
      }
      request?.throwIfCancelled();
    }
    final profile = File(
      paths.join(paths.dirname(await executable()), 'sRGB.icc'),
    );
    return run(
      decodeArguments(
        path,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
        crop: crop,
        frame: frame,
        destinationProfile: await profile.exists() ? profile.path : null,
        assumeAdobeRgb: assumeAdobeRgb,
      ),
      request: request,
    );
  }

  /// Builds the deterministic SDR fallback pipeline used when the platform
  /// decoder cannot read an extended format. Sources are first converted to
  /// sRGB and then stale source profiles are removed, so the PNG handed to
  /// Flutter has one unambiguous color space. HDR sources are converted
  /// with Reinhard highlight compression in linear RGB, followed by the sRGB
  /// transfer. This preserves highlight steps on ordinary SDR displays.
  static List<String> decodeArguments(
    String path, {
    int? targetWidth,
    int? targetHeight,
    int frame = 0,
    String? crop,
    String? destinationProfile,
    bool assumeAdobeRgb = false,
  }) {
    final extension = paths.extension(path).toLowerCase();
    final isHdr = extension == '.hdr' || extension == '.exr';
    return [
      '$path[$frame]',
      if (assumeAdobeRgb) ...[
        // ImageMagick's Adobe98 matrix path uses the sRGB transfer. Normalize
        // Adobe RGB's 563/256 gamma first, then apply its gamut conversion.
        '-set', 'colorspace', 'RGB',
        '-gamma', '0.4547069271758437',
        '-colorspace', 'sRGB',
        '-set', 'colorspace', 'Adobe98',
        '-colorspace', 'sRGB',
      ],
      '-auto-orient',
      if (crop != null) ...['-crop', crop, '+repage'],
      if (targetWidth != null || targetHeight != null) ...[
        '-resize',
        '${targetWidth ?? ''}x${targetHeight ?? ''}>',
      ],
      if (isHdr) ...[
        '-set',
        'colorspace',
        'RGB',
        // Reinhard in linear light: x / (1 + x). ImageMagick evaluate Add
        // accepts percentages of QuantumRange, so 100% adds exactly 1.0
        // independently of Q16/Q32. Restrict operations to RGB, not alpha.
        '-channel',
        'RGB',
        '-evaluate',
        'Max',
        '0',
        '-evaluate',
        'Add',
        '100%',
        '-evaluate',
        'Pow',
        '-1',
        '-negate',
        '+channel',
        '-colorspace',
        'sRGB',
        '-clamp',
      ] else ...[
        if (destinationProfile != null) ...[
          // Matrix/TRC sRGB (e.g. libjxl) and the destination ICC may use
          // different black points. Match them instead of crushing shadows.
          '-intent',
          'relative',
          '-black-point-compensation',
          '-profile',
          destinationProfile,
        ],
        '-colorspace',
        'sRGB',
      ],
      '-strip',
      '-depth',
      '8',
      'png32:-',
    ];
  }

  Future<PlatformDecodedImage?> decodePlatform(
    String path, {
    int? targetWidth,
    int? targetHeight,
    Map<String, int>? region,
    bool preserveHdr = false,
    DecodeRequest? request,
  }) {
    return _platform.decode(
      path,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      region: region,
      preserveHdr: preserveHdr,
      request: request,
    );
  }

  Future<int> frameCount(String path) async {
    final bytes = await run([path, '-format', '%n', 'info:']);
    final count = int.tryParse(utf8.decode(bytes).trim());
    return count == null || count < 1 ? 1 : count;
  }

  Future<Map<String, dynamic>> metadata(
    String path, {
    DecodeRequest? request,
  }) async {
    final bytes = await run([
      '$path[0]',
      '-ping',
      '-format',
      '%m|%w|%h|%[EXIF:Orientation]|%[EXIF:Make]|%[EXIF:Model]|%[EXIF:DateTimeOriginal]|%[EXIF:LensModel]|%[EXIF:FNumber]|%[EXIF:ExposureTime]|%[EXIF:PhotographicSensitivity]|%[EXIF:FocalLength]|%[EXIF:ExposureBiasValue]|%[EXIF:WhiteBalance]|%[EXIF:Flash]|%[EXIF:GPSLatitude]|%[EXIF:GPSLongitude]|%[colorspace]|%z|%[channels]|%[orientation]|%[EXIF:GPSLatitudeRef]|%[EXIF:GPSLongitudeRef]|%[EXIF:OffsetTimeOriginal]|%[EXIF:SubSecTimeOriginal]',
      'info:',
    ], request: request);
    final parts = utf8.decode(bytes).trim().split('|');
    return <String, dynamic>{
      'format': parts.elementAtOrNull(0) ?? '',
      'width': int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0,
      'height': int.tryParse(parts.elementAtOrNull(2) ?? '') ?? 0,
      // HEIF readers may already apply container rotation while retaining the
      // original EXIF tag. Geometry follows ImageMagick's current orientation.
      'orientation': switch (parts.elementAtOrNull(20)) {
        'TopLeft' => 1,
        'TopRight' => 2,
        'BottomRight' => 3,
        'BottomLeft' => 4,
        'LeftTop' => 5,
        'RightTop' => 6,
        'RightBottom' => 7,
        'LeftBottom' => 8,
        _ => int.tryParse(parts.elementAtOrNull(3) ?? '') ?? 1,
      },
      'make': parts.elementAtOrNull(4) ?? '',
      'model': parts.elementAtOrNull(5) ?? '',
      'dateTimeOriginal': parts.elementAtOrNull(6) ?? '',
      'lensModel': parts.elementAtOrNull(7) ?? '',
      'fNumber': parts.elementAtOrNull(8) ?? '',
      'exposureTime': parts.elementAtOrNull(9) ?? '',
      'iso': parts.elementAtOrNull(10) ?? '',
      'focalLength': parts.elementAtOrNull(11) ?? '',
      'exposureBias': parts.elementAtOrNull(12) ?? '',
      'whiteBalance': parts.elementAtOrNull(13) ?? '',
      'flash': parts.elementAtOrNull(14) ?? '',
      'gpsLatitude': parts.elementAtOrNull(15) ?? '',
      'gpsLongitude': parts.elementAtOrNull(16) ?? '',
      'gpsLatitudeRef': parts.elementAtOrNull(21) ?? '',
      'gpsLongitudeRef': parts.elementAtOrNull(22) ?? '',
      'offsetTimeOriginal': parts.elementAtOrNull(23) ?? '',
      'subSecTimeOriginal': parts.elementAtOrNull(24) ?? '',
      'colorSpace': parts.elementAtOrNull(17) ?? '',
      'bitDepth': parts.elementAtOrNull(18) ?? '',
      'hasAlpha': (parts.elementAtOrNull(19) ?? '').toLowerCase().contains('a'),
      'codec': parts.elementAtOrNull(0) ?? '',
    };
  }
}
