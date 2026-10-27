import 'comic_layout_direction.dart';
import 'view_scale_mode.dart';
import 'viewer_mode.dart';
import 'viewer_settings.dart';

/// A folder or book's preferences and reading point, without transient zoom.
class ReadingState {
  const ReadingState({
    this.mode = ViewerMode.single,
    this.scales = const {},
    this.readingDirection,
    this.layoutDirection,
    this.entryPath,
    this.pageFraction,
    this.crossFraction,
  });

  final ViewerMode mode;
  final Map<ViewerMode, ViewScaleMode> scales;
  final ReadingDirection? readingDirection;
  final ComicLayoutDirection? layoutDirection;
  final String? entryPath;
  final double? pageFraction;
  final double? crossFraction;

  factory ReadingState.fromJson(Map<String, dynamic> json) {
    final rawScales = json['scales'];
    return ReadingState(
      mode: enumValue(ViewerMode.values, json['mode']) ?? ViewerMode.single,
      scales: {
        if (rawScales is Map)
          for (final mode in ViewerMode.values)
            mode: ?enumValue(ViewScaleMode.values, rawScales[mode.name]),
      },
      readingDirection: enumValue(
        ReadingDirection.values,
        json['readingDirection'],
      ),
      layoutDirection: enumValue(
        ComicLayoutDirection.values,
        json['layoutDirection'],
      ),
      entryPath: safeEntryPath(json['entryPath']),
      pageFraction: _fraction(json['pageFraction']),
      crossFraction: _fraction(json['crossFraction']),
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'scales': {
      for (final entry in scales.entries) entry.key.name: entry.value.name,
    },
    if (readingDirection != null) 'readingDirection': readingDirection!.name,
    if (layoutDirection != null) 'layoutDirection': layoutDirection!.name,
    if (entryPath != null) 'entryPath': entryPath,
    if (pageFraction != null) 'pageFraction': pageFraction,
    if (crossFraction != null) 'crossFraction': crossFraction,
  };

  static T? enumValue<T extends Enum>(List<T> values, Object? value) =>
      values.where((item) => item.name == value).firstOrNull;

  static String? safeEntryPath(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final path = value.replaceAll('\\', '/');
    if (path.startsWith('/') ||
        path.contains(':') ||
        path.split('/').any((part) => part == '..' || part == '.')) {
      return null;
    }
    return path;
  }

  static double? _fraction(Object? value) =>
      value is num && value.isFinite ? value.toDouble().clamp(0, 1) : null;
}
