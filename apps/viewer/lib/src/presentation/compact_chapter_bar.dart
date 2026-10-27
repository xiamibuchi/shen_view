import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../application/viewer_controller.dart';
import 'components/app_icon_button.dart';
import 'components/app_select.dart';
import 'theme/app_theme.dart';
import 'viewer_shortcuts.dart';

/// Chapter switching stays bounded in width regardless of directory depth.
class CompactChapterBar extends StatelessWidget {
  const CompactChapterBar({
    this.shortcuts = ViewerShortcutBindings.defaults,
    super.key,
    required this.controller,
    required this.onOpenChapter,
    this.onCancelOpening,
  });
  final ViewerController controller;
  final ViewerShortcutBindings shortcuts;
  final ValueChanged<String> onOpenChapter;
  final VoidCallback? onCancelOpening;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = ViewerThemeTokens.of(context);
    final chapters = controller.chapterChoices;
    final selected = controller.selectedChapterPath;
    final index = chapters.indexWhere((chapter) => chapter.path == selected);
    final opening = controller.isOpeningArchive;
    final folderRoot = controller.directoryRoot?.isArchive == false;
    final warning =
        controller.indexTruncated || controller.skippedFolders.isNotEmpty;
    return Row(
      key: const ValueKey('navigation.compact'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Tooltip(
              message: controller.currentDirectoryPath == null
                  ? ''
                  : controller.directoryDisplayPath(
                      controller.currentDirectoryPath!,
                    ),
              child: AppSelect<String>(
                key: const ValueKey('navigation.chapter'),
                value: selected,
                hint: folderRoot ? l10n.chooseLocation : l10n.chooseChapter,
                enabled: !opening,
                borderless: true,
                shrinkWrap: true,
                onChanged: onOpenChapter,
                options: [
                  for (final chapter in chapters)
                    AppSelectOption(
                      value: chapter.path,
                      label: chapter.name.isEmpty
                          ? l10n.directoryImages
                          : chapter.name,
                      icon: chapter.name.isEmpty
                          ? FluentIcons.image_20_regular
                          : chapter.isArchive
                          ? FluentIcons.archive_20_regular
                          : FluentIcons.folder_20_regular,
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        if (opening) ...[
          Tooltip(
            message: controller.isPreparingArchivePage
                ? l10n.archivePreparingPage
                : l10n.archiveReadingDirectory,
            child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ),
          AppIconButton(
            key: const ValueKey('archive.cancelOpening'),
            icon: FluentIcons.dismiss_20_regular,
            tooltip: l10n.archiveCancelOpening,
            onPressed: onCancelOpening,
            size: 36,
            iconSize: 18,
          ),
        ] else ...[
          if (warning)
            Tooltip(
              message: controller.indexTruncated
                  ? l10n.recursiveScanLimit
                  : l10n.scanSkippedFolders(controller.skippedFolders.length),
              child: Icon(
                FluentIcons.warning_20_regular,
                size: 18,
                color: tokens.warning,
              ),
            ),
          AppIconButton(
            key: const ValueKey('navigation.previousChapter'),
            icon: FluentIcons.chevron_left_20_regular,
            tooltip:
                '${folderRoot ? l10n.previousLocation : l10n.previousChapter} · ${shortcuts.label(ViewerCommand.previousChapter, platform: Theme.of(context).platform)}',
            size: 36,
            iconSize: 18,
            onPressed: index > 0
                ? () => onOpenChapter(chapters[index - 1].path)
                : null,
          ),
          AppIconButton(
            key: const ValueKey('navigation.nextChapter'),
            icon: FluentIcons.chevron_right_20_regular,
            tooltip:
                '${folderRoot ? l10n.nextLocation : l10n.nextChapter} · ${shortcuts.label(ViewerCommand.nextChapter, platform: Theme.of(context).platform)}',
            size: 36,
            iconSize: 18,
            onPressed: index >= 0 && index + 1 < chapters.length
                ? () => onOpenChapter(chapters[index + 1].path)
                : null,
          ),
        ],
      ],
    );
  }
}
