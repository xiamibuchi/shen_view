import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Bar groups collapse by measured content width, including localization and
/// text scaling. All extents are in logical pixels.
abstract final class BarLayoutMetrics {
  /// Clearance between groups, including the centered element.
  static const minGap = 12.0;

  /// Protect this title width until no more controls can collapse.
  static const minFileNameWidth = 64.0;

  /// Material 3 icon buttons never shrink below this size, even when the theme
  /// asks for shrink-wrapped tap targets.
  static const iconButtonMinimum = 40.0;

  /// Width a bar has to regain before a collapsed group comes back.
  static const hysteresisBand = 24.0;
}

/// [resolveAt] must be a pure function of the bar width and [richnessOf] must
/// order results by the collapse ladder. Collapse is immediate to avoid overflow;
/// recovery requires [band] extra width to prevent flicker near a threshold.
/// Feeding the result back as [previous] preserves the layout at the same width.
T resolveWithHysteresis<T>({
  required double width,
  required T Function(double width) resolveAt,
  required int Function(T layout) richnessOf,
  required T? previous,
  double band = BarLayoutMetrics.hysteresisBand,
}) {
  final current = resolveAt(width);
  if (previous == null || band <= 0) return current;

  final currentRichness = richnessOf(current);
  final previousRichness = richnessOf(previous);
  if (previousRichness >= currentRichness) return current;

  final slack = resolveAt(width - band);
  final slackRichness = richnessOf(slack);
  if (slackRichness >= currentRichness) return current;
  // Partial recovery: take the richest layout that is still poorer than what
  // this width could hold, so the next frame does not want to grow again.
  return previousRichness > slackRichness ? previous : slack;
}

/// Includes the ambient text scale and font family.
double measureBarLabelWidth(
  BuildContext context,
  String text,
  TextStyle style,
) {
  final effective = DefaultTextStyle.of(context).style.merge(style);
  final painter = TextPainter(
    text: TextSpan(text: text, style: effective),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Layout extent of an icon button that is not wrapped in a fixed [SizedBox].
///
/// Matches IconButton's Material 3 minimum and density-adjusted tap target;
/// the requested visual size alone can underestimate its width.
double barIconButtonExtent(
  BuildContext context, {
  required double size,
  double horizontalPadding = 0,
}) {
  final theme = Theme.of(context);
  final adjustment = theme.visualDensity.baseSizeAdjustment;
  final tapTarget = theme.materialTapTargetSize == MaterialTapTargetSize.padded
      ? math.max(0.0, kMinInteractiveDimension + adjustment.dx)
      : 0.0;
  final extent = math.max(
    size,
    math.max(tapTarget, BarLayoutMetrics.iconButtonMinimum),
  );
  return extent + horizontalPadding * 2;
}
