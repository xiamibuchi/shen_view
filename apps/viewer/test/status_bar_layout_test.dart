import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/presentation/bar_layout_metrics.dart';
import 'package:shen_view/src/presentation/status_bar_layout.dart';

/// Widths measured from the real status bar widgets: 52 px per icon button
/// (48 px padded tap target plus 2 px padding on both sides), a 120 px slider
/// and 17 px separators.
const _button = 52.0;
const _divider = 17.0;
const _slider = 120.0;

const _inset = 16.0;
const _extents = StatusBarExtents(
  horizontalInset: _inset,
  thumbnailToggle: _button,
  metadata: 238,
  infoToggle: _button,
  divider: _divider,
  scaleModes: _button * 2 + _divider,
  zoomCluster: _slider + _button * 2,
  zoomTrigger: _button,
  fullscreen: _button,
);

StatusBarLayout _resolve(double width, {double metadata = 238}) =>
    StatusBarLayout.resolve(
      width: width,
      extents: StatusBarExtents(
        horizontalInset: _inset,
        thumbnailToggle: _button,
        metadata: metadata,
        infoToggle: _button,
        divider: _divider,
        scaleModes: _extents.scaleModes,
        zoomCluster: _extents.zoomCluster,
        zoomTrigger: _button,
        fullscreen: _button,
      ),
    );

/// Narrowest width at which [extent] still fits on one side of the centered
/// info toggle.
double _widthFor(double extent) =>
    (extent + BarLayoutMetrics.minGap) * 2 + _button + _inset;

void main() {
  test('a wide bar keeps the file facts and the whole zoom cluster', () {
    final layout = _resolve(1280);
    expect(layout.showMetadata, isTrue);
    expect(layout.showZoomControls, isTrue);
    expect(layout.showScaleModes, isTrue);
    expect(layout.showFullscreen, isTrue);
    expect(layout.showZoomPopoverTrigger, isFalse);
  });

  test('groups only collapse when their own width stops fitting', () {
    // The zoom cluster is the widest right group, so it is the first control
    // group to fold; the file facts survive far longer than before.
    final zoomLimit = _widthFor(_extents.rightWithZoom);
    expect(_resolve(zoomLimit).showZoomControls, isTrue);
    expect(_resolve(zoomLimit - 1).showZoomControls, isFalse);
    expect(
      _resolve(zoomLimit - 1).showMetadata,
      isTrue,
      reason: 'the file facts still fit at that width',
    );

    final zoomPopoverLimit = _widthFor(_extents.rightWithZoomPopover);
    expect(_resolve(zoomPopoverLimit).showScaleModes, isTrue);
    expect(_resolve(zoomPopoverLimit - 1).showScaleModes, isFalse);
    expect(_resolve(zoomPopoverLimit - 1).popoverHasScaleModes, isTrue);

    final metadataLimit = _widthFor(_extents.leftWidth);
    expect(_resolve(metadataLimit).showMetadata, isTrue);
    expect(_resolve(metadataLimit - 1).showMetadata, isFalse);
  });

  test('an 800 px bar keeps the file facts and only folds the slider', () {
    // Regression guard: the old fixed breakpoints hid the file facts at 1040
    // and folded both the slider and the scale modes at 880 while there was
    // plenty of room.
    final layout = _resolve(800);
    expect(layout.showMetadata, isTrue);
    expect(layout.showZoomControls, isFalse);
    expect(layout.showScaleModes, isTrue);
    expect(layout.showFullscreen, isTrue);
  });

  test('longer file facts fold earlier than short ones', () {
    final short = _resolve(620, metadata: 180);
    final long = _resolve(620, metadata: 320);
    expect(short.showMetadata, isTrue);
    expect(long.showMetadata, isFalse);
  });

  test('fullscreen is the last command to leave the bar', () {
    final minimalLimit = _widthFor(_extents.rightMinimal);
    expect(_resolve(minimalLimit).showFullscreen, isTrue);
    final tiny = _resolve(minimalLimit - 1);
    expect(tiny.showFullscreen, isFalse);
    expect(tiny.showZoomPopoverTrigger, isTrue);
  });

  test('the info toggle keeps its share at every supported width', () {
    for (var width = 320.0; width <= 1600; width += 4) {
      final layout = _resolve(width);
      // Whatever is dropped, the right side never asks for more than the band
      // next to the centered toggle.
      final right = layout.showZoomControls
          ? _extents.rightWithZoom
          : layout.showScaleModes
          ? _extents.rightWithZoomPopover
          : layout.showFullscreen
          ? _extents.rightMinimal
          : _button;
      expect(right, lessThanOrEqualTo((width - _inset - _button) / 2));
    }
  });
}
