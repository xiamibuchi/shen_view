import 'dart:math' as math;

import 'decode_scheduler.dart';

enum PrefetchLevel { normal, conservative, onDemand }

/// Direction in logical reading order, independent of the screen's RTL axis.
enum ReadingDirection { backward, stationary, forward }

class PageGeometry {
  const PageGeometry({
    required this.index,
    required this.start,
    required this.end,
  });

  final int index;
  final double start;
  final double end;
}

class PrefetchTask {
  const PrefetchTask({
    required this.index,
    required this.priority,
    required this.distance,
  });

  final int index;
  final DecodePriority priority;
  final double distance;
}

class PrefetchPlan {
  PrefetchPlan({
    required Set<int> protectedPages,
    required Set<int> nearPages,
    required Set<int> emergencyPages,
    required List<PrefetchTask> tasks,
    required this.reserveBytes,
    required this.estimatedBytes,
    required this.oversubscribed,
  }) : protectedPages = Set.unmodifiable(protectedPages),
       nearPages = Set.unmodifiable(nearPages),
       emergencyPages = Set.unmodifiable(emergencyPages),
       tasks = List.unmodifiable(tasks);

  final Set<int> protectedPages;
  final Set<int> nearPages;
  final Set<int> emergencyPages;
  final List<PrefetchTask> tasks;
  final int reserveBytes;
  final int estimatedBytes;
  final bool oversubscribed;

  Set<int> get retainedPages => {
    ...protectedPages,
    ...nearPages,
    ...emergencyPages,
  };
}

/// Recomputes a bounded working set; emergency pages are retained, never fetched.
class PrefetchPlanner {
  const PrefetchPlanner();

