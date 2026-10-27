import 'bar_layout_metrics.dart';

/// Natural widths of the command bar groups, in logical pixels.
class CommandBarExtents {
  const CommandBarExtents({
    required this.leadingInset,
    required this.commandButton,
    required this.sortLabel,
    required this.sortCompact,
    required this.pin,
    required this.windowControls,
  });

  final double leadingInset;

  /// One command icon button, including its padded tap target.
  final double commandButton;

  final double sortLabel;

  final double sortCompact;

  final double pin;

  final double windowControls;

  double commandGroupWidth(int slots) => leadingInset + slots * commandButton;

  double trailingGroupWidth({
    required bool compactSort,
    required bool showPin,
  }) =>
      (compactSort ? sortCompact : sortLabel) +
      (showPin ? pin : 0) +
      windowControls;
}

class CommandBarLayout {
  const CommandBarLayout({
    required this.commandSlots,
    required this.commandCount,
    required this.compactSort,
    required this.showPin,
    required this.fileNameWidth,
  });

  /// Buttons that stay inline, including the overflow trigger. When
  /// [commandSlots] is smaller than [commandCount] the last slot belongs to the
  /// overflow menu.
  final int commandSlots;
  final int commandCount;

  final bool compactSort;

  final bool showPin;

  /// Space the centered file name may use. Negative when the side groups alone
  /// are already wider than the bar; the bar then hides the title.
  final double fileNameWidth;

  bool get showOverflow => commandSlots < commandCount;

  bool get showFileName => fileNameWidth >= 24;

  /// Hysteresis ranking: command slots outweigh the pin and sort label together.
  int get richness =>
      commandSlots * 8 + (showPin ? 2 : 0) + (compactSort ? 0 : 1);

  @override
  bool operator ==(Object other) =>
      other is CommandBarLayout &&
      other.commandSlots == commandSlots &&
      other.commandCount == commandCount &&
      other.compactSort == compactSort &&
      other.showPin == showPin &&
      other.fileNameWidth == fileNameWidth;

  @override
  int get hashCode => Object.hash(
    commandSlots,
    commandCount,
    compactSort,
    showPin,
    fileNameWidth,
  );

  @override
  String toString() =>
      'CommandBarLayout(slots: $commandSlots/$commandCount, '
      'compactSort: $compactSort, pin: $showPin, '
      'fileName: ${fileNameWidth.toStringAsFixed(1)})';

  /// Degradation order: sort label, always-on-top button, then inline commands
  /// from the end of the list. The file name stays centered, so both sides have
  /// to leave room for it; it is only squeezed below
  /// [BarLayoutMetrics.minFileNameWidth] when nothing else can be dropped.
  ///
  /// [previous] enables [resolveWithHysteresis] threshold stabilization.
  static CommandBarLayout resolve({
    required double width,
    required CommandBarExtents extents,
    required int commandCount,
    double minGap = BarLayoutMetrics.minGap,
    double minFileNameWidth = BarLayoutMetrics.minFileNameWidth,
    double hysteresisBand = BarLayoutMetrics.hysteresisBand,
    CommandBarLayout? previous,
  }) {
    // The command list changes with mode (fullscreen adds an exit command), so
    // never trust a slot count from a wider or richer mode.
    final normalized = previous == null || previous.commandCount == commandCount
        ? previous
        : _clampSlots(previous, commandCount);
    return resolveWithHysteresis(
      width: width,
      band: hysteresisBand,
      previous: normalized,
      resolveAt: (width) => _resolveAt(
        width: width,
        extents: extents,
        commandCount: commandCount,
        minGap: minGap,
        minFileNameWidth: minFileNameWidth,
      ),
      richnessOf: (layout) => layout.richness,
    );
  }

  static CommandBarLayout _clampSlots(
    CommandBarLayout layout,
    int commandCount,
  ) {
    final slots = layout.commandSlots.clamp(
      1,
      commandCount < 1 ? 1 : commandCount,
    );
    if (slots == layout.commandSlots && layout.commandCount == commandCount) {
      return layout;
    }
    return CommandBarLayout(
      commandSlots: slots,
      commandCount: commandCount,
      compactSort: layout.compactSort,
      showPin: layout.showPin,
      fileNameWidth: layout.fileNameWidth,
    );
  }

  static CommandBarLayout _resolveAt({
    required double width,
    required CommandBarExtents extents,
    required int commandCount,
    required double minGap,
    required double minFileNameWidth,
  }) {
    CommandBarLayout? fallback;
    CommandBarLayout? fittingFallback;
    var smallestGroups = double.infinity;
    for (final layout in _ladder(
      width: width,
      extents: extents,
      commandCount: commandCount,
      minGap: minGap,
    )) {
      if (layout.fileNameWidth >= minFileNameWidth) return layout;
      final groups =
          extents.commandGroupWidth(layout.commandSlots) +
          extents.trailingGroupWidth(
            compactSort: layout.compactSort,
            showPin: layout.showPin,
          );
      // Below the centered-title limit, the groups must still fit together.
      // Comparing title space alone can retain commands that overlap the
      // window buttons when a pinned directory leaves a very narrow bar.
      if (groups <= width &&
          (fittingFallback == null ||
              layout.fileNameWidth > fittingFallback.fileNameWidth)) {
        fittingFallback = layout;
      }
      if (groups < smallestGroups) {
        fallback = layout;
        smallestGroups = groups;
      }
    }
    return fittingFallback ?? fallback!;
  }

  /// Every state of the collapse ladder, richest first, ending with a single
  /// overflow trigger.
  static Iterable<CommandBarLayout> _ladder({
    required double width,
    required CommandBarExtents extents,
    required int commandCount,
    required double minGap,
  }) sync* {
    final maximumSlots = commandCount < 1 ? 1 : commandCount;
    var slots = maximumSlots;
    var compactSort = false;
    var showPin = true;
    while (true) {
      final left = extents.commandGroupWidth(slots);
      final right = extents.trailingGroupWidth(
        compactSort: compactSort,
        showPin: showPin,
      );
      // The file name is centered, so the wider side decides how much room is
      // left for it.
      final side = left > right ? left : right;
      yield CommandBarLayout(
        commandSlots: slots,
        commandCount: commandCount,
        compactSort: compactSort,
        showPin: showPin,
        fileNameWidth: width - side * 2 - minGap * 2,
      );
      if (!compactSort) {
        compactSort = true;
        continue;
      }
      if (showPin) {
        showPin = false;
        continue;
      }
      if (slots > 1) {
        slots--;
        continue;
      }
      return;
    }
  }
}
