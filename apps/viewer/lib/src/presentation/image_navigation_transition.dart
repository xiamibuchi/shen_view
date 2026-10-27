import 'package:flutter/material.dart';

import '../domain/viewer_interaction_settings.dart';

/// A bounded transition: rapid navigation keeps only the newest outgoing image.
class ImageNavigationTransition extends StatelessWidget {
  const ImageNavigationTransition({
    required this.imageKey,
    required this.effect,
    required this.duration,
    required this.direction,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final String imageKey;
  final ImageTransition effect;
  final Duration duration;
  final int direction;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final keyedChild = KeyedSubtree(key: ValueKey(imageKey), child: child);
    if (!enabled ||
        effect == ImageTransition.none ||
        MediaQuery.disableAnimationsOf(context)) {
      return keyedChild;
    }
    return ClipRect(
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final faded = FadeTransition(opacity: animation, child: child);
          return switch (effect) {
            ImageTransition.none => child,
            ImageTransition.fade => faded,
            ImageTransition.zoom => ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
              child: faded,
            ),
            ImageTransition.slide => AnimatedBuilder(
              animation: animation,
              child: faded,
              builder: (context, child) => FractionalTranslation(
                translation: Offset(
                  (1 - animation.value) *
                      0.12 *
                      direction *
                      (animation.status == AnimationStatus.reverse ? -1 : 1),
                  0,
                ),
                child: child,
              ),
            ),
          };
        },
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.passthrough,
          alignment: Alignment.center,
          children: [if (previous.isNotEmpty) previous.last, ?current],
        ),
        child: keyedChild,
      ),
    );
  }
}
