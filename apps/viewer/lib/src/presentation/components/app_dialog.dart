import 'package:flutter/material.dart';

import '../theme/app_styles.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'app_button.dart';

class AppDialog extends StatelessWidget {
  const AppDialog({
    required this.title,
    required this.content,
    required this.actions,
    this.maxWidth = 460,
    super.key,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTokens.space5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: AppTextStyles.dialogTitle.copyWith(
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: AppTokens.space4),
              DefaultTextStyle.merge(
                style: AppTextStyles.control.copyWith(
                  color: tokens.textSecondary,
                ),
                child: content,
              ),
              const SizedBox(height: AppTokens.space5),
              AppDialogActions(children: actions),
            ],
          ),
        ),
      ),
    );
  }
}

/// Equal-width actions, centered vertically and stacked in narrow dialogs.
class AppDialogActions extends StatelessWidget {
  const AppDialogActions({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final minimumWidth =
            children.length * AppTokens.dialogActionMinWidth +
            (children.length - 1) * AppTokens.space2;
        if (constraints.maxWidth < minimumWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: AppTokens.space2),
                children[i],
              ],
            ],
          );
        }
        return Align(
          alignment: Alignment.centerRight,
          child: IntrinsicWidth(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppTokens.space2),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: AppTokens.dialogActionMinWidth,
                      ),
                      child: children[i],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog({
    required this.title,
    required this.content,
    required this.cancelLabel,
    required this.confirmLabel,
    this.danger = false,
    super.key,
  });
  final String title;
  final Widget content;
  final String cancelLabel;
  final String confirmLabel;
  final bool danger;

  @override
  Widget build(BuildContext context) => AppDialog(
    title: title,
    content: content,
    actions: [
      AppButton(
        label: cancelLabel,
        variant: AppButtonVariant.neutral,
        autofocus: true,
        onPressed: () => Navigator.pop(context, false),
      ),
      AppButton(
        label: confirmLabel,
        variant: danger ? AppButtonVariant.danger : AppButtonVariant.accent,
        onPressed: () => Navigator.pop(context, true),
      ),
    ],
  );
}
