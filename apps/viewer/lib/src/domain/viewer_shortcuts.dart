import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

enum ViewerCommand {
  openFile,
  openFolder,
  copyFile,
  deleteFile,
  rename,
  saveOriginal,
  zoomIn,
  zoomOut,
  actualSize,
  autoFit,
  fitWidth,
  fitHeight,
  rotate,
  flip,
  toggleInfo,
  toggleDirectory,
  settings,
  autoPlay,
  stopAutoPlay,
  firstImage,
  lastImage,
  pageUp,
  pageDown,
  home,
  end,
  previousChapter,
  nextChapter,
  singlePage,
  doublePage,
  longImage,
  comic,
  search,
  previousFrame,
  nextFrame,
  reveal,
  copyPath,
  lockZoom,
  alwaysOnTop,
  parentFolder,
  print,
  toggleThumbnails,
  toggleGrid,
  colorPicker,
  fullscreen,
  borderless,
  newWindow,
  reload,
  previousImage,
  nextImage,
  previousSingleImage,
  nextSingleImage,
  toggleAnimation,
}

/// A persisted binding shared by key handling, menus and tooltips.
class ViewerShortcutBinding {
  const ViewerShortcutBinding({
    required this.key,
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
    this.physicalControl = false,
  });

  final LogicalKeyboardKey key;
  final bool control;
  final bool shift;
  final bool alt;
  final bool meta;
  final bool physicalControl;

  bool get isAssigned => key.keyId != 0;

  factory ViewerShortcutBinding.fromEvent(
    KeyEvent event,
    TargetPlatform platform,
  ) {
    final keyboard = HardwareKeyboard.instance;
    final mac = platform == TargetPlatform.macOS;
    return ViewerShortcutBinding(
      key: event.logicalKey,
      control: mac ? keyboard.isMetaPressed : keyboard.isControlPressed,
      physicalControl: mac && keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
      meta: !mac && keyboard.isMetaPressed,
    );
  }

  Map<String, Object> toJson() => {
    'key': key.keyId,
    'control': control,
    'shift': shift,
    'alt': alt,
    'meta': meta,
    'physicalControl': physicalControl,
  };

