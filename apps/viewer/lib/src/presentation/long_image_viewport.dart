import 'package:flutter/material.dart';

import '../application/decode_scheduler.dart';
import '../application/image_resource_service.dart';
import '../application/color_picker_controller.dart';
import '../domain/image_entry.dart';
import '../domain/image_resource_key.dart';
import 'components/app_image_error.dart';
import 'resource_image.dart';
import 'color_picker_target.dart';

class LongImageViewport extends StatefulWidget {
  const LongImageViewport({
    required this.entry,
    required this.resources,
    required this.sourceSize,
    required this.viewport,
    required this.baseWidth,
    required this.controller,
    required this.targetWidth,
    this.onDisplayed,
    this.sampleKind = ColorSampleKind.srgb,
    super.key,
  });

  final ImageEntry entry;
  final ImageResourceService resources;
  final Size sourceSize;
  final Size viewport;
  final double baseWidth;
  final TransformationController controller;
  final int targetWidth;
  final VoidCallback? onDisplayed;
  final ColorSampleKind sampleKind;

  @override
  State<LongImageViewport> createState() => _LongImageViewportState();
}

class _LongImageViewportState extends State<LongImageViewport> {
  static const _tileSourceHeight = 2048;

  int get _tileCount =>
      (widget.sourceSize.height / _tileSourceHeight).ceil().clamp(1, 100000);

  double get _contentHeight =>
      widget.baseWidth * widget.sourceSize.height / widget.sourceSize.width;

  int _firstVisibleTile(Matrix4 matrix) {
    final scale = matrix.getMaxScaleOnAxis();
    final translation = matrix.getTranslation();
    final sceneTop = (-translation.y / scale).clamp(0.0, _contentHeight);
    final tileHeight = _tileDisplayHeight(0);
    return (sceneTop / tileHeight).floor().clamp(0, _tileCount - 1);
  }

  int _lastVisibleTile(Matrix4 matrix) {
    final scale = matrix.getMaxScaleOnAxis();
    final translation = matrix.getTranslation();
    final sceneBottom = ((widget.viewport.height - translation.y) / scale)
        .clamp(0.0, _contentHeight);
    final tileHeight = _tileDisplayHeight(0);
    return (sceneBottom / tileHeight).ceil().clamp(0, _tileCount - 1);
  }

  double _tileDisplayHeight(int index) {
    final top = index * _tileSourceHeight;
    final sourceHeight = (widget.sourceSize.height - top).clamp(
      1.0,
      _tileSourceHeight.toDouble(),
    );
    return widget.baseWidth * sourceHeight / widget.sourceSize.width;
  }

  @override
  Widget build(BuildContext context) {
    final contentSize = Size(widget.baseWidth, _contentHeight);
    return SizedBox(
      width: contentSize.width,
      height: contentSize.height,
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final matrix = widget.controller.value;
          final first = (_firstVisibleTile(matrix) - 1).clamp(
            0,
            _tileCount - 1,
          );
          final last = (_lastVisibleTile(matrix) + 1).clamp(0, _tileCount - 1);
          final children = <Widget>[];
          for (var index = first; index <= last; index++) {
            final top = index * _tileSourceHeight;
            final height = _tileDisplayHeight(index);
            children.add(
              Positioned(
                key: ValueKey('${widget.entry.id}:$index'),
                left: 0,
                top: top * widget.baseWidth / widget.sourceSize.width,
                width: widget.baseWidth,
                height: height,
                child: _LongImageTile(
                  entry: widget.entry,
                  onDisplayed: widget.onDisplayed,
                  resources: widget.resources,
                  sourceWidth: widget.sourceSize.width.round(),
                  sourceTop: top,
                  sourceHeight: (widget.sourceSize.height - top)
                      .clamp(1.0, _tileSourceHeight.toDouble())
                      .round(),
                  targetWidth: widget.targetWidth,
                  sampleKind: widget.sampleKind,
                ),
              ),
            );
          }
          return Stack(children: children);
        },
      ),
    );
  }
}

class _LongImageTile extends StatelessWidget {
  const _LongImageTile({
    required this.entry,
    this.onDisplayed,
    required this.resources,
    required this.sourceWidth,
    required this.sourceTop,
    required this.sourceHeight,
    required this.targetWidth,
    required this.sampleKind,
  });
  final ImageEntry entry;
  final ImageResourceService resources;
  final VoidCallback? onDisplayed;
  final int sourceWidth;
  final int sourceTop;
  final int sourceHeight;
  final int targetWidth;
  final ColorSampleKind sampleKind;

  @override
  Widget build(BuildContext context) => ColorPickerTarget(
    id: entry.id,
    name: entry.name,
    kind: sampleKind,
    region: ImageRegion(
      left: 0,
      top: sourceTop,
      width: sourceWidth,
      height: sourceHeight,
    ),
    child: ResourceImage(
      resources: resources,
      entry: entry,
      targetWidth: ColorPickerScope.of(context)?.active == true
          ? sourceWidth
          : targetWidth,
      region: ImageRegion(
        left: 0,
        top: sourceTop,
        width: sourceWidth,
        height: sourceHeight,
      ),
      priority: DecodePriority.visible,
      fit: BoxFit.fill,
      frameBuilder: (context, child, frame, synchronous) {
        if (frame != null || synchronous) onDisplayed?.call();
        return child;
      },
      errorBuilder: (context, error, stack) => const AppImagePlaceholder(),
    ),
  );
}
