import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as imaging;
import 'package:path/path.dart' as paths;
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/external_open_service.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';
import 'package:shen_view/src/presentation/zoomable_viewport.dart';
import 'package:window_manager/window_manager.dart';

import 'support/style_review_fonts.dart';

const _capture = ValueKey('externalOpen.capture');
const _editor = '测试图像编辑器';
const _longEditor =
    'A very long application name for editing photographs and illustrations';

void main() {
  StyleReviewBinding();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late File image;
  final calls = <MethodCall>[];
  var applications = <Map<String, Object>>[];
  var failList = false;
  var failOpen = false;
  Completer<List<Map<String, Object>>>? pending;
  Completer<bool>? launch;

  setUp(() {
    Directory('build/external-open-tests').createSync(recursive: true);
    directory = Directory('build/external-open-tests')
        .createTempSync('input-')
        .absolute;
    final bytes = imaging.encodePng(imaging.Image(width: 32, height: 32));
    image = File('${directory.path}/图片 空格.png')..writeAsBytesSync(bytes);
    calls.clear();
    applications = [
      {'id': 'editor', 'name': _editor, 'icon': bytes},
      {'id': 'long-editor', 'name': _longEditor},
    ];
    failList = failOpen = false;
    pending = null;
    launch = null;
    messenger.setMockMethodCallHandler(ExternalOpenService.channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'applications') {
        if (failList) throw PlatformException(code: 'list_failed');
        return pending == null ? applications : await pending!.future;
      }
      if (failOpen) {
        throw PlatformException(code: 'open_failed', message: '无法启动程序');
      }
      return launch == null ? true : await launch!.future;
    });
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (
      call,
    ) async {
      if ([
        'isFullScreen',
        'isMaximized',
        'isAlwaysOnTop',
      ].contains(call.method)) {
        return false;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(ExternalOpenService.channel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
  });

  Future<void> pumpViewer(
    WidgetTester tester, {
    Size size = const Size(1100, 800),
    bool dark = true,
    bool empty = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    });
    if (Platform.environment['EXTERNAL_OPEN_REVIEW'] == '1') {
      await loadStyleReviewFonts(tester);
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: _capture,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark
              ? AppTheme.dark(platform: TargetPlatform.windows)
              : AppTheme.light(platform: TargetPlatform.windows),
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: ViewerPage(
            initialPath: empty
                ? (Directory('${directory.path}/empty')..createSync()).path
                : image.path,
            initialSettings: const ViewerSettings(
              showDirectoryPanel: false,
              watchFolderChanges: false,
            ),
            configStore: _MemoryConfigStore('${directory.path}/config.json'),
          ),
        ),
      ),
    );
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      final ready = empty
          ? i >= 5 && find.byType(CircularProgressIndicator).evaluate().isEmpty
          : find.byType(ZoomableViewport).evaluate().isNotEmpty;
      if (ready) break;
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> showMenu(WidgetTester tester) async {
    await tester.tapAt(
      const Offset(100, 160),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await tester.ensureVisible(find.text('用其他程序打开'));
    await tester.tap(find.text('用其他程序打开'));
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(600, 460), const Size(1100, 800)]) {
    for (final dark in [false, true]) {
      testWidgets(
        'external menu fits $size dark=$dark and opens the original file',
        (tester) async {
          await pumpViewer(tester, size: size, dark: dark);
          await showMenu(tester);
          expect(find.text(_editor), findsOneWidget);
          expect(find.text(_longEditor), findsOneWidget);
          expect(find.text('选择其他程序…'), findsOneWidget);
          final rows = [
            for (final label in [_editor, _longEditor, '选择其他程序…'])
              tester.getRect(
                find
                    .ancestor(
                      of: find.text(label),
                      matching: find.byType(MenuItemButton),
                    )
                    .first,
              ),
          ];
          for (final row in rows) {
            expect(row.left, greaterThanOrEqualTo(0));
            expect(row.right, lessThanOrEqualTo(size.width));
            expect(row.top, greaterThanOrEqualTo(0));
            expect(row.bottom, lessThanOrEqualTo(size.height));
            expect(row.height, greaterThanOrEqualTo(32));
          }
          expect(rows[0].left, closeTo(rows[2].left, 0.5));
          expect(rows[0].bottom, lessThanOrEqualTo(rows[1].top));
          expect(rows[2].top - rows[1].bottom, greaterThanOrEqualTo(8));
          expect(
            tester.widget<Text>(find.text(_longEditor)).overflow,
            TextOverflow.ellipsis,
          );
          if (Platform.environment['EXTERNAL_OPEN_REVIEW'] == '1') {
            await _save(
              tester,
              'build/external-open-review/${size.width.toInt()}-$dark.png',
            );
          }
          await tester.runAsync(() async {
            await tester.tap(find.text(_editor));
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 60));
          });
          await tester.pumpAndSettle();
          final opened = calls.where((call) => call.method == 'open').single;
          expect(opened.arguments, {
            'path': paths.normalize(image.absolute.path),
            'application': 'editor',
          });
          expect(find.text('用其他程序打开'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'empty association list still lets the user choose another application',
    (tester) async {
      applications = [];
      await pumpViewer(tester);
      await showMenu(tester);
      expect(find.text('没有关联的程序'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('选择其他程序…'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pumpAndSettle();
      expect(calls.last.method, 'choose');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('association query failure leaves the system picker available', (
    tester,
  ) async {
    failList = true;
    await pumpViewer(tester);
    await showMenu(tester);
    expect(find.text('无法读取可用程序'), findsOneWidget);
    expect(
      tester
          .widget<MenuItemButton>(
            find
                .ancestor(
                  of: find.text('选择其他程序…'),
                  matching: find.byType(MenuItemButton),
                )
                .first,
          )
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'application query does not block the context menu and late replies cannot reopen it',
    (tester) async {
      pending = Completer();
      await pumpViewer(tester);
      await showMenu(tester);
      expect(find.text('正在读取可用程序…'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      pending!.complete(applications);
      await tester.pumpAndSettle();
      expect(find.text(_editor), findsNothing);
      expect(find.text('用其他程序打开'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('launch failure displays a dismissible error notification', (
    tester,
  ) async {
    failOpen = true;
    await pumpViewer(tester);
    await showMenu(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text(_editor));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('用其他程序打开失败：'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'context menu works after opening an app and returning to the viewer',
    (tester) async {
      await pumpViewer(tester);
      final window = tester.state(find.byType(ViewerPage)) as WindowListener;
      for (var attempt = 0; attempt < 3; attempt++) {
        await showMenu(tester);
        expect(find.text(_editor), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.text(_editor));
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 60));
        });
        await tester.pumpAndSettle();
        window.onWindowBlur();
        await tester.pump(const Duration(milliseconds: 250));
        window.onWindowFocus();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(calls.where((call) => call.method == 'open').length, 3);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'clicking before hover opens the submenu does not close it later',
    (tester) async {
      await pumpViewer(tester);
      await tester.tapAt(
        const Offset(100, 160),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(900, 500));
      await mouse.moveTo(tester.getCenter(find.text('用其他程序打开')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('用其他程序打开'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text(_editor), findsOneWidget);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('returning before launch finishes restores the open-with entry', (
    tester,
  ) async {
    launch = Completer();
    await pumpViewer(tester);
    await showMenu(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text(_editor));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
    final window = tester.state(find.byType(ViewerPage)) as WindowListener;
    window.onWindowBlur();
    await tester.pump(const Duration(milliseconds: 250));
    window.onWindowFocus();
    await tester.pump();
    await tester.tapAt(const Offset(100, 160), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    final button = find
        .ancestor(
          of: find.text('用其他程序打开'),
          matching: find.byType(MenuItemButton),
        )
        .first;
    expect(tester.widget<MenuItemButton>(button).onPressed, isNull);
    launch!.complete(true);
    await tester.pumpAndSettle();
    expect(tester.widget<MenuItemButton>(button).onPressed, isNotNull);
    await tester.tap(find.text('用其他程序打开'));
    await tester.pumpAndSettle();
    expect(find.text(_editor), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a pending menu close cannot dismiss the menu opened on return', (
    tester,
  ) async {
    await pumpViewer(tester);
    await showMenu(tester);
    final item = tester.widget<MenuItemButton>(
      find
          .ancestor(
            of: find.text(_editor),
            matching: find.byType(MenuItemButton),
          )
          .first,
    );
    final canvas = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('viewer.content')),
    );
    final window = tester.state(find.byType(ViewerPage)) as WindowListener;
    // Keep the framework's asynchronous close pending across the focus handoff.
    await tester.runAsync(() async {
      item.onPressed!();
      window.onWindowBlur();
      window.onWindowFocus();
      canvas.onSecondaryTapUp!(
        TapUpDetails(
          globalPosition: const Offset(100, 160),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
    expect(find.text('用其他程序打开'), findsOneWidget);
    await tester.tap(find.text('用其他程序打开'));
    await tester.pumpAndSettle();
    expect(find.text(_editor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final primaryClick in [false, true]) {
    testWidgets(
      'a new mouse click recovers a lost release without blur, primary=$primaryClick',
      (tester) async {
        await pumpViewer(tester);
        final cancelled = <int>[];
        void recordCancel(PointerEvent event) {
          if (event is PointerCancelEvent) cancelled.add(event.pointer);
        }

        tester.binding.pointerRouter.addGlobalRoute(recordCancel);
        addTearDown(
          () => tester.binding.pointerRouter.removeGlobalRoute(recordCancel),
        );
        final oldMouse = await tester.startGesture(
          const Offset(100, 160),
          pointer: 77,
          kind: PointerDeviceKind.mouse,
        );
        await oldMouse.moveBy(const Offset(80, 40));
        await tester.pump();
        if (primaryClick) {
          await tester.tapAt(
            const Offset(240, 240),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();
        }
        await showMenu(tester);
        expect(cancelled, contains(77));
        expect(find.text(_editor), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('button-free mouse movement clears a lost release', (
    tester,
  ) async {
    await pumpViewer(tester);
    final cancelled = <int>[];
    void recordCancel(PointerEvent event) {
      if (event is PointerCancelEvent) cancelled.add(event.pointer);
    }

    tester.binding.pointerRouter.addGlobalRoute(recordCancel);
    addTearDown(
      () => tester.binding.pointerRouter.removeGlobalRoute(recordCancel),
    );
    final oldMouse = await tester.startGesture(
      const Offset(100, 160),
      pointer: 77,
      kind: PointerDeviceKind.mouse,
    );
    await oldMouse.moveBy(const Offset(80, 40));
    final hover = await tester.createGesture(
      pointer: 78,
      kind: PointerDeviceKind.mouse,
    );
    await hover.moveTo(const Offset(240, 240));
    await tester.pump();
    expect(cancelled, contains(77));
    await showMenu(tester);
    expect(find.text(_editor), findsOneWidget);
  });

  testWidgets('a second touch keeps the first finger active for pinch zoom', (
    tester,
  ) async {
    await pumpViewer(tester);
    final cancelled = <int>[];
    void recordCancel(PointerEvent event) {
      if (event is PointerCancelEvent) cancelled.add(event.pointer);
    }

    tester.binding.pointerRouter.addGlobalRoute(recordCancel);
    addTearDown(
      () => tester.binding.pointerRouter.removeGlobalRoute(recordCancel),
    );
    final first = await tester.startGesture(
      const Offset(100, 160),
      pointer: 77,
    );
    final second = await tester.startGesture(
      const Offset(220, 160),
      pointer: 78,
    );
    await first.moveBy(const Offset(-40, 0));
    await second.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(cancelled, isEmpty);
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final lifecycleBlur in [false, true]) {
    testWidgets(
      'right click recovers after a lost mouse release, lifecycle=$lifecycleBlur',
      (tester) async {
        await pumpViewer(tester);
        final mouse = await tester.startGesture(
          const Offset(100, 160),
          pointer: 77,
          kind: PointerDeviceKind.mouse,
        );
        await mouse.moveBy(const Offset(80, 40));
        await tester.pump();
        final state = tester.state(find.byType(ViewerPage));
        if (lifecycleBlur) {
          final observer = state as WidgetsBindingObserver;
          observer.didChangeAppLifecycleState(AppLifecycleState.inactive);
          await tester.pump();
          observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
        } else {
          final window = state as WindowListener;
          window.onWindowBlur();
          await tester.pump();
          window.onWindowFocus();
        }
        await tester.pump();
        // Windows may deliver no mouse-up when the other application takes focus.
        // A new right click must work even though the old pointer never ended.
        await showMenu(tester);
        expect(find.text(_editor), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.text(_editor));
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 60));
        });
        await tester.pumpAndSettle();
        expect(calls.where((call) => call.method == 'open'), hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('empty viewer keeps the external-open entry disabled', (
    tester,
  ) async {
    await pumpViewer(tester, empty: true);
    await tester.tap(
      find.byIcon(FluentIcons.image_24_regular),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    final button = find
        .ancestor(
          of: find.text('用其他程序打开'),
          matching: find.byType(MenuItemButton),
        )
        .first;
    expect(tester.widget<MenuItemButton>(button).onPressed, isNull);
    expect(calls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _save(WidgetTester tester, String path) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

class _MemoryConfigStore extends AppConfigStore {
  _MemoryConfigStore(String path) : super(filePath: path);
  Map<String, dynamic> _data = {};

  @override
  Future<Map<String, dynamic>> read() async => Map.of(_data);

  @override
  Future<Map<String, dynamic>> readOrEmpty() => read();

  @override
  Future<void> write(Map<String, dynamic> config) async {
    _data = config;
  }

  @override
  Future<void> update(
    Map<String, dynamic> Function(Map<String, dynamic>) transform,
  ) async {
    _data = transform(Map.of(_data));
  }
}
