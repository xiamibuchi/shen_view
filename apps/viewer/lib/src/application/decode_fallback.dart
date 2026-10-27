import 'dart:ui' as ui;

import 'decode_request.dart';

class DecodeBackend {
  const DecodeBackend(this.name, this.open);
  final String name;
  final Future<ui.Codec?> Function() open;
}

class ImageDecodeFailure implements Exception {
  ImageDecodeFailure(this.attempts);
  final Map<String, Object> attempts;
  @override
  String toString() =>
      '图片解码失败：${attempts.entries.map((e) => '${e.key}: ${e.value}').join('; ')}';
}

/// A backend is successful only once its first frame has been generated.
Future<FirstFrameCodec> decodeWithFallback(
  List<DecodeBackend> backends, {
  required DecodeRequest request,
  bool speculative = false,
  bool Function()? speculativeNow,
}) async {
  final failures = <String, Object>{};
  for (final backend in backends) {
    request.throwIfCancelled();
    ui.Codec? codec;
    try {
      codec = await backend.open();
      request.throwIfCancelled();
      if (codec == null) {
        failures[backend.name] = StateError('不支持此图片');
        continue;
      }
      final frame = await codec.getNextFrame();
      if (request.cancelled) {
        frame.image.dispose();
        throw DecodeCancelled();
      }
      return FirstFrameCodec(codec, frame);
    } on DecodeCancelled {
      codec?.dispose();
      rethrow;
    } on DecodeBudgetExceeded {
      codec?.dispose();
      rethrow;
    } catch (error) {
      codec?.dispose();
      request.throwIfCancelled();
      failures[backend.name] = error;
      // Long background fallback chains belong to explicit viewing demand.
      if ((speculativeNow?.call() ?? speculative) && error is DecodeTimedOut) {
        rethrow;
      }
    }
  }
  throw ImageDecodeFailure(Map.unmodifiable(failures));
}

class FirstFrameCodec implements ui.Codec {
  FirstFrameCodec(this._codec, this._first);
  final ui.Codec _codec;
  ui.FrameInfo? _first;
  bool _disposed = false;
  ui.Image? get firstImage => _first?.image;
  @override
  int get frameCount => _codec.frameCount;
  @override
  int get repetitionCount => _codec.repetitionCount;
  @override
  Future<ui.FrameInfo> getNextFrame() async {
    final frame = _first;
    if (frame != null) {
      _first = null;
      return frame;
    }
    return _codec.getNextFrame();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _first?.image.dispose();
    _first = null;
    _codec.dispose();
  }
}