  PrefetchPlan plan({
    required int totalPages,
    required Iterable<int> visiblePages,
    List<List<int>>? pageGroups,
    ReadingDirection direction = ReadingDirection.stationary,
    PrefetchLevel level = PrefetchLevel.normal,
    List<PageGeometry>? geometry,
    double? viewportStart,
    double? viewportEnd,
    Set<int> cachedPages = const {},
    Map<int, int> estimatedBytes = const {},
    int? budgetBytes,
    int usedBytes = 0,
    int estimatedPageBytes = 4 * 1024 * 1024,
  }) {
    final total = math.max(0, totalPages);
    final pageCost = math.max(1, estimatedPageBytes);
    final groupFor = <int, List<int>>{};
    for (final group in pageGroups ?? const <List<int>>[]) {
      final valid =
          group
              .where(
                (index) =>
                    index >= 0 && index < total && !groupFor.containsKey(index),
              )
              .toSet()
              .toList()
            ..sort();
      if (valid.isEmpty) continue;
      for (final index in valid) {
        groupFor[index] = valid;
      }
    }
    List<int> groupOf(int index) =>
        index >= 0 && index < total ? groupFor[index] ?? [index] : const [];
    final protected = <int>{};
    void protect(int index) {
      protected.addAll(groupOf(index));
    }

    for (final index in visiblePages) {
      protect(index);
    }
    final hasViewport =
        viewportStart != null &&
        viewportEnd != null &&
        viewportEnd > viewportStart;
    if (hasViewport) {
      for (final page in geometry ?? const <PageGeometry>[]) {
        if (page.end > viewportStart && page.start < viewportEnd) {
          protect(page.index);
        }
      }
    }
    int cost(Iterable<int> pages) => pages.fold(
      0,
      (sum, index) => sum + math.max(1, estimatedBytes[index] ?? pageCost),
    );
    int committed = cost(protected) + math.max(0, usedBytes);
    final int? limit = budgetBytes == null ? null : math.max(0, budgetBytes);
    int reserve = level == PrefetchLevel.normal ? pageCost * 3 : 0;
    if (limit != null) {
      reserve = math.min(reserve, math.max(0, limit - committed) ~/ 3);
    }
    final near = <int>{};
    final emergency = <int>{};
    if (protected.isEmpty) {
      return PrefetchPlan(
        protectedPages: protected,
        nearPages: near,
        emergencyPages: emergency,
        tasks: const [],
        reserveBytes: 0,
        estimatedBytes: committed,
        oversubscribed: limit != null && committed > limit,
      );
    }
    final first = protected.reduce(math.min);
    final last = protected.reduce(math.max);
    final relevantGeometry = <int, PageGeometry>{};
    double distance(int index) {
      if (protected.contains(index)) return 0;
      if (hasViewport) {
        final page = relevantGeometry[index];
        if (page != null) {
          final span = viewportEnd - viewportStart;
          return math.max(
                0,
                math.max(viewportStart - page.end, page.start - viewportEnd),
              ) /
              span;
        }
      }
      return (index < first ? first - index : index - last).toDouble();
    }

    bool ahead(int index) => switch (direction) {
      ReadingDirection.forward => index > last,
      ReadingDirection.backward => index < first,
      ReadingDirection.stationary => false,
    };
    int compare(int left, int right) {
      final distanceOrder = distance(left).compareTo(distance(right));
      if (distanceOrder != 0) return distanceOrder;
      final directionOrder = (ahead(right) ? 1 : 0).compareTo(
        ahead(left) ? 1 : 0,
      );
      return directionOrder != 0 ? directionOrder : left.compareTo(right);
    }

    final candidates = <int>{};
    final radius = switch (level) {
      PrefetchLevel.normal => 3,
      PrefetchLevel.conservative => 2,
      PrefetchLevel.onDemand => 0,
    };
    for (var offset = 1; offset <= radius; offset++) {
      candidates.addAll(groupOf(first - offset));
      candidates.addAll(groupOf(last + offset));
    }
    if (radius > 0 && hasViewport) {
      final span = viewportEnd - viewportStart;
      for (final page in geometry ?? const <PageGeometry>[]) {
        if (page.end > viewportStart - span &&
            page.start < viewportEnd + span) {
          candidates.addAll(groupOf(page.index));
        }
        if (candidates.contains(page.index) ||
            cachedPages.contains(page.index)) {
          relevantGeometry[page.index] = page;
        }
      }
    }
    candidates.removeAll(protected);
    final ordered = candidates.toList()..sort(compare);
    final considered = <int>{};
    for (final index in ordered) {
      if (considered.contains(index)) continue;
      final group = groupOf(index);
      considered.addAll(group);
      final additional = group.where((page) => !protected.contains(page));
      final bytes = cost(additional);
      if (limit != null && committed + bytes + reserve > limit) {
        // Reserve is headroom, not a reason to starve the closest complete group.
        if (near.isNotEmpty || committed + bytes > limit) continue;
        reserve = math.max(0, limit - committed - bytes);
      }
      near.addAll(additional);
      committed += bytes;
    }
    if (level == PrefetchLevel.normal) {
      final cached =
          cachedPages
              .where(
                (index) =>
                    index >= 0 &&
                    index < total &&
                    !protected.contains(index) &&
                    !near.contains(index),
              )
              .toList()
            ..sort(compare);
      for (final index in cached) {
        if (emergency.contains(index)) continue;
        final group = groupOf(index);
        if (!group.every(cachedPages.contains)) continue;
        final additional = group
            .where(
              (page) =>
                  !protected.contains(page) &&
                  !near.contains(page) &&
                  !emergency.contains(page),
            )
            .toSet();
        if (emergency.length + additional.length > 5) continue;
        final bytes = cost(additional);
        if (limit != null && committed + bytes + reserve > limit) continue;
        emergency.addAll(additional);
        committed += bytes;
      }
    }
    final tasks = <PrefetchTask>[
      for (final index in protected)
        PrefetchTask(
          index: index,
          priority: DecodePriority.foreground,
          distance: 0,
        ),
      for (final index in near.toList()..sort(compare))
        PrefetchTask(
          index: index,
          priority: distance(index) <= 1
              ? DecodePriority.adjacent
              : DecodePriority.near,
          distance: distance(index),
        ),
    ];
    return PrefetchPlan(
      protectedPages: protected,
      nearPages: near,
      emergencyPages: emergency,
      tasks: tasks,
      reserveBytes: reserve,
      estimatedBytes: committed,
      oversubscribed:
          limit != null && cost(protected) + math.max(0, usedBytes) > limit,
    );
  }
}
