import 'package:flutter/foundation.dart';

import 'viewer_mode.dart';

enum AutoPlayAnimationPolicy { completeOnce, fixedInterval, stop }

enum AutoPlayStatusDisplay { autoHide, always }

@immutable
class AutoPlaySettings {
  const AutoPlaySettings({
    this.intervals = const {},
    this.scrollSpeeds = const {},
    this.loop = false,
    this.animationPolicy = AutoPlayAnimationPolicy.completeOnce,
    this.statusDisplay = AutoPlayStatusDisplay.autoHide,
  });

  final Map<ViewerMode, double> intervals;
  final Map<ViewerMode, double> scrollSpeeds;
  final bool loop;
  final AutoPlayAnimationPolicy animationPolicy;
  final AutoPlayStatusDisplay statusDisplay;

  static double _number(
    Object? value,
    double fallback,
    double min,
    double max,
  ) => value is num && value.isFinite
      ? value.toDouble().clamp(min, max)
      : fallback;

  static double _roundInterval(double value) => (value * 10).round() / 10;

  double intervalFor(ViewerMode mode) =>
      _roundInterval(_number(intervals[mode], 5, 0.5, 3600));
  double speedFor(ViewerMode mode) => _number(scrollSpeeds[mode], 60, 5, 1000);

  AutoPlaySettings copyWith({
    Map<ViewerMode, double>? intervals,
    Map<ViewerMode, double>? scrollSpeeds,
    bool? loop,
    AutoPlayAnimationPolicy? animationPolicy,
    AutoPlayStatusDisplay? statusDisplay,
  }) => AutoPlaySettings(
    intervals: Map.unmodifiable(intervals ?? this.intervals),
    scrollSpeeds: Map.unmodifiable(scrollSpeeds ?? this.scrollSpeeds),
    loop: loop ?? this.loop,
    animationPolicy: animationPolicy ?? this.animationPolicy,
    statusDisplay: statusDisplay ?? this.statusDisplay,
  );

  factory AutoPlaySettings.fromJson(Object? value) {
    if (value is! Map) return const AutoPlaySettings();
    Map<ViewerMode, double> read(
      Object? raw,
      double fallback,
      double min,
      double max,
    ) => {
      if (raw is Map)
        for (final mode in ViewerMode.values)
          if (raw.containsKey(mode.name))
            mode: _number(raw[mode.name], fallback, min, max),
    };
    return AutoPlaySettings(
      intervals: Map.unmodifiable({
        for (final entry in read(value['intervals'], 5, 0.5, 3600).entries)
          entry.key: _roundInterval(entry.value),
      }),
      scrollSpeeds: Map.unmodifiable(read(value['scrollSpeeds'], 60, 5, 1000)),
      loop: value['loop'] == true,
      animationPolicy: AutoPlayAnimationPolicy.values.firstWhere(
        (policy) => policy.name == value['animationPolicy'],
        orElse: () => AutoPlayAnimationPolicy.completeOnce,
      ),
      statusDisplay: AutoPlayStatusDisplay.values.firstWhere(
        (display) => display.name == value['statusDisplay'],
        orElse: () => AutoPlayStatusDisplay.autoHide,
      ),
    );
  }

  Map<String, Object> toJson() => {
    'intervals': {
      for (final mode in intervals.keys) mode.name: intervalFor(mode),
    },
    'scrollSpeeds': {
      for (final mode in scrollSpeeds.keys) mode.name: speedFor(mode),
    },
    'loop': loop,
    'animationPolicy': animationPolicy.name,
    'statusDisplay': statusDisplay.name,
  };

  @override
  bool operator ==(Object other) =>
      other is AutoPlaySettings &&
      mapEquals(intervals, other.intervals) &&
      mapEquals(scrollSpeeds, other.scrollSpeeds) &&
      loop == other.loop &&
      animationPolicy == other.animationPolicy &&
      statusDisplay == other.statusDisplay;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(ViewerMode.values.map((mode) => intervals[mode])),
    Object.hashAll(ViewerMode.values.map((mode) => scrollSpeeds[mode])),
    loop,
    animationPolicy,
    statusDisplay,
  );
}
