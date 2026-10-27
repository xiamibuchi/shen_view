import 'package:flutter/material.dart';

import '../theme/app_styles.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

class AppInfoField extends StatelessWidget {
  const AppInfoField({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    final labelWidget = Text(
      label,
      style: AppTextStyles.control.copyWith(color: tokens.textSecondary),
    );
    final valueWidget = SelectableText(
      value,
      style: AppTextStyles.control.copyWith(color: tokens.textPrimary),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.space2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (label.isEmpty) return valueWidget;
          // Preserve useful value width when accessibility text is enlarged.
          final labelWidth = MediaQuery.textScalerOf(context).scale(88);
          if (constraints.maxWidth < labelWidth + 120) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                labelWidget,
                const SizedBox(height: AppTokens.space1),
                valueWidget,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: labelWidth, child: labelWidget),
              const SizedBox(width: AppTokens.space3),
              Expanded(child: valueWidget),
            ],
          );
        },
      ),
    );
  }
}
