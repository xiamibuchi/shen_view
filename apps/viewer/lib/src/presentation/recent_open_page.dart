import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../application/recent_open_store.dart';
import 'components/app_button.dart';
import 'components/app_dialog.dart';
import 'components/app_icon_button.dart';
import 'components/app_input.dart';
import 'components/app_interactive_surface.dart';
import 'components/app_text_action.dart';
import 'theme/app_styles.dart';
import 'theme/app_theme.dart';

String recentCopy(BuildContext context, String zh, String en) =>
    AppLocalizations.of(context)!.localeName.startsWith('zh') ? zh : en;

Future<bool> confirmClearRecentOpen(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AppConfirmDialog(
        title: recentCopy(context, '清空最近打开？', 'Clear recent items?'),
        content: Text(
          recentCopy(
            context,
            '清除列表及上次打开位置。不会删除文件，也不影响各目录的阅读设置与进度。',
            'Clears the list and last-opened location. Files, reading preferences and progress are kept.',
          ),
        ),
        cancelLabel: recentCopy(context, '取消', 'Cancel'),
        confirmLabel: recentCopy(context, '清空', 'Clear'),
        danger: true,
      ),
    ) ??
    false;

class RecentOpenPage extends StatefulWidget {
  const RecentOpenPage({
    required this.store,
    required this.enabled,
    required this.limit,
    required this.onOpenFile,
    required this.onOpenFolder,
    required this.onOpenPath,
    this.beforeLoad,
    this.onBack,
    super.key,
  });

  final RecentOpenStore store;
  final bool enabled;
  final int limit;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final Future<void> Function(String path) onOpenPath;
  final Future<void> Function()? beforeLoad;
  final VoidCallback? onBack;

  @override
  State<RecentOpenPage> createState() => _RecentOpenPageState();
}

class _RecentOpenPageState extends State<RecentOpenPage> {
  final _search = TextEditingController();
  List<RecentOpenEntry>? _entries;
  String? _error;
  bool _busy = false;

