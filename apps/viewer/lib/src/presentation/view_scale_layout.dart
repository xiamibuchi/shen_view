import 'dart:math' as math;
import 'dart:ui';

import '../domain/view_scale_mode.dart';

/// One scale shared by every image in a page or spread.
double viewScaleFor(Size source, Size viewport, ViewScaleMode mode) {
  if (source.isEmpty || viewport.isEmpty) return 1;
  return switch (mode) {
    ViewScaleMode.autoFit => math.min(
      viewport.width / source.width,
      viewport.height / source.height,
    ),
    ViewScaleMode.fitWidth => viewport.width / source.width,
    ViewScaleMode.fitHeight => viewport.height / source.height,
    ViewScaleMode.originalSize => 1,
  };
}
