import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/presentation/bar_layout_metrics.dart';
import 'package:shen_view/src/presentation/command_bar_layout.dart';
import 'package:shen_view/src/presentation/status_bar_layout.dart';

/// Same fixtures as the layout tests: 52 px icon buttons, a 120 px slider,
/// 17 px separators and a 238 px file-facts group.
const _button = 52.0;
const _divider = 17.0;
const _slider = 120.0;
const _inset = 16.0;

const _statusExtents = StatusBarExtents(
  horizontalInset: _inset,
  thumbnailToggle: _button,
  metadata: 238,
  infoToggle: _button,
  divider: _divider,
  scaleModes: _button * 2 + _divider,
  zoomCluster: _slider + _button * 2,
  zoomTrigger: _button,
  fullscreen: _button,
);

const _commandExtents = CommandBarExtents(
  leadingInset: 10,
  commandButton: 48,
  sortLabel: 90,
  sortCompact: 36,
  pin: 36,
  windowControls: 132,
);

StatusBarLayout _status(double width, {StatusBarLayout? previous}) =>
    StatusBarLayout.resolve(
      width: width,
      extents: _statusExtents,
      previous: previous,
    );

StatusBarLayout _statusPure(double width) => StatusBarLayout.resolve(
  width: width,
  extents: _statusExtents,
  hysteresisBand: 0,
);

CommandBarLayout _command(double width, {CommandBarLayout? previous}) =>
    CommandBarLayout.resolve(
      width: width,
      extents: _commandExtents,
      commandCount: 4,
      previous: previous,
    );

CommandBarLayout _commandPure(double width) => CommandBarLayout.resolve(
  width: width,
  extents: _commandExtents,
  commandCount: 4,
  hysteresisBand: 0,
);

/// Smallest width (0.5 px steps) at which [predicate] holds.
double _firstWidth(double from, double to, bool Function(double) predicate) {
  for (var width = from; width <= to; width += 0.5) {
    if (predicate(width)) return width;
  }
  fail('predicate never held between $from and $to');
}

void main() {
  group('bar hysteresis', () {
    test('a shrinking window never regains a status bar group', () {
      var previous = _statusPure(1400);
      final transitions = <StatusBarLayout>[];
      for (var width = 1400.0; width >= 320; width -= 1) {
        final next = _status(width, previous: previous);
        expect(
          next.richness,
          lessThanOrEqualTo(previous.richness),
          reason: 'width $width regained a group: $next',
        );
        if (next != previous) transitions.add(next);
        previous = next;
      }
      // One transition per group: zoom cluster, file facts, scale modes,
      // fullscreen.
      expect(transitions.length, lessThanOrEqualTo(4));
      expect(previous.richness, lessThanOrEqualTo(1));
    });

    test('growing back waits for the hysteresis band', () {
      final pureThreshold = _firstWidth(
        300,
        1400,
        (width) => _statusPure(width).showZoomControls,
      );

      var previous = _statusPure(pureThreshold - 1);
      expect(previous.showZoomControls, isFalse);

      double? restoredAt;
      for (
        var width = pureThreshold - 1;
        width <= pureThreshold + 80;
        width += 0.5
      ) {
        final next = _status(width, previous: previous);
        if (next.showZoomControls && restoredAt == null) restoredAt = width;
        previous = next;
      }

      expect(restoredAt, isNotNull);
      expect(
        restoredAt!,
        closeTo(pureThreshold + BarLayoutMetrics.hysteresisBand, 1.0),
      );
    });

    test('flapping the width around the threshold does not flicker', () {
      final pureThreshold = _firstWidth(
        300,
        1400,
        (width) => _statusPure(width).showZoomControls,
      );

      var previous = _statusPure(pureThreshold + 40);
      expect(previous.showZoomControls, isTrue);

      var flips = 0;
      var shown = previous.showZoomControls;
      for (var i = 0; i < 200; i++) {
        final width = i.isEven ? pureThreshold - 0.5 : pureThreshold + 0.5;
        final next = _status(width, previous: previous);
        if (next.showZoomControls != shown) {
          flips++;
          shown = next.showZoomControls;
        }
        previous = next;
      }

      expect(
        flips,
        1,
        reason: 'the cluster collapsed once and must stay hidden',
      );
      expect(previous.showZoomControls, isFalse);
    });

    test('the status bar decision is stable when fed back', () {
      for (var width = 240.0; width <= 1600; width += 4) {
        final first = _status(width);
        expect(_status(width, previous: first), first, reason: 'width $width');
      }
    });

    test('a shrinking window never regains a command bar group', () {
      var previous = _commandPure(1400);
      var transitions = 0;
      for (var width = 1400.0; width >= 300; width -= 1) {
        final next = _command(width, previous: previous);
        expect(
          next.richness,
          lessThanOrEqualTo(previous.richness),
          reason: 'width $width regained a group: $next',
        );
        if (next.richness != previous.richness) transitions++;
        previous = next;
      }
      // Label, pin and at most three command slots.
      expect(transitions, lessThanOrEqualTo(5));
    });

    test('the command bar sort label only returns after the band', () {
      final pureThreshold = _firstWidth(
        300,
        1400,
        (width) => !_commandPure(width).compactSort,
      );

      var previous = _commandPure(pureThreshold - 40);
      expect(previous.compactSort, isTrue);

      double? restoredAt;
      for (
        var width = pureThreshold - 40;
        width <= pureThreshold + 120;
        width += 0.5
      ) {
        final next = _command(width, previous: previous);
        if (!next.compactSort && restoredAt == null) restoredAt = width;
        previous = next;
      }

      expect(restoredAt, isNotNull);
      expect(
        restoredAt!,
        greaterThanOrEqualTo(
          pureThreshold + BarLayoutMetrics.hysteresisBand - 1,
        ),
      );
    });

    test(
      'flapping the width around the command bar threshold does not flicker',
      () {
        final pureThreshold = _firstWidth(
          300,
          1400,
          (width) => !_commandPure(width).compactSort,
        );

        var previous = _commandPure(pureThreshold + 40);
        var flips = 0;
        var compact = previous.compactSort;
        for (var i = 0; i < 200; i++) {
          final width = i.isEven ? pureThreshold - 0.5 : pureThreshold + 0.5;
          final next = _command(width, previous: previous);
          if (next.compactSort != compact) {
            flips++;
            compact = next.compactSort;
          }
          previous = next;
        }

        expect(
          flips,
          1,
          reason: 'the label collapsed once and must stay hidden',
        );
        expect(previous.compactSort, isTrue);
      },
    );

    test('the command bar decision is stable when fed back', () {
      for (var width = 240.0; width <= 1600; width += 4) {
        final first = _command(width);
        final second = _command(width, previous: first);
        expect(second.commandSlots, first.commandSlots, reason: 'width $width');
        expect(second.compactSort, first.compactSort, reason: 'width $width');
        expect(second.showPin, first.showPin, reason: 'width $width');
      }
    });

    test('a new command count does not resurrect stale slots', () {
      // Fullscreen adds a command; the previous layout came from a mode with
      // fewer commands and must not request more slots than exist.
      final fewer = CommandBarLayout.resolve(
        width: 900,
        extents: _commandExtents,
        commandCount: 3,
      );
      expect(fewer.commandSlots, 3);
      final more = CommandBarLayout.resolve(
        width: 900,
        extents: _commandExtents,
        commandCount: 4,
        previous: fewer,
      );
      expect(more.commandSlots, lessThanOrEqualTo(4));
      expect(more.commandCount, 4);
    });
  });
}
