import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_styles.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'app_icon_button.dart';
import 'app_notification.dart';
import 'app_input.dart';

class AppFileNameEditor extends StatefulWidget {
  const AppFileNameEditor({
    required this.label,
    required this.fileName,
    required this.canEdit,
    required this.unavailableMessage,
    required this.invalidMessage,
    required this.renameTooltip,
    required this.onRename,
    super.key,
  });
  final String label;
  final String fileName;
  final bool canEdit;
  final String unavailableMessage;
  final String invalidMessage;
  final String renameTooltip;
  final Future<String?> Function(String fileName) onRename;
  @override
  State<AppFileNameEditor> createState() => AppFileNameEditorState();
}

class AppFileNameEditorState extends State<AppFileNameEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String _extension = '';
  bool _editing = false;
  bool _saving = false;
  String? _error;
  String get _stem {
    final dot = widget.fileName.lastIndexOf('.');
    if (dot <= 0) return widget.fileName;
    return widget.fileName.substring(0, dot);
  }

  @override
  void initState() {
    super.initState();
    _updateExtension(widget.fileName);
    _controller = TextEditingController(text: _stem);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant AppFileNameEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fileName == oldWidget.fileName) return;
    _updateExtension(widget.fileName);
    _controller.text = _stem;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    if (_editing) {
      _editing = false;
      _saving = false;
      _error = null;
    }
  }

  void _updateExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    _extension = dot > 0 ? fileName.substring(dot) : '';
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void beginEditing() {
    if (!widget.canEdit || _editing) return;
    setState(() {
      _editing = true;
      _error = null;
      _controller
        ..text = _stem
        ..selection = TextSelection(baseOffset: 0, extentOffset: _stem.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) {
        _focusNode.requestFocus();
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      }
    });
  }

  void _cancel() {
    if (!_editing || _saving) return;
    setState(() {
      _editing = false;
      _error = null;
      _controller.text = _stem;
    });
  }

  Future<void> _submit() async {
    if (!_editing || _saving) return;
    final stem = _controller.text.trim();
    if (stem.isEmpty) {
      setState(() => _error = widget.invalidMessage);
      _focusNode.requestFocus();
      return;
    }
    final name = '$stem$_extension';
    setState(() => _saving = true);
    final error = await widget.onRename(name);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      // The disabled field must rebuild before it can receive focus again.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _editing && !_saving) _focusNode.requestFocus();
      });
      return;
    }
    setState(() {
      _saving = false;
      _editing = false;
      _error = null;
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    return Padding(
      padding: EdgeInsets.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.label,
                  style: AppTextStyles.caption.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: AppTokens.space1),
                if (_editing)
                  TapRegion(
                    onTapOutside: (_) {
                      if (!_saving) _cancel();
                    },
                    child: Focus(
                      onKeyEvent: _handleKey,
                      child: AppInput(
                        controller: _controller,
                        focusNode: _focusNode,
                        enabled: !_saving,
                        maxLength: 240,
                        suffixText: _extension.isEmpty ? null : _extension,
                        errorText: _error,
                        textInputAction: TextInputAction.done,
                        clearTooltip: MaterialLocalizations.of(context)
                            .deleteButtonTooltip,
                        onClear: _focusNode.requestFocus,
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppTokens.iconButtonSize,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Tooltip(
                        message: widget.fileName,
                        child: Text(
                          widget.fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.compactTitle.copyWith(
                            color: tokens.textPrimary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!_editing)
            Padding(
              padding: const EdgeInsets.only(
                top: AppTokens.space5,
                left: AppTokens.space2,
              ),
              child: AppIconButton(
                size: AppTokens.iconButtonSize,
                iconSize: 16,
                icon: FluentIcons.edit_16_regular,
                tooltip: widget.canEdit
                    ? widget.renameTooltip
                    : widget.unavailableMessage,
                onPressed: widget.canEdit
                    ? beginEditing
                    : () => AppNotificationHost.of(context).show(
                        widget.unavailableMessage,
                        type: AppNotificationType.warning,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
