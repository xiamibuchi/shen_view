import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'decode_request.dart';
import 'decode_priority.dart';
import 'platform_pixel_conversion.dart';

class PlatformDecodedImage {
  const PlatformDecodedImage({
    required this.width,
    required this.height,
    required this.pixels,
    this.isFloat = false,
  });

  final int width;
  final int height;
  final Uint8List pixels;
  final bool isFloat;

  int get bytesPerPixel => isFloat ? 16 : 4;

  Future<ui.Image> toImage({DecodeRequest? request}) async {
    final codec = await toCodec(request: request);
    try {
      final frame = await codec.getNextFrame();
      if (request?.cancelled ?? false) {
        frame.image.dispose();
        throw DecodeCancelled();
      }
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  Future<ui.Codec> toCodec({DecodeRequest? request}) async {
    request?.throwIfCancelled();
    try {
      return await _codecFromPixels(pixels, isFloat: isFloat, request: request);
    } on DecodeCancelled {
      rethrow;
    } on Object {
      // Some desktop Flutter renderers cannot instantiate float image
      // descriptors even though the native decoder returned valid HDR data.
      // Keep the native float path for capable renderers and tone-map only the
      // failing frame so an HDR file never turns into an error placeholder.
      if (!isFloat) rethrow;
      request?.throwIfCancelled();
      final mapped = await compute(toneMapPlatformFloatPixels, (
        pixels,
        width,
        height,
      ));
      request?.throwIfCancelled();
      return _codecFromPixels(mapped, isFloat: false, request: request);
    }
  }

  Future<ui.Codec> _codecFromPixels(
    Uint8List source, {
    required bool isFloat,
    DecodeRequest? request,
  }) async {
    request?.throwIfCancelled();
    final buffer = await ui.ImmutableBuffer.fromUint8List(source);
    ui.ImageDescriptor? descriptor;
    try {
      request?.throwIfCancelled();
      descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        rowBytes: width * (isFloat ? 16 : 4),
        pixelFormat: isFloat
            ? ui.PixelFormat.rgbaFloat32
            : ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      if (request?.cancelled ?? false) {
        codec.dispose();
        throw DecodeCancelled();
      }
      return _RetainedCodec(codec, descriptor, buffer);
    } catch (_) {
      descriptor?.dispose();
      buffer.dispose();
      rethrow;
    }
  }
}

class _RetainedCodec implements ui.Codec {
  _RetainedCodec(this._codec, this._descriptor, this._buffer);

  final ui.Codec _codec;
  final ui.ImageDescriptor _descriptor;
  final ui.ImmutableBuffer _buffer;
  bool _disposed = false;

  @override
  int get frameCount => _codec.frameCount;

  @override
  int get repetitionCount => _codec.repetitionCount;

  @override
  Future<ui.FrameInfo> getNextFrame() => _codec.getNextFrame();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _codec.dispose();
    _descriptor.dispose();
    _buffer.dispose();
  }
}

class PlatformImageDecoder {
  static const _channel = MethodChannel('shenview/native_decoder');
  static int _nextRequestId = 0;

  Future<Map<Object?, Object?>?> _invoke(
    String method,
    Map<String, Object?> arguments,
    DecodeRequest? request,
  ) async {
    if (!Platform.isWindows && !Platform.isMacOS) return null;
    request?.throwIfCancelled();
    final requestId = ++_nextRequestId;
    Map<String, Object?> scheduling() => {
      'requestId': requestId,
      'priority':
          (request?.priority ??
                  (method == 'metadata'
                      ? DecodePriority.metadata
                      : DecodePriority.foreground))
              .index,
      'distance': request?.distance ?? 0,
    };
    void updatePriority() {
      _channel
          .invokeMethod<void>('updatePriority', scheduling())
          .catchError((_) {});
    }

    void cancel() {
      _channel
          .invokeMethod<void>('cancel', {'requestId': requestId})
          .catchError((_) {});
    }

    request?.addCancelListener(cancel);
    request?.addPriorityListener(updatePriority);
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        method,
        {...arguments, ...scheduling()},
      );
      request?.throwIfCancelled();
      return result;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      request?.throwIfCancelled();
      return null;
    } finally {
      request?.removeCancelListener(cancel);
      request?.removePriorityListener(updatePriority);
    }
  }

  Future<PlatformDecodedImage?> decode(
    String path, {
    int? targetWidth,
    int? targetHeight,
    Map<String, int>? region,
    bool preserveHdr = false,
    DecodeRequest? request,
  }) async {
    final result = await _invoke('decode', {
      'path': path,
      'targetWidth': ?targetWidth,
      'targetHeight': ?targetHeight,
      'region': ?region,
      'preserveHdr': preserveHdr,
    }, request);
    request?.throwIfCancelled();
    if (result == null) return null;
    final width = result['width'];
    final height = result['height'];
    final pixels = result['pixels'];
    if (width is! int || height is! int || pixels is! Uint8List) {
      return null;
    }
    final isFloat = result['pixelFormat'] == 'rgbaFloat32';
    final bytesPerPixel = isFloat ? 16 : 4;
    if (width < 1 ||
        height < 1 ||
        pixels.length != width * height * bytesPerPixel) {
      return null;
    }
    return PlatformDecodedImage(
      width: width,
      height: height,
      pixels: pixels,
      isFloat: isFloat,
    );
  }

  Future<Map<String, dynamic>?> metadata(
    String path, {
    DecodeRequest? request,
  }) async {
    final result = await _invoke('metadata', {'path': path}, request);
    return result?.cast<String, dynamic>();
  }
}
