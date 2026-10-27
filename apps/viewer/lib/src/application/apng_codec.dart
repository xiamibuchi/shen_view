import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as imaging;

import '../domain/animation_timeline.dart';

/// APNG keeps a canvas and a disposal backup, never a list of decoded frames.
class ApngFrameDecoder {
  ApngFrameDecoder(Uint8List bytes, {required int maxPixels}) {
    decoder = imaging.PngDecoder(maxPixels: maxPixels);
    final info = decoder.startDecode(bytes);
    if (info == null || decoder.info.frames.isEmpty) {
      throw const FormatException('Invalid APNG');
    }
    timeline = AnimationTimeline.parse(bytes)!;
    canvas = imaging.Image(
      width: info.width,
      height: info.height,
      numChannels: 4,
    );
  }

  late final imaging.PngDecoder decoder;
  late final AnimationTimeline timeline;
  late imaging.Image canvas;
  imaging.Image? _backup;
  int index = 0;

  imaging.Image next() {
    final frames = decoder.info.frames;
    if (index == 0) {
      canvas.clear();
      _backup = null;
    } else {
      final previous = frames[index - 1];
      switch (previous.dispose) {
        case imaging.PngDisposeMode.background:
          imaging.fillRect(
            canvas,
            x1: previous.xOffset,
            y1: previous.yOffset,
            x2: previous.xOffset + previous.width - 1,
            y2: previous.yOffset + previous.height - 1,
            color: imaging.ColorRgba8(0, 0, 0, 0),
            alphaBlend: false,
          );
        case imaging.PngDisposeMode.previous:
          if (_backup != null) canvas = _backup!;
        case imaging.PngDisposeMode.none:
          break;
      }
      _backup = null;
    }
    final frame = frames[index];
    if (frame.dispose == imaging.PngDisposeMode.previous) {
      _backup = imaging.Image.from(canvas, noAnimation: true);
    }
    final patch = decoder.decodeFrame(index);
    if (patch == null) throw const FormatException('Invalid APNG frame');
    imaging.compositeImage(
      canvas,
      patch.convert(numChannels: 4),
      dstX: frame.xOffset,
      dstY: frame.yOffset,
      blend: frame.blend == imaging.PngBlendMode.source
          ? imaging.BlendMode.direct
          : imaging.BlendMode.alpha,
    );
    index = (index + 1) % frames.length;
    return canvas;
  }
}

class ApngCodec implements ui.Codec {
  ApngCodec._(
    this._isolate,
    this._port,
    this._replies,
    this._commands,
    this.frameCount,
    this.repetitionCount,
    this._targetWidth,
    this._targetHeight,
  );

  final Isolate _isolate;
  final ReceivePort _port;
  final StreamIterator<Object?> _replies;
  final SendPort _commands;
  final int? _targetWidth;
  final int? _targetHeight;
  bool _disposed = false;
  @override
  final int frameCount;
  @override
  final int repetitionCount;

