import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../application/third_party_licenses.dart';
import 'components/app_button.dart';
import 'components/app_icon_button.dart';
import 'components/app_input.dart';
import 'theme/app_styles.dart';
import 'theme/app_theme.dart';
import 'theme/app_tokens.dart';

const _contentMaxWidth = 760.0;

/// Lists runtime dependency and bundled native component licenses.
class LicensesPage extends StatefulWidget {
  const LicensesPage({this.source, super.key});

  /// Test seam; the packaged app uses [appLicenseEntries].
  final Stream<LicenseEntry>? source;

  @override
  State<LicensesPage> createState() => _LicensesPageState();
}

class _LicensesPageState extends State<LicensesPage> {
  final _searchController = TextEditingController();
  late Future<List<LicenseComponent>> _licenses;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _licenses = _loadLicenses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LicensesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _licenses = _loadLicenses();
    }
  }

  Future<List<LicenseComponent>> _loadLicenses() =>
      collectLicenseComponents(widget.source ?? appLicenseEntries());

  void _retry() {
    setState(() => _licenses = _loadLicenses());
  }

  String _copy(String zh, String en) =>
      AppLocalizations.of(context)!.localeName.startsWith('zh') ? zh : en;

  List<LicenseComponent> _filtered(List<LicenseComponent> items) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return items;
    return items
        .where((item) => item.name.toLowerCase().contains(query))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.appBackground,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          return Center(
            child: SizedBox(
              width: math.min(constraints.maxWidth, _contentMaxWidth),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 20 : 28,
                  compact ? 18 : 24,
                  compact ? 20 : 32,
                  24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(tokens),
                    const SizedBox(height: 18),
                    _buildSearch(tokens),
                    const SizedBox(height: 12),
                    Expanded(child: _buildBody(tokens)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(ViewerThemeTokens tokens) {
    final canPop = Navigator.of(context).canPop();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canPop) ...[
          AppIconButton(
            icon: FluentIcons.chevron_left_20_regular,
            tooltip: _copy('返回', 'Back'),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _copy('开源许可', 'Open-source licenses'),
                style: AppTextStyles.pageTitle.copyWith(
                  color: tokens.textPrimary,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _copy(
                  '查看 Flutter、运行时依赖及随应用分发的原生组件许可。',
                  'Licenses for Flutter, runtime dependencies and bundled native components.',
                ),
                style: AppTextStyles.bodySmall.copyWith(
                  color: tokens.textTertiary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearch(ViewerThemeTokens tokens) => AppInput(
    key: const ValueKey('licenses.search'),
    controller: _searchController,
    hint: _copy('搜索组件', 'Search components'),
    leadingIcon: FluentIcons.search_20_regular,
    clearTooltip: _copy('清除搜索', 'Clear search'),
    onChanged: (value) => setState(() => _query = value),
    clearable: true,
  );

  Widget _buildBody(ViewerThemeTokens tokens) {
    return FutureBuilder<List<LicenseComponent>>(
      future: _licenses,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: tokens.accent,
              ),
            ),
          );
        }
        if (snapshot.hasError) return _buildError(tokens);
        final all = snapshot.data ?? const <LicenseComponent>[];
        final filtered = _filtered(all);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _copy('共 ${all.length} 个组件', '${all.length} components'),
                    style: AppTextStyles.finePrint.copyWith(
                      color: tokens.textTertiary,
                    ),
                  ),
                ),
                if (filtered.length != all.length)
                  Text(
                    _copy(
                      '匹配 ${filtered.length} 条',
                      '${filtered.length} matches',
                    ),
                    style: AppTextStyles.finePrint.copyWith(
                      color: tokens.textTertiary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppTokens.space2),
            Expanded(
              child: filtered.isEmpty
                  ? _buildEmpty(tokens, all.isEmpty)
                  : _buildList(filtered, tokens),
            ),
          ],
        );
      },
    );
  }

  Widget _buildList(List<LicenseComponent> items, ViewerThemeTokens tokens) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AppTokens.containerRadius),
        border: Border.all(color: tokens.border.withValues(alpha: 0.9)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.containerRadius),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: items.length,
          separatorBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Container(
              height: 1,
              color: tokens.border.withValues(alpha: 0.65),
            ),
          ),
          itemBuilder: (context, index) => _buildRow(items[index], tokens),
        ),
      ),
    );
  }

  Widget _buildRow(LicenseComponent item, ViewerThemeTokens tokens) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => _showLicense(item),
        hoverColor: tokens.surfaceHover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _packageTitle(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        color: tokens.textPrimary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _licenseCount(item.documents.length),
                      style: AppTextStyles.finePrint.copyWith(
                        color: tokens.textTertiary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                FluentIcons.chevron_right_16_regular,
                size: 16,
                color: tokens.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(ViewerThemeTokens tokens, bool noLicenses) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          FluentIcons.document_text_20_regular,
          size: 24,
          color: tokens.textTertiary,
        ),
        const SizedBox(height: 10),
        Text(
          noLicenses
              ? _copy('没有可显示的许可证', 'No licenses available')
              : _copy('没有匹配的组件', 'No matching components'),
          style: AppTextStyles.bodySmall.copyWith(color: tokens.textSecondary),
        ),
      ],
    ),
  );

  Widget _buildError(ViewerThemeTokens tokens) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(FluentIcons.warning_20_regular, size: 24, color: tokens.warning),
        const SizedBox(height: 10),
        Text(
          _copy('无法读取许可证信息', 'Unable to load licenses'),
          style: AppTextStyles.body.copyWith(color: tokens.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          _copy(
            '请重试；如果问题仍然存在，请重新安装完整应用。',
            'Try again. If the problem persists, reinstall the complete app.',
          ),
          textAlign: TextAlign.center,
          style: AppTextStyles.label.copyWith(color: tokens.textTertiary),
        ),
        const SizedBox(height: 14),
        AppButton(
          label: _copy('重试', 'Retry'),
          variant: AppButtonVariant.neutral,
          onPressed: _retry,
        ),
      ],
    ),
  );

  String _packageTitle(LicenseComponent item) =>
      item.name.isEmpty ? _copy('未命名许可证', 'Unnamed license') : item.name;

  String _licenseCount(int count) => _copy(
    '$count 份许可文本',
    count == 1 ? '1 license text' : '$count license texts',
  );

  Future<void> _showLicense(LicenseComponent item) async {
    final viewport = MediaQuery.sizeOf(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final tokens = ViewerThemeTokens.of(dialogContext);
        return Dialog(
          insetPadding: const EdgeInsets.all(AppTokens.space5),
          child: SizedBox(
            width: math.max(0, math.min(720, viewport.width - 48)),
            height: math.max(0, math.min(640, viewport.height - 48)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 10, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _packageTitle(item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.subtitle.copyWith(
                                color: tokens.textPrimary,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _licenseCount(item.documents.length),
                              style: AppTextStyles.finePrint.copyWith(
                                color: tokens.textTertiary,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AppIconButton(
                        icon: FluentIcons.dismiss_20_regular,
                        tooltip: _copy('关闭', 'Close'),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 1,
                  color: tokens.border.withValues(alpha: 0.65),
                ),
                Expanded(child: _buildLicenseText(item, tokens)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLicenseText(LicenseComponent item, ViewerThemeTokens tokens) {
    final rows = <(String?, LicenseParagraph?)>[
      for (var index = 0; index < item.documents.length; index++) ...[
        if (item.documents.length > 1 || item.documents[index].title != null)
          (
            item.documents[index].title ??
                _copy('许可 ${index + 1}', 'License ${index + 1}'),
            null,
          ),
        for (final paragraph in item.documents[index].paragraphs)
          (null, paragraph),
      ],
    ];
    if (rows.isEmpty) {
      rows.add((_copy('没有许可证文本。', 'No license text.'), null));
    }
    return ListView.builder(
      key: const ValueKey('licenses.text'),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final (title, paragraph) = rows[index];
        if (title != null) {
          return Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 14),
            child: Text(
              title,
              style: AppTextStyles.label.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
        final centered = paragraph!.indent == LicenseParagraph.centeredIndent;
        return Padding(
          padding: EdgeInsets.only(
            left: math.max(0, paragraph.indent) * 12,
            bottom: 10,
          ),
          child: SelectableText(
            paragraph.text,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: AppTextStyles.code.copyWith(
              color: tokens.textSecondary,
              height: 1.65,
            ),
          ),
        );
      },
    );
  }
}
