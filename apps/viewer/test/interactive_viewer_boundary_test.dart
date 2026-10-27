import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/presentation/zoomable_viewport.dart';

void main() {
  testWidgets(
    'initial placement and requested resets paint at their final position',
    (tester) async {
      final controller = TransformationController();
      addTearDown(controller.dispose);
      Widget host(Size content, int request) => MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: ZoomableViewport(
              contentSize: content,
              controller: controller,
              resetRequest: request,
              child: const ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      );
      await tester.pumpWidget(host(const Size(200, 100), 0));
      final transform = find.descendant(
        of: find.byType(ZoomableViewport),
        matching: find.byType(Transform),
      );
      expect(
        tester
            .renderObject<RenderTransform>(transform)
            .child!
            .getTransformTo(tester.renderObject<RenderTransform>(transform)),
        controller.value,
      );
      expect(controller.value.getTranslation().x, 100);
      expect(controller.value.getTranslation().y, 100);
      controller.value = Matrix4.identity()..scaleByDouble(2, 2, 2, 1);
      await tester.pump();
      await tester.pumpWidget(host(const Size(800, 600), 1));
      expect(
        tester
            .renderObject<RenderTransform>(transform)
            .child!
            .getTransformTo(tester.renderObject<RenderTransform>(transform)),
        controller.value,
      );
      expect(controller.value.getMaxScaleOnAxis(), 1);
      expect(controller.value.getTranslation().x, -200);
      expect(controller.value.getTranslation().y, -150);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('hover controls repaint without repainting the image canvas', (
    tester,
  ) async {
    final controller = TransformationController();
    final hovered = ValueNotifier(false);
    addTearDown(controller.dispose);
    addTearDown(hovered.dispose);
    var paints = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: ZoomableViewport(
                contentSize: const Size(800, 600),
                controller: controller,
                child: _PaintCounter(
                  onPaint: () => paints++,
                  child: const ColoredBox(color: Colors.blue),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              child: MouseRegion(
                onEnter: (_) => hovered.value = true,
                onExit: (_) => hovered.value = false,
                child: ValueListenableBuilder<bool>(
                  valueListenable: hovered,
                  builder: (context, value, child) => ColoredBox(
                    color: value ? Colors.red : Colors.green,
                    child: const SizedBox(width: 80, height: 40),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    final initial = paints;
    expect(initial, greaterThan(0));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 300));
    await tester.pump();
    await mouse.moveTo(const Offset(30, 20));
    await tester.pump();
    expect(hovered.value, isTrue);
    expect(paints, initial);
    await mouse.moveTo(const Offset(400, 300));
    await tester.pump();
    expect(hovered.value, isFalse);
    expect(paints, initial);
    controller.value = Matrix4.identity()..scaleByDouble(2, 2, 2, 1);
    await tester.pump();
    expect(
      paints,
      greaterThan(initial),
      reason: 'Real image changes must still paint.',
    );
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reset places the image atomically and ignores repeated resets', (
    tester,
  ) async {
    final controller = TransformationController();
    final commands = ZoomableViewportCommands();
    addTearDown(controller.dispose);
    addTearDown(commands.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ZoomableViewport(
          contentSize: const Size(1200, 1600),
          controller: controller,
          commands: commands,
          startAtTop: true,
          child: const ColoredBox(color: Colors.blue),
        ),
      ),
    );
    await tester.pump();
    controller.value = Matrix4.identity()
      ..scaleByDouble(2, 2, 2, 1)
      ..setTranslationRaw(-450, -900, 0);
    var changes = 0;
    controller.addListener(() => changes++);
    commands.resetView();
    expect(changes, 1);
    expect(controller.value.getMaxScaleOnAxis(), 1);
    expect(controller.value.getTranslation().x, -200);
    expect(controller.value.getTranslation().y, 0);
    await tester.pump();
    expect(changes, 1);
    commands.resetView();
    expect(changes, 1);
    await tester.pump();
    expect(changes, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('zoomed fitted image stays inside the viewport', (tester) async {
    final controller = TransformationController();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: ZoomableViewport(
            contentSize: const Size(400, 300),
            controller: controller,
            child: const ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    );
    await tester.pump();

    final viewport = find.byType(ZoomableViewport);
    controller.value = Matrix4.identity()
      ..translateByDouble(0, 0, 0, 1)
      ..scaleByDouble(2, 2, 2, 1);
    await tester.pump();

    await tester.drag(viewport, const Offset(1200, 900));
    await tester.pump();
    expect(controller.value.getTranslation().x, greaterThanOrEqualTo(-0.1));
    expect(controller.value.getTranslation().y, greaterThanOrEqualTo(-0.1));

    await tester.drag(viewport, const Offset(-2400, -1800));
    await tester.pump();
    expect(controller.value.getTranslation().x, lessThanOrEqualTo(0.1));
    expect(controller.value.getTranslation().y, lessThanOrEqualTo(0.1));
  });

  testWidgets('original-size image can pan only within its real bounds', (
    tester,
  ) async {
    final controller = TransformationController();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: ZoomableViewport(
            contentSize: const Size(800, 600),
            controller: controller,
            child: const ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    );
    await tester.pump();

    final viewport = find.byType(ZoomableViewport);
    await tester.drag(viewport, const Offset(1200, 900));
    await tester.pump();
    expect(controller.value.getTranslation().x, lessThanOrEqualTo(0.1));
    expect(controller.value.getTranslation().y, lessThanOrEqualTo(0.1));

    await tester.drag(viewport, const Offset(-2400, -1800));
    await tester.pump();
    expect(controller.value.getTranslation().x, greaterThanOrEqualTo(-400.1));
    expect(controller.value.getTranslation().y, greaterThanOrEqualTo(-300.1));
  });

  testWidgets(
    'a wide image clamps horizontal and vertical axes independently',
    (tester) async {
      final controller = TransformationController();
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 300,
            child: ZoomableViewport(
              contentSize: const Size(1600, 200),
              controller: controller,
              child: const ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      );
      await tester.pump();

      final viewport = find.byType(ZoomableViewport);
      await tester.drag(viewport, const Offset(-2400, -1800));
      await tester.pump();
      expect(controller.value.getTranslation().x, closeTo(-800, 0.1));
      expect(controller.value.getTranslation().y, closeTo(200, 0.1));
    },
  );

  testWidgets('top-aligned content starts at the top edge', (tester) async {
    final controller = TransformationController();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: ZoomableViewport(
            contentSize: const Size(400, 1200),
            controller: controller,
            startAtTop: true,
            child: const ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(controller.value.getTranslation().y, closeTo(0, 0.1));
  });

  testWidgets('keyboard scroll commands clamp and report vertical boundaries', (
    tester,
  ) async {
    final controller = TransformationController();
    final commands = ZoomableViewportCommands();
    final boundaries = <VerticalScrollBoundary>[];
    addTearDown(commands.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: ZoomableViewport(
            contentSize: const Size(400, 1200),
            controller: controller,
            commands: commands,
            startAtTop: true,
            onVerticalBoundary: boundaries.add,
            child: const ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    );
    await tester.pump();
    final viewportHeight = tester.getSize(find.byType(ZoomableViewport)).height;
    final bottomOffset = viewportHeight - 1200;

    commands.moveVertically(-240);
    expect(controller.value.getTranslation().y, closeTo(-240, 0.1));

    commands.moveVertically(-1000);
    expect(controller.value.getTranslation().y, closeTo(bottomOffset, 0.1));
    expect(boundaries.last, VerticalScrollBoundary.end);

    commands.moveVertically(-1000);
    expect(controller.value.getTranslation().y, closeTo(bottomOffset, 0.1));
    expect(boundaries.last, VerticalScrollBoundary.end);

    commands.moveVertically(1000);
    expect(controller.value.getTranslation().y, closeTo(0, 0.1));
    commands.moveVertically(1000);
    expect(controller.value.getTranslation().y, closeTo(0, 0.1));
    expect(boundaries.last, VerticalScrollBoundary.start);
  });

  testWidgets('content size changes preserve legal bounds', (tester) async {
    final controller = TransformationController();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: ZoomableViewport(
            contentSize: const Size(800, 600),
            controller: controller,
            child: const ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.drag(find.byType(ZoomableViewport), const Offset(-320, -220));
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: ZoomableViewport(
            contentSize: const Size(1200, 900),
            controller: controller,
            child: const ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final translation = controller.value.getTranslation();
    expect(translation.x, inInclusiveRange(-800.1, 0.1));
    expect(translation.y, inInclusiveRange(-600.1, 0.1));
  });
}

class _PaintCounter extends SingleChildRenderObjectWidget {
  const _PaintCounter({required this.onPaint, required super.child});
  final VoidCallback onPaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _CountedPaint(onPaint);
}

class _CountedPaint extends RenderProxyBox {
  _CountedPaint(this.onPaint);
  final VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}
