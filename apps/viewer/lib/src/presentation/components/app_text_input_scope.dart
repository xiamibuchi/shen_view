import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Includes the Focus widget nested inside EditableText, not just its own node.
EditableText? get focusedTextEditor {
  final context = FocusManager.instance.primaryFocus?.context;
  final widget = context?.widget;
  return widget is EditableText
      ? widget
      : context?.findAncestorWidgetOfExactType<EditableText>();
}

/// Windows IME belongs to text editors; canvas keys must reach the shortcuts.
class AppTextInputScope extends StatefulWidget {
  const AppTextInputScope({super.key, required this.child});

  final Widget child;

  @override
  State<AppTextInputScope> createState() => _AppTextInputScopeState();
}

class _AppTextInputScopeState extends State<AppTextInputScope> {
  static const _channel = MethodChannel('shenview/text_input');
  bool _pending = false;
  int _focusRevision = 0;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      FocusManager.instance.addListener(_scheduleUpdate);
      _scheduleUpdate();
    }
  }

  void _scheduleUpdate() {
    _focusRevision++;
    // Do not wait for a frame to protect canvas keys. Even if the last requested
    // state was disabled, native activation may have restored an IME context.
    if (!_canEdit) unawaited(_setEnabled(false));
    if (_pending) return;
    _pending = true;
    // Run after EditableText has attached/detached its platform input client.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      if (!mounted) return;
      unawaited(_settleInputConnection(_focusRevision));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool get _canEdit {
    final editor = focusedTextEditor;
    return editor != null &&
        !editor.readOnly &&
        editor.keyboardType != TextInputType.none;
  }

  Future<void> _settleInputConnection(int revision) async {
    // This channel is FIFO: the barrier follows EditableText's setClient/clear
    // calls (including its deferred hide) before we apply the final native state.
    await SystemChannels.textInput.invokeMethod<void>(
      _canEdit ? 'TextInput.show' : 'TextInput.hide',
    );
    if (!mounted || revision != _focusRevision) return;
    await _setEnabled(_canEdit);
  }

  Future<void> _setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setEnabled', enabled);
    } on MissingPluginException {
      debugPrint('Windows text-input support requires a rebuilt runner.');
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      FocusManager.instance.removeListener(_scheduleUpdate);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
