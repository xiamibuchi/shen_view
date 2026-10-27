import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/prefetch_planner.dart';
import 'package:shen_view/src/application/prefetch_policy.dart';
import 'package:shen_view/src/application/resource_budget.dart';

void main() {
  const planner = PrefetchPlanner();
  test(
    '3-5-3 keeps six near pages and only five already cached emergency pages',
    () {
      final plan = planner.plan(
        totalPages: 40,
        visiblePages: [20],
        cachedPages: Set.of(List.generate(40, (index) => index)),
        estimatedPageBytes: 10,
      );
      expect(plan.protectedPages, {20});
      expect(plan.nearPages, {17, 18, 19, 21, 22, 23});
      expect(plan.emergencyPages.length, 5);
      expect(plan.reserveBytes, 30);
      expect(
        plan.tasks.map((task) => task.index),
        isNot(containsAll(plan.emergencyPages)),
      );
    },
  );

  test('double pages expand three-page near radius into full spreads', () {
    final plan = planner.plan(
      totalPages: 12,
      visiblePages: [4],
      pageGroups: [
        [0],
        [1, 2],
        [3],
        [4, 5],
        [6, 7],
        [8, 9],
        [10, 11],
      ],
    );
    expect(plan.protectedPages, {4, 5});
    expect(plan.nearPages, containsAll([6, 7, 8, 9]));
    expect(plan.nearPages.contains(10), false);
  });

  test(
    'budget admits whole groups or none and preserves oversized visible spread',
    () {
      final plan = planner.plan(
        totalPages: 10,
        visiblePages: [4],
        pageGroups: [
          [4, 5],
          [6, 7],
        ],
        estimatedPageBytes: 10,
        budgetBytes: 15,
      );
      expect(plan.protectedPages, {4, 5});
      expect(plan.nearPages, isEmpty);
      expect(plan.oversubscribed, true);
    },
  );

  test('turnover reserve yields to one affordable adjacent page', () {
    final plan = planner.plan(
      totalPages: 3,
      visiblePages: [0],
      estimatedPageBytes: 10,
      budgetBytes: 20,
    );
    expect(plan.nearPages, {1});
    expect(plan.reserveBytes, 0);
    expect(plan.estimatedBytes, 20);
  });

  test('fast reversal reprioritizes both sides without historical targets', () {
    final forward = planner.plan(
      totalPages: 40,
      visiblePages: [20],
      direction: ReadingDirection.forward,
    );
    final backward = planner.plan(
      totalPages: 40,
      visiblePages: [20],
      direction: ReadingDirection.backward,
    );
    expect(forward.tasks[1].index, 21);
    expect(backward.tasks[1].index, 19);
    expect(forward.nearPages, backward.nearPages);
    final jump = planner.plan(totalPages: 40, visiblePages: [2]);
    expect(jump.retainedPages, isNot(contains(20)));
  });

  test('strip protects every short visible page and covers one screen on both sides', () {
    final geometry = List.generate(
      100,
      (index) =>
          PageGeometry(index: index, start: index * 10, end: (index + 1) * 10),
    );
    final plan = planner.plan(
      totalPages: 100,
      visiblePages: [25],
      geometry: geometry,
      viewportStart: 200,
      viewportEnd: 300,
    );
    expect(
      plan.protectedPages,
      Set.of(List.generate(10, (index) => 20 + index)),
    );
    expect(
      plan.nearPages,
      containsAll(List.generate(10, (index) => 10 + index)),
    );
    expect(
      plan.nearPages,
      containsAll(List.generate(10, (index) => 30 + index)),
    );
    final demand = planner.plan(
      totalPages: 100,
      visiblePages: [25],
      geometry: geometry,
      viewportStart: 200,
      viewportEnd: 300,
      level: PrefetchLevel.onDemand,
    );
    expect(demand.protectedPages, plan.protectedPages);
    expect(demand.nearPages, isEmpty);
  });

  test(
    'emergency group is retained only when whole group was already cached',
    () {
      final plan = planner.plan(
        totalPages: 30,
        visiblePages: [0],
        pageGroups: [
          [20, 21],
        ],
        cachedPages: {20},
      );
      expect(plan.emergencyPages, isEmpty);
    },
  );

  test(
    'resource reservations count inflight bytes and release exactly once',
    () {
      final budget = ResourceBudget(limitBytes: 100);
      final lease = budget.reserve(60)!;
      expect(budget.reserve(30, headroomBytes: 20), isNull);
      budget.limitBytes = 50;
      expect(budget.oversubscribed, true);
      lease.release();
      lease.release();
      expect(budget.usedBytes, 0);
    },
  );

  final start = DateTime(2026, 10, 20);
  AdaptivePrefetchPolicy policy() => AdaptivePrefetchPolicy(
    now: start,
    physicalMemoryBytes: 8 * 1024 * 1024 * 1024,
    availableMemoryBytes: 2 * 1024 * 1024 * 1024,
  );

  test('unknown machine starts conservative and small RAM never gains a minimum budget', () {
    expect(
      AdaptivePrefetchPolicy(now: start).level,
      PrefetchLevel.conservative,
    );
    final weak = AdaptivePrefetchPolicy(
      now: start,
      availableMemoryBytes: 32 * 1024 * 1024,
      physicalMemoryBytes: 512 * 1024 * 1024,
    );
    expect(weak.memoryBudgetBytes, 8 * 1024 * 1024);
  });

  test(
    'continuous bad frames downgrade, stable thirty seconds recovers one level',
    () {
      final state = policy();
      for (var step = 0; step <= 8; step++) {
        state.recordFrame(
          elapsed: const Duration(milliseconds: 40),
          frameBudget: const Duration(milliseconds: 16),
          hasSpeculativeWork: true,
          now: start.add(Duration(milliseconds: step * 500)),
        );
      }
      expect(state.level, PrefetchLevel.onDemand);
      state.tick(now: start.add(const Duration(seconds: 20)));
      expect(state.level, PrefetchLevel.onDemand);
      state.tick(now: start.add(const Duration(seconds: 34)));
      expect(state.level, PrefetchLevel.conservative);
      state.tick(now: start.add(const Duration(seconds: 35)));
      expect(state.level, PrefetchLevel.conservative);
      state.tick(now: start.add(const Duration(seconds: 64)));
      expect(state.level, PrefetchLevel.normal);
    },
  );

  test(
    'pressure stops speculative work immediately until cleared and stable',
    () {
      final state = policy();
      state.pressure(now: start);
      state.tick(now: start.add(const Duration(minutes: 5)));
      expect(state.maxBackgroundConcurrent, 0);
      state.clearPressure(now: start.add(const Duration(minutes: 5)));
      state.tick(now: start.add(const Duration(minutes: 5, seconds: 29)));
      expect(state.level, PrefetchLevel.onDemand);
      state.tick(now: start.add(const Duration(minutes: 5, seconds: 30)));
      expect(state.level, PrefetchLevel.conservative);
    },
  );

  test(
    'conservative preference caps recovery and idle pauses all prefetch',
    () {
      final state = policy();
      state.configure(maxLevel: PrefetchLevel.conservative, now: start);
      state.tick(now: start.add(const Duration(minutes: 1)));
      expect(state.level, PrefetchLevel.conservative);
      state.setActive(false, now: start);
      expect(state.level, PrefetchLevel.onDemand);
      state.setActive(true, now: start);
      expect(state.level, PrefetchLevel.conservative);
    },
  );

  test('slow format alone does not classify machine as weak', () {
    final state = policy();
    for (var step = 0; step < 20; step++) {
      state.recordDecode(
        elapsed: const Duration(seconds: 1),
        hasSpeculativeWork: true,
        now: start.add(Duration(seconds: step)),
      );
    }
    expect(state.level, PrefetchLevel.normal);
  });

  test(
    'focus and prefetch preference do not shrink visible image capacity',
    () {
      final state = policy();
      final capacity = state.memoryBudgetBytes;
      state.setActive(false);
      expect(state.memoryBudgetBytes, capacity);
      state.setActive(true);
      state.configure(maxLevel: PrefetchLevel.onDemand);
      expect(state.memoryBudgetBytes, capacity);
      state.configure(maxLevel: PrefetchLevel.normal);
      expect(state.level, PrefetchLevel.normal);
      state.pressure();
      expect(state.memoryBudgetBytes, lessThan(capacity));
      state.clearPressure();
      expect(state.memoryBudgetBytes, capacity);
    },
  );
}
