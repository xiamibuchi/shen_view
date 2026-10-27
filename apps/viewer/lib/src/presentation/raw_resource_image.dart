import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/image_resource_service.dart';
import '../domain/image_entry.dart';
import 'resource_image.dart';

/// Requests RAW detail at the actual draw size, including desktop DPI and zoom.
/// Keep the existing frame during refinement and coalesce continuous gestures.
class RawResourceImage extends StatefulWidget {
  const RawResourceImage({
    required this.resources,
    required this.entry,
    required this.transform,
    required this.sourceSize,
    required this.fit,
    required this.errorBuilder,
    this.frameBuilder,
    this.fullResolution = false,
    super.key,
  });
  final ImageResourceService resources;
  final ImageEntry entry;
  final TransformationController transform;
  final Size? sourceSize;
  final BoxFit fit;
  final ImageErrorWidgetBuilder errorBuilder;
  final ImageFrameBuilder? frameBuilder;
  final bool fullResolution;

  @override
  State<RawResourceImage> createState() => _RawResourceImageState();
}

class _RawResourceImageState extends State<RawResourceImage> {
  Timer? _timer;
  Size? _requested;
  Size? _pending;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => AnimatedBuilder(
      animation: widget.transform,
      builder: (context, _) {
        final source = widget.sourceSize;
        final box = Size(constraints.maxWidth, constraints.maxHeight);
        final bounded = box.width.isFinite && box.height.isFinite;
        final drawn = bounded && source != null
            ? applyBoxFit(widget.fit, source, box).destination
            : box;
        final scale =
            MediaQuery.devicePixelRatioOf(context) *
            widget.transform.value.getMaxScaleOnAxis();
        final wanted = source == null || !bounded || widget.fullResolution
            ? source
            : Size(
                math.min(source.width, drawn.width * scale).ceilToDouble(),
                math.min(source.height, drawn.height * scale).ceilToDouble(),
              );
        if (_requested == null) {
          _requested = wanted;
        } else if (wanted != null &&
            (wanted.width > _requested!.width + 1 ||
                wanted.height > _requested!.height + 1)) {
          _pending = wanted;
          // Do not restart the timer on every frame: a long gesture still
          // makes periodic progress instead of waiting indefinitely.
          _timer ??= Timer(const Duration(milliseconds: 160), () {
            _timer = null;
            if (mounted) setState(() => _requested = _pending);
          });
        }
        return ResourceImage(
          resources: widget.resources,
          entry: widget.entry,
          fit: widget.fit,
          targetWidth: _requested?.width.toInt(),
          targetHeight: _requested?.height.toInt(),
          frameBuilder: widget.frameBuilder,
          errorBuilder: widget.errorBuilder,
        );
      },
    ),
  );
}
