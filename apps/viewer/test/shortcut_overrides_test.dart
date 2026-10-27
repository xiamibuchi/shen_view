import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/domain/viewer_shortcuts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const win = TargetPlatform.windows;
  const mac = TargetPlatform.macOS;
  const chosen = ViewerShortcutBinding(
    key: LogicalKeyboardKey.keyB,
    control: true,
    shift: true,
  );
  test('concurrent edits replace a binding atomically', () async {
    final directory = await Directory.systemTemp.createTemp('shortcut-atomic-');
    addTearDown(() => directory.delete(recursive: true));
    final store = AppConfigStore(filePath: '${directory.path}/config.json');
    const initial = ViewerSettings(
      shortcutOverrides: {'windows.rotate': chosen},
    );
    await initial.save(store: store);
    await initial
        .copyWith(
          shortcutOverrides: {
            'windows.rotate': const ViewerShortcutBinding(
              key: LogicalKeyboardKey.keyX,
              control: true,
              shift: true,
            ),
          },
        )
        .save(store: store, previous: initial);
    const last = ViewerShortcutBinding(
      key: LogicalKeyboardKey.keyB,
      control: true,
      shift: true,
      alt: true,
    );
    await initial
        .copyWith(shortcutOverrides: {'windows.rotate': last})
        .save(store: store, previous: initial);
    expect(
      (await ViewerSettings.load(store: store))
          .shortcutOverrides['windows.rotate'],
      last,
    );
  });

  test('conflicts include default aliases and ignore the edited command', () {
    const bindings = ViewerShortcutBindings.defaults;
    expect(
      bindings.conflict(
        ViewerCommand.rotate,
        const ViewerShortcutBinding(key: LogicalKeyboardKey.f11),
        mac,
      ),
      ViewerCommand.fullscreen,
    );
    expect(
      bindings.conflict(
        ViewerCommand.rotate,
        const ViewerShortcutBinding(key: LogicalKeyboardKey.equal, shift: true),
        win,
      ),
      ViewerCommand.zoomIn,
    );
    expect(
      bindings.conflict(
        ViewerCommand.rotate,
        const ViewerShortcutBinding(key: LogicalKeyboardKey.arrowLeft),
        win,
      ),
      ViewerCommand.previousImage,
    );
    expect(
      bindings.conflict(
        ViewerCommand.rotate,
        const ViewerShortcutBinding(key: LogicalKeyboardKey.keyR),
        win,
      ),
      isNull,
    );
    expect(
      bindings.conflict(
        ViewerCommand.rotate,
        ViewerShortcutBindings.unassigned,
        win,
      ),
      isNull,
    );
  });

  test('reserved keys preserve controls and operating system commands', () {
    for (final key in [
      LogicalKeyboardKey.escape,
      LogicalKeyboardKey.tab,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.controlLeft,
    ]) {
      expect(
        ViewerShortcutBindings.isReserved(ViewerShortcutBinding(key: key), win),
        isTrue,
      );
    }
    expect(
      ViewerShortcutBindings.isReserved(
        const ViewerShortcutBinding(key: LogicalKeyboardKey.f4, alt: true),
        win,
      ),
      isTrue,
    );
    expect(
      ViewerShortcutBindings.isReserved(
        const ViewerShortcutBinding(
          key: LogicalKeyboardKey.keyQ,
          control: true,
        ),
        mac,
      ),
      isTrue,
    );
    expect(ViewerShortcutBindings.isReserved(chosen, mac), isFalse);
    expect(
      ViewerShortcutBindings.isReserved(ViewerShortcutBindings.unassigned, mac),
      isFalse,
    );
  });

  testWidgets(
    'edits replace old keys and aliases only on the selected platform',
    (tester) async {
      final bindings = ViewerShortcutBindings.defaults.withOverrides({
        ViewerShortcutBindings.overrideKey(win, ViewerCommand.rotate): chosen,
        ViewerShortcutBindings.overrideKey(win, ViewerCommand.zoomIn):
            ViewerShortcutBindings.unassigned,
        ViewerShortcutBindings.overrideKey(mac, ViewerCommand.fullscreen):
            chosen,
      });
      ViewerCommand? resolve(LogicalKeyboardKey key, TargetPlatform platform) =>
          bindings.commandFor(
            KeyDownEvent(
              physicalKey: PhysicalKeyboardKey.keyB,
              logicalKey: key,
              timeStamp: Duration.zero,
            ),
            platform: platform,
          );
      expect(resolve(LogicalKeyboardKey.keyR, win), isNull);
      expect(resolve(LogicalKeyboardKey.keyR, mac), ViewerCommand.rotate);
      expect(resolve(LogicalKeyboardKey.equal, win), isNull);
      expect(resolve(LogicalKeyboardKey.numpadAdd, win), isNull);
      expect(resolve(LogicalKeyboardKey.f11, mac), isNull);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(resolve(LogicalKeyboardKey.keyB, win), ViewerCommand.rotate);
      expect(resolve(LogicalKeyboardKey.keyB, mac), isNull);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(resolve(LogicalKeyboardKey.keyB, mac), ViewerCommand.fullscreen);
      expect(
        bindings.label(ViewerCommand.fullscreen, platform: mac),
        '⌘+Shift+B',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    },
  );

  test(
    'corrupt, reserved, unknown and conflicting overrides fall back safely',
    () {
      final values = {
        'windows.rotate': const ViewerShortcutBinding(
          key: LogicalKeyboardKey.keyP,
          control: true,
        ).toJson(),
        'windows.flip': const ViewerShortcutBinding(
          key: LogicalKeyboardKey.escape,
        ).toJson(),
        'windows.toggleInfo': {'key': -999},
        'windows.unknown': chosen.toJson(),
        'unknown.rotate': chosen.toJson(),
        'macOS.rotate': chosen.toJson(),
        'windows.zoomIn': ViewerShortcutBindings.unassigned.toJson(),
      };
      final overrides = ViewerShortcutBindings.readOverrides(values);
      expect(
        overrides.keys,
        unorderedEquals(['macOS.rotate', 'windows.zoomIn']),
      );
      expect(overrides['windows.zoomIn']!.isAssigned, isFalse);
      expect(overrides['macOS.rotate'], chosen);
    },
  );

  test(
    'platform bindings and cleared keys survive restart and reset',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'shortcut-settings-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = AppConfigStore(filePath: '${directory.path}/config.json');
      final settings = const ViewerSettings(autoHdr: false).copyWith(
        shortcutOverrides: {
          'windows.rotate': chosen,
          'macOS.rotate': chosen,
          'windows.zoomIn': ViewerShortcutBindings.unassigned,
        },
      );
      await settings.save(store: store);
      final loaded = await ViewerSettings.load(store: store);
      expect(loaded, settings);
      expect(loaded.hashCode, settings.hashCode);
      await loaded
          .copyWith(shortcutOverrides: const {})
          .save(store: store, previous: loaded);
      final reset = await ViewerSettings.load(store: store);
      expect(reset.shortcutOverrides, isEmpty);
      expect(reset.autoHdr, isFalse);
    },
  );

  test(
    'independent windows merge edits to different shortcut commands',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'shortcut-merge-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = AppConfigStore(filePath: '${directory.path}/config.json');
      const initial = ViewerSettings();
      await initial.save(store: store);
      await initial
          .copyWith(shortcutOverrides: {'windows.rotate': chosen})
          .save(store: store, previous: initial);
      await initial
          .copyWith(
            shortcutOverrides: {
              'windows.flip': const ViewerShortcutBinding(
                key: LogicalKeyboardKey.keyY,
                control: true,
                shift: true,
              ),
            },
          )
          .save(store: store, previous: initial);
      expect(
        (await ViewerSettings.load(store: store)).shortcutOverrides.keys,
        unorderedEquals(['windows.rotate', 'windows.flip']),
      );
    },
  );
}
