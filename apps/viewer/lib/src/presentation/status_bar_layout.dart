import 'bar_layout_metrics.dart';

/// Natural widths of the bottom status bar groups, in logical pixels.
class StatusBarExtents {
  const StatusBarExtents({
    required this.horizontalInset,
    required this.thumbnailToggle,
    required this.metadata,
    required this.infoToggle,
    required this.divider,
    required this.scaleModes,
    required this.zoomCluster,
    required this.zoomTrigger,
    required this.fullscreen,
    this.directoryToggle = 0,
  });

  final double horizontalInset;

  final double thumbnailToggle;

  final double directoryToggle;

  /// Format, dimensions and byte size. Zero when no image is selected.
  final double metadata;

  final double infoToggle;

  final double divider;

  /// Fit-to-window, actual size and the separator before the zoom cluster.
  final double scaleModes;

  final double zoomCluster;

  final double zoomTrigger;

  /// Excludes the leading separator, which the right-group getters add.
  final double fullscreen;

  double get leftWidth => directoryToggle + thumbnailToggle + metadata;

  double get rightWithZoom => scaleModes + zoomCluster + divider + fullscreen;

  double get rightWithZoomPopover =>
      scaleModes + zoomTrigger + divider + fullscreen;

  double get rightMinimal => zoomTrigger + divider + fullscreen;
}

class StatusBarLayout {
  const StatusBarLayout({
    required this.showMetadata,
    required this.showZoomControls,
    required this.showScaleModes,
    required this.showFullscreen,
  });

  final bool showMetadata;

  final bool showZoomControls;

  final bool showScaleModes;

  final bool showFullscreen;

  bool get showZoomPopoverTrigger => !showZoomControls;

  bool get popoverHasScaleModes => !showScaleModes;

  /// Hysteresis ranking; each group outweighs all lower-ranked groups together.
  int get richness =>
      (showMetadata ? 8 : 0) +
      (showZoomControls ? 4 : 0) +
      (showScaleModes ? 2 : 0) +
      (showFullscreen ? 1 : 0);

  @override
  bool operator ==(Object other) =>
      other is StatusBarLayout &&
      other.showMetadata == showMetadata &&
      other.showZoomControls == showZoomControls &&
      other.showScaleModes == showScaleModes &&
      other.showFullscreen == showFullscreen;

  @override
  int get hashCode => Object.hash(
    showMetadata,
    showZoomControls,
    showScaleModes,
    showFullscreen,
  );

  @override
  String toString() =>
      'StatusBarLayout(metadata: $showMetadata, zoom: $showZoomControls, '
      'scaleModes: $showScaleModes, fullscreen: $showFullscreen)';

  /// Each side gets half the space left by the centered info toggle. Metadata
  /// collapses independently of the right group: zoom controls, then scale modes,
  /// then fullscreen. [previous] enables [resolveWithHysteresis] stabilization.
  static StatusBarLayout resolve({
    required double width,
    required StatusBarExtents extents,
    double minGap = BarLayoutMetrics.minGap,
    double hysteresisBand = BarLayoutMetrics.hysteresisBand,
    StatusBarLayout? previous,
  }) => resolveWithHysteresis(
    width: width,
    band: hysteresisBand,
    previous: previous,
    resolveAt: (width) =>
        _resolveAt(width: width, extents: extents, minGap: minGap),
    richnessOf: (layout) => layout.richness,
  );

  static StatusBarLayout _resolveAt({
    required double width,
    required StatusBarExtents extents,
    required double minGap,
  }) {
    final sideWidth =
        (width - extents.horizontalInset - extents.infoToggle) / 2 - minGap;
    bool fits(double extent) => extent <= sideWidth;

    final showMetadata = extents.metadata > 0 && fits(extents.leftWidth);
    final showZoomControls = fits(extents.rightWithZoom);
    final showScaleModes =
        showZoomControls || fits(extents.rightWithZoomPopover);
    final showFullscreen = showScaleModes || fits(extents.rightMinimal);
    return StatusBarLayout(
      showMetadata: showMetadata,
      showZoomControls: showZoomControls,
      showScaleModes: showScaleModes,
      showFullscreen: showFullscreen,
    );
  }
}