  static ViewerShortcutBinding? fromJson(Object? value) {
    if (value is! Map || value['key'] is! int) return null;
    final key = value['key'] == 0
        ? const LogicalKeyboardKey(0)
        : LogicalKeyboardKey.findKeyByKeyId(value['key'] as int);
    if (key == null) return null;
    return ViewerShortcutBinding(
      key: key,
      control: value['control'] == true,
      shift: value['shift'] == true,
      alt: value['alt'] == true,
      meta: value['meta'] == true,
      physicalControl: value['physicalControl'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ViewerShortcutBinding &&
      key == other.key &&
      control == other.control &&
      shift == other.shift &&
      alt == other.alt &&
      meta == other.meta &&
      physicalControl == other.physicalControl;

  @override
  int get hashCode =>
      Object.hash(key, control, shift, alt, meta, physicalControl);

  String signature(TargetPlatform platform) =>
      '${key.keyId}:${physicalControl || (control && platform != TargetPlatform.macOS)}:'
      '${meta || (control && platform == TargetPlatform.macOS)}:$shift:$alt';

  bool matches(KeyEvent event, {TargetPlatform? platform}) {
    if (!isAssigned) return false;
    if (event.logicalKey != key) return false;
    final keyboard = HardwareKeyboard.instance;
    final mac = (platform ?? defaultTargetPlatform) == TargetPlatform.macOS;
    return keyboard.isControlPressed ==
            (physicalControl || (control && !mac)) &&
        keyboard.isMetaPressed == (meta || (control && mac)) &&
        keyboard.isShiftPressed == shift &&
        keyboard.isAltPressed == alt;
  }

  String displayLabel({TargetPlatform platform = TargetPlatform.windows}) {
    if (!isAssigned) return '—';
    final modifiers = <String>[];
    if (physicalControl) {
      modifiers.add(platform == TargetPlatform.macOS ? '⌃' : 'Ctrl');
    }
    if (control) modifiers.add(platform == TargetPlatform.macOS ? '⌘' : 'Ctrl');
    if (shift) modifiers.add('Shift');
    if (alt) modifiers.add(platform == TargetPlatform.macOS ? '⌥' : 'Alt');
    if (meta) modifiers.add(platform == TargetPlatform.macOS ? '⌘' : 'Win');
    return [...modifiers, _keyLabel].join('+');
  }

  String get _keyLabel => switch (key) {
    LogicalKeyboardKey.space => 'Space',
    LogicalKeyboardKey.delete => 'Delete',
    LogicalKeyboardKey.backspace => '⌫',
    LogicalKeyboardKey.equal => '+',
    LogicalKeyboardKey.pageUp => 'PageUp',
    LogicalKeyboardKey.pageDown => 'PageDown',
    LogicalKeyboardKey.home => 'Home',
    LogicalKeyboardKey.end => 'End',
    LogicalKeyboardKey.enter => 'Enter',
    LogicalKeyboardKey.arrowUp => '↑',
    LogicalKeyboardKey.arrowDown => '↓',
    LogicalKeyboardKey.arrowLeft => '←',
    LogicalKeyboardKey.arrowRight => '→',
    LogicalKeyboardKey.f2 => 'F2',
    LogicalKeyboardKey.f5 => 'F5',
    LogicalKeyboardKey.f6 => 'F6',
    LogicalKeyboardKey.f11 => 'F11',
    _ => key.keyLabel.toUpperCase(),
  };
}

/// Platform defaults with optional user overrides, including compatibility keys.
class ViewerShortcutBindings {
  const ViewerShortcutBindings({
    this.overrides = const {},
    this.print = const ViewerShortcutBinding(
      key: LogicalKeyboardKey.keyP,
      control: true,
    ),
    this.toggleThumbnails = const ViewerShortcutBinding(
      key: LogicalKeyboardKey.keyT,
    ),
    this.toggleGrid = const ViewerShortcutBinding(key: LogicalKeyboardKey.keyG),
    this.colorPicker = const ViewerShortcutBinding(
      key: LogicalKeyboardKey.keyC,
      control: true,
      shift: true,
    ),
    this.fullscreen = const ViewerShortcutBinding(key: LogicalKeyboardKey.f11),
    this.borderless = const ViewerShortcutBinding(
      key: LogicalKeyboardKey.keyF,
      control: true,
      shift: true,
    ),
    this.newWindow = const ViewerShortcutBinding(
      key: LogicalKeyboardKey.keyN,
      control: true,
    ),
    this.reload = const ViewerShortcutBinding(key: LogicalKeyboardKey.f5),
  });

  static const defaults = ViewerShortcutBindings();
  static const unassigned = ViewerShortcutBinding(key: LogicalKeyboardKey(0));
  final Map<String, ViewerShortcutBinding> overrides;

  static String overrideKey(TargetPlatform platform, ViewerCommand command) =>
      '${platform.name}.${command.name}';

  ViewerShortcutBindings withOverrides(
    Map<String, ViewerShortcutBinding> values,
  ) => ViewerShortcutBindings(
    overrides: values,
    print: print,
    toggleThumbnails: toggleThumbnails,
    toggleGrid: toggleGrid,
    colorPicker: colorPicker,
    fullscreen: fullscreen,
    borderless: borderless,
    newWindow: newWindow,
    reload: reload,
  );

  bool isCustomized(ViewerCommand command, TargetPlatform platform) =>
      overrides.containsKey(overrideKey(platform, command));

  Iterable<ViewerShortcutBinding> activators(
    ViewerCommand command,
    TargetPlatform platform,
  ) sync* {
    yield binding(command, platform: platform);
    if (isCustomized(command, platform)) return;
    if (command == ViewerCommand.fullscreen &&
        platform == TargetPlatform.macOS) {
      yield fullscreen;
    }
    if (command == ViewerCommand.zoomIn) {
      yield const ViewerShortcutBinding(
        key: LogicalKeyboardKey.equal,
        shift: true,
      );
      yield const ViewerShortcutBinding(key: LogicalKeyboardKey.add);
      yield const ViewerShortcutBinding(
        key: LogicalKeyboardKey.add,
        shift: true,
      );
      yield const ViewerShortcutBinding(key: LogicalKeyboardKey.numpadAdd);
    }
    if (command == ViewerCommand.zoomOut) {
      yield const ViewerShortcutBinding(key: LogicalKeyboardKey.numpadSubtract);
    }
  }

  ViewerCommand? conflict(
    ViewerCommand command,
    ViewerShortcutBinding candidate,
    TargetPlatform platform,
  ) {
    if (!candidate.isAssigned) return null;
    for (final other in ViewerCommand.values) {
      if (other == command) continue;
      if (activators(other, platform).any(
        (binding) =>
            binding.isAssigned &&
            binding.signature(platform) == candidate.signature(platform),
      )) {
        return other;
      }
    }
    return null;
  }

  static bool isModifier(LogicalKeyboardKey key) => const [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.fn,
    LogicalKeyboardKey.capsLock,
  ].contains(key);

  static bool isReserved(
    ViewerShortcutBinding binding,
    TargetPlatform platform,
  ) {
    if (!binding.isAssigned) return false;
    final key = binding.key;
    if (isModifier(key) ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.tab) {
      return true;
    }
    final bare =
        !binding.control &&
        !binding.physicalControl &&
        !binding.meta &&
        !binding.alt &&
        !binding.shift;
    if (bare &&
        const [
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.backspace,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown,
        ].contains(key)) {
      return true;
    }
    if (binding.alt && key == LogicalKeyboardKey.f4) return true;
    if (platform == TargetPlatform.macOS &&
        binding.control &&
        const [
          LogicalKeyboardKey.keyQ,
          LogicalKeyboardKey.keyH,
        ].contains(key)) {
      return true;
    }
    if (platform != TargetPlatform.macOS && binding.meta) return true;
    return binding.control && binding.alt && key == LogicalKeyboardKey.delete;
  }

  static Map<String, ViewerShortcutBinding> readOverrides(Object? value) {
    if (value is! Map) return const {};
    final result = <String, ViewerShortcutBinding>{};
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      for (final command in ViewerCommand.values) {
        final key = overrideKey(platform, command);
        final binding = ViewerShortcutBinding.fromJson(value[key]);
        if (binding != null && !isReserved(binding, platform)) {
          result[key] = binding;
        }
      }
      while (true) {
        final bindings = defaults.withOverrides(result);
        final invalid = <String>[];
        for (final command in ViewerCommand.values) {
          final key = overrideKey(platform, command);
          final binding = result[key];
          if (binding != null &&
              bindings.conflict(command, binding, platform) != null) {
            invalid.add(key);
          }
        }
        if (invalid.isEmpty) break;
        for (final key in invalid) {
          result.remove(key);
        }
      }
    }
    return Map.unmodifiable(result);
  }

  static const _macFullscreen = ViewerShortcutBinding(
    key: LogicalKeyboardKey.keyF,
    control: true,
    physicalControl: true,
  );

  final ViewerShortcutBinding print;
  final ViewerShortcutBinding toggleThumbnails;
  final ViewerShortcutBinding toggleGrid;
  final ViewerShortcutBinding colorPicker;
  final ViewerShortcutBinding fullscreen;
  final ViewerShortcutBinding borderless;
  final ViewerShortcutBinding reload;
  final ViewerShortcutBinding newWindow;

  ViewerShortcutBinding binding(
    ViewerCommand command, {
    TargetPlatform platform = TargetPlatform.windows,
  }) {
    final custom = overrides[overrideKey(platform, command)];
    if (custom != null) return custom;
    if (command == ViewerCommand.fullscreen &&
        platform == TargetPlatform.macOS) {
      return _macFullscreen;
    }
    if (command == ViewerCommand.deleteFile &&
        platform == TargetPlatform.macOS) {
      return const ViewerShortcutBinding(
        key: LogicalKeyboardKey.backspace,
        control: true,
      );
    }
    return switch (command) {
      ViewerCommand.print => print,
      ViewerCommand.toggleThumbnails => toggleThumbnails,
      ViewerCommand.toggleGrid => toggleGrid,
      ViewerCommand.colorPicker => colorPicker,
      ViewerCommand.fullscreen => fullscreen,
      ViewerCommand.borderless => borderless,
      ViewerCommand.newWindow => newWindow,
      ViewerCommand.reload => reload,
      _ => _additional[command]!,
    };
  }

  String label(
    ViewerCommand command, {
    TargetPlatform platform = TargetPlatform.windows,
  }) => binding(command, platform: platform).displayLabel(platform: platform);

  ViewerCommand? commandFor(
    KeyEvent event, {
    required TargetPlatform platform,
  }) {
    for (final command in ViewerCommand.values) {
      if (activators(
        command,
        platform,
      ).any((binding) => binding.matches(event, platform: platform))) {
        return command;
      }
    }
    return null;
  }

  static const _additional = <ViewerCommand, ViewerShortcutBinding>{
    ViewerCommand.previousImage: ViewerShortcutBinding(
      key: LogicalKeyboardKey.arrowLeft,
    ),
    ViewerCommand.nextImage: ViewerShortcutBinding(
      key: LogicalKeyboardKey.arrowRight,
    ),
    ViewerCommand.previousSingleImage: ViewerShortcutBinding(
      key: LogicalKeyboardKey.arrowLeft,
      shift: true,
    ),
    ViewerCommand.nextSingleImage: ViewerShortcutBinding(
      key: LogicalKeyboardKey.arrowRight,
      shift: true,
    ),
    ViewerCommand.toggleAnimation: ViewerShortcutBinding(
      key: LogicalKeyboardKey.space,
    ),
    ViewerCommand.openFile: ViewerShortcutBinding(
      key: LogicalKeyboardKey.keyO,
      control: true,
    ),
    ViewerCommand.openFolder: ViewerShortcutBinding(
      key: LogicalKeyboardKey.keyO,
      control: true,
      shift: true,
    ),
    ViewerCommand.copyFile: ViewerShortcutBinding(
      key: LogicalKeyboardKey.keyC,
      control: true,
    ),
    ViewerCommand.deleteFile: ViewerShortcutBinding(
      key: LogicalKeyboardKey.delete,
    ),
    ViewerCommand.rename: ViewerShortcutBinding(key: LogicalKeyboardKey.f2),
    ViewerCommand.saveOriginal: ViewerShortcutBinding(
      key: LogicalKeyboardKey.keyS,
      control: true,
      shift: true,
    ),
    ViewerCommand.zoomIn: ViewerShortcutBinding(key: LogicalKeyboardKey.equal),
    ViewerCommand.zoomOut: ViewerShortcutBinding(key: LogicalKeyboardKey.minus),
    ViewerCommand.actualSize: ViewerShortcutBinding(
      key: LogicalKeyboardKey.digit0,
    ),
    ViewerCommand.autoFit: ViewerShortcutBinding(key: LogicalKeyboardKey.keyF),
    ViewerCommand.fitWidth: ViewerShortcutBinding(key: LogicalKeyboardKey.keyW),
    ViewerCommand.fitHeight: ViewerShortcutBinding(
      key: LogicalKeyboardKey.keyH,
    ),
    ViewerCommand.rotate: ViewerShortcutBinding(key: LogicalKeyboardKey.keyR),
    ViewerCommand.flip: ViewerShortcutBinding(
      key: LogicalKeyboardKey.keyM,
      control: true,
    ),
    ViewerCommand.toggleInfo: ViewerShortcutBinding(
      key: LogicalKeyboardKey.keyI,
    ),
    ViewerCommand.toggleDirectory: ViewerShortcutBinding(
      key: LogicalKeyboardKey.keyD,
    ),
    ViewerCommand.settings: ViewerShortcutBinding(
      key: LogicalKeyboardKey.comma,
      control: true,
    ),
    ViewerCommand.autoPlay: ViewerShortcutBinding(key: LogicalKeyboardKey.f6),
    ViewerCommand.stopAutoPlay: ViewerShortcutBinding(
      key: LogicalKeyboardKey.f6,
      shift: true,
    ),
    ViewerCommand.firstImage: ViewerShortcutBinding(
      key: LogicalKeyboardKey.home,
      control: true,
    ),
    ViewerCommand.lastImage: ViewerShortcutBinding(
      key: LogicalKeyboardKey.end,
      control: true,
    ),
    ViewerCommand.pageUp: ViewerShortcutBinding(key: LogicalKeyboardKey.pageUp),
    ViewerCommand.pageDown: ViewerShortcutBinding(
      key: LogicalKeyboardKey.pageDown,
    ),
    ViewerCommand.home: ViewerShortcutBinding(key: LogicalKeyboardKey.home),
    ViewerCommand.end: ViewerShortcutBinding(key: LogicalKeyboardKey.end),
    ViewerCommand.previousChapter: ViewerShortcutBinding(
      key: LogicalKeyboardKey.bracketLeft,
    ),
    ViewerCommand.nextChapter: ViewerShortcutBinding(
      key: LogicalKeyboardKey.bracketRight,
    ),
    ViewerCommand.singlePage: ViewerShortcutBinding(
      key: LogicalKeyboardKey.digit1,
      control: true,
    ),
    ViewerCommand.doublePage: ViewerShortcutBinding(
      key: LogicalKeyboardKey.digit2,
      control: true,
    ),
    ViewerCommand.longImage: ViewerShortcutBinding(
      key: LogicalKeyboardKey.digit3,
      control: true,
    ),
    ViewerCommand.comic: ViewerShortcutBinding(
      key: LogicalKeyboardKey.digit4,
      control: true,
    ),
    ViewerCommand.search: ViewerShortcutBinding(
      key: LogicalKeyboardKey.keyF,
      control: true,
    ),
    ViewerCommand.previousFrame: ViewerShortcutBinding(
      key: LogicalKeyboardKey.comma,
    ),
    ViewerCommand.nextFrame: ViewerShortcutBinding(
      key: LogicalKeyboardKey.period,
    ),
    ViewerCommand.reveal: ViewerShortcutBinding(
      key: LogicalKeyboardKey.enter,
      control: true,
    ),
    ViewerCommand.copyPath: ViewerShortcutBinding(
      key: LogicalKeyboardKey.keyC,
      control: true,
      alt: true,
    ),
    ViewerCommand.lockZoom: ViewerShortcutBinding(
      key: LogicalKeyboardKey.keyK,
      control: true,
    ),
    ViewerCommand.alwaysOnTop: ViewerShortcutBinding(
      key: LogicalKeyboardKey.keyT,
      control: true,
      shift: true,
    ),
    ViewerCommand.parentFolder: ViewerShortcutBinding(
      key: LogicalKeyboardKey.arrowUp,
      alt: true,
    ),
  };
}
