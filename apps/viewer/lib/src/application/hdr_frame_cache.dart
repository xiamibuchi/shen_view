import 'dart:async';
import 'dart:math' as math;

import '../domain/image_resource_key.dart';
import 'decode_request.dart';
import 'hdr_frame.dart';

/// Source frames are independent of display size and output HDR capability.
/// Each consumer owns its cancellation; the worker stops after the last leaves.
class HdrFrameCache {
  HdrFrameCache({this.onChanged});

  final void Function()? onChanged;
  final _frames = <ImageFileVersion, HdrFrame>{};
  final _pending = <ImageFileVersion, _PendingFrame>{};
  int _limitBytes = 0;
  int _bytes = 0;
  bool _disposed = false;

  int get currentBytes => _bytes;

  void configure(int limitBytes) {
    _limitBytes = math.max(0, limitBytes);
    _trim();
  }

  Future<HdrFrame> load(
    ImageFileVersion key,
    DecodeRequest consumer,
    Future<HdrFrame> Function(DecodeRequest) decode,
  ) {
    consumer.throwIfCancelled();
    if (_disposed) throw DecodeCancelled();
    final cached = _frames.remove(key);
    if (cached != null) {
      _frames[key] = cached;
      return Future.value(cached);
    }
    final existing = _pending[key];
    final pending = existing ?? _PendingFrame();
    _pending[key] = pending;
    final waiter = _FrameWaiter();
    void cancel() {
      if (!pending.waiters.contains(waiter)) return;
      consumer.removeCancelListener(cancel);
      if (pending.waiters.length == 1) {
        // The last caller holds the decode reservation until the actual
        // process and source lease drain, including cancellation cleanup.
        pending.request.cancel();
        if (identical(_pending[key], pending)) _pending.remove(key);
      } else {
        pending.waiters.remove(waiter);
        waiter.result.completeError(DecodeCancelled());
      }
    }

    waiter.detach = () => consumer.removeCancelListener(cancel);
    pending.waiters.add(waiter);
    consumer.addCancelListener(cancel);
    if (existing == null && !pending.request.cancelled) {
      unawaited(_decode(key, pending, decode));
    }
    return waiter.result.future;
  }

  Future<void> _decode(
    ImageFileVersion key,
    _PendingFrame pending,
    Future<HdrFrame> Function(DecodeRequest) decode,
  ) async {
    try {
      final frame = await decode(pending.request);
      pending.request.throwIfCancelled();
      if (!_disposed && identical(_pending[key], pending)) {
        if (frame.pixels.lengthInBytes <= _limitBytes) {
          _frames[key] = frame;
          _bytes += frame.pixels.lengthInBytes;
          _trim();
          onChanged?.call();
        }
      }
      for (final waiter in pending.waiters.toList()) {
        waiter.detach();
        waiter.result.complete(frame);
      }
    } catch (error, stack) {
      final failure = pending.request.cancelled ? DecodeCancelled() : error;
      for (final waiter in pending.waiters.toList()) {
        waiter.detach();
        waiter.result.completeError(failure, stack);
      }
    } finally {
      pending.waiters.clear();
      if (identical(_pending[key], pending)) _pending.remove(key);
    }
  }

  void _trim() {
    var changed = false;
    while (_bytes > _limitBytes && _frames.isNotEmpty) {
      _bytes -= _frames.remove(_frames.keys.first)!.pixels.lengthInBytes;
      changed = true;
    }
    if (changed) onChanged?.call();
  }

  void invalidate(String path) => _removeWhere((key) => key.path == path);

  void retainPaths(Set<String> paths) =>
      _removeWhere((key) => !paths.contains(key.path));

  void _removeWhere(bool Function(ImageFileVersion) remove) {
    for (final key in _frames.keys.where(remove).toList()) {
      _bytes -= _frames.remove(key)!.pixels.lengthInBytes;
    }
    for (final key in _pending.keys.where(remove).toList()) {
      final pending = _pending.remove(key)!;
      pending.request.cancel();
    }
    onChanged?.call();
  }

  void dispose() {
    _disposed = true;
    _removeWhere((_) => true);
  }
}

class _PendingFrame {
  final request = DecodeRequest();
  final waiters = <_FrameWaiter>{};
}

class _FrameWaiter {
  final result = Completer<HdrFrame>();
  late final void Function() detach;
}
