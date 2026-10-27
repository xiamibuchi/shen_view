import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../domain/animation_timeline.dart';
import 'codec_process.dart';
import 'decode_request.dart';
import 'indexed_animation_codec.dart';

class AvifAnimationInfo {
  AvifAnimationInfo._(Map<String, dynamic> data)
    : width = data['width'] as int,
      height = data['height'] as int,
      depth = data['depth'] as int,
      hasAlpha = data['alpha'] as bool,
      sequence = data['sequence'] as bool,
      repetitions = data['repetitions'] as int,
      timeline = AnimationTimeline(
        (data['durations'] as List).cast<int>(),
        totalPlays: (data['repetitions'] as int) < 0
            ? (data['repetitions'] == -1 ? 0 : 1)
            : (data['repetitions'] as int) + 1,
      ) {
    if (width < 1 ||
        height < 1 ||
        width * height > 16 * 1024 * 1024 ||
        timeline.durations.isEmpty ||
        timeline.durations.length > 10000) {
      throw const FormatException('AVIF metadata bounds');
    }
  }

  final int width, height, depth, repetitions;
  final bool hasAlpha, sequence;
  final AnimationTimeline timeline;
  bool get animated => sequence && timeline.durations.length > 1;
}

/// A persistent, demand-driven libavif process; no decoded frame list is kept.
class AvifCodec implements ui.Codec, IndexedAnimationCodec {
  AvifCodec._(
    this._process,
    this._output,
    this._request,
    this._targetWidth,
    this._targetHeight,
  );

  final Process _process;
  final _AvifOutput _output;
  final DecodeRequest? _request;
  final int? _targetWidth, _targetHeight;
  late final AvifAnimationInfo info;
  bool _disposed = false;
  int _next = 0;

  static Future<AvifAnimationInfo> inspect(
    String path, {
    DecodeRequest? request,
  }) async {
    final helper = await CodecProcess.locate(
      'viewer_avif_animation',
      'SHENVIEW_AVIF_ANIMATION',
    );
    final bytes = await CodecProcess.run(
      helper,
      ['probe', path],
      request: request,
      maxOutput: 256 * 1024,
    );
    return AvifAnimationInfo._(
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
    );
  }

  static Future<AvifCodec> open(
    String path, {
    required int maxPixels,
    int? targetWidth,
    int? targetHeight,
    DecodeRequest? request,
    Future<void> Function()? releaseFile,
  }) async {
    AvifCodec? codec;
    Process? process;
    try {
      request?.throwIfCancelled();
      final helper = await CodecProcess.locate(
        'viewer_avif_animation',
        'SHENVIEW_AVIF_ANIMATION',
      );
      request?.throwIfCancelled();
      process = await Process.start(helper, ['serve', path, '$maxPixels']);
      if (releaseFile != null) {
        // libavif reads samples lazily; archive leases outlive the entire session.
        unawaited(process.exitCode.then((_) => releaseFile()));
      }
      codec = AvifCodec._(
        process,
        _AvifOutput(process.stdout),
        request,
        targetWidth,
        targetHeight,
      );
      unawaited(process.stderr.drain<void>());
      request?.addCancelListener(codec.dispose);
      request?.throwIfCancelled();
      codec.info = await codec._operation(() async {
        final line = await codec!._output.line(256 * 1024);
        return AvifAnimationInfo._(jsonDecode(line) as Map<String, dynamic>);
      });
      return codec;
    } on Object {
      codec?.dispose();
      process?.kill();
      if (process == null && releaseFile != null) await releaseFile();
      rethrow;
    }
  }

  Future<T> _operation<T>(Future<T> Function() action) async {
    if (_disposed) throw DecodeCancelled();
    try {
      return await action().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          dispose();
          throw DecodeTimedOut('AVIF 动画解码超时，请重试或选择较小的图片。');
        },
      );
    } on Object {
      dispose();
      rethrow;
    }
  }

  @override
  int get frameCount => info.timeline.durations.length;
  @override
  int get repetitionCount =>
      info.timeline.totalPlays == 0 ? -1 : info.timeline.totalPlays - 1;

  @override
  bool get supportsFrameIndex => true;

  @override
  Future<ui.FrameInfo> getNextFrame() => getFrame(_next);

  @override
  Future<ui.FrameInfo> getFrame(int index) => _operation(() async {
    if (index < 0 || index >= frameCount) {
      throw RangeError.index(index, info.timeline.durations);
    }
    _process.stdin.writeln(index);
    await _process.stdin.flush();
    final fields = (await _output.line(128)).split(' ');
    if (fields.length != 4 || fields[0] != 'FRAME') {
      throw const FormatException('AVIF frame header');
    }
    final width = int.parse(fields[1]), height = int.parse(fields[2]);
    final size = int.parse(fields[3]);
    if (width < 1 ||
        height < 1 ||
        width * height > info.width * info.height ||
        size != width * height * 4) {
      throw const FormatException('AVIF frame bounds');
    }
    final pixels = await _output.bytes(size);
    if (_disposed) throw DecodeCancelled();
    final scale = math.min(
      1.0,
      math.min(
        (_targetWidth ?? width) / width,
        (_targetHeight ?? height) / height,
      ),
    );
    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      // Raw Flutter RGBA is premultiplied sRGB, including HDR tone mapping.
      descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (width * scale).round()),
        targetHeight: math.max(1, (height * scale).round()),
      );
      final image = (await codec.getNextFrame()).image;
      if (_disposed) {
        image.dispose();
        throw DecodeCancelled();
      }
      _next = (index + 1) % frameCount;
      return _AvifFrame(
        image,
        Duration(milliseconds: info.timeline.durations[index]),
      );
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  });

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _request?.removeCancelListener(dispose);
    _process.kill();
    unawaited(_process.stdin.close().catchError((Object _) {}));
    unawaited(_output.close());
  }
}

class _AvifFrame implements ui.FrameInfo {
  const _AvifFrame(this.image, this.duration);
  @override
  final ui.Image image;
  @override
  final Duration duration;
}

class _AvifOutput {
  _AvifOutput(Stream<List<int>> stream) : _chunks = StreamIterator(stream);
  final StreamIterator<List<int>> _chunks;
  List<int> _chunk = const [];
  int _offset = 0;

  Future<void> _ready() async {
    while (_offset == _chunk.length) {
      if (!await _chunks.moveNext()) {
        throw const FormatException('AVIF decoder stopped unexpectedly');
      }
      _chunk = _chunks.current;
      _offset = 0;
    }
  }

  Future<String> line(int limit) async {
    final result = BytesBuilder(copy: false);
    while (result.length <= limit) {
      await _ready();
      final end = _chunk.indexOf(10, _offset);
      final count = (end < 0 ? _chunk.length : end) - _offset;
      if (result.length + count > limit) break;
      result.add(_chunk.sublist(_offset, _offset + count));
      _offset += count;
      if (end >= 0) {
        _offset++;
        return utf8.decode(result.takeBytes());
      }
    }
    throw const FormatException('AVIF header budget exceeded');
  }

  Future<Uint8List> bytes(int count) async {
    final result = Uint8List(count);
    var offset = 0;
    while (offset < count) {
      await _ready();
      final take = math.min(count - offset, _chunk.length - _offset);
      result.setRange(offset, offset + take, _chunk, _offset);
      _offset += take;
      offset += take;
    }
    return result;
  }

  Future<void> close() => _chunks.cancel();
}
