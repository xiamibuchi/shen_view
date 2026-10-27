import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../application/decode_request.dart';
import '../application/decode_scheduler.dart';
import '../application/image_resource_service.dart';
import '../application/viewer_controller.dart';

import '../domain/image_entry.dart';
import '../domain/image_format.dart';
import '../domain/viewer_interaction_settings.dart';
import '../domain/viewer_mode.dart';

import 'localized_labels.dart';
import 'components/app_icon_button.dart';
import 'compact_chapter_bar.dart';
import 'resource_image.dart';
import 'scroll_navigation_controller.dart';
import 'source_image_view.dart';
import 'svg_image.dart';
import '../application/svg_resources.dart' show svgVersion;
import 'theme/app_styles.dart';
import 'theme/app_theme.dart';
import 'theme/app_tokens.dart';
import 'viewer_shortcuts.dart';

class ViewerBottomBar extends StatelessWidget {
  const ViewerBottomBar({
    this.shortcuts = ViewerShortcutBindings.defaults,
    super.key,
    required this.controller,
    required this.resources,
    required this.mode,
    required this.parentFolderPath,
    required this.onOpenFolder,
    required this.onOpenArchive,
    required this.onSelect,
    this.showFileNames = true,
    this.viewportVisible = true,
    this.interaction = const ViewerInteractionSettings(),
    this.onNavigate,
    this.onCancelArchiveOpening,
    this.onOpenChapter,
    this.onPreviousArchive,
    this.onNextArchive,
  });
  final ViewerController controller;
  final ViewerShortcutBindings shortcuts;
  final ImageResourceService resources;
  final ViewerMode mode;
  final String? parentFolderPath;
  final ValueChanged<String> onOpenFolder;
  final ValueChanged<ImageEntry> onOpenArchive;
  final VoidCallback? onCancelArchiveOpening;
  final ValueChanged<String>? onOpenChapter;
  final VoidCallback? onPreviousArchive;
  final VoidCallback? onNextArchive;
  final ValueChanged<int> onSelect;
  final bool showFileNames;
  final bool viewportVisible;
  final ViewerInteractionSettings interaction;
  final ValueChanged<int>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = ViewerThemeTokens.of(context);
    final hasFolders = controller.hasFolderNavigation;
    return Container(
      color: tokens.surfaceSubtle,
      height: hasFolders ? 128 : 88,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasFolders)
            SizedBox(
              height: 36,
              child: CompactChapterBar(
                shortcuts: shortcuts,
                controller: controller,
                onOpenChapter: onOpenChapter ?? onOpenFolder,
                onCancelOpening: onCancelArchiveOpening,
              ),
            ),
          if (hasFolders) const SizedBox(height: 6),
          Expanded(
            child: controller.entries.isEmpty
                ? _buildEmptyContent(context, l10n, tokens)
                : _ThumbnailStrip(
                    controller: controller,
                    resources: resources,
                    viewportVisible: viewportVisible,
                    onSelect: onSelect,
                    showFileNames: showFileNames,
                    interaction: interaction,
                    onNavigate: onNavigate,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyContent(
    BuildContext context,
    AppLocalizations l10n,
    ViewerThemeTokens tokens,
  ) {
    final recursive =
        controller.activeBrowseMode.isRecursive ||
        controller.archiveContext != null;
    final message = controller.isIndexing
        ? controller.isOpeningArchive
              ? l10n.archiveOpening
              : controller.scanProgress == null
              ? l10n.scanProgress(0, 0)
              : l10n.scanProgress(
                  controller.scanProgress!.scannedDirectories,
                  controller.scanProgress!.foundImages,
                )
        : controller.archiveContext != null &&
              (controller.containers.isNotEmpty ||
                  controller.childFolders.isNotEmpty)
        ? l10n.archiveBrowseContainers
        : controller.folderPath == null
        ? l10n.folderNotOpened
        : recursive
        ? l10n.emptyRecursiveFolder
        : l10n.emptyFolder;
    final path = controller.folderPath;
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, overflow: TextOverflow.ellipsis),
          if (path != null && !controller.isIndexing) ...[
            const SizedBox(height: 4),
            Text(
              controller.archiveContext?.displayPath(path) ?? path,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.finePrint.copyWith(
                color: tokens.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThumbnailStrip extends StatefulWidget {
  const _ThumbnailStrip({
    required this.controller,
    required this.resources,
    required this.onSelect,
    required this.showFileNames,
    required this.interaction,
    required this.onNavigate,
    required this.viewportVisible,
  });

  final ViewerController controller;
  final ImageResourceService resources;
  final ValueChanged<int> onSelect;
  final bool showFileNames;
  final ViewerInteractionSettings interaction;
  final ValueChanged<int>? onNavigate;
  final bool viewportVisible;

  @override
  State<_ThumbnailStrip> createState() => _ThumbnailStripState();
}

class _ThumbnailStripState extends State<_ThumbnailStrip> {
  static const itemWidth = AppTokens.thumbnailStep;
  static const thumbnailWidth = AppTokens.thumbnailWidth;
  static const thumbnailHeight = AppTokens.thumbnailHeight;

  late final ScrollController _scrollController;
  final _scrollNavigation = ScrollNavigationController();
  String? _lastSelection;
  bool _selectionAnimationRunning = false;
  bool _viewportScheduled = false;
  double _lastViewportOffset = 0;
  double _viewportPadding = 0;

  void _scheduleViewport() {
    if (_viewportScheduled) return;
    _viewportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportScheduled = false;
      if (!mounted ||
          !_scrollController.hasClients ||
          !widget.viewportVisible ||
          widget.controller.entries.isEmpty) {
        return;
      }
      final entries = widget.controller.entries;
      final position = _scrollController.position;
      final offset = position.pixels;
      final ratio = MediaQuery.devicePixelRatioOf(context);
      widget.resources.setThumbnailCollection((
        widget.controller.folderPath,
        widget.controller.archiveContext?.session?.identity,
      ), entries);
      widget.resources.thumbnails.updateViewport(
        owner: 'strip',
        entries: entries,
        first: ((offset - _viewportPadding) / itemWidth).floor(),
        last:
            ((offset + position.viewportDimension - _viewportPadding) /
                    itemWidth)
                .ceil() -
            1,
        targetWidth: (thumbnailWidth * ratio).ceil(),
        targetHeight: (thumbnailHeight * ratio).ceil(),
        direction: (offset - _lastViewportOffset).sign.toInt(),
      );
      _lastViewportOffset = offset;
    });
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_scheduleViewport);
    widget.controller.addListener(_onControllerChanged);
    _scheduleSelectionIntoView();
    _scheduleViewport();
  }

  @override
  void didUpdateWidget(covariant _ThumbnailStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _lastSelection = null;
    }
    _scheduleSelectionIntoView();
    _scheduleViewport();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final selection = _selectionKey();
    if (selection == _lastSelection) return;
    _lastSelection = selection;
    setState(() {});
    _scheduleSelectionIntoView();
    _scheduleViewport();
  }

  String _selectionKey() {
    final entry = widget.controller.currentEntry;
    return '${widget.controller.currentIndex}:${entry?.id}:${widget.controller.entries.length}';
  }

  void _scheduleSelectionIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final index = widget.controller.currentIndex;
      if (index < 0 || index >= widget.controller.entries.length) return;
      final position = _scrollController.position;
      final itemStart = index * itemWidth;
      final itemEnd = itemStart + itemWidth;
      final visibleStart = position.pixels;
      final visibleEnd = visibleStart + position.viewportDimension;
      final target = itemStart < visibleStart
          ? itemStart
          : itemEnd > visibleEnd
          ? itemEnd - position.viewportDimension
          : position.pixels;
      final clamped = target.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((clamped - position.pixels).abs() < 0.5) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scrollController.jumpTo(clamped);
      } else {
        _selectionAnimationRunning = true;
        _scrollController
            .animateTo(
              clamped,
              duration: AppTokens.thumbnailScrollAnimation,
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() {
              _selectionAnimationRunning = false;
            });
      }
    });
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null &&
        _selectionAnimationRunning &&
        _scrollController.hasClients) {
      // A user's drag always wins over programmatic selection-following.
      // Jumping to the current offset aborts ScrollPosition.animateTo.
      _selectionAnimationRunning = false;
      _scrollController.jumpTo(_scrollController.position.pixels);
    }
    return false;
  }

  void _selectRelative(int delta) {
    final navigate = widget.onNavigate;
    if (navigate != null) {
      navigate(delta);
      return;
    }
    final index = widget.controller.currentIndex + delta;
    if (index < 0 || index >= widget.controller.entries.length) return;
    widget.onSelect(index);
  }

  void _scrollByWheel(PointerScrollEvent event) {
    if (!_scrollController.hasClients) return;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final ctrlPressed =
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight);
    final direction = _scrollNavigation.handle(
      event,
      enabled: !ctrlPressed,
      interval: Duration(milliseconds: widget.interaction.wheelIntervalMs),
    );
    if (ctrlPressed) return;
    final position = _scrollController.position;
    final horizontal = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs();
    if (!horizontal) {
      if (direction != null) {
        _selectRelative(
          widget.interaction.reverseWheel ? -direction : direction,
        );
      }
      return;
    }
    final delta = event.scrollDelta.dx * widget.interaction.scrollSpeed;
    if (!delta.isFinite) return;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.controller.entries;
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollInertiaCancelEvent) _scrollNavigation.reset();
        if (event is PointerScrollEvent) _scrollByWheel(event);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = entries.length * itemWidth;
          final sidePadding = math
              .max(0, (constraints.maxWidth - contentWidth) / 2)
              .toDouble();
          _viewportPadding = sidePadding;
          _scheduleViewport();
          return NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: ScrollConfiguration(
              behavior: const _ThumbnailScrollBehavior(),
              child: ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                dragStartBehavior: DragStartBehavior.start,
                padding: EdgeInsets.symmetric(horizontal: sidePadding),
                itemExtent: itemWidth,
                // Mounted tiles are visible demand. Do not start eight extra
                // decodes on either side when background loading is paused.
                scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final item = entries[index];
                  return _ThumbnailItem(
                    key: ValueKey(item.id),
                    index: index,
                    label:
                        (widget.controller.activeBrowseMode.isFlat ||
                            widget.controller.isArchiveView)
                        ? item.relativePath
                        : item.name,
                    image: _thumbnailWidget(context, item),
                    selected: index == widget.controller.currentIndex,
                    showFileName: widget.showFileNames,
                    onSelected: () {
                      widget.onSelect(index);
                      _scheduleSelectionIntoView();
                    },
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _thumbnailWidget(BuildContext context, ImageEntry item) {
    if (item.format == ImageFormat.svg) {
      if (!item.isMaterialized) {
        return SourceImageView(
          entry: item,
          showRetryButton: false,
          builder: (resolved) => _thumbnailWidget(context, resolved),
          errorBuilder: (_) => _ThumbnailPlaceholder.error(
            context,
            label: localizedFormatLabel(
              AppLocalizations.of(context)!,
              item.format,
            ),
          ),
        );
      }
      return SvgImage(
        file: item.file,
        version: svgVersion(item),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Center(
          child: _ThumbnailPlaceholder.error(
            context,
            label: localizedFormatLabel(
              AppLocalizations.of(context)!,
              item.format,
            ),
          ),
        ),
      );
    }
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return ResourceImage(
      resources: widget.resources,
      entry: item,
      targetWidth: (thumbnailWidth * ratio).ceil(),
      targetHeight: (thumbnailHeight * ratio).ceil(),
      priority: DecodePriority.visibleThumbnail,
      fit: BoxFit.contain,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return _ThumbnailPlaceholder.loading(context);
      },
      errorBuilder: (context, error, stack) => error is DecodeCancelled
          ? _ThumbnailPlaceholder.deferred(
              context,
              label: localizedFormatLabel(
                AppLocalizations.of(context)!,
                item.format,
              ),
            )
          : Center(
              child: _ThumbnailPlaceholder.error(
                context,
                onRetry: () =>
                    setState(() => widget.resources.invalidate(item.id)),
                label: localizedFormatLabel(
                  AppLocalizations.of(context)!,
                  item.format,
                ),
              ),
            ),
    );
  }
}

