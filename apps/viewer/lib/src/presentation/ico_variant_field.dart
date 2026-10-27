import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../application/ico_file.dart';
import 'components/app_info_field.dart';
import 'components/app_select.dart';
import 'theme/app_tokens.dart';
import 'theme/app_styles.dart';
import 'theme/app_theme.dart';

class IcoVariantField extends StatelessWidget {
  const IcoVariantField({
    required this.variants,
    required this.selectedIndex,
    required this.onChanged,
    super.key,
  });

  final List<IcoVariant> variants;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  String _label(IcoVariant variant) =>
      '${variant.width} × ${variant.height} · ${variant.bitDepth} bit · ${variant.codec}';

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context)!.icoVariant;
    final tokens = ViewerThemeTokens.of(context);
    if (variants.length == 1) {
      return AppInfoField(label: label, value: _label(variants.single));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.caption.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${variants.length}',
                style: AppTextStyles.caption.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.space2),
          Semantics(
            label: label,
            child: AppSelect<int>(
              key: const ValueKey('info.icoVariant'),
              value: selectedIndex,
              onChanged: onChanged,
              options: [
                for (final variant in variants)
                  AppSelectOption(
                    value: variant.index,
                    label:
                        variants
                                .where(
                                  (other) => _label(other) == _label(variant),
                                )
                                .length >
                            1
                        ? '${_label(variant)} · #${variant.index + 1}'
                        : _label(variant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
