import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';
import 'package:shen_view/src/domain/comic_layout_direction.dart';
import 'package:shen_view/src/domain/view_scale_mode.dart';
import 'package:shen_view/src/application/prefetch_planner.dart';
import 'package:shen_view/src/presentation/comic_strip_viewport.dart';
import 'package:shen_view/src/presentation/zoomable_viewport.dart';

ImageEntry _entry(String name, {int? width, int? height}) => ImageEntry(
  file: File(name),
  format: ImageFormat.png,
  width: width,
  height: height,
  byteLength: 0,
  modifiedAt: DateTime(2026, 10, 16),
);

Widget _comic({
  required List<ImageEntry> entries,
  required TransformationController controller,
  required ZoomableViewportCommands commands,
  required Future<Size?> Function(String path) loadSize,
  int currentIndex = 0,
  int jumpToken = 0,
  bool originalSize = false,
  ViewScaleMode? scaleMode,
  bool uniformPageSize = true,
  int resetRequest = 0,
  bool zoomAroundCenter = false,
  double wheelScrollSpeed = 1,
  double wheelZoomSpeed = 1,
  ComicLayoutDirection layoutDirection = ComicLayoutDirection.vertical,
  ValueChanged<VerticalScrollBoundary>? onBoundary,
  ValueChanged<int>? onPage,
  Widget Function(ImageEntry entry, bool isCurrent)? buildPage,
  void Function(Set<int>, List<PageGeometry>, double, double)?
  onVisiblePagesChanged,
  int metadataPreloadPages = 3,
  Set<String>? admittedPageIds,
  ComicPositionController? positionController,
  ComicReadingPosition? initialPosition,
}) => MaterialApp(
  home: Center(
    child: SizedBox(
      width: 400,
      height: 300,
      child: ComicStripViewport(
        positionController: positionController,
        initialPosition: initialPosition,
        entries: entries,
        currentIndex: currentIndex,
        jumpToken: jumpToken,
        viewport: const Size(400, 300),
        baseWidth: 400,
        originalSize: originalSize,
        scaleMode: scaleMode,
        uniformPageSize: uniformPageSize,
        resetRequest: resetRequest,
        zoomAroundCenter: zoomAroundCenter,
        wheelScrollSpeed: wheelScrollSpeed,
        wheelZoomSpeed: wheelZoomSpeed,
        layoutDirection: layoutDirection,
        controller: controller,
        commands: commands,
        onVerticalBoundary: onBoundary ?? (_) {},
        pageGap: 2,
        loadSize: loadSize,
        onCurrentPageChanged: onPage ?? (_) {},
        onVisiblePagesChanged: onVisiblePagesChanged,
        metadataPreloadPages: metadataPreloadPages,
        admittedPageIds: admittedPageIds,
        buildPage:
            buildPage ?? (entry, _) => const ColoredBox(color: Colors.blue),
      ),
    ),
  ),
);

