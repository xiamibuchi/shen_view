import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';

import 'hdr_decoder.dart';
import 'hdr_frame.dart';
import 'native_decoder.dart';

class HdrDisplayCapabilities {
  const HdrDisplayCapabilities({
    this.available = false,
    this.output = 'SDR',
    this.headroom = 1,
    this.reason = 'unsupported',
    this.colorManagement = 'system',
    this.displayProfile,
  });

  final bool available;
  final String output;
  final double headroom;
  final String reason;
  final String colorManagement;
  final String? displayProfile;

  factory HdrDisplayCapabilities.fromMap(Map<dynamic, dynamic> value) =>
      HdrDisplayCapabilities(
        available: value['available'] == true,
        output: value['output'] as String? ?? 'SDR',
        headroom: (value['headroom'] as num?)?.toDouble() ?? 1,
        reason: value['reason'] as String? ?? 'unsupported',
        colorManagement: value['colorManagement'] as String? ?? 'system',
        displayProfile: value['displayProfile'] as String?,
      );
}

/// A separate native surface: never passes float frames through Flutter's SDR
/// external-texture/image compositor. Failure only removes the HDR overlay.
class HdrDisplayService {
  HdrDisplayService({NativeDecoder? decoder})
    : _decoder = decoder ?? NativeDecoder() {
    if (!_listening) {
      _listening = true;
      channel.setMethodCallHandler((call) async {
        if (call.method == 'invalidated') {
          _invalidations.add(call.arguments as String? ?? 'device-failed');
        }
      });
    }
  }
  static const channel = MethodChannel('shenview/hdr_display');
  static bool _listening = false;
  static final _invalidations = StreamController<String>.broadcast();
  static final instance = HdrDisplayService();
  Stream<String> get invalidations => _invalidations.stream;
  final NativeDecoder _decoder;
  Future<HdrDisplayCapabilities>? _probe;

  Future<HdrDisplayCapabilities> capabilities() => _probe ??= _capabilities();

  Future<HdrDisplayCapabilities> _capabilities() async {
    try {
      if (!Platform.isWindows && !Platform.isMacOS) {
        return const HdrDisplayCapabilities();
      }
      final result = await channel.invokeMapMethod<dynamic, dynamic>(
        'capabilities',
      );
      return HdrDisplayCapabilities.fromMap(result ?? const {});
    } catch (_) {
      return const HdrDisplayCapabilities(reason: 'native-unavailable');
    } finally {
      _probe = null;
    }
  }

  Future<HdrFrame> decode(String path, DecodeRequest request) async {
    return HdrDecoder(decoder: _decoder).decode(path, request);
  }

  Future<bool> upload(int id, HdrFrame frame) async {
    try {
      return await channel.invokeMethod<bool>('upload', {
            'id': id,
            'width': frame.width,
            'height': frame.height,
            'pixels': frame.pixels,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> geometry(Map<String, Object> arguments) async {
    try {
      return await channel.invokeMethod<bool>('geometry', arguments) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> remove(int id) async {
    try {
      await channel.invokeMethod<void>('remove', {'id': id});
    } catch (_) {
      // The engine may already be closing; the native owner frees all surfaces.
    }
  }
}
