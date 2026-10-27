import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'codec_process.dart';
import 'decode_request.dart';
import 'indexed_animation_codec.dart';
import 'media_container.dart';
import 'photo_media_info.dart';
import 'photo_media_audio.dart';

/// One decoder and one bounded raw-frame buffer; no decoded movie is retained.
class PhotoMediaCodec
    implements ui.Codec, IndexedAnimationCodec, MediaPlaybackCodec {
  PhotoMediaCodec._(
    this.info,
    this._lease,
    this._releaseFile,
    this._request,
    this._executable,
    this.width,
    this.height,
  ) {
    audio = PhotoMediaAudio(
      _executable,
      _lease.file.path,
      info.audioTracks,
      startOffsetUs: info.seekOriginUs,
    );
    _request?.addCancelListener(dispose);
  }
  final PhotoMediaInfo info;
  final PhotoMediaLease _lease;
  final Future<void> Function()? _releaseFile;
  final DecodeRequest? _request;
  final String _executable;
  final int width, height;
  late final PhotoMediaAudio audio;
  Process? _process;
  MediaByteReader? _output;
  Future<void> _stopped = Future.value();
  bool _disposed = false;
  int _next = 0;
  String _errors = '';

  static Future<PhotoMediaCodec> open(
    String path,
    PhotoMediaInfo info, {
    int? targetWidth,
    int? targetHeight,
    DecodeRequest? request,
    Future<void> Function()? releaseFile,
  }) async {
    PhotoMediaLease? lease;
    try {
      request?.throwIfCancelled();
      final executable = await CodecProcess.locate('ffmpeg', 'SHENVIEW_FFMPEG');
      lease = await info.location.acquire(path, request: request);
      final scale = math.min(
        1.0,
        math.min(
          (targetWidth ?? 2048) / info.width,
          (targetHeight ?? 2048) / info.height,
        ),
      );
      final width = math.max(1, (info.width * scale).round());
      final height = math.max(1, (info.height * scale).round());
      if (width * height > 16777216) throw DecodeBudgetExceeded('视频帧超过解码预算。');
      request?.throwIfCancelled();
      return PhotoMediaCodec._(
        info,
        lease,
        releaseFile,
        request,
        executable,
        width,
        height,
      );
    } on Object {
      await lease?.release();
      await releaseFile?.call();
      rethrow;
    }
  }

  @override
  bool get realtime => true;
  @override
  int get audioTrackCount => info.audioTracks.length;
  @override
  Object? get audioError => audio.error;
  @override
  void synchronizePlayback({
    required int positionMs,
    required double speed,
    required bool playing,
    required bool muted,
    required int audioTrack,
  }) {
    audio.synchronize(
      positionMs: positionMs,
      speed: speed,
      playing: playing && !_disposed,
      muted: muted,
      track: audioTrack,
    );
  }

  @override
  int get frameCount => info.timeline.durations.length;
  @override
  int get repetitionCount => 0;
  @override
  bool get supportsFrameIndex => true;
  @override
  Future<ui.FrameInfo> getNextFrame() => getFrame(_next % frameCount);

  String get _colorFilter {
    final scale = 'scale=$width:$height,setsar=1';
    if (!info.hdr) return '$scale,format=rgba';
    if (info.dolbyVision) {
      return 'libplacebo=w=$width:h=$height:apply_dolbyvision=1:format=rgba:'
          'colorspace=0:color_primaries=1:color_trc=13:range=2:peak_detect=0,setsar=1';
    }
    return '$scale,zscale=t=linear:npl=100,format=gbrpf32le,'
        'tonemap=mobius:desat=0,zscale=p=bt709:t=iec61966-2-1:m=gbr:r=full,format=rgba';
  }

  Future<void> _start(int index) async {
    await _stop();
    if (_disposed) throw DecodeCancelled();
    final filters = info.alphaIndex == null
        ? '[0:${info.videoIndex}]$_colorFilter[out]'
        : '[0:${info.videoIndex}]$_colorFilter[color];[0:${info.alphaIndex}]scale=$width:$height,format=gray[alpha];[color][alpha]alphamerge[out]';
    final process = await Process.start(_executable, [
      '-nostdin',
      '-v',
      'error',
      '-threads',
      '2',
      '-filter_complex_threads',
      '1',
      '-protocol_whitelist',
      'file,pipe',
      if (index > 0) ...[
        '-ss',
        ((info.seekOriginUs + info.timestampsUs[index]) / 1000000)
            .toStringAsFixed(6),
      ],
      '-i',
      _lease.file.path,
      '-filter_complex',
      filters,
      '-map',
      '[out]',
      '-an',
      '-sn',
      '-dn',
      '-fps_mode',
      'passthrough',
      '-c:v',
      'rawvideo',
      '-threads:v',
      '1',
      '-pix_fmt',
      'rgba',
      '-f',
      'rawvideo',
      'pipe:1',
    ]);
    _process = process;
    _errors = '';
    unawaited(
      process.stderr.transform(utf8.decoder).forEach((text) {
        if (_errors.length < 8192) {
          _errors += text.substring(
            0,
            math.min(text.length, 8192 - _errors.length),
          );
        }
      }),
    );
    _output = MediaByteReader(process.stdout);
    if (_disposed) {
      await _stop();
      throw DecodeCancelled();
    }
    _next = index;
  }

  Future<void> _stop() async {
    final process = _process;
    final output = _output;
    _process = null;
    _output = null;
    process?.kill();
    if (process != null) {
      _stopped = () async {
        await output?.close();
        await process.exitCode;
      }();
    }
    await _stopped;
  }

  @override
  Future<ui.FrameInfo> getFrame(int index) async {
    if (index < 0 || index >= frameCount) {
      throw RangeError.index(index, info.timestampsUs);
    }
    if (_disposed) throw DecodeCancelled();
    try {
      return await _frame(index).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          dispose();
          throw DecodeTimedOut('动态照片解码超时，请重试。');
        },
      );
    } on Object {
      dispose();
      rethrow;
    }
  }

  Future<ui.FrameInfo> _frame(int index) async {
    if (_process == null || index != _next) await _start(index);
    final Uint8List pixels;
    try {
      pixels = await _output!.bytes(width * height * 4);
    } on FormatException {
      throw FormatException('动态照片取帧失败：$_errors');
    }
    if (_disposed) throw DecodeCancelled();
    if (info.alphaIndex != null && !info.premultipliedAlpha) {
      for (var i = 0; i < pixels.length; i += 4) {
        final a = pixels[i + 3];
        for (var c = 0; c < 3; c++) {
          pixels[i + c] = (pixels[i + c] * a + 127) ~/ 255;
        }
      }
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    ui.Codec? codec;
    try {
      codec = await descriptor.instantiateCodec();
      final image = (await codec.getNextFrame()).image;
      if (_disposed) {
        image.dispose();
        throw DecodeCancelled();
      }
      _next = index + 1;
      return _MediaFrame(
        image,
        Duration(milliseconds: info.timeline.durations[index]),
      );
    } finally {
      codec?.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _request?.removeCancelListener(dispose);
    unawaited(() async {
      await audio.dispose();
      await _stop();
      await _lease.release();
      await _releaseFile?.call();
    }());
  }
}

class _MediaFrame implements ui.FrameInfo {
  const _MediaFrame(this.image, this.duration);
  @override
  final ui.Image image;
  @override
  final Duration duration;
}

class MediaByteReader {
  MediaByteReader(Stream<List<int>> stream) : _chunks = StreamIterator(stream);
  final StreamIterator<List<int>> _chunks;
  List<int> _chunk = const [];
  int _offset = 0;
  Future<Uint8List> bytes(int count) async {
    final result = Uint8List(count);
    var offset = 0;
    while (offset < count) {
      while (_offset == _chunk.length) {
        if (!await _chunks.moveNext()) {
          throw const FormatException('Truncated video frame');
        }
        _chunk = _chunks.current;
        _offset = 0;
      }
      final take = math.min(count - offset, _chunk.length - _offset);
      result.setRange(offset, offset + take, _chunk, _offset);
      _offset += take;
      offset += take;
    }
    return result;
  }

  Future<void> close() => _chunks.cancel();
}
