import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Two non-destructive page crops of a scan. Both views share the image cache.
/// Physical left/right placement stays intact for either reading direction.
class SplitWideImage extends StatelessWidget {
  const SplitWideImage({
    required this.sourceSize,
    required this.buildImage,
    this.gap = 12,
    super.key,
  });

  final Size sourceSize;
  final Widget Function() buildImage;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = math.min(
        math.max(0, constraints.maxWidth - gap) / sourceSize.width,
        constraints.maxHeight / sourceSize.height,
      );
      return Center(
        child: SizedBox(
          width: sourceSize.width * scale + gap,
          height: sourceSize.height * scale,
          child: Row(
            children: [
              Expanded(child: _half(false)),
              SizedBox(width: gap),
              Expanded(child: _half(true)),
            ],
          ),
        ),
      );
    },
  );

  Widget _half(bool right) => FittedBox(
    key: ValueKey(right ? 'split.right' : 'split.left'),
    fit: BoxFit.contain,
    child: SizedBox(
      width: sourceSize.width / 2,
      height: sourceSize.height,
      child: ClipRect(
        child: OverflowBox(
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          minWidth: sourceSize.width,
          maxWidth: sourceSize.width,
          minHeight: sourceSize.height,
          maxHeight: sourceSize.height,
          child: buildImage(),
        ),
      ),
    ),
  );
}
