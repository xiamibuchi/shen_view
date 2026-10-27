import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/presentation/components/app_text_input_scope.dart';

void main() {
  testWidgets(
    'Windows IME follows editable focus without interrupting composition',
    (tester) async {
      const channel = MethodChannel('shenview/text_input');
      final changes = <bool>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expectSync(call.method, 'setEnabled');
        changes.add(call.arguments as bool);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final editor = FocusNode();
      final canvas = FocusNode();
      final readOnly = FocusNode();
      final controller = TextEditingController();
      addTearDown(editor.dispose);
      addTearDown(canvas.dispose);
      addTearDown(readOnly.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        AppTextInputScope(
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  TextField(focusNode: editor, controller: controller),
                  TextField(focusNode: readOnly, readOnly: true),
                  Focus(focusNode: canvas, child: const SizedBox()),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(changes, isNotEmpty);
      expect(changes.every((enabled) => !enabled), isTrue);
      editor.requestFocus();
      await tester.pumpAndSettle();
      expect(changes.last, isTrue);
      final beforeComposition = changes.length;
      expect(focusedTextEditor?.controller, same(controller));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'zhong',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 0, end: 5),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.value.composing, const TextRange(start: 0, end: 5));
      expect(changes.length, beforeComposition);
      canvas.requestFocus();
      FocusManager.instance.applyFocusChangesIfNeeded();
      await tester.idle();
      expect(changes.last, isFalse, reason: '失去编辑焦点后不能等待下一帧才关闭输入法');
      await tester.pumpAndSettle();
      expect(changes.last, isFalse);
      expect(focusedTextEditor, isNull);
      final beforeReadOnly = changes.length;
      readOnly.requestFocus();
      await tester.pumpAndSettle();
      expect(changes.last, isFalse);
      expect(changes.length, greaterThan(beforeReadOnly));
      editor.requestFocus();
      await tester.pumpAndSettle();
      expect(changes.last, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    skip: !Platform.isWindows,
  );

  testWidgets(
    'late platform input attachment cannot enable IME after canvas refocus',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('shenview/text_input');
      final changes = <bool>[];
      final attach = Completer<void>();
      var holdShow = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        changes.add(call.arguments as bool);
        return null;
      });
      messenger.setMockMethodCallHandler(SystemChannels.textInput, (
        call,
      ) async {
        if (holdShow && call.method == 'TextInput.show') await attach.future;
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        tester.testTextInput.register();
      });
      final editor = FocusNode();
      final canvas = FocusNode();
      addTearDown(editor.dispose);
      addTearDown(canvas.dispose);
      await tester.pumpWidget(
        AppTextInputScope(
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  TextField(focusNode: editor),
                  Focus(focusNode: canvas, child: const SizedBox()),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      holdShow = true;
      editor.requestFocus();
      await tester.pump();
      await tester.idle();
      expect(changes.every((enabled) => !enabled), isTrue);
      canvas.requestFocus();
      FocusManager.instance.applyFocusChangesIfNeeded();
      await tester.idle();
      expect(changes.last, isFalse);
      attach.complete();
      await tester.pumpAndSettle();
      expect(changes.every((enabled) => !enabled), isTrue);
      holdShow = false;
      editor.requestFocus();
      await tester.pumpAndSettle();
      expect(changes.last, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    skip: !Platform.isWindows,
  );
}