class _ThumbnailScrollBehavior extends MaterialScrollBehavior {
  const _ThumbnailScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

class _ThumbnailItem extends StatefulWidget {
  const _ThumbnailItem({
    super.key,
    required this.index,
    required this.label,
    required this.image,
    required this.selected,
    required this.showFileName,
    required this.onSelected,
  });

  final int index;
  final String label;
  final Widget image;
  final bool selected;
  final bool showFileName;
  final VoidCallback onSelected;

  @override
  State<_ThumbnailItem> createState() => _ThumbnailItemState();
}

class _ThumbnailItemState extends State<_ThumbnailItem> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppTokens.selectionAnimation;
    final stateBackground = _pressed
        ? tokens.surfacePressed
        : _hovered
        ? tokens.surfaceHover
        : tokens.canvasBackground;
    final borderColor = _focused
        ? tokens.focusRing
        : widget.selected
        ? tokens.accentStrong
        : _pressed
        ? tokens.textSecondary
        : _hovered
        ? tokens.textSecondary
        : tokens.border.withValues(alpha: 0.8);
    final stateShadow = widget.selected
        ? [
            BoxShadow(
              color: tokens.accent.withValues(alpha: 0.32),
              blurRadius: 3,
              spreadRadius: 0.5,
            ),
          ]
        : _focused
        ? [
            BoxShadow(
              color: tokens.focusRing.withValues(alpha: 0.22),
              blurRadius: 3,
              spreadRadius: 0.5,
            ),
          ]
        : _hovered || _pressed
        ? [
            BoxShadow(
              color: tokens.borderStrong.withValues(alpha: 0.18),
              blurRadius: 2,
              spreadRadius: 0.25,
            ),
          ]
        : const <BoxShadow>[];
    final labelVisible =
        widget.showFileName &&
        (_hovered || _pressed || _focused || widget.selected);

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      value: '${widget.index + 1}',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onSelected();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onSelected,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              width: AppTokens.thumbnailWidth,
              height: AppTokens.thumbnailHeight,
              decoration: BoxDecoration(
                color: stateBackground,
                borderRadius: BorderRadius.circular(AppTokens.thumbnailRadius),
                boxShadow: stateShadow,
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTokens.thumbnailRadius),
                border: Border.all(
                  color: borderColor,
                  width: widget.selected || _focused ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.image,
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: AppTokens.thumbnailLabelHeight,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: labelVisible ? 1 : 0,
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: AppTextStyles.thumbnailCaption.copyWith(
                                fontWeight: widget.selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

abstract final class _ThumbnailPlaceholder {
  static Widget deferred(BuildContext context, {required String label}) =>
      Center(
        child: Text(
          label,
          style: AppTextStyles.finePrint.copyWith(
            color: ViewerThemeTokens.of(context).textTertiary,
          ),
        ),
      );
  static Widget loading(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    return ColoredBox(
      color: tokens.surfaceHover.withValues(alpha: 0.45),
      child: Center(
        child: MediaQuery.disableAnimationsOf(context)
            ? Icon(
                FluentIcons.more_horizontal_16_regular,
                size: 16,
                color: tokens.textTertiary,
              )
            : SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  value: 0.28,
                  strokeWidth: 1.5,
                  color: tokens.textTertiary,
                ),
              ),
      ),
    );
  }

  static Widget error(
    BuildContext context, {
    required String label,
    VoidCallback? onRetry,
  }) {
    final tokens = ViewerThemeTokens.of(context);
    return ColoredBox(
      color: tokens.surfaceHover.withValues(alpha: 0.6),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onRetry != null)
              AppIconButton(
                icon: FluentIcons.arrow_clockwise_20_regular,
                tooltip: AppLocalizations.of(context)!.archiveRetryPage,
                onPressed: onRetry,
                size: 28,
                iconSize: 16,
              )
            else
              Icon(
                FluentIcons.image_off_20_regular,
                size: 16,
                color: tokens.textTertiary,
              ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.thumbnailText.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
