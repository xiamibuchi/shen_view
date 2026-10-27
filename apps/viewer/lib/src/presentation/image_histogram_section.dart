import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../application/decode_request.dart';
import '../application/image_histogram.dart';
import '../application/image_resource_service.dart';
import '../domain/image_entry.dart';
import '../domain/image_resource_key.dart';
import 'bar_layout_metrics.dart';
import 'components/app_button.dart';
import 'components/app_tab_switch.dart';
import 'histogram_sample.dart';
import 'theme/app_styles.dart';
import 'theme/app_theme.dart';
import 'theme/app_tokens.dart';
import 'theme/histogram_palette.dart';

class ImageHistogramSection extends StatefulWidget {
  const ImageHistogramSection({
    required this.entry,
    required this.resources,
    super.key,
  });

  final ImageEntry entry;
  final ImageResourceService resources;

  @override
  State<ImageHistogramSection> createState() => _ImageHistogramSectionState();
}

class _ImageHistogramSectionState extends State<ImageHistogramSection> {
  late Future<ImageHistogram> _future;
  late ImageFileVersion _version;
  DecodeRequest? _request;
  Object? _failure;
  bool _rgb = false;

  @override
  void initState() {
    super.initState();
    widget.resources.recovery.addListener(_recover);
    _start();
  }

  void _start() {
    _request?.cancel();
    _failure = null;
    _version = widget.resources.version(widget.entry);
    _future = readImageHistogram(
      widget.resources,
      widget.entry,
      _request = DecodeRequest(),
    );
  }

  void _recover() {
    if (mounted &&
        (_failure is DecodeCancelled || _failure is ImageResourceUnavailable)) {
      setState(_start);
    }
  }

  @override
  void didUpdateWidget(covariant ImageHistogramSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resources != widget.resources) {
      oldWidget.resources.recovery.removeListener(_recover);
      widget.resources.recovery.addListener(_recover);
    }
    if (oldWidget.resources != widget.resources ||
        _version != widget.resources.version(widget.entry)) {
      _start();
    }
  }

  @override
  void dispose() {
    widget.resources.recovery.removeListener(_recover);
    _request?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = ViewerThemeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppTokens.space3,
          runSpacing: AppTokens.space2,
          children: [
            Text(
              l10n.histogram,
              style: AppTextStyles.caption.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            AppTabSwitch<bool>(
              options: [
                AppTabOption(value: false, label: l10n.histogramLuminance),
                const AppTabOption(value: true, label: 'RGB'),
              ],
              value: _rgb,
              showSelectedIcon: false,
              onChanged: (value) => setState(() => _rgb = value),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.space2),
        FutureBuilder<ImageHistogram>(
          future: _future,
          builder: (context, snapshot) {
            final waiting = snapshot.connectionState != ConnectionState.done;
            final data = waiting ? null : snapshot.data;
            _failure = waiting ? null : snapshot.error;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 156,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: tokens.surfaceSubtle,
                    borderRadius: BorderRadius.circular(
                      AppTokens.controlRadius,
                    ),
                    border: Border.all(color: tokens.border),
                  ),
                  child: data != null && data.samples > 0
                      ? _chart(data)
                      : Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppTokens.space2),
                            child: Text(
                              waiting
                                  ? l10n.histogramLoading
                                  : snapshot.hasError
                                  ? l10n.histogramUnavailable
                                  : l10n.histogramEmpty,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.caption.copyWith(
                                color: tokens.textTertiary,
                              ),
                            ),
                          ),
                        ),
                ),
                if (snapshot.hasError && !waiting)
                  Padding(
                    padding: const EdgeInsets.only(top: AppTokens.space2),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        label: l10n.histogramRetry,
                        variant: AppButtonVariant.neutral,
                        onPressed: () => setState(_start),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (_rgb) ...[
          const SizedBox(height: AppTokens.space2),
          Wrap(
            spacing: AppTokens.space3,
            runSpacing: AppTokens.space1,
            children: [
              for (final (index, label) in [
                l10n.histogramRed,
                l10n.histogramGreen,
                l10n.histogramBlue,
              ].indexed)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: HistogramPalette.channels(
                          Theme.of(context).brightness,
                        )[index],
                      ),
                    ),
                    const SizedBox(width: AppTokens.space1),
                    Text(
                      label,
                      style: AppTextStyles.caption.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
        const SizedBox(height: AppTokens.space2),
        Text(
          widget.resources.isAnimated(widget.entry)
              ? l10n.histogramAnimationNote
              : l10n.histogramSampleNote,
          style: AppTextStyles.finePrint.copyWith(color: tokens.textSecondary),
        ),
      ],
    );
  }

  Widget _chart(ImageHistogram data) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = ViewerThemeTokens.of(context);
    return Semantics(
      label: _rgb ? l10n.histogramRgbDescription : l10n.histogramLuminance,
      image: true,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CustomPaint(
                key: const ValueKey('histogram.chart'),
                painter: HistogramPainter(
                  data: data,
                  rgb: _rgb,
                  colors: HistogramPalette.channels(
                    Theme.of(context).brightness,
                  ),
                  foreground: tokens.textPrimary,
                  grid: tokens.border,
                ),
              ),
            ),
            const SizedBox(height: AppTokens.space2),
            const SizedBox(
              height: AppTokens.space1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: HistogramPalette.tonalRange),
                ),
              ),
            ),
            const SizedBox(height: AppTokens.space1),
            _axis(),
          ],
        ),
      ),
    );
  }

  Widget _axis() => LayoutBuilder(
    builder: (context, constraints) {
      final style = AppTextStyles.finePrint.copyWith(
        color: ViewerThemeTokens.of(context).textSecondary,
      );
      return SizedBox(
        height: MediaQuery.textScalerOf(context).scale(16),
        child: Stack(
          children: [
            for (final value in [0, 64, 128, 192, 255])
              Builder(
                builder: (context) {
                  final width = measureBarLabelWidth(context, '$value', style);
                  final left = (constraints.maxWidth * value / 255 - width / 2)
                      .clamp(0.0, math.max(0.0, constraints.maxWidth - width));
                  return Positioned(
                    left: left.toDouble(),
                    child: Text('$value', style: style),
                  );
                },
              ),
          ],
        ),
      );
    },
  );
}

