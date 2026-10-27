import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/presentation/navigation_hold_controller.dart';

void main() {
  testWidgets(
    'hold waits, repeats at its own rate, and release stops immediately',
    (tester) async {
      final turns = <int>[];
      final hold = NavigationHoldController(turns.add);
      addTearDown(hold.dispose);
      hold.press(1);
      expect(turns, [1]);
      await tester.pump(const Duration(milliseconds: 399));
      expect(turns, [1]);
      await tester.pump(const Duration(milliseconds: 1));
      expect(turns, [1, 1]);
      await tester.pump(const Duration(milliseconds: 540));
      expect(turns.length, 5);
      hold.release(1);
      await tester.pump(const Duration(seconds: 2));
      expect(turns.length, 5);
    },
  );

  testWidgets(
    'opposite key replaces the held direction and stale key-up cannot stop it',
    (tester) async {
      final turns = <int>[];
      final hold = NavigationHoldController(turns.add);
      addTearDown(hold.dispose);
      hold.press(1);
      hold.press(
        -1,
        delay: const Duration(milliseconds: 200),
        interval: const Duration(milliseconds: 100),
      );
      hold.release(1);
      await tester.pump(const Duration(milliseconds: 400));
      expect(turns, [1, -1, -1, -1, -1]);
      hold.stop();
      await tester.pump(const Duration(seconds: 2));
      expect(turns.length, 5);
    },
  );

  testWidgets(
    'disabled repeat keeps single presses and cancellation in callback is safe',
    (tester) async {
      final turns = <int>[];
      late final NavigationHoldController hold;
      hold = NavigationHoldController((direction) {
        turns.add(direction);
        if (turns.length == 3) hold.stop();
      });
      addTearDown(hold.dispose);
      hold.press(1, enabled: false);
      await tester.pump(const Duration(seconds: 2));
      expect(turns, [1]);
      hold.press(-1);
      await tester.pump(const Duration(seconds: 2));
      expect(turns, [1, -1, -1]);
    },
  );
}
