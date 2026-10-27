import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/presentation/scroll_navigation_controller.dart';

PointerScrollEvent _event(Offset delta, int milliseconds, {int device = 0}) =>
    PointerScrollEvent(
      scrollDelta: delta,
      timeStamp: Duration(milliseconds: milliseconds),
      device: device,
    );

void main() {
  test('small vertical deltas accumulate before turning a page', () {
    final navigation = ScrollNavigationController();
    for (var i = 0; i < 19; i++) {
      expect(navigation.handle(_event(const Offset(0, 1), i * 8)), isNull);
    }
    expect(navigation.handle(_event(const Offset(0, 1), 152)), 1);
  });

  test('continuous input repeats at a bounded rate and can reverse', () {
    final navigation = ScrollNavigationController();
    final turns = <int>[];
    final times = <int>[];
    for (var i = 0; i < 400; i++) {
      final direction = navigation.handle(
        _event(Offset(0, i < 200 ? 2 : -3), i * 16),
      );
      if (direction != null) {
        turns.add(direction);
        times.add(i * 16);
      }
    }
    expect(turns.where((turn) => turn == 1).length, greaterThan(10));
    expect(turns.where((turn) => turn == -1).length, greaterThan(10));
    for (var i = 1; i < times.length; i++) {
      expect(times[i] - times[i - 1], greaterThanOrEqualTo(180));
    }
    expect(navigation.handle(_event(const Offset(0, -20), 6634)), -1);
  });

  test(
    'horizontal gestures cannot turn a page through their vertical tail',
    () {
      final navigation = ScrollNavigationController();
      expect(navigation.handle(_event(const Offset(100, 0), 0)), isNull);
      expect(navigation.handle(_event(const Offset(0, 120), 16)), isNull);
      expect(navigation.handle(_event(const Offset(0, -120), 32)), isNull);
      expect(navigation.handle(_event(const Offset(0, 20), 282)), 1);
    },
  );

  test('opposite jitter cancels and quiet gaps discard unfinished motion', () {
    final navigation = ScrollNavigationController();
    for (var i = 0; i < 100; i++) {
      expect(
        navigation.handle(_event(Offset(0, i.isEven ? 2 : -2), i * 8)),
        isNull,
      );
    }
    expect(navigation.handle(_event(const Offset(0, 10), 1100)), isNull);
    expect(navigation.handle(_event(const Offset(0, 10), 1400)), isNull);
    expect(navigation.handle(_event(const Offset(0, 10), 1410)), 1);
  });

  test(
    'separate wheel notches remain immediately usable in both directions',
    () {
      final navigation = ScrollNavigationController();
      expect(navigation.handle(_event(const Offset(0, 20), 0)), 1);
      expect(navigation.handle(_event(const Offset(0, 120), 300)), 1);
      expect(navigation.handle(_event(const Offset(0, -20), 600)), -1);
    },
  );

  test('zoom and scrolling modes suppress the rest of their burst', () {
    final navigation = ScrollNavigationController();
    expect(
      navigation.handle(_event(const Offset(0, 5), 0), enabled: false),
      isNull,
    );
    expect(navigation.handle(_event(const Offset(0, 100), 16)), isNull);
    expect(navigation.handle(_event(const Offset(0, 20), 266)), 1);
  });

  test('inertia cancellation cannot bypass the configured interval', () {
    final navigation = ScrollNavigationController();
    expect(navigation.handle(_event(const Offset(0, 20), 0)), 1);
    navigation.reset();
    expect(navigation.handle(_event(const Offset(0, -20), 16)), isNull);
    expect(
      navigation.handle(_event(const Offset(0, 20), 32, device: 1)),
      isNull,
    );
    expect(navigation.handle(_event(const Offset(0, 20), 180, device: 1)), 1);
  });

  test(
    'large wheel deltas never create a backlog and interval is configurable',
    () {
      final navigation = ScrollNavigationController();
      const interval = Duration(milliseconds: 500);
      expect(
        navigation.handle(
          _event(const Offset(0, 12000), 0),
          interval: interval,
        ),
        1,
      );
      for (var i = 1; i < 500; i++) {
        expect(
          navigation.handle(
            _event(const Offset(0, 120), i),
            interval: interval,
          ),
          isNull,
        );
      }
      expect(
        navigation.handle(
          _event(const Offset(0, 120), 500),
          interval: interval,
        ),
        1,
      );
      // A quiet gap discards accumulated motion, rather than replaying it.
      expect(
        navigation.handle(_event(const Offset(0, 1), 1200), interval: interval),
        isNull,
      );
    },
  );

  test('zero and invalid deltas do not navigate or poison accumulation', () {
    final navigation = ScrollNavigationController();
    for (final delta in [
      Offset.zero,
      const Offset(double.nan, 20),
      const Offset(0, double.infinity),
    ]) {
      expect(navigation.handle(_event(delta, 0)), isNull);
    }
    expect(navigation.handle(_event(const Offset(0, 20), 16)), 1);
  });
}
