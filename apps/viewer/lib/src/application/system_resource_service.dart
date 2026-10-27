import 'package:flutter/services.dart';

/// Host measurements, not process limits or estimates from image dimensions.
/// A missing measurement stays unknown so callers can choose a conservative budget.
class SystemResourceSnapshot {
  const SystemResourceSnapshot({
    this.physicalMemoryBytes,
    this.availableMemoryBytes,
    this.availableDiskBytes,
    this.diskCapacityBytes,
  });

  final int? physicalMemoryBytes;
  final int? availableMemoryBytes;
  final int? availableDiskBytes;
  final int? diskCapacityBytes;
}

class SystemResourceService {
  const SystemResourceService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('shenview/system_resources');

  final MethodChannel _channel;

  /// Reads available memory and, if supplied, the volume containing [diskPath].
  /// Native hosts resolve an uncreated cache directory to its existing parent.
  Future<SystemResourceSnapshot?> read({String? diskPath}) async {
    try {
      final response = await _channel.invokeMethod<Object?>('read', {
        if (diskPath != null && diskPath.isNotEmpty) 'diskPath': diskPath,
      });
      if (response is! Map) return null;
      final physical = _bytes(response['physicalMemoryBytes'], positive: true);
      final capacity = _bytes(response['diskCapacityBytes'], positive: true);
      final memory = _bounded(
        _bytes(response['availableMemoryBytes']),
        physical,
      );
      final disk = _bounded(_bytes(response['availableDiskBytes']), capacity);
      if (physical == null &&
          memory == null &&
          capacity == null &&
          disk == null) {
        return null;
      }
      return SystemResourceSnapshot(
        physicalMemoryBytes: physical,
        availableMemoryBytes: memory,
        availableDiskBytes: disk,
        diskCapacityBytes: capacity,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static int? _bytes(Object? value, {bool positive = false}) =>
      value is int && value >= (positive ? 1 : 0) ? value : null;

  static int? _bounded(int? value, int? ceiling) =>
      value == null || ceiling == null ? value : value.clamp(0, ceiling);
}
