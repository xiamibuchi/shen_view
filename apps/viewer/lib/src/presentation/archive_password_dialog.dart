import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'components/app_button.dart';
import 'components/app_dialog.dart';
import 'components/app_input.dart';
import 'theme/app_styles.dart';
import 'theme/app_theme.dart';
import 'theme/app_tokens.dart';

enum ArchivePasswordError { wrongPassword, cannotVerify, unsupported }

/// Passwords live only in this dialog and the returned in-memory value.
Future<String?> showArchivePasswordDialog(
  BuildContext context, {
  required String archiveName,
  ArchivePasswordError? error,
}) => showDialog<String>(
  context: context,
  requestFocus: true,
  builder: (_) => ArchivePasswordDialog(archiveName: archiveName, error: error),
);

class ArchivePasswordDialog extends StatefulWidget {
  const ArchivePasswordDialog({
    required this.archiveName,
    this.error,
    super.key,
  });

  final String archiveName;
  final ArchivePasswordError? error;

  @override
  State<ArchivePasswordDialog> createState() => _ArchivePasswordDialogState();
}

class _ArchivePasswordDialogState extends State<ArchivePasswordDialog> {
  final _controller = TextEditingController();
  bool _showPassword = false;

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.isNotEmpty &&
        widget.error != ArchivePasswordError.unsupported) {
      Navigator.of(context).pop(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = ViewerThemeTokens.of(context);
    final error = switch (widget.error) {
      ArchivePasswordError.wrongPassword => l10n.archivePasswordWrong,
      ArchivePasswordError.cannotVerify => l10n.archivePasswordUnverified,
      ArchivePasswordError.unsupported => l10n.archivePasswordUnsupported,
      null => null,
    };
    return Dialog(
      insetPadding: const EdgeInsets.all(AppTokens.space5),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTokens.space5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.archivePasswordTitle,
                style: AppTextStyles.sectionTitle.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppTokens.space2),
              Text(
                widget.archiveName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: AppTokens.space4),
              AppInput(
                key: const ValueKey('archive.passwordInput'),
                controller: _controller,
                label: l10n.archivePasswordHint,
                helperText: l10n.archivePasswordDescription,
                errorText: error,
                leadingIcon: FluentIcons.lock_closed_20_regular,
                autofocus: true,
                obscureText: !_showPassword,
                enabled: widget.error != ArchivePasswordError.unsupported,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppTokens.space2),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  key: const ValueKey('archive.passwordVisibility'),
                  label: _showPassword
                      ? l10n.archivePasswordHide
                      : l10n.archivePasswordShow,
                  variant: AppButtonVariant.subtle,
                  leadingIcon: _showPassword
                      ? FluentIcons.eye_off_20_regular
                      : FluentIcons.eye_20_regular,
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
              const SizedBox(height: AppTokens.space4),
              AppDialogActions(
                children: [
                  AppButton(
                    label: l10n.cancel,
                    variant: AppButtonVariant.neutral,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  AppButton(
                    key: const ValueKey('archive.passwordSubmit'),
                    label: l10n.archivePasswordOpen,
                    variant: AppButtonVariant.accent,
                    onPressed:
                        _controller.text.isEmpty ||
                            widget.error == ArchivePasswordError.unsupported
                        ? null
                        : _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
