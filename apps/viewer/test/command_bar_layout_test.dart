import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/presentation/bar_layout_metrics.dart';
import 'package:shen_view/src/presentation/command_bar_layout.dart';

const _extents = CommandBarExtents(
  leadingInset: 10,
  commandButton: 48,
  sortLabel: 90,
  sortCompact: 36,
  pin: 36,
  windowControls: 132,
);

CommandBarLayout _resolve(double width, {int commands = 5}) =>
    CommandBarLayout.resolve(
      width: width,
      extents: _extents,
      commandCount: commands,
    );

/// Narrowest width that still keeps the requested state with the preferred
/// file name width. Derived from the same extents the resolver uses, so the
/// tests follow the content instead of repeating pixel breakpoints.
double _requiredWidth({
  required int slots,
  required bool compactSort,
  required bool showPin,
}) {
  final left = _extents.commandGroupWidth(slots);
  final right = _extents.trailingGroupWidth(
    compactSort: compactSort,
    showPin: showPin,
  );
  final side = left > right ? left : right;
  return side * 2 +
      BarLayoutMetrics.minGap * 2 +
      BarLayoutMetrics.minFileNameWidth;
}

void main() {
  test('the bare command groups fit beside a pinned directory', () {
    final minimum =
        _extents.commandGroupWidth(1) +
        _extents.trailingGroupWidth(compactSort: true, showPin: false);
    final narrowest = _resolve(minimum);
    expect(narrowest.commandSlots, 1);
    expect(narrowest.compactSort, isTrue);
    expect(narrowest.showPin, isFalse);
    expect(narrowest.showFileName, isFalse);
    CommandBarLayout? previous;
    for (var width = minimum; width <= 440; width++) {
      final layout = CommandBarLayout.resolve(
        width: width,
        extents: _extents,
        commandCount: 5,
        previous: previous,
      );
      expect(
        _extents.commandGroupWidth(layout.commandSlots) +
            _extents.trailingGroupWidth(
              compactSort: layout.compactSort,
              showPin: layout.showPin,
            ),
        lessThanOrEqualTo(width),
      );
      previous = layout;
    }
  });

  test('the full layout survives down to its measured requirement', () {
    final required = _requiredWidth(
      slots: 5,
      compactSort: false,
      showPin: true,
    );
    final atLimit = _resolve(required);
    expect(atLimit.commandSlots, 5);
    expect(atLimit.compactSort, isFalse);
    expect(atLimit.showPin, isTrue);
    expect(atLimit.showOverflow, isFalse);
    expect(
      atLimit.fileNameWidth,
      greaterThanOrEqualTo(BarLayoutMetrics.minFileNameWidth),
    );

    final belowLimit = _resolve(required - 1);
    expect(
      belowLimit.compactSort || !belowLimit.showPin,
      isTrue,
      reason: 'below the requirement something has to give',
    );
  });

  test('a 900 px bar keeps every group inline', () {
    // Regression guard for the old fixed breakpoints, which collapsed the sort
    // label at 1120 and the pin at 1020 while the content still fitted.
    final layout = _resolve(900);
    expect(layout.commandSlots, 5);
    expect(layout.compactSort, isFalse);
    expect(layout.showPin, isTrue);
    expect(layout.showOverflow, isFalse);
    expect(layout.fileNameWidth, greaterThan(200));
  });

  test('the sort label goes before the pin, and the pin before commands', () {
    // A short command list keeps the left group narrower than the right one, so
    // the right group drives the decisions here.
    const commands = 2;
    CommandBarLayout at(double width) => _resolve(width, commands: commands);

    double? firstCompact;
    for (var width = 900.0; width >= 200; width -= 1) {
      if (at(width).compactSort) {
        firstCompact = width;
        break;
      }
    }
    expect(firstCompact, isNotNull);
    expect(at(firstCompact!).showPin, isTrue);
    expect(at(firstCompact).commandSlots, commands);

    double? firstWithoutPin;
    for (var width = firstCompact; width >= 200; width -= 1) {
      if (!at(width).showPin) {
        firstWithoutPin = width;
        break;
      }
    }
    expect(firstWithoutPin, isNotNull);
    expect(at(firstWithoutPin!).compactSort, isTrue);
    expect(at(firstWithoutPin).commandSlots, commands);
  });

  test('commands leave one slot at a time down to the overflow trigger', () {
    final slots = <int>[];
    for (var width = 640.0; width >= 280; width -= 2) {
      slots.add(_resolve(width).commandSlots);
    }
    for (var i = 1; i < slots.length; i++) {
      expect(slots[i], lessThanOrEqualTo(slots[i - 1]));
    }
    expect(slots.first, 5);
    // The right group (sort + window buttons) decides how far the left group
    // has to shrink before the file name is the only thing left to squeeze.
    expect(slots.last, lessThan(5));
    expect(_resolve(280).showOverflow, isTrue);
  });

  test(
    'one extra command is absorbed by the content, not by new constants',
    () {
      final required = _requiredWidth(
        slots: 5,
        compactSort: false,
        showPin: true,
      );
      final five = _resolve(required);
      final six = _resolve(required, commands: 6);
      expect(five.compactSort, isFalse);
      // The sixth command no longer fits next to the label, so the label goes.
      expect(six.compactSort, isTrue);
      expect(six.commandSlots, 5);
    },
  );

  test('a squeezed title is still reported so the bar can clamp it', () {
    for (var width = 200.0; width <= 1600; width += 4) {
      final layout = _resolve(width);
      expect(layout.showFileName, layout.fileNameWidth >= 24);
    }
    expect(_resolve(200).fileNameWidth, lessThan(0));
  });
}
