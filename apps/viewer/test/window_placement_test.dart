import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/window_placement_controller.dart';
import 'package:shen_view/src/application/window_placement_store.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppConfigStore config;
  late WindowPlacementStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('viewer-placement-');
    config = AppConfigStore(filePath: '${root.path}/config.json');
    store = WindowPlacementStore(config);
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'geometry follows work areas, minimum size and negative monitor origins',
    () {
      const screens = [
        WindowWorkArea(0, 0, 1920, 1040),
        WindowWorkArea(-1600, 0, 1600, 860),
      ];
      final secondary = _placement(
        -1500,
        40,
        900,
        700,
        1,
      ).fitToWorkAreas(screens);
      expect(
        [secondary.x, secondary.y, secondary.width, secondary.height],
        [-1500, 40, 900, 700],
      );
      final removed = _placement(
        4000,
        -300,
        3000,
        2000,
        1,
      ).fitToWorkAreas(screens);
      expect(
        [removed.x, removed.y, removed.width, removed.height],
        [0, 0, 1920, 1040],
      );
      final small = _placement(1900, 1000, 300, 200, 1).fitToWorkAreas(screens);
      expect(
        [small.x, small.y, small.width, small.height],
        [1320, 580, 600, 460],
      );
      final tinyScreen = _placement(
        -20,
        -20,
        1280,
        800,
        1,
      ).fitToWorkAreas([const WindowWorkArea(0, 0, 500, 400)]);
      expect(
        [tinyScreen.x, tinyScreen.y, tinyScreen.width, tinyScreen.height],
        [0, 0, 600, 460],
      );
    },
  );

  test(
    'invalid geometry falls back without accepting non-finite coordinates',
    () {
      final valid = _placement(20, 30, 800, 600, 1).toJson();
      expect(WindowPlacement.fromJson(valid)?.width, 800);
      for (final edit in [
        <String, dynamic>{'x': double.nan},
        {'height': 0},
        {'width': '800'},
        {'updatedAt': null},
        {'source': null},
        {'scaleFactor': 0},
      ]) {
        expect(WindowPlacement.fromJson({...valid, ...edit}), isNull);
      }
    },
  );

  test(
    'mixed-DPI monitors preserve logical size and physical screen position',
    () {
      const saved = WindowPlacement(
        x: 1050,
        y: 30,
        width: 900,
        height: 700,
        updatedAt: 1,
        source: 'old-200-percent',
        scaleFactor: 2,
      );
      final fitted = saved.fitToWorkAreas([
        const WindowWorkArea(0, 0, 1920, 1040),
        const WindowWorkArea(1280, 0, 1706, 960, scaleFactor: 1.5),
      ]);
      expect(
        [fitted.x, fitted.y, fitted.width, fitted.height, fitted.scaleFactor],
        [1400, 40, 900, 700, 1.5],
      );
    },
  );

  test('late writes from old windows cannot overwrite newer geometry or other settings', () async {
    await const ViewerSettings().save(store: config);
    await config.update((value) => {...value, 'unrelated': 42});
    final settingsBefore = await ViewerSettings.load(store: config);
    await store.save(_placement(100, 80, 900, 650, 20));
    await store.save(_placement(20, 30, 700, 500, 10));
    await settingsBefore
        .copyWith(directoryPanelWidth: 300)
        .save(store: config, previous: settingsBefore);
    expect((await store.load())?.width, 900);
    expect((await config.read())['unrelated'], 42);
    expect((await ViewerSettings.load(store: config)).directoryPanelWidth, 300);
  });

  group('native event lifecycle', () {
    const channel = MethodChannel('window_manager');
    late Rect bounds;
    late bool maximized;
    late bool minimized;
    late bool fullscreen;
    Completer<void>? boundsGate;
    Completer<void>? boundsQuery;
    final controllers = <WindowPlacementController>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    setUp(() {
      bounds = const Rect.fromLTWH(50, 70, 1000, 700);
      maximized = minimized = fullscreen = false;
      boundsGate = null;
      boundsQuery = null;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'getBounds':
            if (boundsQuery case final query? when !query.isCompleted) {
              query.complete();
            }
            await boundsGate?.future;
            return {
              'x': bounds.left,
              'y': bounds.top,
              'width': bounds.width,
              'height': bounds.height,
            };
          case 'setBounds':
            final args = call.arguments as Map;
            bounds = Rect.fromLTWH(
              args['x'] as double,
              args['y'] as double,
              args['width'] as double,
              args['height'] as double,
            );
            return null;
          case 'isMaximized':
            return maximized;
          case 'isMinimized':
            return minimized;
          case 'isFullScreen':
            return fullscreen;
        }
        throw StateError('Unexpected method ${call.method}');
      });
    });
    tearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
      controllers.clear();
      messenger.setMockMethodCallHandler(channel, null);
    });
    WindowPlacementController create() {
      final controller = WindowPlacementController(
        store,
        coordinateScale: () => 1,
        loadWorkAreas: () async => [const WindowWorkArea(0, 0, 1920, 1040)],
      );
      controllers.add(controller);
      return controller;
    }

    test('restore happens before recording and startup/unchanged close do not write', () async {
      await store.save(_placement(1800, 900, 900, 700, 7));
      final controller = create();
      await controller.restore();
      expect(bounds, const Rect.fromLTWH(1020, 340, 900, 700));
      await controller.start();
      controller.onWindowMoved();
      await controller.flush();
      expect((await store.load())?.updatedAt, 7);
      expect((await store.load())?.x, 1800);
    });

    test('restore converts target-monitor coordinates before moving from the primary monitor', () async {
      await store.save(
        const WindowPlacement(
          x: 1400,
          y: 40,
          width: 900,
          height: 700,
          updatedAt: 1,
          source: 'secondary',
          scaleFactor: 1.5,
        ),
      );
      final controller = WindowPlacementController(
        store,
        coordinateScale: () => 1,
        loadWorkAreas: () async => [
          const WindowWorkArea(0, 0, 1920, 1040),
          const WindowWorkArea(1280, 0, 1706, 960, scaleFactor: 1.5),
        ],
      );
      controllers.add(controller);
      await controller.restore();
      expect(bounds, const Rect.fromLTWH(2100, 60, 1350, 1050));
    });

    test(
      'closing an older untouched window preserves the last adjusted window',
      () async {
        final older = create();
        await older.start();
        final newer = create();
        await newer.start();
        bounds = const Rect.fromLTWH(140, 180, 1100, 720);
        newer.onWindowResized();
        await newer.flush();
        final saved = (await store.load())!;
        bounds = const Rect.fromLTWH(50, 70, 1000, 700);
        older.onWindowMoved();
        await older.flush();
        expect((await store.load())?.toJson(), saved.toJson());
      },
    );

    test(
      'close cannot re-date an in-flight old drag after another window writes',
      () async {
        final older = create();
        await older.start();
        bounds = const Rect.fromLTWH(300, 100, 800, 600);
        boundsGate = Completer<void>();
        boundsQuery = Completer<void>();
        older.onWindowMoved();
        await boundsQuery!.future;
        final newer = _placement(
          400,
          200,
          1000,
          700,
          DateTime.now().microsecondsSinceEpoch + 1,
        );
        await store.save(newer);
        final closing = older.flush();
        boundsGate!.complete();
        await closing;
        expect((await store.load())?.toJson(), newer.toJson());
      },
    );

    test('flush saves a final drag while max/min/fullscreen never replace normal bounds', () async {
      final controller = create();
      await controller.start();
      bounds = const Rect.fromLTWH(250, 90, 800, 600);
      controller.didChangeMetrics();
      controller.onWindowMove();
      await controller.flush();
      final saved = (await store.load())!;
      expect(
        [saved.x, saved.y, saved.width, saved.height],
        [250, 90, 800, 600],
      );
      for (var index = 0; index < 3; index++) {
        maximized = index == 0;
        minimized = index == 1;
        fullscreen = index == 2;
        bounds = const Rect.fromLTWH(-32000, -32000, 1920, 1080);
        controller.onWindowResize();
        await controller.flush();
        expect((await store.load())?.toJson(), saved.toJson());
      }
    });
  });
}

WindowPlacement _placement(
  double x,
  double y,
  double width,
  double height,
  int stamp,
) => WindowPlacement(
  x: x,
  y: y,
  width: width,
  height: height,
  updatedAt: stamp,
  source: 'test',
);