  static Future<ApngCodec> open(
    String path, {
    required int maxPixels,
    int? targetWidth,
    int? targetHeight,
  }) async {
    final port = ReceivePort();
    final replies = StreamIterator<Object?>(port);
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(_worker, (port.sendPort, path, maxPixels));
      if (!await replies.moveNext()) {
        throw const FormatException('APNG worker stopped');
      }
      final response = replies.current;
      if (response is String) throw FormatException(response);
      final (commands, count, plays) = response! as (SendPort, int, int);
      return ApngCodec._(
        isolate,
        port,
        replies,
        commands,
        count,
        plays == 0 ? -1 : plays - 1,
        targetWidth,
        targetHeight,
      );
    } on Object {
      isolate?.kill(priority: Isolate.immediate);
      port.close();
      unawaited(replies.cancel());
      rethrow;
    }
  }

  @override
  Future<ui.FrameInfo> getNextFrame() async {
    if (_disposed) throw StateError('APNG codec disposed');
    _commands.send(null);
    if (!await _replies.moveNext() || _disposed) {
      throw StateError('APNG codec disposed');
    }
    final response = _replies.current;
    if (response is String) throw FormatException(response);
    final (pixels, width, height, delay, encoded) =
        response! as (TransferableTypedData, int, int, int, bool);
    final result = Completer<ui.Image>();
    final scale = math.min(
      1.0,
      math.min(
        (_targetWidth ?? width) / width,
        (_targetHeight ?? height) / height,
      ),
    );
    if (encoded) {
      final codec = await ui.instantiateImageCodec(
        pixels.materialize().asUint8List(),
        targetWidth: math.max(1, (width * scale).round()),
        targetHeight: math.max(1, (height * scale).round()),
      );
      try {
        final frame = await codec.getNextFrame();
        if (_disposed) {
          frame.image.dispose();
          throw StateError('APNG codec disposed');
        }
        return _Frame(frame.image, Duration(milliseconds: delay));
      } finally {
        codec.dispose();
      }
    }
    ui.decodeImageFromPixels(
      pixels.materialize().asUint8List(),
      width,
      height,
      ui.PixelFormat.rgba8888,
      result.complete,
      targetWidth: math.max(1, (width * scale).round()),
      targetHeight: math.max(1, (height * scale).round()),
    );
    final image = await result.future;
    if (_disposed) {
      image.dispose();
      throw StateError('APNG codec disposed');
    }
    return _Frame(image, Duration(milliseconds: delay));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _isolate.kill(priority: Isolate.immediate);
    _port.close();
    unawaited(_replies.cancel());
  }

  static void _worker((SendPort, String, int) args) {
    final (reply, path, maxPixels) = args;
    try {
      final bytes = File(path).readAsBytesSync();
      final colors = _colorChunks(bytes);
      final decoder = ApngFrameDecoder(bytes, maxPixels: maxPixels);
      final commands = ReceivePort();
      reply.send((
        commands.sendPort,
        decoder.timeline.durations.length,
        decoder.timeline.totalPlays,
      ));
      commands.listen((_) {
        try {
          final delay = decoder.timeline.durations[decoder.index];
          final image = decoder.next();
          // Raw RGBA loses the PNG color description. Keep tagged frames encoded
          // until Flutter creates a color-managed image on the rendering isolate.
          final pixels = colors.isEmpty
              ? _premultipliedPixels(image)
              : _taggedPng(image, colors);
          reply.send((
            TransferableTypedData.fromList([pixels]),
            image.width,
            image.height,
            delay,
            colors.isNotEmpty,
          ));
        } on Object catch (error) {
          reply.send(error.toString());
        }
      });
    } on Object catch (error) {
      reply.send(error.toString());
    }
  }
}

Uint8List _premultipliedPixels(imaging.Image image) {
  // Flutter's raw RGBA entry point expects associated alpha. Keep the
  // compositor's straight-alpha canvas intact for the next frame.
  final pixels = Uint8List.fromList(
    image.getBytes(order: imaging.ChannelOrder.rgba),
  );
  for (var i = 0; i < pixels.length; i += 4) {
    final alpha = pixels[i + 3];
    if (alpha == 255) continue;
    for (var c = 0; c < 3; c++) {
      pixels[i + c] = (pixels[i + c] * alpha + 127) ~/ 255;
    }
  }
  return pixels;
}

Uint8List _colorChunks(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final chunks = BytesBuilder(copy: false);
  for (var offset = 8; offset + 12 <= bytes.length;) {
    final length = data.getUint32(offset);
    if (length > bytes.length - offset - 12) break;
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    if (type == 'IDAT') break;
    if ({'iCCP', 'cICP', 'sRGB', 'gAMA', 'cHRM'}.contains(type)) {
      if (chunks.length + length + 12 > 4 * 1024 * 1024) {
        throw const FormatException('APNG color metadata budget');
      }
      chunks.add(Uint8List.sublistView(bytes, offset, offset + length + 12));
    }
    offset += length + 12;
  }
  return chunks.takeBytes();
}

Uint8List _taggedPng(imaging.Image image, Uint8List colors) {
  final png = imaging.encodePng(image, level: 0, singleFrame: true);
  return (BytesBuilder(copy: false)
        ..add(Uint8List.sublistView(png, 0, 33))
        ..add(colors)
        ..add(Uint8List.sublistView(png, 33)))
      .takeBytes();
}

class _Frame implements ui.FrameInfo {
  const _Frame(this.image, this.duration);
  @override
  final ui.Image image;
  @override
  final Duration duration;
}
