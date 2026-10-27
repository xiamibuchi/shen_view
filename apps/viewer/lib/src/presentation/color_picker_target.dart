import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../application/color_picker_controller.dart';
import '../domain/image_resource_key.dart';

/// The scope changes only on entering/exiting the tool, not on mouse movement.
class ColorPickerScope extends InheritedWidget {
  const ColorPickerScope({
    required this.controller,
    required this.active,
    required super.child,
    super.key,
  });
  final ColorPickerController controller;
  final bool active;
  static ColorPickerScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ColorPickerScope>();
  @override
  bool updateShouldNotify(ColorPickerScope oldWidget) =>
      active != oldWidget.active || controller != oldWidget.controller;
}

/// Reads the exact RenderImage used by this page, including current animation
/// frames. RenderBox.globalToLocal inverts every parent zoom/rotation/crop.
class ColorPickerTarget extends StatefulWidget {
  const ColorPickerTarget({
    required this.id,
    required this.name,
    required this.child,
    this.sourceSize,
    this.region,
    this.kind = ColorSampleKind.srgb,
    super.key,
  });
  final String id, name;
  final Widget child;
  final Size? sourceSize;
  final ImageRegion? region;
  final ColorSampleKind kind;
  @override
  State<ColorPickerTarget> createState() => _ColorPickerTargetState();
}

class _ColorPickerTargetState extends State<ColorPickerTarget> {
  ColorPickerScope? _scope;

  RenderImage? _image(RenderObject? object) {
    if (object is RenderImage && object.image != null) return object;
    RenderImage? found;
    object?.visitChildren((child) {
      found ??= _image(child);
    });
    return found;
  }

  void _sample(Offset global, {bool lock = false, Offset? pixel}) {
    final scope = _scope;
    if (!mounted || scope == null || !scope.controller.active) return;
    final render = _image(context.findRenderObject());
    final image = render?.image;
    if (render == null ||
        image == null ||
        !render.attached ||
        !render.hasSize) {
      return;
    }
    final input = Size(image.width / render.scale, image.height / render.scale);
    final fitted = applyBoxFit(
      render.fit ?? BoxFit.scaleDown,
      input,
      render.size,
    );
    final alignment = render.alignment.resolve(Directionality.of(context));
    final destination = alignment.inscribe(
      fitted.destination,
      Offset.zero & render.size,
    );
    final source = alignment.inscribe(fitted.source, Offset.zero & input);
    final local = render.globalToLocal(global);
    if (pixel == null && !destination.contains(local)) {
      scope.controller.clearHover();
      return;
    }
    final point =
        pixel ??
        Offset(
          ((source.left +
                      (local.dx - destination.left) /
                          destination.width *
                          source.width) *
                  render.scale)
              .floorToDouble(),
          ((source.top +
                      (local.dy - destination.top) /
                          destination.height *
                          source.height) *
                  render.scale)
              .floorToDouble(),
        );
    if (!point.dx.isFinite ||
        !point.dy.isFinite ||
        point.dx < 0 ||
        point.dy < 0 ||
        point.dx >= image.width ||
        point.dy >= image.height) {
      return;
    }
    final region = widget.region;
    final size = region == null
        ? widget.sourceSize ??
              Size(image.width.toDouble(), image.height.toDouble())
        : Size(region.width.toDouble(), region.height.toDouble());
    final sourcePoint = Offset(
      (region?.left ?? 0) + point.dx / image.width * size.width,
      (region?.top ?? 0) + point.dy / image.height * size.height,
    );
    final request = ColorPickerRequest(
      image: image,
      pixel: point,
      sourcePixel: sourcePoint,
      id: widget.id,
      name: widget.name,
      kind: widget.kind,
      previewOnly:
          size.width.round() != image.width ||
          size.height.round() != image.height,
      refresh: () {
        if (mounted) _sample(global);
      },
      nudge: (dx, dy) {
        if (mounted && scope.controller.active) {
          _sample(
            global,
            pixel: point + Offset(dx.toDouble(), dy.toDouble()),
            lock: true,
          );
        }
      },
    );
    scope.controller.preview(request, global);
    if (lock) unawaited(scope.controller.lock(request));
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope = ColorPickerScope.of(context);
    final active = scope?.active ?? false;
    return MouseRegion(
      cursor: active ? SystemMouseCursors.precise : MouseCursor.defer,
      onHover: active ? (event) => _sample(event.position) : null,
      onExit: active ? (_) => scope!.controller.clearHover() : null,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: active
            ? (details) => _sample(details.globalPosition, lock: true)
            : null,
        child: widget.child,
      ),
    );
  }
}
