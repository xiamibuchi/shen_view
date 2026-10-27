import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/folder_change_watcher.dart';
import 'package:path/path.dart' as paths;

String np(String path) => paths.normalize(path);

String _picturePath([String relative = '']) =>
    paths.join(Directory.systemTemp.path, 'shenview-watcher', relative);

void main() {
  late StreamController<FileSystemEvent> events;
  late List<FolderChangeBatch> batches;
  late List<Object> errors;
  late FolderChangeWatcher watcher;

  setUp(() {
    events = StreamController<FileSystemEvent>.broadcast();
    batches = [];
    errors = [];
    watcher =
        FolderChangeWatcher(
            debounce: const Duration(milliseconds: 60),
            maxLatency: const Duration(milliseconds: 250),
            streamFactory: (path, recursive) => events.stream,
            includePath: (path) => !path.endsWith('.txt'),
          )
          ..onChanged = batches.add
          ..onError = (error, stackTrace) => errors.add(error);
  });

  tearDown(() async {
    watcher.dispose();
    await events.close();
  });

  Future<void> emit(String path) async {
    events.add(FileSystemCreateEvent(path, false));
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }

  Future<void> settle(int milliseconds) =>
      Future<void>.delayed(Duration(milliseconds: milliseconds));

  test('coalesces a burst of changes into one debounced batch', () async {
    watcher.watch(_picturePath(), recursive: true);
    expect(watcher.isActive, isTrue);
    await emit(_picturePath('a.png'));
    await emit(_picturePath('b.png'));
    await emit(_picturePath('c.png'));
    expect(batches, isEmpty);
    await settle(140);
    expect(batches, hasLength(1));
    expect(batches.single.paths, hasLength(3));
    expect(batches.single.overflowed, isFalse);
    expect(watcher.hasPendingChanges, isFalse);
    await settle(140);
    expect(batches, hasLength(1));
  });

  test('drops irrelevant paths before they extend the debounce', () async {
    watcher.watch(_picturePath(), recursive: false);
    await emit(_picturePath('notes.txt'));
    await settle(140);
    expect(batches, isEmpty);
    await emit(_picturePath('new.png'));
    await settle(140);
    expect(batches, hasLength(1));
    expect(batches.single.paths, {np(_picturePath('new.png'))});
  });

  test('accumulates changes while unfocused and flushes on focus', () async {
    watcher.watch(_picturePath(), recursive: true);
    watcher.setPaused(true);
    await emit(_picturePath('a.png'));
    await settle(160);
    expect(batches, isEmpty);
    expect(watcher.hasPendingChanges, isTrue);
    watcher.setPaused(false);
    watcher.flushNow();
    expect(batches, hasLength(1));
    expect(batches.single.paths, {np(_picturePath('a.png'))});
  });

  test('keeps refreshing during a long burst instead of waiting', () async {
    watcher.watch(_picturePath(), recursive: true);
    for (var index = 0; index < 20; index++) {
      await emit(_picturePath('$index.png'));
      await settle(35);
    }
    await settle(100);
    expect(batches.length, greaterThanOrEqualTo(2));
    final delivered = batches.expand((batch) => batch.paths).toSet();
    expect(delivered.length, greaterThanOrEqualTo(2));
  });

  test('switching folders drops changes from the previous folder', () async {
    watcher.watch(_picturePath('one'), recursive: false);
    await emit(_picturePath('one/a.png'));
    watcher.watch(_picturePath('two'), recursive: false);
    expect(watcher.hasPendingChanges, isFalse);
    await settle(140);
    expect(batches, isEmpty);
    await emit(_picturePath('two/b.png'));
    await settle(140);
    expect(batches.single.paths, {np(_picturePath('two/b.png'))});
  });

  test('watch stream errors stop watching and are reported once', () async {
    watcher.watch(_picturePath(), recursive: true);
    events.addError(FileSystemException('watch failed'));
    await settle(20);
    expect(errors, hasLength(1));
    expect(watcher.isActive, isFalse);
    expect(watcher.hasPendingChanges, isFalse);
  });

  test('move events filter and retain both source and destination', () async {
    watcher.watch(_picturePath(), recursive: true);
    events.add(
      FileSystemMoveEvent(
        _picturePath('download.txt'),
        false,
        _picturePath('new.png'),
      ),
    );
    events.add(
      FileSystemMoveEvent(
        _picturePath('old.png'),
        false,
        _picturePath('removed.txt'),
      ),
    );
    events.add(
      FileSystemMoveEvent(
        _picturePath('one/a.png'),
        false,
        _picturePath('two/a.png'),
      ),
    );
    await settle(140);
    expect(batches.single.paths, {
      np(_picturePath('new.png')),
      np(_picturePath('old.png')),
      np(_picturePath('one/a.png')),
      np(_picturePath('two/a.png')),
    });
  });

  test('directory events bypass file extension filters', () async {
    watcher.watch(_picturePath(), recursive: true);
    events.add(FileSystemCreateEvent(_picturePath('chapter.txt'), true));
    await settle(140);
    expect(batches.single.paths, {np(_picturePath('chapter.txt'))});
  });

  test(
    'stream completion delivers pending changes and permits restart',
    () async {
      watcher.watch(_picturePath(), recursive: true);
      await emit(_picturePath('a.png'));
      await events.close();
      expect(watcher.isActive, isFalse);
      expect(errors, hasLength(1));
      expect(batches.single.paths, {np(_picturePath('a.png'))});
      events = StreamController<FileSystemEvent>.broadcast();
      watcher.watch(_picturePath(), recursive: true);
      expect(watcher.isActive, isTrue);
      await emit(_picturePath('b.png'));
      await settle(140);
      expect(batches.last.paths, {np(_picturePath('b.png'))});
    },
  );

  test('stop clears pending changes without emitting a batch', () async {
    watcher.watch(_picturePath(), recursive: false);
    await emit(_picturePath('a.png'));
    watcher.stop();
    expect(watcher.isActive, isFalse);
    expect(watcher.hasPendingChanges, isFalse);
    await settle(140);
    expect(batches, isEmpty);
  });

  test(
    'repeated watch calls keep the subscription and pending changes',
    () async {
      watcher.watch(_picturePath(), recursive: true);
      await emit(_picturePath('a.png'));
      expect(watcher.hasPendingChanges, isTrue);
      watcher.watch(_picturePath(), recursive: true);
      expect(watcher.hasPendingChanges, isTrue);
      await settle(140);
      expect(batches, hasLength(1));
      // Still subscribed after the repeated watch call.
      await emit(_picturePath('b.png'));
      await settle(140);
      expect(batches, hasLength(2));
    },
  );

  test('oversized batches report an overflow instead of every path', () async {
    watcher.watch(_picturePath(), recursive: true);
    for (var index = 0; index < 700; index++) {
      events.add(FileSystemCreateEvent(_picturePath('$index.png'), false));
    }
    await settle(140);
    expect(batches, hasLength(1));
    expect(batches.single.overflowed, isTrue);
    expect(batches.single.paths, contains(np(_picturePath())));
  });
}
