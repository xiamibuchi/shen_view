import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import 'components/app_button.dart';
import 'components/app_dialog.dart';
import 'components/app_interactive_surface.dart';
import 'components/app_text_action.dart';
import 'theme/app_styles.dart';
import 'theme/app_theme.dart';
import 'theme/app_tokens.dart';
import 'viewer_shortcuts.dart';

class ShortcutEditorDialog extends StatefulWidget {
  const ShortcutEditorDialog({
    required this.command,
    required this.action,
    required this.bindings,
    required this.defaults,
    required this.commandLabel,
    super.key,
  });

  final ViewerCommand command;
  final String action;
  final ViewerShortcutBindings bindings;
  final ViewerShortcutBindings defaults;
  final String Function(ViewerCommand) commandLabel;

  @override
  State<ShortcutEditorDialog> createState() => _ShortcutEditorDialogState();
}

class _ShortcutEditorDialogState extends State<ShortcutEditorDialog> {
  final _recorderFocus = FocusNode();
  ViewerShortcutBinding? _candidate;
  bool _recording = false;

  String _copy(String zh, String en) =>
      AppLocalizations.of(context)!.localeName.startsWith('zh') ? zh : en;

  @override
  void dispose() {
    _recorderFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final tokens = ViewerThemeTokens.of(context);
    final candidate =
        _candidate ??
        widget.bindings.binding(widget.command, platform: platform);
    final conflict = widget.bindings.conflict(
      widget.command,
      candidate,
      platform,
    );
    final error = ViewerShortcutBindings.isReserved(candidate, platform)
        ? _copy(
            '此按键由系统或界面导航使用，请选择其他组合。',
            'This key is reserved for system or interface navigation. Choose another combination.',
          )
        : conflict == null
        ? null
        : _copy(
            '已被「${widget.commandLabel(conflict)}」使用，请选择其他按键。',
            'Already used by “${widget.commandLabel(conflict)}”. Choose another key.',
          );
    return AppDialog(
      title: _copy('修改快捷键', 'Edit shortcut'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.action,
            style: AppTextStyles.bodyLarge.copyWith(color: tokens.textPrimary),
          ),
          const SizedBox(height: AppTokens.space3),
          Text(
            _recording
                ? _copy(
                    '按下新的按键或组合键即可完成录入。',
                    'Press a new key or combination to finish recording.',
                  )
                : _copy(
                    '点击下方区域开始录入快捷键。',
                    'Click below to start recording a shortcut.',
                  ),
          ),
          const SizedBox(height: AppTokens.space4),
          Focus(
            focusNode: _recorderFocus,
            onFocusChange: (focused) {
              if (!focused && _recording) {
                setState(() => _recording = false);
              }
            },
            onKeyEvent: (node, event) {
              if (!_recording || event.logicalKey == LogicalKeyboardKey.tab) {
                return KeyEventResult.ignored;
              }
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  Navigator.of(context).pop();
                } else if (!ViewerShortcutBindings.isModifier(
                  event.logicalKey,
                )) {
                  setState(() {
                    _candidate = ViewerShortcutBinding.fromEvent(
                      event,
                      platform,
                    );
                    _recording = false;
                  });
                }
              }
              return KeyEventResult.handled;
            },
            child: AppInteractiveSurface(
              canRequestFocus: false,
              key: const ValueKey('shortcuts.recorder'),
              onTap: () {
                setState(() => _recording = true);
                _recorderFocus.requestFocus();
              },
              child: Container(
                padding: const EdgeInsets.all(AppTokens.space5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    AppTokens.containerRadius,
                  ),
                  border: Border.all(
                    color: _recording ? tokens.accentStrong : tokens.border,
                  ),
                ),
                child: Text(
                  _recording
                      ? _copy('等待按键…', 'Waiting for a key…')
                      : candidate.isAssigned
                      ? candidate.displayLabel(platform: platform)
                      : _copy('未设置', 'Unassigned'),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.sectionTitle.copyWith(
                    color: tokens.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTokens.space3),
          Text(
            error ??
                _copy(
                  '默认：${widget.defaults.label(widget.command, platform: platform)}',
                  'Default: ${widget.defaults.label(widget.command, platform: platform)}',
                ),
            key: const ValueKey('shortcuts.validation'),
            style: AppTextStyles.bodySmall.copyWith(
              color: error == null ? tokens.textTertiary : tokens.danger,
            ),
          ),
          const SizedBox(height: AppTokens.space3),
          Wrap(
            spacing: AppTokens.space5,
            runSpacing: AppTokens.space2,
            children: [
              AppTextAction(
                key: const ValueKey('shortcuts.restoreOne'),
                label: _copy('恢复默认', 'Restore default'),
                onPressed: () => setState(() {
                  _recording = false;
                  _candidate = widget.defaults.binding(
                    widget.command,
                    platform: platform,
                  );
                }),
              ),
              AppTextAction(
                key: const ValueKey('shortcuts.clearOne'),
                label: _copy('清除快捷键', 'Clear shortcut'),
                onPressed: () => setState(() {
                  _recording = false;
                  _candidate = ViewerShortcutBindings.unassigned;
                }),
              ),
            ],
          ),
        ],
      ),
      actions: [
        AppButton(
          label: AppLocalizations.of(context)!.cancel,
          variant: AppButtonVariant.neutral,
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          key: const ValueKey('shortcuts.save'),
          label: _copy('保存', 'Save'),
          onPressed: error == null
              ? () => Navigator.of(context).pop(candidate)
              : null,
        ),
      ],
    );
  }
}
