import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/components/app_text_input_scope.dart';
import 'package:shen_view/src/presentation/grid_overview.dart';
import 'package:shen_view/src/presentation/settings_page.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_bottom_bar.dart';
import 'package:shen_view/src/presentation/viewer_page.dart';

import 'support/settings_navigation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Windows editors retain native IME and canvas shortcuts',
    (tester) async {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1280, 800));
      await windowManager.show();
      await windowManager.focus();
      final root = await Directory.systemTemp.createTemp(
        'settings-native-ime-',
      );
      final first = await File('testdata/formats/format_static.webp')
          .copy('${root.path}/a.webp');
      await first.copy('${root.path}/b.webp');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await root.delete(recursive: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => AppTextInputScope(child: child!),
          home: ViewerPage(
            initialPath: first.path,
            initialSettings: const ViewerSettings(
              watchFolderChanges: false,
              // Canvas shortcuts are tested without the directory popup owning navigation.
              showDirectoryPanel: false,
            ),
            configStore: AppConfigStore(filePath: '${root.path}/config.json'),
          ),
        ),
      );
      Future<void> waitFor(bool Function() ready) async {
        for (var attempt = 0; attempt < 200; attempt++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('等待 Windows 输入或快捷键响应超时');
      }

      await waitFor(
        () =>
            find.byType(ViewerBottomBar).evaluate().isNotEmpty &&
            tester
                    .widget<ViewerBottomBar>(find.byType(ViewerBottomBar))
                    .controller
                    .entries
                    .length ==
                2,
      );
      final native = _WindowsInput();
      // Verify actual HWND associations rather than mocked Widget text input.
      await waitFor(
        () => !native.hasIme(native.window) && !native.hasIme(native.view),
      );
      await openViewerSettings(tester);
      await waitFor(() => find.byType(SettingsPage).evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      final search = find.descendant(
        of: find.byKey(const ValueKey('settings.search')),
        matching: find.byType(EditableText),
      );
      await tester.tap(search);
      await tester.pumpAndSettle();
      await waitFor(
        () => native.hasIme(native.window) && native.hasIme(native.view),
      );
      expect(
        native.hasIme(native.view),
        isTrue,
        reason: '搜索框获得焦点后，Flutter 原生窗口必须有可用输入法上下文',
      );
      native.rememberEditorContexts();
      // Send actual Win32 text messages through the engine, without replacing
      // the platform text-input connection with tester.enterText.
      native.text('缓存');
      await waitFor(
        () => tester.widget<EditableText>(search).controller.text == '缓存',
      );
      expect(tester.widget<EditableText>(search).focusNode.hasFocus, isTrue);
      expect(find.text('没有匹配的设置'), findsNothing);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await waitFor(
        () => !native.hasIme(native.window) && !native.hasIme(native.view),
      );
      // Windows/IME activation can re-associate contexts without a Dart focus
      // change. This deliberately recreates that native-side race.
      for (var attempt = 0; attempt < 3; attempt++) {
        native.reattachEditorContexts();
        native.activateImeContexts();
        await tester.pump(const Duration(milliseconds: 30));
        expect(native.hasIme(native.window), isFalse);
        expect(native.hasIme(native.view), isFalse);
      }
      final controller = tester
          .widget<ViewerBottomBar>(find.byType(ViewerBottomBar))
          .controller;
      native.key(0x27); // Right arrow still navigates on the canvas.
      await waitFor(() => controller.currentIndex == 1);
      native.key(
        0x47,
        imeProcessed: true,
      ); // A queued IME key must still open G.
      await waitFor(() => find.byType(GridOverview).evaluate().isNotEmpty);
      native.key(0x47);
      await waitFor(() => find.byType(GridOverview).evaluate().isEmpty);
      // A second visit must restore the same IME contexts, not stay disabled.
      await openViewerSettings(tester);
      await waitFor(() => find.byType(SettingsPage).evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      await tester.tap(search);
      await tester.pumpAndSettle();
      await waitFor(
        () => native.hasIme(native.window) && native.hasIme(native.view),
      );
      native.text('中文');
      await waitFor(
        () => tester.widget<EditableText>(search).controller.text == '中文',
      );
      final field = tester.widget<EditableText>(search);
      for (var attempt = 0; attempt < 8; attempt++) {
        field.focusNode.unfocus();
        FocusManager.instance.applyFocusChangesIfNeeded();
        await tester.pump();
        await waitFor(
          () => !native.hasIme(native.window) && !native.hasIme(native.view),
        );
        native.reattachEditorContexts();
        native.activateImeContexts();
        expect(native.hasIme(native.window), isFalse);
        expect(native.hasIme(native.view), isFalse);
        field.focusNode.requestFocus();
        await tester.pump();
        await waitFor(
          () => native.hasIme(native.window) && native.hasIme(native.view),
        );
        field.controller.clear();
        await tester.pump(const Duration(milliseconds: 100));
        native.text('中');
        await waitFor(() => field.controller.text == '中');
      }
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await waitFor(
        () => !native.hasIme(native.window) && !native.hasIme(native.view),
      );
      native.key(0x47, imeProcessed: true);
      await waitFor(() => find.byType(GridOverview).evaluate().isNotEmpty);
      native.key(0x47);
      await waitFor(() => find.byType(GridOverview).evaluate().isEmpty);
      expect(tester.takeException(), isNull);
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _WindowsInput {
  final _user = DynamicLibrary.open('user32.dll');
  final _imm = DynamicLibrary.open('imm32.dll');
  late Pointer<Void> _windowContext;
  late Pointer<Void> _viewContext;
  late final window = _findWindow();
  late final view = _user
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Uint32),
        Pointer<Void> Function(Pointer<Void>, int)
      >('GetWindow')(window, 5);
  late final _post = _user
      .lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, UintPtr, IntPtr),
        int Function(Pointer<Void>, int, int, int)
      >('PostMessageW');

  Pointer<Void> _findWindow() {
    // The user's viewer can also be open. Match this test process rather than
    // relying on whichever window Windows currently allows to be foreground.
    final kernel = DynamicLibrary.open('kernel32.dll');
    final heap = kernel
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'GetProcessHeap',
        )();
    final storage = kernel
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>, Uint32, UintPtr),
          Pointer<Void> Function(Pointer<Void>, int, int)
        >('HeapAlloc')(heap, 0, 4);
    if (storage == nullptr) throw StateError('无法分配窗口进程 ID 缓冲区');
    try {
      final getNext = _user
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Uint32),
            Pointer<Void> Function(Pointer<Void>, int)
          >('GetWindow');
      final getPid = _user
          .lookupFunction<
            Uint32 Function(Pointer<Void>, Pointer<Uint32>),
            int Function(Pointer<Void>, Pointer<Uint32>)
          >('GetWindowThreadProcessId');
      final visible = _user
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('IsWindowVisible');
      var candidate = _user
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>),
            Pointer<Void> Function(Pointer<Void>)
          >('GetTopWindow')(nullptr);
      while (candidate != nullptr) {
        getPid(candidate, storage.cast<Uint32>());
        if (storage.cast<Uint32>().value == pid && visible(candidate) != 0) {
          return candidate;
        }
        candidate = getNext(candidate, 2);
      }
      throw StateError('找不到当前原生测试进程的窗口');
    } finally {
      kernel.lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Pointer<Void>),
        int Function(Pointer<Void>, int, Pointer<Void>)
      >('HeapFree')(heap, 0, storage);
    }
  }

  Pointer<Void> _context(Pointer<Void> window) {
    final context = _imm
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>)
        >('ImmGetContext')(window);
    if (context == nullptr) return nullptr;
    _imm.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Void>)
    >('ImmReleaseContext')(window, context);
    return context;
  }

  bool hasIme(Pointer<Void> window) => _context(window) != nullptr;

  void rememberEditorContexts() {
    _windowContext = _context(window);
    _viewContext = _context(view);
    expect(_windowContext, isNot(nullptr));
    expect(_viewContext, isNot(nullptr));
  }

  void reattachEditorContexts() {
    final associate = _imm
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>, Pointer<Void>)
        >('ImmAssociateContext');
    associate(window, _windowContext);
    associate(view, _viewContext);
  }

  void activateImeContexts() {
    final send = _user
        .lookupFunction<
          IntPtr Function(Pointer<Void>, Uint32, UintPtr, IntPtr),
          int Function(Pointer<Void>, int, int, int)
        >('SendMessageW');
    // Native activation follows an IME/context switch independently of Dart.
    send(window, 0x0281, 1, 0xc000000f); // WM_IME_SETCONTEXT
    send(view, 0x0281, 1, 0xc000000f);
  }

  void text(String text) {
    for (final unit in text.codeUnits) {
      expect(_post(view, 0x0102, unit, 1), isNot(0)); // WM_CHAR
    }
  }

  void key(int key, {bool imeProcessed = false}) {
    final scan = _user
        .lookupFunction<
          Uint32 Function(Uint32, Uint32),
          int Function(int, int)
        >('MapVirtualKeyW')(key, 0);
    final flags = 1 | (scan << 16) | (key == 0x27 ? 1 << 24 : 0);
    final virtualKey = imeProcessed ? 0xe5 : key; // VK_PROCESSKEY
    expect(_post(view, 0x0100, virtualKey, flags), isNot(0));
    expect(_post(view, 0x0101, virtualKey, flags | (3 << 30)), isNot(0));
  }
}