  String _copy(String zh, String en) => recentCopy(context, zh, en);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await widget.beforeLoad?.call();
      final entries = await widget.store.load(limit: widget.limit);
      if (mounted) setState(() => _entries = entries);
    } catch (_) {
      if (mounted) {
        setState(() {
          _entries = const [];
          _error = _copy(
            '无法读取最近打开记录，请重试。',
            'Unable to read recent items. Try again.',
          );
        });
      }
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(RecentOpenEntry entry) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final type = await FileSystemEntity.type(entry.path);
      final exists = entry.kind == RecentOpenKind.folder
          ? type == FileSystemEntityType.directory
          : type == FileSystemEntityType.file;
      if (!mounted) return;
      if (exists) {
        await widget.onOpenPath(entry.path);
      } else {
        setState(
          () => _error = _copy(
            '找不到此项目，请检查磁盘或网络连接，或从列表移除。',
            'Item not found. Check the drive or network connection, or remove it from the list.',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _copy(
            '无法访问此项目，请检查权限后重试。',
            'Unable to access this item. Check permissions and try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(RecentOpenEntry entry) async {
    try {
      await widget.store.remove(entry.path);
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = _copy('移除失败，请重试。', 'Unable to remove item. Try again.'),
        );
      }
    }
  }

  Future<void> _clear() async {
    if (!await confirmClearRecentOpen(context)) return;
    try {
      await widget.store.clear();
      if (mounted) {
        setState(() {
          _entries = const [];
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = _copy('清空失败，请重试。', 'Unable to clear items. Try again.'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    final query = _search.text.trim().toLowerCase();
    final entries = (_entries ?? const <RecentOpenEntry>[])
        .where((entry) => entry.path.toLowerCase().contains(query))
        .toList();
    final start = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 36,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              _copy('开始', 'Start'),
              style: AppTextStyles.sectionTitle.copyWith(
                color: tokens.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _startAction(
              'recent.start.openFile',
              _copy('打开图片或压缩包', 'Open image or archive'),
              FluentIcons.image_20_regular,
              widget.onOpenFile,
            ),
            const SizedBox(height: 8),
            _startAction(
              'recent.start.openFolder',
              _copy('打开文件夹', 'Open folder'),
              FluentIcons.folder_open_20_regular,
              widget.onOpenFolder,
            ),
            if (widget.onBack != null) ...[
              const SizedBox(height: 8),
              _startAction(
                'recent.start.back',
                _copy('返回当前图片', 'Return to current image'),
                FluentIcons.arrow_left_20_regular,
                widget.onBack!,
              ),
            ],
          ],
        ),
      ],
    );
    final recent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _copy('最近打开', 'Recent items'),
                style: AppTextStyles.sectionTitle.copyWith(
                  color: tokens.textPrimary,
                ),
              ),
            ),
            AppButton(
              key: const ValueKey('recent.clear'),
              label: _copy('清空', 'Clear'),
              variant: AppButtonVariant.subtle,
              onPressed: (_entries?.isNotEmpty ?? false) ? _clear : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.enabled)
          AppInput(
            key: const ValueKey('recent.search'),
            controller: _search,
            hint: _copy('搜索名称或路径', 'Search names or paths'),
            leadingIcon: FluentIcons.search_20_regular,
            clearable: true,
            clearTooltip: _copy('清空搜索', 'Clear search'),
            onChanged: (_) => setState(() {}),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _error!,
                    style: AppTextStyles.body.copyWith(color: tokens.danger),
                  ),
                ),
                AppIconButton(
                  icon: FluentIcons.dismiss_20_regular,
                  tooltip: _copy('关闭提示', 'Dismiss'),
                  onPressed: () => setState(() => _error = null),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        if (!widget.enabled)
          Text(
            _copy(
              '最近打开记录已关闭，可在设置 → 通用中开启。',
              'Recording is off. Enable it in Settings → General.',
            ),
            style: AppTextStyles.body.copyWith(color: tokens.textSecondary),
          )
        else if (_entries == null)
          const Center(child: CircularProgressIndicator())
        else if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              query.isEmpty
                  ? _copy('还没有最近打开的项目', 'No recent items')
                  : _copy('没有匹配的项目', 'No matching items'),
              style: AppTextStyles.body.copyWith(color: tokens.textTertiary),
            ),
          )
        else
          for (final entry in entries) _row(entry),
      ],
    );
    return Material(
      key: const ValueKey('recent.welcome'),
      color: tokens.appBackground,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 850;
          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 64 : 28,
                    vertical: 32,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 240, child: start),
                            const SizedBox(width: 64),
                            Expanded(child: recent),
                          ],
                        )
                      else ...[
                        start,
                        const SizedBox(height: 32),
                        recent,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _startAction(
    String key,
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return AppTextAction(
      key: ValueKey(key),
      label: label,
      icon: icon,
      onPressed: onTap,
    );
  }

  Widget _row(RecentOpenEntry entry) {
    final tokens = ViewerThemeTokens.of(context);
    final (icon, kind) = switch (entry.kind) {
      RecentOpenKind.image => (
        FluentIcons.image_20_regular,
        _copy('图片', 'Image'),
      ),
      RecentOpenKind.folder => (
        FluentIcons.folder_open_20_regular,
        _copy('文件夹', 'Folder'),
      ),
      RecentOpenKind.archive => (
        FluentIcons.archive_20_regular,
        _copy('压缩包', 'Archive'),
      ),
    };
    return Row(
      children: [
        Expanded(
          child: AppInteractiveSurface(
            key: ValueKey('recent.open.${entry.path}'),
            onTap: _busy ? null : () => _open(entry),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: Row(
                children: [
                  Icon(icon, color: tokens.textSecondary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyLarge.copyWith(
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Tooltip(
                          message:
                              '$kind · ${DateFormat('yyyy-MM-dd HH:mm').format(entry.openedAt.toLocal())}\n${entry.path}',
                          child: Text(
                            entry.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption.copyWith(
                              color: tokens.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AppIconButton(
          key: ValueKey('recent.remove.${entry.path}'),
          icon: FluentIcons.dismiss_20_regular,
          tooltip: _copy('从最近打开移除', 'Remove from recent items'),
          onPressed: () => _remove(entry),
        ),
      ],
    );
  }
}
