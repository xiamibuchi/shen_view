import 'dart:math' as math;

import 'app_config_store.dart';

/// Normal-window geometry in logical screen coordinates. This partition is
/// separate from preferences so stale settings snapshots cannot replace it.
class WindowPlacement {
  const WindowPlacement({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.updatedAt,
    required this.source,
    this.scaleFactor = 1,
  });

  static const minimumWidth = 600.0;
  static const minimumHeight = 460.0;
  final double x;
  final double y;
  final double width;
  final double height;
  final int updatedAt;
  final String source;
  final double scaleFactor;

  static WindowPlacement? fromJson(Object? value) {
    if (value is! Map) return null;
    final numbers = [value['x'], value['y'], value['width'], value['height']];
    if (numbers.any((number) => number is! num || !number.isFinite)) {
      return null;
    }
    final width = (value['width'] as num).toDouble();
    final height = (value['height'] as num).toDouble();
    final scale = value['scaleFactor'] ?? 1;
    if (width <= 0 ||
        height <= 0 ||
        value['updatedAt'] is! int ||
        value['source'] is! String ||
        scale is! num ||
        !scale.isFinite ||
        scale <= 0) {
      return null;
    }
    return WindowPlacement(
      x: (value['x'] as num).toDouble(),
      y: (value['y'] as num).toDouble(),
      width: width,
      height: height,
      updatedAt: value['updatedAt'] as int,
      source: value['source'] as String,
      scaleFactor: scale.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'updatedAt': updatedAt,
    'source': source,
    'scaleFactor': scaleFactor,
  };

  /// Choose the work area with the largest intersection, or the primary area
  /// when a previously used monitor was disconnected. Negative origins are valid.
  WindowPlacement fitToWorkAreas(List<WindowWorkArea> areas) {
    if (areas.isEmpty) return this;
    var area = areas.first;
    var largest = 0.0;
    final physicalX = x * scaleFactor;
    final physicalY = y * scaleFactor;
    for (final candidate in areas) {
      final overlap =
          math.max(
            0.0,
            math.min(
                  physicalX + width * scaleFactor,
                  candidate.right * candidate.scaleFactor,
                ) -
                math.max(physicalX, candidate.x * candidate.scaleFactor),
          ) *
          math.max(
            0.0,
            math.min(
                  physicalY + height * scaleFactor,
                  candidate.bottom * candidate.scaleFactor,
                ) -
                math.max(physicalY, candidate.y * candidate.scaleFactor),
          );
      if (overlap > largest) {
        largest = overlap;
        area = candidate;
      }
    }
    final fittedWidth = width
        .clamp(minimumWidth, math.max(minimumWidth, area.width))
        .toDouble();
    final fittedHeight = height
        .clamp(minimumHeight, math.max(minimumHeight, area.height))
        .toDouble();
    return WindowPlacement(
      x: (physicalX / area.scaleFactor)
          .clamp(area.x, math.max(area.x, area.right - fittedWidth))
          .toDouble(),
      y: (physicalY / area.scaleFactor)
          .clamp(area.y, math.max(area.y, area.bottom - fittedHeight))
          .toDouble(),
      width: fittedWidth,
      height: fittedHeight,
      updatedAt: updatedAt,
      source: source,
      scaleFactor: area.scaleFactor,
    );
  }
}

class WindowWorkArea {
  const WindowWorkArea(
    this.x,
    this.y,
    this.width,
    this.height, {
    this.scaleFactor = 1,
  });
  final double x;
  final double y;
  final double width;
  final double height;
  final double scaleFactor;
  double get right => x + width;
  double get bottom => y + height;
}

class WindowPlacementStore {
  const WindowPlacementStore(this.config);
  final AppConfigStore config;

  Future<WindowPlacement?> load() async =>
      WindowPlacement.fromJson((await config.readOrEmpty())['windowPlacement']);

  /// Event time, not close/write time, decides the default for future windows.
  /// A delayed save from another process must never roll back a newer change.
  Future<void> save(WindowPlacement placement) => config.update((config) {
    final previous = WindowPlacement.fromJson(config['windowPlacement']);
    if (previous == null ||
        placement.updatedAt > previous.updatedAt ||
        (placement.updatedAt == previous.updatedAt &&
            placement.source.compareTo(previous.source) > 0)) {
      config['windowPlacement'] = placement.toJson();
    }
    return config;
  });
}
