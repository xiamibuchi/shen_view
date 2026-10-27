import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/prefetch_planner.dart';
import 'package:shen_view/src/application/thumbnail_prefetch_service.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';
import 'package:shen_view/src/domain/image_resource_key.dart';
import 'package:shen_view/src/domain/thumbnail_prefetch_mode.dart';

List<ImageEntry> entries(String folder) => List.generate(
  160,
  (i) => ImageEntry(
    file: File('$folder/$i.png'),
    format: ImageFormat.png,
    width: 100,
    height: 100,
    byteLength: 100,
    modifiedAt: DateTime(2026),
  ),
);

class Harness {
  Harness({Future<void> Function(ThumbnailPrefetchTask, DecodeRequest)? load}) {
    service = ThumbnailPrefetchService(
      version: (entry) => ImageFileVersion(
        path: entry.id,
        modifiedMicroseconds: 0,
        byteLength: 100,
      ),
      load: (task, request) async {
        started.add(task.key);
        requests.add(request);
        if (load != null) await load(task, request);
        if (!request.cancelled) cached.add(task.key);
      },
      isCached: cached.contains,
      onRetainedChanged: (keys) => retained = keys,
    );
    service.configure(ThumbnailPrefetchMode.automatic, PrefetchLevel.normal);
    service.setCollection('a');
  }
  late final ThumbnailPrefetchService service;
  final cached = <ImageResourceKey>{};
  final started = <ImageResourceKey>[];
  final requests = <DecodeRequest>[];
  Set<ImageResourceKey> retained = {};
  void viewport({
    String folder = 'a',
    int first = 60,
    int last = 69,
    bool visible = true,
    int direction = 1,
    List<int>? indices,
  }) {
    service.updateViewport(
      owner: 'strip',
      entries: entries(folder),
      first: first,
      last: last,
      targetWidth: 192,
      targetHeight: 144,
      visible: visible,
      direction: direction,
      indices: indices,
    );
  }
}

void main() {
  testWidgets('automatic uses two screens on each side with a 32 image cap', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.service.dispose);
    h.viewport();
    expect(h.retained.length, 40);
    expect(h.retained.any((key) => key.version.path == 'a/60.png'), false);
    h.viewport(first: 60, last: 99);
    expect(h.retained.length, 64);
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.started.single.version.path, 'a/100.png');
    h.service.dispose();
  });

  testWidgets(
    'conservative and resource degradation each use half a screen capped at eight',
    (tester) async {
      final h = Harness();
      addTearDown(h.service.dispose);
      h.viewport();
      h.service.configure(
        ThumbnailPrefetchMode.conservative,
        PrefetchLevel.normal,
      );
      expect(h.retained.length, 10);
      h.viewport(first: 60, last: 99);
      expect(h.retained.length, 16);
      h.service.configure(
        ThumbnailPrefetchMode.automatic,
        PrefetchLevel.conservative,
      );
      expect(h.retained.length, 16);
      h.service.dispose();
    },
  );

  testWidgets(
    'hidden viewport freezes the last range and finishes progressively',
    (tester) async {
      final h = Harness();
      addTearDown(h.service.dispose);
      h.viewport(first: 60, last: 61);
      final frozen = Set.of(h.retained);
      h.viewport(first: 120, last: 121, visible: false);
      expect(h.retained, frozen);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(h.started.toSet(), frozen);
      expect(h.started.length, frozen.length);
      h.viewport(first: 120, last: 121);
      expect(h.retained.intersection(frozen), isEmpty);
      h.service.dispose();
    },
  );

  testWidgets(
    'new collection cancels old work and starts without waiting for an uncancellable codec',
    (tester) async {
      final gates = <Completer<void>>[];
      final h = Harness(
        load: (_, _) {
          final gate = Completer<void>();
          gates.add(gate);
          return gate.future;
        },
      );
      h.viewport();
      await tester.pump(const Duration(milliseconds: 100));
      h.service.setCollection('b');
      expect(h.requests.first.cancelled, true);
      h.viewport(folder: 'b');
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.started.length, 2);
      expect(h.started.last.version.path.startsWith('b/'), true);
      gates.first.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.started.length, 2);
      h.service.dispose();
      gates.last.complete();
      await tester.pump();
    },
  );

  testWidgets('off cancels invisible work and does not dispatch more', (
    tester,
  ) async {
    final gate = Completer<void>();
    final h = Harness(load: (_, _) => gate.future);
    h.viewport();
    await tester.pump(const Duration(milliseconds: 100));
    h.service.configure(ThumbnailPrefetchMode.off, PrefetchLevel.normal);
    expect(h.requests.single.cancelled, true);
    expect(h.retained, isEmpty);
    gate.complete();
    await tester.pump(const Duration(seconds: 1));
    expect(h.started.length, 1);
    h.service.dispose();
  });

  testWidgets('pressure pauses plans and resumes unfinished images', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.service.dispose);
    h.viewport();
    h.service.configure(
      ThumbnailPrefetchMode.automatic,
      PrefetchLevel.onDemand,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(h.started, isEmpty);
    expect(h.retained, isNotEmpty);
    h.service.configure(ThumbnailPrefetchMode.automatic, PrefetchLevel.normal);
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.started.length, 1);
    h.service.dispose();
  });

  testWidgets(
    'decode failures never loop, while deferred capacity retries on recovery',
    (tester) async {
      var deferred = true;
      final h = Harness(
        load: (_, _) async {
          if (deferred) throw ThumbnailPrefetchDeferred();
          throw StateError('corrupt');
        },
      );
      addTearDown(h.service.dispose);
      h.viewport(first: 0, last: 0);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(h.started.length, 2);
      deferred = false;
      h.service.capacityChanged();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(h.started.length, 4);
      h.service.capacityChanged();
      await tester.pump(const Duration(seconds: 1));
      expect(h.started.length, 4);
      h.service.retry('a/1.png');
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.started.length, 5);
      h.service.dispose();
    },
  );

  testWidgets(
    'backward direction and filtered grid indices preserve candidate order',
    (tester) async {
      final h = Harness();
      addTearDown(h.service.dispose);
      h.viewport(
        first: 3,
        last: 4,
        direction: -1,
        indices: [10, 20, 30, 40, 50, 60, 70],
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.started.single.version.path, 'a/30.png');
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.started.last.version.path, 'a/60.png');
      h.service.replaceEntries(
        entries('a').where((e) => e.id != 'a/30.png').toList(),
      );
      expect(h.retained.any((key) => key.version.path == 'a/30.png'), false);
      h.service.dispose();
    },
  );
}