class HistogramPainter extends CustomPainter {
  const HistogramPainter({
    required this.data,
    required this.rgb,
    required this.colors,
    required this.foreground,
    required this.grid,
  });

  final ImageHistogram data;
  final bool rgb;
  final List<Color> colors;
  final Color foreground;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 2 || size.height <= 6) return;
    final plot = Rect.fromLTWH(1, 5, size.width - 2, size.height - 6);
    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.40)
      ..strokeWidth = 0.75;
    for (var i = 1; i < 4; i++) {
      final x = plot.left + plot.width * (64 * i) / 255;
      final y = plot.top + plot.height * i / 4;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }
    final channels = rgb ? [data.red, data.green, data.blue] : [data.luminance];
    final peak = channels.expand((bins) => bins).fold(1, math.max);
    final lines = <Path>[];
    for (var channel = 0; channel < channels.length; channel++) {
      final bins = channels[channel];
      final color = rgb ? colors[channel] : foreground;
      final line = Path();
      for (var i = 0; i < 256; i++) {
        final x = plot.left + i * plot.width / 255;
        final y = plot.bottom - bins[i] / peak * plot.height;
        if (i == 0) {
          line.moveTo(x, y);
        } else {
          line.lineTo(x, y);
        }
      }
      final area = Path.from(line)
        ..lineTo(plot.right, plot.bottom)
        ..lineTo(plot.left, plot.bottom)
        ..close();
      lines.add(line);
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: rgb ? 0.24 : 0.22),
              color.withValues(alpha: 0.03),
            ],
          ).createShader(plot),
      );
    }
    // Draw every outline last, so later channel fills cannot mute earlier lines.
    for (var channel = 0; channel < lines.length; channel++) {
      canvas.drawPath(
        lines[channel],
        Paint()
          ..color = rgb ? colors[channel] : foreground
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant HistogramPainter oldDelegate) =>
      data != oldDelegate.data ||
      rgb != oldDelegate.rgb ||
      !listEquals(colors, oldDelegate.colors) ||
      foreground != oldDelegate.foreground ||
      grid != oldDelegate.grid;
}
