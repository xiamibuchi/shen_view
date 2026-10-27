import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../application/file_association_service.dart';
import 'components/app_button.dart';
import 'components/app_dialog.dart';
import 'components/app_switch.dart';
import 'components/app_text_action.dart';
import 'theme/app_styles.dart';
import 'theme/app_theme.dart';
import 'theme/app_tokens.dart';

class FileAssociationsDialog extends StatefulWidget {
  const FileAssociationsDialog({
    this.service = const FileAssociationService(),
    super.key,
  });
  final FileAssociationService service;

  @override
  State<FileAssociationsDialog> createState() => _FileAssociationsDialogState();
}

class _FileAssociationsDialogState extends State<FileAssociationsDialog>
    with WidgetsBindingObserver {
  FileAssociationState? _state;
  Set<String> _selected = {};
  bool _busy = true;
  String? _message;
  bool _failed = false;

  String _copy(String zh, String en) =>
      AppLocalizations.of(context)!.localeName.startsWith('zh') ? zh : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) {
      _load(preserveSelection: true);
    }
  }

  Future<void> _load({bool preserveSelection = false}) async {
    if (mounted) setState(() => _busy = true);
    try {
      final state = await widget.service.read();
      if (!mounted) return;
      setState(() {
        _state = state;
        if (!preserveSelection) _selected = {...state.registered};
        _busy = false;
        _failed = false;
        _message = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
          _message = _copy(
            '读取文件关联失败，请重试。',
            'Unable to read file associations. Try again.',
          );
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.service.update(_selected);
      await _load();
      if (mounted && !_failed) {
        setState(
          () => _message = _copy(
            '已更新打开方式候选。默认应用请在 Windows 中选择。',
            'Open With choices updated. Select defaults in Windows.',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
          _message = _copy(
            '更新文件关联失败，请重试。',
            'Unable to update file associations. Try again.',
          );
        });
      }
    }
  }

  Future<void> _openSettings() async {
    try {
      await widget.service.openSettings();
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = _copy(
            '无法打开系统设置，请前往 Windows 设置 → 应用 → 默认应用。',
            'Open Windows Settings → Apps → Default apps manually.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    final packaged = _state?.isPackaged ?? false;
    return AppDialog(
      title: _copy('文件关联', 'File associations'),
      maxWidth: 600,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _copy(
              '注册为“打开方式”候选后，再到 Windows 选择默认应用。取消注册不会恢复之前的默认应用。',
              'Register Open With choices, then select defaults in Windows. Removing choices does not restore a previous default.',
            ),
          ),
          const SizedBox(height: AppTokens.space3),
          if (packaged)
            Text(
              _copy(
                'MSIX 的候选格式由安装包管理。可在 Windows 中分别选择图片和压缩包的默认应用。',
                'MSIX file types are managed by the package. Choose image and archive defaults in Windows.',
              ),
            )
          else if (_state?.mode == 'installed-system')
            Text(
              _copy(
                '修改安装版的打开方式候选需要管理员权限，并对所有用户生效。默认应用由各用户自行选择。',
                'Changing installed Open With choices requires administrator approval and applies to all users. Each user chooses their own defaults.',
              ),
            )
          else if (_state?.mode == 'portable' || _state?.mode == 'scoop')
            Text(
              _copy(
                '关联指向当前副本。移动目录后，请重新注册；删除前可取消下方全部格式并应用。',
                'Choices point to this copy. Register again after moving it; clear all choices and apply before deleting it.',
              ),
            ),
          if (_state != null) ...[
            const SizedBox(height: AppTokens.space3),
            SizedBox(
              height: 280,
              child: ListView(
                children: [
                  _group(
                    _copy('图片', 'Images'),
                    FileAssociationFormats.images,
                    packaged,
                    tokens,
                  ),
                  const SizedBox(height: AppTokens.space4),
                  _group(
                    _copy('压缩包与漫画', 'Archives & comics'),
                    FileAssociationFormats.archives,
                    packaged,
                    tokens,
                  ),
                ],
              ),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: AppTokens.space3),
            Text(
              _message!,
              style: AppTextStyles.bodySmall.copyWith(
                color: _failed ? tokens.danger : tokens.textSecondary,
              ),
            ),
          ],
          if (_failed && !_busy)
            AppTextAction(label: _copy('重试', 'Retry'), onPressed: _load),
          if (_busy) ...[
            const SizedBox(height: AppTokens.space3),
            Text(_copy('正在处理…', 'Working…')),
          ],
          const SizedBox(height: AppTokens.space3),
          Align(
            alignment: Alignment.centerLeft,
            child: AppTextAction(
              label: _copy('在 Windows 中选择默认应用', 'Choose defaults in Windows'),
              onPressed: _busy ? null : _openSettings,
            ),
          ),
        ],
      ),
      actions: [
        AppButton(
          label: _copy('关闭', 'Close'),
          variant: AppButtonVariant.neutral,
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (!packaged)
          AppButton(
            key: const ValueKey('associations.apply'),
            label: _copy('应用', 'Apply'),
            variant: AppButtonVariant.accent,
            onPressed: _busy || _state == null ? null : _save,
          ),
      ],
    );
  }

  Widget _group(
    String title,
    Set<String> extensions,
    bool packaged,
    ViewerThemeTokens tokens,
  ) {
    final all = extensions.every(_selected.contains);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTextStyles.label.copyWith(color: tokens.textTertiary),
              ),
            ),
            if (!packaged)
              AppTextAction(
                label: all
                    ? _copy('全部取消', 'Clear all')
                    : _copy('全选', 'Select all'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        all
                            ? _selected.removeAll(extensions)
                            : _selected.addAll(extensions);
                      }),
              ),
          ],
        ),
        for (final ext in extensions.toList()..sort())
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: AppSwitch(
              key: ValueKey('association.$ext'),
              label: '.$ext',
              description: _state!.defaults.contains(ext)
                  ? _copy('当前默认应用', 'Current default app')
                  : null,
              value: _selected.contains(ext),
              enabled: !packaged && !_busy,
              onChanged: (value) => setState(() {
                value ? _selected.add(ext) : _selected.remove(ext);
              }),
            ),
          ),
      ],
    );
  }
}
