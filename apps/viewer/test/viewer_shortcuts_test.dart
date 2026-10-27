import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/presentation/viewer_shortcuts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every command has an unambiguous default on each platform', () {
    const bindings = ViewerShortcutBindings.defaults;
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      final labels = ViewerCommand.values
          .map((command) => bindings.label(command, platform: platform))
          .toList();
      expect(
        labels.toSet().length,
        labels.length,
        reason: '$platform default collisions',
      );
    }
  });

  testWidgets('extra modifiers never activate simpler shortcuts', (
    tester,
  ) async {
    const bindings = ViewerShortcutBindings.defaults;
    Future<ViewerCommand?> resolve(
      LogicalKeyboardKey key,
      List<LogicalKeyboardKey> modifiers,
    ) async {
      for (final modifier in modifiers) {
        await tester.sendKeyDownEvent(modifier);
      }
      await tester.sendKeyDownEvent(key);
      final command = bindings.commandFor(
        KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyG,
          logicalKey: key,
          timeStamp: Duration.zero,
        ),
        platform: TargetPlatform.windows,
      );
      await tester.sendKeyUpEvent(key);
      for (final modifier in modifiers.reversed) {
        await tester.sendKeyUpEvent(modifier);
      }
      return command;
    }

    expect(
      await resolve(LogicalKeyboardKey.keyG, []),
      ViewerCommand.toggleGrid,
    );
    expect(
      await resolve(LogicalKeyboardKey.keyG, [LogicalKeyboardKey.controlLeft]),
      isNull,
    );
    expect(
      await resolve(LogicalKeyboardKey.keyT, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ]),
      ViewerCommand.alwaysOnTop,
    );
    expect(
      await resolve(LogicalKeyboardKey.keyP, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ]),
      isNull,
    );
    expect(
      await resolve(LogicalKeyboardKey.keyC, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.altLeft,
      ]),
      isNull,
    );
    expect(
      await resolve(LogicalKeyboardKey.equal, [LogicalKeyboardKey.shiftLeft]),
      ViewerCommand.zoomIn,
    );
    expect(
      await resolve(LogicalKeyboardKey.numpadAdd, []),
      ViewerCommand.zoomIn,
    );
    expect(
      await resolve(LogicalKeyboardKey.numpadSubtract, []),
      ViewerCommand.zoomOut,
    );
  });

  testWidgets('Mac uses Command, with native fullscreen and trash aliases', (
    tester,
  ) async {
    const bindings = ViewerShortcutBindings.defaults;
    ViewerCommand? resolve(LogicalKeyboardKey key, TargetPlatform platform) =>
        bindings.commandFor(
          KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.keyF,
            logicalKey: key,
            timeStamp: Duration.zero,
          ),
          platform: platform,
        );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    expect(
      resolve(LogicalKeyboardKey.keyO, TargetPlatform.macOS),
      ViewerCommand.openFile,
    );
    expect(resolve(LogicalKeyboardKey.keyO, TargetPlatform.windows), isNull);
    expect(
      resolve(LogicalKeyboardKey.backspace, TargetPlatform.macOS),
      ViewerCommand.deleteFile,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    expect(
      resolve(LogicalKeyboardKey.keyF, TargetPlatform.macOS),
      ViewerCommand.fullscreen,
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    expect(resolve(LogicalKeyboardKey.keyO, TargetPlatform.macOS), isNull);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(
      resolve(LogicalKeyboardKey.f11, TargetPlatform.macOS),
      ViewerCommand.fullscreen,
    );
    expect(
      bindings.label(ViewerCommand.fullscreen, platform: TargetPlatform.macOS),
      '⌃+⌘+F',
    );
    expect(
      bindings.label(ViewerCommand.deleteFile, platform: TargetPlatform.macOS),
      '⌘+⌫',
    );
  });
  test('default labels are suitable for tooltips', () {
    const shortcuts = ViewerShortcutBindings.defaults;

    expect(shortcuts.print.displayLabel(), 'Ctrl+P');
    expect(shortcuts.toggleThumbnails.displayLabel(), 'T');
    expect(shortcuts.fullscreen.displayLabel(), 'F11');
    expect(shortcuts.borderless.displayLabel(), 'Ctrl+Shift+F');
  });

  test('custom bindings produce updated labels', () {
    const custom = ViewerShortcutBindings(
      print: ViewerShortcutBinding(
        key: LogicalKeyboardKey.keyB,
        control: true,
        shift: true,
      ),
    );

    expect(custom.print.displayLabel(), 'Ctrl+Shift+B');
  });
}