Future<void> _flushLayout(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Rect _displayRect(WidgetTester tester, String path) {
  final box = tester.renderObject<RenderBox>(find.byKey(ValueKey(path)));
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
}

void main() {
  for (final direction in ComicLayoutDirection.values) {
    testWidgets(
      'panning reuses page widgets until the visible window changes in $direction',
      (tester) async {
        final vertical = direction == ComicLayoutDirection.vertical;
        final entries = List.generate(
          4,
          (i) => _entry(
            'page-$i.png',
            width: vertical ? 400 : 2000,
            height: vertical ? 2000 : 400,
          ),
        );
        final controller = TransformationController();
        final commands = ZoomableViewportCommands();
        var builds = 0;
        final active = <String, bool>{};
        Widget comic(int current, int jump) => _comic(
          entries: entries,
          controller: controller,
          commands: commands,
          currentIndex: current,
          jumpToken: jump,
          layoutDirection: direction,
          loadSize: (_) async => null,
          buildPage: (entry, current) {
            builds++;
            active[entry.id] = current;
            return const ColoredBox(color: Colors.blue);
          },
        );
        await tester.pumpWidget(comic(0, 0));
        await _flushLayout(tester);
        final beforeBuilds = builds;
        final before = controller.value.getTranslation();
        for (var i = 0; i < 3; i++) {
          if (vertical) {
            commands.moveVertically(-10);
          } else {
            commands.moveHorizontally(
              direction == ComicLayoutDirection.horizontalRightToLeft
                  ? 10
                  : -10,
            );
          }
          await tester.pump();
        }
        final after = controller.value.getTranslation();
        expect(
          vertical ? after.y : after.x,
          isNot(vertical ? before.y : before.x),
        );
        expect(builds, beforeBuilds);
        await tester.pumpWidget(comic(1, 1));
        await _flushLayout(tester);
        expect(active['page-1.png'], isTrue);
        expect(builds, greaterThan(beforeBuilds));
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        commands.dispose();
      },
    );
  }

  testWidgets(
    'auto play waits for real visible page dimensions before testing strip end',
    (tester) async {
      final dimensions = Completer<Size?>();
      final position = ComicPositionController();
      final transform = TransformationController();
      final commands = ZoomableViewportCommands();
      await tester.pumpWidget(
        _comic(
          entries: [_entry('pending.png')],
          controller: transform,
          commands: commands,
          positionController: position,
          loadSize: (_) => dimensions.future,
        ),
      );
      await _flushLayout(tester);
      expect(position.layoutReady, isFalse);
      dimensions.complete(const Size(400, 1800));
      await _flushLayout(tester);
      expect(position.layoutReady, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(position.layoutReady, isFalse);
      transform.dispose();
      commands.dispose();
    },
  );
  for (final direction in ComicLayoutDirection.values) {
    for (final mode in ViewScaleMode.values) {
      testWidgets('continuous sizing $mode applies to one page in $direction', (
        tester,
      ) async {
        final controller = TransformationController();
        final commands = ZoomableViewportCommands();
        final entries = [
          _entry('first.png', width: 200, height: 400),
          _entry('second.png', width: 200, height: 400),
          _entry('third.png', width: 200, height: 400),
        ];
        await tester.pumpWidget(
          _comic(
            entries: entries,
            controller: controller,
            commands: commands,
            loadSize: (_) async => null,
            layoutDirection: direction,
            scaleMode: mode,
          ),
        );
        await _flushLayout(tester);
        final page = _displayRect(tester, entries.first.id);
        final expected = switch (mode) {
          ViewScaleMode.autoFit ||
          ViewScaleMode.fitHeight => const Size(150, 300),
          ViewScaleMode.fitWidth => const Size(400, 800),
          ViewScaleMode.originalSize => const Size(200, 400),
        };
        expect(page.width, closeTo(expected.width, 0.01));
        expect(page.height, closeTo(expected.height, 0.01));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        commands.dispose();
      });
    }
  }

  testWidgets('native pages retain their own size when uniform layout is off', (
    tester,
  ) async {
    final controller = TransformationController();
    final commands = ZoomableViewportCommands();
    final entries = [
      _entry('first.png', width: 200, height: 400),
      _entry('second.png', width: 600, height: 300),
    ];
    await tester.pumpWidget(
      _comic(
        entries: entries,
        controller: controller,
        commands: commands,
        loadSize: (_) async => null,
        scaleMode: ViewScaleMode.originalSize,
        uniformPageSize: false,
      ),
    );
    await _flushLayout(tester);
    expect(_displayRect(tester, entries.first.id).size, const Size(200, 400));
    commands.moveVertically(-400);
    await _flushLayout(tester);
    expect(_displayRect(tester, entries.last.id).size, const Size(600, 300));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    commands.dispose();
  });

  testWidgets(
    'applying sizing keeps the current reading anchor and resets manual zoom',
    (tester) async {
      final controller = TransformationController();
      final commands = ZoomableViewportCommands();
      final positions = ComicPositionController();
      final entries = List.generate(
        4,
        (i) => _entry('$i.png', width: 200, height: 600),
      );
      Widget comic(ViewScaleMode mode, int revision) => _comic(
        entries: entries,
        controller: controller,
        commands: commands,
        loadSize: (_) async => null,
        scaleMode: mode,
        resetRequest: revision,
        positionController: positions,
        currentIndex: 1,
      );
      await tester.pumpWidget(comic(ViewScaleMode.fitWidth, 0));
      await _flushLayout(tester);
      commands.setScale(2);
      commands.moveVertically(-200);
      await _flushLayout(tester);
      final anchor = positions.capture()!;
      await tester.pumpWidget(comic(ViewScaleMode.autoFit, 1));
      await _flushLayout(tester);
      final restored = positions.capture()!;
      expect(restored.path, anchor.path);
      expect(restored.pageFraction, closeTo(anchor.pageFraction, 0.002));
      expect(controller.value.getMaxScaleOnAxis(), 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      commands.dispose();
    },
  );

  for (final direction in ComicLayoutDirection.values) {
    testWidgets('mode remount restores page fraction and zoom for $direction', (
      tester,
    ) async {
      final controller = TransformationController();
      final commands = ZoomableViewportCommands();
      final positions = ComicPositionController();
      addTearDown(controller.dispose);
      addTearDown(commands.dispose);
      final entries = List.generate(
        5,
        (index) => _entry('restore-$index.png', width: 600, height: 800),
      );
      var selected = 2;
      Widget host({ComicReadingPosition? position}) => _comic(
        entries: entries,
        controller: controller,
        commands: commands,
        loadSize: (_) async => null,
        layoutDirection: direction,
        currentIndex: selected,
        positionController: positions,
        initialPosition: position,
        onPage: (index) => selected = index,
      );
      await tester.pumpWidget(host());
      await _flushLayout(tester);
      commands.setScale(1.4);
      if (direction == ComicLayoutDirection.vertical) {
        commands.moveVertically(-180);
      } else {
        commands.moveHorizontally(
          direction == ComicLayoutDirection.horizontalRightToLeft ? 180 : -180,
        );
      }
      // Flush before the normal 160ms report debounce expires.
      positions.flushCurrentPage();
      final saved = positions.capture()!;
      final scale = controller.value.getMaxScaleOnAxis();
      await tester.pumpWidget(const SizedBox());
      expect(positions.capture(), isNull);
      await tester.pumpWidget(host(position: saved));
      await _flushLayout(tester);
      final restored = positions.capture()!;
      expect(restored.path, saved.path);
      expect(restored.pageFraction, closeTo(saved.pageFraction, 0.001));
      expect(restored.crossFraction, closeTo(saved.crossFraction, 0.001));
      expect(controller.value.getMaxScaleOnAxis(), closeTo(scale, 0.001));
      expect(tester.takeException(), isNull);
    });
  }

  for (final direction in ComicLayoutDirection.values) {
    testWidgets('wheel follows $direction and honors scroll and zoom speeds', (
      tester,
    ) async {
      final controller = TransformationController();
      final commands = ZoomableViewportCommands();
      addTearDown(controller.dispose);
      addTearDown(commands.dispose);
      await tester.pumpWidget(
        _comic(
          entries: List.generate(
            5,
            (index) => _entry('wheel-$index.png', width: 400, height: 400),
          ),
          controller: controller,
          commands: commands,
          loadSize: (_) async => null,
          layoutDirection: direction,
          wheelScrollSpeed: 2,
          wheelZoomSpeed: 2,
        ),
      );
      await _flushLayout(tester);
      final position = tester.getCenter(find.byType(ZoomableViewport));
      final before = controller.value.getTranslation();
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, 40),
        ),
      );
      final after = controller.value.getTranslation();
      if (direction == ComicLayoutDirection.vertical) {
        expect(after.y - before.y, closeTo(-80, 0.01));
      } else {
        expect(
          after.x - before.x,
          closeTo(
            direction == ComicLayoutDirection.horizontalRightToLeft ? 80 : -80,
            0.01,
          ),
        );
      }
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, -120),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(controller.value.getMaxScaleOnAxis(), closeTo(2.7182818, 0.0001));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'offscreen pages require admission while the complete viewport always builds',
    (tester) async {
      final controller = TransformationController();
      final commands = ZoomableViewportCommands();
      final entries = List.generate(
        10,
        (index) => _entry('admit-$index.png', width: 400, height: 200),
      );
      final built = <String>{};
      Widget comic(Set<String> admitted) => _comic(
        entries: entries,
        controller: controller,
        commands: commands,
        admittedPageIds: admitted,
        loadSize: (_) async => null,
        buildPage: (entry, current) {
          built.add(entry.id);
          return const SizedBox();
        },
      );
      await tester.pumpWidget(comic({}));
      await _flushLayout(tester);
      expect(built, {'admit-0.png', 'admit-1.png'});
      built.clear();
      await tester.pumpWidget(comic({'admit-2.png'}));
      await _flushLayout(tester);
      expect(built, {'admit-0.png', 'admit-1.png', 'admit-2.png'});
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      commands.dispose();
    },
  );

  testWidgets(
    'viewport callback includes every short visible page in scene coordinates',
    (tester) async {
      final controller = TransformationController();
      final commands = ZoomableViewportCommands();
      Set<int> visible = {};
      double start = -1;
      double end = -1;
      await tester.pumpWidget(
        _comic(
          entries: List.generate(
            100,
            (index) => _entry('short-$index.png', width: 400, height: 50),
          ),
          controller: controller,
          commands: commands,
          loadSize: (_) async => null,
          onVisiblePagesChanged: (pages, geometry, from, to) {
            visible = pages;
            start = from;
            end = to;
          },
        ),
      );
      await _flushLayout(tester);
      expect(visible, {0, 1, 2, 3, 4, 5});
      expect(start, closeTo(0, .01));
      expect(end, closeTo(300, .01));
      commands.moveVertically(-250);
      await _flushLayout(tester);
      expect(visible, containsAll([5, 6, 7, 8, 9, 10]));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      commands.dispose();
    },
  );

  testWidgets(
    'RTL viewport callback mirrors scene positions into logical page order',
    (tester) async {
      final controller = TransformationController();
      final commands = ZoomableViewportCommands();
      Set<int> visible = {};
      List<PageGeometry> geometry = [];
      double start = -1;
      await tester.pumpWidget(
        _comic(
          entries: List.generate(
            10,
            (index) => _entry('rtl-$index.png', width: 100, height: 300),
          ),
          controller: controller,
          commands: commands,
          loadSize: (_) async => null,
          layoutDirection: ComicLayoutDirection.horizontalRightToLeft,
          onVisiblePagesChanged: (pages, layouts, from, to) {
            visible = pages;
            geometry = layouts;
            start = from;
          },
        ),
      );
      await _flushLayout(tester);
      expect(visible, {0, 1, 2, 3});
      expect(start, closeTo(0, .01));
      expect(
        geometry.map((page) => page.index),
        List.generate(10, (index) => index),
      );
      expect(geometry.first.start, closeTo(0, .01));
      expect(geometry[1].start, closeTo(102, .01));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      commands.dispose();
    },
  );

  testWidgets(
    'metadata never sweeps an archive and jump requests the new local window',
    (tester) async {
      final controller = TransformationController();
      final commands = ZoomableViewportCommands();
      final entries = List.generate(
        100,
        (index) => _entry('unknown-$index.png'),
      );
      final loaded = <String>{};
      Widget comic(int currentIndex, int jumpToken) => _comic(
        entries: entries,
        controller: controller,
        commands: commands,
        currentIndex: currentIndex,
        jumpToken: jumpToken,
        loadSize: (path) async {
          loaded.add(path);
          return const Size(400, 400);
        },
      );
      await tester.pumpWidget(comic(0, 0));
      await _flushLayout(tester);
      expect(loaded.length, lessThanOrEqualTo(4));
      expect(loaded, isNot(contains('unknown-99.png')));
      await tester.pumpWidget(comic(60, 1));
      await _flushLayout(tester);
      expect(loaded, contains('unknown-60.png'));
      // Placeholder corrections can expose another page while preserving the
      // anchor; both local windows remain bounded and skip the intervening book.
      expect(loaded.length, lessThanOrEqualTo(20));
      expect(loaded, isNot(contains('unknown-30.png')));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      commands.dispose();
    },
  );

  testWidgets('on-demand metadata does not prepare speculative neighbors', (
    tester,
  ) async {
    final controller = TransformationController();
    final commands = ZoomableViewportCommands();
    final loaded = <String>{};
    await tester.pumpWidget(
      _comic(
        entries: List.generate(20, (index) => _entry('demand-$index.png')),
        controller: controller,
        commands: commands,
        metadataPreloadPages: 0,
        loadSize: (path) async {
          loaded.add(path);
          return const Size(400, 400);
        },
      ),
    );
    await _flushLayout(tester);
    expect(loaded, {'demand-0.png'});
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    commands.dispose();
  });

  testWidgets(
    'zoom scales the entire strip without relayout or per-page zoom',
    (tester) async {
      final entries = [
        _entry('first.png', width: 400, height: 400),
        _entry('second.png', width: 800, height: 400),
        _entry('third.png', width: 200, height: 100),
      ];
      final controller = TransformationController();
      final commands = ZoomableViewportCommands();
      await tester.pumpWidget(
        _comic(
          entries: entries,
          controller: controller,
          commands: commands,
          loadSize: (_) async => null,
        ),
      );
      await _flushLayout(tester);
      final viewportFinder = find.byType(ZoomableViewport);
      final before = tester.widget<ZoomableViewport>(viewportFinder);
      final viewport = tester.getRect(viewportFinder);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: viewport.center,
          scrollDelta: Offset(0, 240 * 0.6931471805599453),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(controller.value.getMaxScaleOnAxis(), closeTo(0.5, 0.0001));
      final after = tester.widget<ZoomableViewport>(viewportFinder);
      expect(after.contentSize, before.contentSize);
      expect(after.contentRevision, before.contentRevision);
      final first = _displayRect(tester, 'first.png');
      final second = _displayRect(tester, 'second.png');
      final third = _displayRect(tester, 'third.png');
      expect(first.width, closeTo(200, 0.01));
      expect(first.height, closeTo(200, 0.01));
      expect(second.width, closeTo(first.width, 0.01));
      expect(second.height, closeTo(100, 0.01));
      expect(third.width, closeTo(first.width, 0.01));
      expect(second.top - first.bottom, closeTo(1, 0.01));
      expect(third.top - second.bottom, closeTo(1, 0.01));
      expect(first.center.dx, closeTo(viewport.center.dx, 0.01));
      commands.moveVertically(-10000);
      await tester.pump();
      expect(
        _displayRect(tester, 'third.png').bottom,
        closeTo(viewport.bottom, 0.01),
      );

      await tester.pumpWidget(
        _comic(
          entries: entries,
          controller: controller,
          commands: commands,
          loadSize: (_) async => null,
          currentIndex: 1,
          jumpToken: 1,
        ),
      );
      await tester.pump();
      expect(controller.value.getMaxScaleOnAxis(), closeTo(0.5, 0.0001));
      expect(
        tester.widget<ZoomableViewport>(viewportFinder).contentRevision,
        before.contentRevision,
      );
      expect(_displayRect(tester, 'second.png').width, closeTo(200, 0.01));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: viewport.center,
          scrollDelta: Offset(0, -240 * 1.3862943611198906),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(controller.value.getMaxScaleOnAxis(), closeTo(2, 0.0001));
      expect(
        tester.widget<ZoomableViewport>(viewportFinder).contentSize,
        before.contentSize,
      );
      commands.moveVertically(-10000);
      await tester.pump();
      expect(
        _displayRect(tester, 'third.png').bottom,
        closeTo(viewport.bottom, 0.01),
      );
      commands.moveVertically(10000);
      await tester.pump();
      expect(
        _displayRect(tester, 'first.png').top,
        closeTo(viewport.top, 0.01),
      );
      expect(_displayRect(tester, 'first.png').width, closeTo(800, 0.01));
      commands.moveVertically(-804);
      await tester.pump();
      expect(_displayRect(tester, 'second.png').width, closeTo(800, 0.01));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      commands.dispose();
    },
  );

  testWidgets('original strip width stays fixed across pages and late sizes', (
    tester,
  ) async {
    final entries = [_entry('first.png'), _entry('second.png')];
    final sizes = {
      for (final entry in entries) entry.file.path: Completer<Size?>(),
    };
    final controller = TransformationController();
    final commands = ZoomableViewportCommands();
    Widget comic({int currentIndex = 0, int jumpToken = 0}) => _comic(
      entries: entries,
      controller: controller,
      commands: commands,
      loadSize: (path) => sizes[path]!.future,
      originalSize: true,
      currentIndex: currentIndex,
      jumpToken: jumpToken,
    );
    await tester.pumpWidget(comic());
    await _flushLayout(tester);
    sizes['first.png']!.complete(const Size(600, 1200));
    await _flushLayout(tester);
    expect(
      tester
          .widget<ZoomableViewport>(find.byType(ZoomableViewport))
          .contentSize
          .width,
      600,
    );
    sizes['second.png']!.complete(const Size(1600, 800));
    await _flushLayout(tester);
    expect(
      tester
          .widget<ZoomableViewport>(find.byType(ZoomableViewport))
          .contentSize,
      const Size(600, 1502),
    );
    await tester.pumpWidget(comic(currentIndex: 1, jumpToken: 1));
    await tester.pump();
    expect(
      tester
          .widget<ZoomableViewport>(find.byType(ZoomableViewport))
          .contentSize,
      const Size(600, 1502),
    );
    expect(controller.value.getMaxScaleOnAxis(), 1);
    expect(controller.value.getTranslation().y, -1202);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    commands.dispose();
  });

  testWidgets('horizontal comic layouts keep page order and boundaries', (
    tester,
  ) async {
    final entries = [
      _entry('first.png', width: 400, height: 400),
      _entry('second.png', width: 800, height: 400),
      _entry('third.png', width: 200, height: 400),
    ];
    final controller = TransformationController();
    final commands = ZoomableViewportCommands();
    await tester.pumpWidget(
      _comic(
        entries: entries,
        controller: controller,
        commands: commands,
        loadSize: (_) async => null,
        layoutDirection: ComicLayoutDirection.horizontalLeftToRight,
      ),
    );
    await _flushLayout(tester);
    final viewportFinder = find.byType(ZoomableViewport);
    final viewport = tester.getRect(viewportFinder);
    final content = tester.widget<ZoomableViewport>(viewportFinder).contentSize;
    expect(content, const Size(1054, 300));
    expect(
      _displayRect(tester, 'first.png').left,
      closeTo(viewport.left, 0.01),
    );
    expect(
      _displayRect(tester, 'second.png').left,
      closeTo(viewport.left + 302, 0.01),
    );
    commands.moveHorizontally(-10000);
    await tester.pump();
    expect(
      _displayRect(tester, 'third.png').right,
      closeTo(viewport.right, 0.01),
    );

    final rtlController = TransformationController();
    final rtlCommands = ZoomableViewportCommands();
    await tester.pumpWidget(
      _comic(
        entries: entries,
        controller: rtlController,
        commands: rtlCommands,
        loadSize: (_) async => null,
        layoutDirection: ComicLayoutDirection.horizontalRightToLeft,
        currentIndex: 0,
        jumpToken: 0,
      ),
    );
    await _flushLayout(tester);
    expect(
      tester.widget<ZoomableViewport>(viewportFinder).contentSize,
      const Size(1054, 300),
    );
    expect(
      _displayRect(tester, 'first.png').right,
      closeTo(viewport.right, 0.01),
    );
    rtlCommands.moveHorizontally(10000);
    await tester.pump();
    expect(
      _displayRect(tester, 'third.png').left,
      closeTo(viewport.left, 0.01),
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    commands.dispose();
  });

  testWidgets('changing comic direction preserves page and page fraction', (
    tester,
  ) async {
    final entries = List.generate(
      4,
      (index) => _entry('page-$index.png', width: 400, height: 600),
    );
    final controller = TransformationController();
    final commands = ZoomableViewportCommands();
    Widget comic(ComicLayoutDirection direction, int token) => _comic(
      entries: entries,
      controller: controller,
      commands: commands,
      loadSize: (_) async => null,
      layoutDirection: direction,
      currentIndex: 0,
      jumpToken: token,
    );
    await tester.pumpWidget(comic(ComicLayoutDirection.vertical, 0));
    await _flushLayout(tester);
    commands.moveVertically(-1100);
    await tester.pump();
    final oldPage = _displayRect(tester, 'page-2.png');
    final oldViewport = tester.getRect(find.byType(ZoomableViewport));
    final oldFraction = (oldViewport.center.dy - oldPage.top) / oldPage.height;
    await tester.pumpWidget(
      comic(ComicLayoutDirection.horizontalRightToLeft, 0),
    );
    await _flushLayout(tester);
    final nextPage = _displayRect(tester, 'page-2.png');
    final nextViewport = tester.getRect(find.byType(ZoomableViewport));
    final nextFraction =
        (nextViewport.center.dx - nextPage.left) / nextPage.width;
    expect(nextFraction, closeTo(oldFraction, 0.03));
    expect(nextPage.left, lessThan(nextViewport.right));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    commands.dispose();
  });

  testWidgets('five percent zoom virtualizes the actual visible pages', (
    tester,
  ) async {
    final entries = List.generate(
      70,
      (index) => _entry('page-$index.png', width: 400, height: 400),
    );
    final controller = TransformationController();
    final commands = ZoomableViewportCommands();
    await tester.pumpWidget(
      _comic(
        entries: entries,
        controller: controller,
        commands: commands,
        loadSize: (_) async => null,
      ),
    );
    await _flushLayout(tester);
    controller.value = Matrix4.identity()..scaleByDouble(0.05, 0.05, 0.05, 1);
    await tester.pump();
    commands.moveVertically(-1000);
    await tester.pump();
    expect(find.byKey(const ValueKey('page-50.png')), findsOneWidget);
    expect(find.byKey(const ValueKey('page-60.png')), findsOneWidget);
    expect(find.byType(Positioned).evaluate().length, lessThan(70));
    final rect = _displayRect(tester, 'page-50.png');
    expect(rect.width, closeTo(20, 0.01));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    commands.dispose();
  });

  testWidgets('late sizes above the reader preserve the current page anchor', (
    tester,
  ) async {
    final pending = Completer<Size?>();
    final entries = [
      _entry('unknown.png'),
      _entry('reading.png', width: 400, height: 800),
      _entry('after.png', width: 400, height: 800),
    ];
    final controller = TransformationController();
    final commands = ZoomableViewportCommands();
    await tester.pumpWidget(
      _comic(
        entries: entries,
        controller: controller,
        commands: commands,
        loadSize: (_) => pending.future,
      ),
    );
    await _flushLayout(tester);
    final oldTop = 400 / 0.7 + 2;
    commands.moveVertically(-(oldTop + 100));
    await tester.pump();
    pending.complete(const Size(400, 1000));
    await _flushLayout(tester);
    expect(controller.value.getTranslation().y, closeTo(-(1002 + 100), 0.01));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    commands.dispose();
  });

  testWidgets(
    'concurrent dimensions all survive and pages have a two pixel gap',
    (tester) async {
      final entries = [
        _entry('wide.png'),
        _entry('tall.png'),
        _entry('last.png'),
      ];
      final sizes = {
        for (final entry in entries) entry.file.path: Completer<Size?>(),
      };
      final controller = TransformationController();
      final commands = ZoomableViewportCommands();
      await tester.pumpWidget(
        _comic(
          entries: entries,
          controller: controller,
          commands: commands,
          loadSize: (path) => sizes[path]!.future,
        ),
      );
      await _flushLayout(tester);
      sizes['wide.png']!.complete(const Size(800, 200));
      await _flushLayout(tester);
      sizes['tall.png']!.complete(const Size(400, 800));
      sizes['last.png']!.complete(const Size(800, 400));
      await _flushLayout(tester);
      final viewport = tester.widget<ZoomableViewport>(
        find.byType(ZoomableViewport),
      );
      expect(viewport.contentSize, const Size(400, 1104));
      final first = tester.widget<Positioned>(
        find.byKey(const ValueKey('wide.png')),
      );
      final second = tester.widget<Positioned>(
        find.byKey(const ValueKey('tall.png')),
      );
      expect(first.height, 100);
      expect(second.height, 800);
      expect(second.top! - first.top! - first.height!, 2);
      expect(controller.value.getTranslation().y, closeTo(0, 0.01));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      commands.dispose();
    },
  );

  testWidgets(
    'comic navigation applies the latest jump without resetting through origin',
    (tester) async {
      final entries = [
        _entry('first.png', width: 400, height: 800),
        _entry('second.png', width: 400, height: 800),
        _entry('third.png', width: 400, height: 800),
      ];
      final controller = TransformationController();
      final commands = ZoomableViewportCommands();
      await tester.pumpWidget(
        _comic(
          entries: entries,
          controller: controller,
          commands: commands,
          loadSize: (_) async => null,
        ),
      );
      await _flushLayout(tester);

      await tester.pumpWidget(
        _comic(
          entries: entries,
          controller: controller,
          commands: commands,
          loadSize: (_) async => null,
          currentIndex: 2,
          jumpToken: 1,
        ),
      );
      await tester.pump();
      expect(controller.value.getTranslation().y, closeTo(-1604, 0.01));

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      commands.dispose();
    },
  );

  testWidgets(
    'comic scrolling crosses pages and stops at the whole strip boundary',
    (tester) async {
      final entries = [
        _entry('first.png', width: 400, height: 800),
        _entry('second.png', width: 400, height: 800),
      ];
      final controller = TransformationController();
      final commands = ZoomableViewportCommands();
      final boundaries = <VerticalScrollBoundary>[];
      final pages = <int>[];
      await tester.pumpWidget(
        _comic(
          entries: entries,
          controller: controller,
          commands: commands,
          loadSize: (_) async => null,
          onBoundary: boundaries.add,
          onPage: pages.add,
        ),
      );
      await _flushLayout(tester);
      commands.moveVertically(-820);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(controller.value.getTranslation().y, -820);
      expect(boundaries.last, VerticalScrollBoundary.none);
      expect(pages.last, 1);
      commands.moveVertically(-2000);
      expect(controller.value.getTranslation().y, -1302);
      expect(boundaries.last, VerticalScrollBoundary.end);
      commands.moveVertically(-2000);
      expect(controller.value.getTranslation().y, -1302);
      commands.moveVertically(2000);
      expect(controller.value.getTranslation().y, 0);
      expect(boundaries.last, VerticalScrollBoundary.start);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      commands.dispose();
    },
  );

  testWidgets('ultra long pages retain their true proportions', (tester) async {
    final controller = TransformationController();
    final commands = ZoomableViewportCommands();
    await tester.pumpWidget(
      _comic(
        entries: [_entry('long.png', width: 400, height: 20000)],
        controller: controller,
        commands: commands,
        loadSize: (_) async => null,
      ),
    );
    await _flushLayout(tester);
    final viewport = tester.widget<ZoomableViewport>(
      find.byType(ZoomableViewport),
    );
    expect(viewport.contentSize.height, 20000);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    commands.dispose();
  });

  testWidgets(
    'dimension loading uses one worker and nearby pages remain queued',
    (tester) async {
      final entries = List.generate(8, (index) => _entry('page-$index.png'));
      final pending = <String, Completer<Size?>>{};
      final controller = TransformationController();
      final commands = ZoomableViewportCommands();
      await tester.pumpWidget(
        _comic(
          entries: entries,
          controller: controller,
          commands: commands,
          loadSize: (path) => (pending[path] = Completer<Size?>()).future,
        ),
      );
      expect(pending.length, 1);
      pending[entries.first.file.path]!.complete(const Size(400, 800));
      await _flushLayout(tester);
      expect(pending.length, 2);
      await tester.pumpWidget(const SizedBox());
      for (final completion in pending.values) {
        if (!completion.isCompleted) completion.complete(null);
      }
      await tester.pump();
      controller.dispose();
      commands.dispose();
    },
  );

  testWidgets('comic pages report whether they are the current page', (
    tester,
  ) async {
    final entries = [
      _entry('first.png', width: 400, height: 200),
      _entry('second.png', width: 400, height: 200),
    ];
    final controller = TransformationController();
    final commands = ZoomableViewportCommands();
    final active = <String, bool>{};
    Widget comic({required int currentIndex, required int jumpToken}) => _comic(
      entries: entries,
      controller: controller,
      commands: commands,
      loadSize: (_) async => null,
      currentIndex: currentIndex,
      jumpToken: jumpToken,
      buildPage: (entry, isCurrent) {
        active[entry.file.path] = isCurrent;
        return const ColoredBox(color: Colors.blue);
      },
    );
    await tester.pumpWidget(comic(currentIndex: 1, jumpToken: 0));
    await _flushLayout(tester);
    expect(active, {'first.png': false, 'second.png': true});

    await tester.pumpWidget(comic(currentIndex: 0, jumpToken: 1));
    await _flushLayout(tester);
    expect(active, {'first.png': true, 'second.png': false});

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    commands.dispose();
  });

  testWidgets('a jump holds the selected page until the reader scrolls', (
    tester,
  ) async {
    final entries = [
      _entry('first.png', width: 400, height: 2000),
      _entry('second.png', width: 400, height: 100),
      _entry('last.png', width: 400, height: 100),
    ];
    final controller = TransformationController();
    final commands = ZoomableViewportCommands();
    final pages = <int>[];
    Widget comic({required int currentIndex, required int jumpToken}) => _comic(
      entries: entries,
      controller: controller,
      commands: commands,
      loadSize: (_) async => null,
      currentIndex: currentIndex,
      jumpToken: jumpToken,
      onPage: pages.add,
    );
    await tester.pumpWidget(comic(currentIndex: 0, jumpToken: 0));
    await _flushLayout(tester);
    await tester.pump(const Duration(milliseconds: 200));
    final beforeJump = pages.length;

    // The second page is so close to the end that its jump is clamped to the
    // strip end. The end-boundary heuristic must not steal the clicked page
    // before the reader scrolls.
    await tester.pumpWidget(comic(currentIndex: 1, jumpToken: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(pages.skip(beforeJump), isNot(contains(2)));

    commands.moveVertically(1);
    await tester.pump();
    commands.moveVertically(-1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(pages.last, 2);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    commands.dispose();
  });

  testWidgets('a short final vertical page becomes current at the strip end', (
    tester,
  ) async {
    final entries = [
      _entry('first.png', width: 400, height: 1000),
      _entry('second.png', width: 400, height: 300),
      _entry('last.png', width: 400, height: 100),
    ];
    final controller = TransformationController();
    final commands = ZoomableViewportCommands();
    final pages = <int>[];
    Widget comic({required int currentIndex, required int jumpToken}) => _comic(
      entries: entries,
      controller: controller,
      commands: commands,
      loadSize: (_) async => null,
      currentIndex: currentIndex,
      jumpToken: jumpToken,
      onPage: pages.add,
    );
    await tester.pumpWidget(comic(currentIndex: 0, jumpToken: 0));
    await _flushLayout(tester);
    final viewport = tester.getRect(find.byType(ZoomableViewport));
    commands.moveVertically(-10000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(pages.last, 2);

    await tester.pumpWidget(comic(currentIndex: 2, jumpToken: 1));
    await tester.pump();
    final last = _displayRect(tester, 'last.png');
    expect(last.bottom, closeTo(viewport.bottom, 0.01));
    expect(last.top, greaterThanOrEqualTo(viewport.top));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    commands.dispose();
  });

  testWidgets('horizontal comic jumps clamp to the strip bounds', (
    tester,
  ) async {
    final entries = [
      _entry('first.png', width: 400, height: 400),
      _entry('second.png', width: 400, height: 400),
      _entry('last.png', width: 100, height: 400),
    ];
    final controller = TransformationController();
    final commands = ZoomableViewportCommands();
    final pages = <int>[];
    Widget comic({
      required int currentIndex,
      required int jumpToken,
      ComicLayoutDirection direction =
          ComicLayoutDirection.horizontalLeftToRight,
    }) => _comic(
      entries: entries,
      controller: controller,
      commands: commands,
      loadSize: (_) async => null,
      layoutDirection: direction,
      currentIndex: currentIndex,
      jumpToken: jumpToken,
      onPage: pages.add,
    );
    await tester.pumpWidget(comic(currentIndex: 0, jumpToken: 0));
    await _flushLayout(tester);
    final viewport = tester.getRect(find.byType(ZoomableViewport));
    commands.moveHorizontally(-10000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(pages.last, 2);

    await tester.pumpWidget(comic(currentIndex: 2, jumpToken: 1));
    await tester.pump();
    var last = _displayRect(tester, 'last.png');
    expect(last.right, closeTo(viewport.right, 0.01));
    expect(last.left, greaterThanOrEqualTo(viewport.left));

    await tester.pumpWidget(
      comic(
        currentIndex: 0,
        jumpToken: 2,
        direction: ComicLayoutDirection.horizontalRightToLeft,
      ),
    );
    await _flushLayout(tester);
    commands.moveHorizontally(10000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(pages.last, 2);

    await tester.pumpWidget(
      comic(
        currentIndex: 2,
        jumpToken: 3,
        direction: ComicLayoutDirection.horizontalRightToLeft,
      ),
    );
    await tester.pump();
    last = _displayRect(tester, 'last.png');
    expect(last.left, closeTo(viewport.left, 0.01));
    expect(last.right, lessThanOrEqualTo(viewport.right));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    commands.dispose();
  });
}
