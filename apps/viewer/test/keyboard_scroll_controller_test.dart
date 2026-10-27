import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/presentation/keyboard_scroll_controller.dart';

void main() {
  testWidgets('short presses animate one finite step', (tester) async {
    final deltas = <double>[];
    final scroll = KeyboardScrollController(
      vsync: tester,
      onScroll: deltas.add,
    );
    addTearDown(scroll.dispose);
    scroll.press(-1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(deltas.single.abs(), inExclusiveRange(0, 80));
    scroll.release(-1);
    await tester.pump(const Duration(milliseconds: 160));
    expect(
      deltas.fold<double>(0, (sum, delta) => sum + delta),
      closeTo(-80, 0.01),
    );
    final count = deltas.length;
    await tester.pump(const Duration(seconds: 1));
    expect(deltas.length, count);
  });

  testWidgets('holding accelerates and release stops continuous motion', (
    tester,
  ) async {
    final deltas = <double>[];
    final scroll = KeyboardScrollController(
      vsync: tester,
      onScroll: deltas.add,
    );
    addTearDown(scroll.dispose);
    scroll.press(-1);
    await tester.pump();
    for (var frame = 0; frame < 50; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(deltas.every((delta) => delta < 0), isTrue);
    expect(deltas.skip(10).first.abs(), lessThan(deltas.last.abs()));
    expect(
      deltas.fold<double>(0, (sum, delta) => sum - delta),
      greaterThan(400),
    );
    scroll.release(-1);
    final count = deltas.length;
    await tester.pump(const Duration(seconds: 1));
    expect(deltas.length, count);
  });

  testWidgets('held keys stop at the boundary and do not restart', (
    tester,
  ) async {
    var position = 0.0;
    var updates = 0;
    late final KeyboardScrollController scroll;
    scroll = KeyboardScrollController(
      vsync: tester,
      onScroll: (delta) {
        position = (position + delta).clamp(-40.0, 0.0);
        updates++;
        if (position <= -40) scroll.stopAtBoundary();
      },
    );
    addTearDown(scroll.dispose);
    scroll.press(-1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(position, -40);
    final stoppedUpdates = updates;
    scroll.press(-1);
    await tester.pump(const Duration(seconds: 1));
    expect(updates, stoppedUpdates);
    scroll.release(-1);
    scroll.press(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(position, greaterThan(-40));
    scroll.cancel();
    final cancelledUpdates = updates;
    await tester.pump(const Duration(seconds: 1));
    expect(updates, cancelledUpdates);
  });
}
