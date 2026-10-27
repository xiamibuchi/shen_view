enum WheelAction { navigate, zoom }

enum ImageTransition { none, fade, slide, zoom }

enum ZoomCenter { pointer, viewport }

/// Persisted input preferences. Continuous layouts always scroll with the wheel.
class ViewerInteractionSettings {
  const ViewerInteractionSettings({
    this.wheelAction = WheelAction.navigate,
    this.wheelIntervalMs = 180,
    this.reverseWheel = false,
    this.scrollSpeed = 1,
    this.zoomSpeed = 1,
    this.keepZoom = false,
    this.keepZoomPosition = false,
    this.zoomCenter = ZoomCenter.pointer,
    this.holdNavigation = true,
    this.holdDelayMs = 400,
    this.holdIntervalMs = 180,
    this.transition = ImageTransition.fade,
    this.transitionDurationMs = 140,
  });

  final WheelAction wheelAction;
  final int wheelIntervalMs;
  final bool reverseWheel;
  final double scrollSpeed;
  final double zoomSpeed;
  final bool keepZoom;
  final bool keepZoomPosition;
  final ZoomCenter zoomCenter;
  final bool holdNavigation;
  final int holdDelayMs;
  final int holdIntervalMs;
  final ImageTransition transition;
  final int transitionDurationMs;

  factory ViewerInteractionSettings.fromJson(Object? value) {
    final json = value is Map ? value : const <String, Object?>{};
    return ViewerInteractionSettings(
      wheelAction: _enum(
        WheelAction.values,
        json['wheelAction'],
        WheelAction.navigate,
      ),
      wheelIntervalMs: _number(json['wheelIntervalMs'], 180, 80, 600).round(),
      reverseWheel: json['reverseWheel'] == true,
      scrollSpeed: _number(json['scrollSpeed'], 1, 0.25, 3),
      zoomSpeed: _number(json['zoomSpeed'], 1, 0.25, 3),
      keepZoom: json['keepZoom'] == true,
      keepZoomPosition: json['keepZoomPosition'] == true,
      zoomCenter: _enum(
        ZoomCenter.values,
        json['zoomCenter'],
        ZoomCenter.pointer,
      ),
      holdNavigation: json['holdNavigation'] != false,
      holdDelayMs: _number(json['holdDelayMs'], 400, 200, 1000).round(),
      holdIntervalMs: _number(json['holdIntervalMs'], 180, 80, 600).round(),
      transition: _enum(
        ImageTransition.values,
        json['transition'],
        ImageTransition.fade,
      ),
      transitionDurationMs: _number(
        json['transitionDurationMs'],
        140,
        50,
        500,
      ).round(),
    );
  }

  Map<String, Object> toJson() => {
    'wheelAction': wheelAction.name,
    'wheelIntervalMs': wheelIntervalMs,
    'reverseWheel': reverseWheel,
    'scrollSpeed': scrollSpeed,
    'zoomSpeed': zoomSpeed,
    'keepZoom': keepZoom,
    'keepZoomPosition': keepZoomPosition,
    'zoomCenter': zoomCenter.name,
    'holdNavigation': holdNavigation,
    'holdDelayMs': holdDelayMs,
    'holdIntervalMs': holdIntervalMs,
    'transition': transition.name,
    'transitionDurationMs': transitionDurationMs,
  };

  ViewerInteractionSettings copyWith({
    WheelAction? wheelAction,
    int? wheelIntervalMs,
    bool? reverseWheel,
    double? scrollSpeed,
    double? zoomSpeed,
    bool? keepZoom,
    bool? keepZoomPosition,
    ZoomCenter? zoomCenter,
    bool? holdNavigation,
    int? holdDelayMs,
    int? holdIntervalMs,
    ImageTransition? transition,
    int? transitionDurationMs,
  }) => ViewerInteractionSettings(
    wheelAction: wheelAction ?? this.wheelAction,
    wheelIntervalMs: wheelIntervalMs ?? this.wheelIntervalMs,
    reverseWheel: reverseWheel ?? this.reverseWheel,
    scrollSpeed: scrollSpeed ?? this.scrollSpeed,
    zoomSpeed: zoomSpeed ?? this.zoomSpeed,
    keepZoom: keepZoom ?? this.keepZoom,
    keepZoomPosition: keepZoomPosition ?? this.keepZoomPosition,
    zoomCenter: zoomCenter ?? this.zoomCenter,
    holdNavigation: holdNavigation ?? this.holdNavigation,
    holdDelayMs: holdDelayMs ?? this.holdDelayMs,
    holdIntervalMs: holdIntervalMs ?? this.holdIntervalMs,
    transition: transition ?? this.transition,
    transitionDurationMs: transitionDurationMs ?? this.transitionDurationMs,
  );

  @override
  bool operator ==(Object other) =>
      other is ViewerInteractionSettings &&
      other.wheelAction == wheelAction &&
      other.wheelIntervalMs == wheelIntervalMs &&
      other.reverseWheel == reverseWheel &&
      other.scrollSpeed == scrollSpeed &&
      other.zoomSpeed == zoomSpeed &&
      other.keepZoom == keepZoom &&
      other.keepZoomPosition == keepZoomPosition &&
      other.zoomCenter == zoomCenter &&
      other.holdNavigation == holdNavigation &&
      other.holdDelayMs == holdDelayMs &&
      other.holdIntervalMs == holdIntervalMs &&
      other.transition == transition &&
      other.transitionDurationMs == transitionDurationMs;

  @override
  int get hashCode => Object.hashAll([
    wheelAction,
    wheelIntervalMs,
    reverseWheel,
    scrollSpeed,
    zoomSpeed,
    keepZoom,
    keepZoomPosition,
    zoomCenter,
    holdNavigation,
    holdDelayMs,
    holdIntervalMs,
    transition,
    transitionDurationMs,
  ]);
}

double _number(Object? value, double fallback, double min, double max) =>
    value is num && value.isFinite
    ? value.toDouble().clamp(min, max)
    : fallback;

T _enum<T extends Enum>(List<T> values, Object? value, T fallback) =>
    values.where((item) => item.name == value).firstOrNull ?? fallback;
