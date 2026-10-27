import 'package:flutter/material.dart';

import '../application/decode_scheduler.dart';
import '../application/decode_request.dart';
import '../application/image_resource_service.dart';
import '../domain/image_entry.dart';
import '../domain/image_resource_key.dart';
import '../domain/image_format.dart';

/// Visible image demand survives prefetch suspension. Only transient resource
/// failures retry when capacity or focus returns; corrupt images do not loop.
class ResourceImage extends StatefulWidget {
  const ResourceImage({
    super.key,
    required this.resources,
    required this.entry,
    required this.errorBuilder,
    this.targetWidth,
    this.targetHeight,
    this.region,
    this.priority = DecodePriority.foreground,
    this.fit = BoxFit.contain,
    this.frameBuilder,
  });

  final ImageResourceService resources;
  final ImageEntry entry;
  final int? targetWidth;
  final int? targetHeight;
  final ImageRegion? region;
  final DecodePriority priority;
  final BoxFit fit;
  final ImageFrameBuilder? frameBuilder;
  final ImageErrorWidgetBuilder errorBuilder;

  @override
  State<ResourceImage> createState() => _ResourceImageState();
}

class _ResourceImageState extends State<ResourceImage> {
  Object? _failure;
  int _attempt = 0;
  int _recoveryAtAttempt = 0;
  bool _retryScheduled = false;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    widget.resources.recovery.addListener(_onRecovery);
    if (widget.priority == DecodePriority.visibleThumbnail) {
      widget.resources.retainThumbnail(widget.entry.id);
    }
    _recoveryAtAttempt = widget.resources.recovery.value;
  }

  void _detach(ResourceImage owner) {
    owner.resources.recovery.removeListener(_onRecovery);
    if (owner.priority == DecodePriority.visibleThumbnail) {
      owner.resources.releaseThumbnail(owner.entry.id);
    }
  }

  @override
  void didUpdateWidget(covariant ResourceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resources != widget.resources ||
        oldWidget.entry.id != widget.entry.id ||
        oldWidget.priority != widget.priority) {
      _detach(oldWidget);
      _attach();
      _failure = null;
      _attempt++;
    }
  }

  void _onRecovery() {
    if (_retryScheduled ||
        (_failure is! ImageResourceUnavailable &&
            _failure is! DecodeCancelled)) {
      return;
    }
    _retryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _retryScheduled = false;
      if (!mounted ||
          (_failure is! ImageResourceUnavailable &&
              _failure is! DecodeCancelled)) {
        return;
      }
      PaintingBinding.instance.imageCache.evict(
        ImageResourceKey(
          version: widget.resources.version(widget.entry),
          targetWidth: widget.targetWidth,
          targetHeight: widget.targetHeight,
          region: widget.region,
          icoIndex: widget.resources.icoCacheIndex(
            widget.entry,
            widget.priority,
          ),
          allowSmallRawPreview:
              widget.entry.format == ImageFormat.raw &&
              (widget.priority == DecodePriority.visibleThumbnail ||
                  widget.priority == DecodePriority.thumbnail),
        ),
      );
      setState(() {
        _failure = null;
        _recoveryAtAttempt = widget.resources.recovery.value;
        _attempt++;
      });
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _detach(widget);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Image(
    key: ValueKey(_attempt),
    image: widget.resources.provider(
      widget.entry,
      targetWidth: widget.targetWidth,
      targetHeight: widget.targetHeight,
      region: widget.region,
      priority: widget.priority,
    ),
    fit: widget.fit,
    filterQuality: FilterQuality.medium,
    gaplessPlayback: true,
    frameBuilder: (context, child, frame, synchronous) {
      if (frame != null || synchronous) _failure = null;
      return widget.frameBuilder?.call(context, child, frame, synchronous) ??
          child;
    },
    errorBuilder: (context, error, stack) {
      _failure = error;
      if (_recoveryAtAttempt != widget.resources.recovery.value) _onRecovery();
      return widget.errorBuilder(context, error, stack);
    },
  );
}
