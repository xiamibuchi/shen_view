import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/domain/viewer_interaction_settings.dart';
import 'package:shen_view/src/presentation/image_navigation_transition.dart';

import 'support/style_review_fonts.dart';

const _capture = ValueKey('transition-capture');

Widget _host(
  ImageTransition effect,
  int page, {
  int direction = 1,
  bool reduced = false,
  bool enabled = true,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Center(
      child: RepaintBoundary(
        key: _capture,
        child: SizedBox(
          width: 360,
          height: 240,
          child: ColoredBox(
            color: const Color(0xff181b22),
            child: ImageNavigationTransition(
              imageKey: '$page',
              effect: effect,
              duration: const Duration(milliseconds: 220),
              direction: direction,
              enabled: enabled,
              child: ColoredBox(
                key: ValueKey('page:$page'),
                color: page.isEven
                    ? const Color(0xff426acb)
                    : const Color(0xffca4658),
                child: Center(
                  child: Text(
                    'PAGE ${page + 1}',
                    style: const TextStyle(
                      color: Color(0xffffffff),
                      fontSize: 32,
                      fontFamily: 'TransitionReview',
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _snapshot(WidgetTester tester, String label) async {
  final directory = Platform.environment['TRANSITION_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final file = File('$directory/$label.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final effect in ImageTransition.values) {
    testWidgets(
      '${effect.name} transition settles and rapid changes retain at most two pages',
      (tester) async {
        if (Platform.environment['TRANSITION_CAPTURE_DIR'] != null) {
          await tester.runAsync(() async {
            final loader = FontLoader('TransitionReview')
              ..addFont(
                File(windowsFontPath('segoeui.ttf'))
                    .readAsBytes()
                    .then(ByteData.sublistView),
              );
            await loader.load();
          });
        }
        await tester.pumpWidget(_host(effect, 1));
        await _snapshot(tester, '${effect.name}-before');
        await tester.pumpWidget(_host(effect, 2));
        await tester.pump(const Duration(milliseconds: 60));
        await _snapshot(tester, '${effect.name}-mid');
        if (effect == ImageTransition.none) {
          expect(find.byKey(const ValueKey('page:1')), findsNothing);
        } else {
          expect(find.byKey(const ValueKey('page:1')), findsOneWidget);
          expect(find.byKey(const ValueKey('page:2')), findsOneWidget);
        }
        for (var page = 3; page <= 8; page++) {
          await tester.pumpWidget(_host(effect, page, direction: -1));
          await tester.pump(const Duration(milliseconds: 10));
          expect(
            find
                .byWidgetPredicate(
                  (widget) => widget is ColoredBox && widget.key != null,
                )
                .evaluate()
                .length,
            lessThanOrEqualTo(2),
          );
        }
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('page:8')), findsOneWidget);
        expect(find.byKey(const ValueKey('page:7')), findsNothing);
        await _snapshot(tester, '${effect.name}-after');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'slide follows navigation direction; reduced motion and native paths switch directly',
    (tester) async {
      for (final direction in [1, -1]) {
        await tester.pumpWidget(
          _host(ImageTransition.slide, 1, direction: direction),
        );
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          _host(ImageTransition.slide, 2, direction: direction),
        );
        await tester.pump(const Duration(milliseconds: 40));
        final incoming = find
            .ancestor(
              of: find.byKey(const ValueKey('page:2')),
              matching: find.byType(FractionalTranslation),
            )
            .first;
        expect(
          tester.widget<FractionalTranslation>(incoming).translation.dx.sign,
          direction,
        );
        await tester.pumpAndSettle();
      }
      for (final reduced in [true, false]) {
        await tester.pumpWidget(
          _host(ImageTransition.zoom, 1, reduced: reduced, enabled: reduced),
        );
        await tester.pumpWidget(
          _host(ImageTransition.zoom, 2, reduced: reduced, enabled: reduced),
        );
        expect(find.byKey(const ValueKey('page:1')), findsNothing);
        expect(find.byType(AnimatedSwitcher), findsNothing);
      }
    },
  );
}
