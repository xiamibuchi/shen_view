import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/decode_scheduler.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('shared worker forwards live priority and restores remaining consumer demand', () async {
    final scheduler = DecodeScheduler();
    final gate = Completer<int>();
    final preload = DecodeRequest();
    final main = DecodeRequest();
    late DecodeRequest worker;
    final first = scheduler.scheduleShared(
      'priority',
      (request) {
        worker = request;
        return gate.future;
      },
      request: preload,
      priority: DecodePriority.preload,
      distance: 8,
    );
    expect(worker.priority, DecodePriority.preload);
    expect(worker.distance, 8);
    final priorities = <DecodePriority>[];
    worker.addPriorityListener(() => priorities.add(worker.priority));
    final second = scheduler.scheduleShared<int>(
      'priority',
      (_) => throw StateError('must share'),
      request: main,
    );
    final cancelled = expectLater(second, throwsA(isA<DecodeCancelled>()));
    expect(worker.priority, DecodePriority.foreground);
    main.cancel();
    expect(worker.cancelled, false);
    expect(worker.priority, DecodePriority.preload);
    scheduler.updatePriority(
      preload,
      priority: DecodePriority.visible,
      distance: -1,
    );
    expect(worker.distance, 0);
    expect(priorities, [
      DecodePriority.foreground,
      DecodePriority.preload,
      DecodePriority.visible,
    ]);
    gate.complete(42);
    expect(await first, 42);
    await cancelled;
    scheduler.dispose();
  });

  test(
    'visible thumbnails leave a main slot and capacity waits occupy no slot',
    () async {
      final scheduler = DecodeScheduler();
      final gate = Completer<void>();
      var ready = false;
      var blockedStarted = false;
      final blocked = scheduler.schedule(
        () async {
          blockedStarted = true;
        },
        request: DecodeRequest(),
        canStart: () => ready,
      );
      final tile = scheduler.schedule(
        () => gate.future,
        request: DecodeRequest(),
        priority: DecodePriority.visibleThumbnail,
      );
      var secondTile = false;
      final tile2 = scheduler.schedule(
        () async {
          secondTile = true;
        },
        request: DecodeRequest(),
        priority: DecodePriority.visibleThumbnail,
      );
      expect(scheduler.runningCount, 1);
      expect(
        await scheduler.schedule(() async => 42, request: DecodeRequest()),
        42,
      );
      expect(blockedStarted, false);
      expect(secondTile, false);
      ready = true;
      scheduler.refresh();
      await blocked;
      gate.complete();
      await Future.wait([tile, tile2]);
      expect(secondTile, true);
      scheduler.dispose();
    },
  );

  test('conservative foreground arrival cancels running speculation', () async {
    final scheduler = DecodeScheduler(maxConcurrent: 1);
    final background = DecodeRequest();
    final gate = Completer<void>();
    final back = scheduler.schedule(
      () => gate.future,
      request: background,
      priority: DecodePriority.thumbnail,
    );
    final cancelled = expectLater(back, throwsA(isA<DecodeCancelled>()));
    var frontStarted = false;
    final front = scheduler.schedule(() async {
      frontStarted = true;
    }, request: DecodeRequest());
    expect(background.cancelled, true);
    expect(frontStarted, false);
    gate.complete();
    await cancelled;
    await front;
    expect(frontStarted, true);
    scheduler.dispose();
  });

  test(
    'background fairness serves a thumbnail after three neighbor tasks',
    () async {
      final scheduler = DecodeScheduler(maxBackgroundConcurrent: 0);
      final order = <String>[];
      final tasks = [
        for (var i = 0; i < 6; i++)
          scheduler.schedule(
            () async {
              order.add('neighbor');
            },
            request: DecodeRequest(),
            priority: DecodePriority.adjacent,
          ),
        scheduler.schedule(
          () async {
            order.add('thumbnail');
          },
          request: DecodeRequest(),
          priority: DecodePriority.thumbnail,
        ),
      ];
      scheduler.setLimits(maxBackgroundConcurrent: 1);
      await Future.wait(tasks);
      expect(order.indexOf('thumbnail'), 3);
      scheduler.dispose();
    },
  );

  test(
    'background occupies only one normal slot so foreground starts immediately',
    () async {
      final scheduler = DecodeScheduler();
      final first = Completer<int>();
      var secondStarted = false;
      final a = scheduler.schedule(
        () => first.future,
        request: DecodeRequest(),
        priority: DecodePriority.preload,
      );
      final b = scheduler.schedule(
        () async {
          secondStarted = true;
          return 2;
        },
        request: DecodeRequest(),
        priority: DecodePriority.thumbnail,
      );
      final front = scheduler.schedule(() async => 3, request: DecodeRequest());
      expect(await front, 3);
      expect(secondStarted, false);
      first.complete(1);
      expect(await a, 1);
      expect(await b, 2);
      scheduler.dispose();
    },
  );

  test(
    'queued promotion and distance ordering reflect latest viewport',
    () async {
      final scheduler = DecodeScheduler(maxConcurrent: 1);
      final blocker = Completer<void>();
      final running = scheduler.schedule(
        () => blocker.future,
        request: DecodeRequest(),
      );
      final order = <String>[];
      final far = DecodeRequest();
      final a = scheduler.schedule(
        () async {
          order.add('far');
        },
        request: far,
        priority: DecodePriority.preload,
        distance: 20,
      );
      final b = scheduler.schedule(
        () async {
          order.add('near');
        },
        request: DecodeRequest(),
        priority: DecodePriority.preload,
        distance: 1,
      );
      scheduler.updatePriority(far, priority: DecodePriority.visible);
      blocker.complete();
      await Future.wait([running, a, b]);
      expect(order, ['far', 'near']);
      scheduler.dispose();
    },
  );

  test(
    'limits stop queued background while preserving foreground navigation',
    () async {
      final scheduler = DecodeScheduler(
        maxConcurrent: 1,
        maxBackgroundConcurrent: 0,
      );
      var started = false;
      final future = scheduler.schedule(
        () async {
          started = true;
          return 1;
        },
        request: DecodeRequest(),
        priority: DecodePriority.adjacent,
      );
      await flush();
      expect(started, false);
      expect(
        await scheduler.schedule(() async => 2, request: DecodeRequest()),
        2,
      );
      scheduler.setLimits(maxBackgroundConcurrent: 1);
      expect(await future, 1);
      scheduler.dispose();
    },
  );

  test(
    'shared cancellation detaches one consumer and preserves visible consumer',
    () async {
      final scheduler = DecodeScheduler();
      final gate = Completer<int>();
      final preload = DecodeRequest();
      final visible = DecodeRequest();
      DecodeRequest? worker;
      var calls = 0;
      Future<int> operation(DecodeRequest request) {
        calls++;
        worker = request;
        return gate.future;
      }

      final a = scheduler.scheduleShared(
        'same-key',
        operation,
        request: preload,
        priority: DecodePriority.preload,
      );
      final cancelled = expectLater(a, throwsA(isA<DecodeCancelled>()));
      final b = scheduler.scheduleShared(
        'same-key',
        operation,
        request: visible,
      );
      preload.cancel();
      expect(worker!.cancelled, false);
      gate.complete(42);
      expect(await b, 42);
      await cancelled;
      expect(calls, 1);
      scheduler.dispose();
    },
  );

  test(
    'last shared consumer cancels worker and discards late codec exactly once',
    () async {
      final scheduler = DecodeScheduler();
      final gate = Completer<int>();
      final user = DecodeRequest();
      var discarded = 0;
      DecodeRequest? worker;
      final result = scheduler.scheduleShared(
        'key',
        (request) {
          worker = request;
          return gate.future;
        },
        request: user,
        onDiscard: (value) {
          discarded += value;
        },
      );
      final cancelled = expectLater(result, throwsA(isA<DecodeCancelled>()));
      user.cancel();
      expect(worker!.cancelled, true);
      gate.complete(1);
      await cancelled;
      await flush();
      expect(discarded, 1);
      expect(scheduler.runningCount, 0);
      scheduler.dispose();
    },
  );

  test('cancelling queued work never runs operation', () async {
    final scheduler = DecodeScheduler(maxBackgroundConcurrent: 0);
    var started = false;
    final request = DecodeRequest();
    final result = scheduler.schedule(
      () async {
        started = true;
      },
      request: request,
      priority: DecodePriority.preload,
    );
    final cancelled = expectLater(result, throwsA(isA<DecodeCancelled>()));
    request.cancel();
    await cancelled;
    expect(started, false);
    expect(scheduler.queuedCount, 0);
    scheduler.dispose();
  });
}
