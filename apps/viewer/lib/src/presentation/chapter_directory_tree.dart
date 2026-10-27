import 'dart:async';
import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as paths;

import '../../l10n/app_localizations.dart';
import '../application/decode_request.dart';
import '../application/viewer_controller.dart';
import '../domain/archive_context.dart';
import '../domain/folder_index_result.dart';
import '../domain/image_entry.dart';
import 'components/app_icon_button.dart';
import 'components/app_button.dart';
import 'components/app_input.dart';
import 'components/app_interactive_surface.dart';
import 'localized_error.dart';
import 'theme/app_styles.dart';
import 'theme/app_theme.dart';

/// A metadata-only tree. Images are decoded by the viewer after explicit entry.
class ChapterDirectoryTree extends StatefulWidget {
  const ChapterDirectoryTree({
    super.key,
    required this.controller,
    required this.onOpenFolder,
    required this.onOpenArchive,
    this.onOpenParent,
    this.pinned = false,
    this.onTogglePinned,
    this.onChooseFolder,
    this.searchFocusNode,
    required this.onClose,
    required this.expandedPaths,
  });
  final ViewerController controller;
  final Future<void> Function(String) onOpenFolder;
  final Future<void> Function(ImageEntry) onOpenArchive;
  final Future<void> Function(String)? onOpenParent;
  final bool pinned;
  final VoidCallback? onTogglePinned;
  final VoidCallback? onChooseFolder;
  final FocusNode? searchFocusNode;
  final VoidCallback onClose;
  final Set<String> expandedPaths;

  @override
  State<ChapterDirectoryTree> createState() => _ChapterDirectoryTreeState();
}

class _ChapterDirectoryTreeState extends State<ChapterDirectoryTree> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  final _indices = <String, FolderIndexResult>{};
  final _childrenCache = <String, List<_DirectoryNode>>{};
  final _pending = <String, Future<void>>{};
  final _errors = <String>{};
  DecodeRequest _request = DecodeRequest();
  Timer? _debounce;
  ArchiveContext? _context;
  Object? _selected;
  Object? _indexOptions;
  int _searchVersion = 0;
  Set<String>? _filteredIds;
  final _searchCollapsed = <String>{};
  bool _searching = false;
  bool _searchLimited = false;
  List<(_DirectoryNode, int)>? _visibleRows;

  Object get _selection => (
    widget.controller.currentEntry?.id,
    widget.controller.currentDirectoryPath,
    widget.controller.navigationLocations
        .map((location) => location.path)
        .join('/'),
  );

  Object get _options => (
    widget.controller.sortOrder,
    widget.controller.archiveSortOrder,
    widget.controller.fileNameSortMode,
    widget.controller.scanUnknownExtensions,
    widget.controller.activeBrowseMode,
  );

  _DirectoryNode? get _root {
    final root = widget.controller.directoryRoot;
    return root == null
        ? null
        : _DirectoryNode(
            root.path,
            root.name,
            directory: root.path,
            rootArchive: root.isArchive,
          );
  }

  @override
  void initState() {
    super.initState();
    _context = widget.controller.archiveContext;
    _selected = _selection;
    _indexOptions = _options;
    unawaited(_revealCurrent());
  }

  @override
  void didUpdateWidget(covariant ChapterDirectoryTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    final context = widget.controller.archiveContext;
    final selected = _selection;
    if (!identical(context, _context) || _indexOptions != _options) {
      _context = context;
      _indexOptions = _options;
      _request.cancel();
      _request = DecodeRequest();
      _indices.clear();
      _childrenCache.clear();
      _visibleRows = null;
      _pending.clear();
      _errors.clear();
      _searchVersion++;
      unawaited(_revealCurrent());
      if (_search.text.isNotEmpty) _scheduleSearch(_search.text);
    } else if (selected != _selected) {
      unawaited(_revealCurrent());
    }
    _selected = selected;
  }

  @override
  void dispose() {
    _request.cancel();
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String? _childrenPath(_DirectoryNode node) {
    if (node.images) return null;
    return node.archive == null
        ? node.directory
        : widget.controller.openedArchiveFor(node.archive!)?.extractionRoot;
  }

  List<_DirectoryNode> _children(_DirectoryNode node) {
    final path = _childrenPath(node);
    final index = _indices[path];
    if (path == null || index == null) return const [];
    return _childrenCache.putIfAbsent(
      path,
      () => [
        if (index.images.isNotEmpty &&
            (index.childFolders.isNotEmpty || index.containers.isNotEmpty))
          _DirectoryNode('images:$path', '', directory: path, images: true),
        for (final folder in index.childFolders.where(
          (_) =>
              widget.controller.isArchiveView ||
              widget.controller.browseMode.isRecursive,
        ))
          _DirectoryNode(
            folder.directory.path,
            folder.name,
            directory: folder.directory.path,
            hasChildren: folder.hasNavigableChildren,
          ),
        for (final archive in index.containers)
          _DirectoryNode(
            archive.id,
            archive.name,
            archive: archive,
            parent: path,
          ),
      ],
    );
  }

  Future<void> _load(_DirectoryNode node) {
    final path = _childrenPath(node);
    if (path == null || _indices.containsKey(path)) return Future.value();
    return _pending[path] ??= _read(path);
  }

  Future<void> _read(String path) async {
    final request = _request;
    try {
      final index = await widget.controller.listNavigationDirectory(
        path,
        request: request,
      );
      if (mounted && identical(request, _request) && !request.cancelled) {
        void update() {
          _indices[path] = index;
          _childrenCache.remove(path);
          _visibleRows = null;
          _errors.remove(path);
        }

        if (_searching) {
          update();
        } else {
          setState(update);
        }
      }
    } on DecodeCancelled {
      // Closing or replacing a tree cancels its metadata work.
    } catch (_) {
      if (mounted && identical(request, _request)) {
        setState(() => _errors.add(path));
      }
    } finally {
      if (identical(request, _request)) _pending.remove(path);
    }
  }

  Future<void> _revealCurrent() async {
    final root = _root;
    if (root == null) return;
    final request = _request;
    final ancestors = {
      ...widget.controller.navigationLocations.map(
        (location) => paths.normalize(location.path),
      ),
      if (widget.controller.currentDirectoryPath case final path?)
        paths.normalize(path),
    };
    Future<void> reveal(_DirectoryNode node) async {
      final path = _childrenPath(node);
      if (path == null ||
          (node.id != root.id &&
              !widget.expandedPaths.contains(node.id) &&
              !ancestors.contains(paths.normalize(path)))) {
        return;
      }
      widget.expandedPaths.add(node.id);
      await _load(node);
      if (!mounted || request.cancelled) return;
      for (final child in _children(node)) {
        await reveal(child);
      }
    }

    await reveal(root);
    if (!mounted || request.cancelled) return;
    setState(() => _visibleRows = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _filteredIds != null) return;
      final rows = _rows();
      final index = rows.indexWhere((row) => _isSelected(row.$1));
      if (index >= 0) {
        _scroll.jumpTo(
          (index * 36 - _scroll.position.viewportDimension / 3).clamp(
            0.0,
            _scroll.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  List<(_DirectoryNode, int)> _rows() {
    if (_visibleRows case final cached?) return cached;
    final rows = <(_DirectoryNode, int)>[];
    void append(_DirectoryNode node, int depth) {
      if (_filteredIds != null && !_filteredIds!.contains(node.id)) return;
      rows.add((node, depth));
      if (_isExpanded(node)) {
        for (final child in _children(node)) {
          append(child, depth + 1);
        }
      }
    }

    if (_root case final root?) append(root, 0);
    return _visibleRows = rows;
  }

  bool _isSelected(_DirectoryNode node) {
    final directory = node.archive == null
        ? node.directory
        : widget.controller.openedArchiveFor(node.archive!)?.extractionRoot;
    final current = widget.controller.currentDirectoryPath;
    if (directory == null ||
        current == null ||
        !paths.equals(directory, current)) {
      return false;
    }
    return node.images || !_children(node).any((child) => child.images);
  }

  void _scheduleSearch(String text) {
    _debounce?.cancel();
    final version = ++_searchVersion;
    if (text.trim().isEmpty) {
      setState(() {
        _filteredIds = null;
        _visibleRows = null;
        _searchCollapsed.clear();
        _searching = false;
        _searchLimited = false;
      });
      return;
    }
    setState(() {
      _searchCollapsed.clear();
      _visibleRows = null;
      _searching = true;
      _searchLimited = false;
    });
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_runSearch(text.trim().toLowerCase(), version)),
    );
  }

  Future<void> _runSearch(String query, int version) async {
    final root = _root;
    if (root == null) return;
    final queue = <_DirectoryNode>[root];
    final parents = <String, String>{};
    final visible = <String>{};
    var limited = false;
    for (var index = 0; index < queue.length; index++) {
      if (index >= 1000) {
        limited = true;
        break;
      }
      final node = queue[index];
      await _load(node);
      if (!mounted || version != _searchVersion) return;
      for (final child in _children(node)) {
        parents[child.id] = node.id;
        final label = _displayPath(child).toLowerCase();
        if (!child.images && label.contains(query)) {
          String? ancestor = child.id;
          while (ancestor != null && visible.add(ancestor)) {
            ancestor = parents[ancestor];
          }
        }
        if (!child.images &&
            child.hasChildren != false &&
            _childrenPath(child) != null) {
          queue.add(child);
        }
      }
      // Cached metadata still yields to input/paint during large searches.
      if (index % 32 == 31) {
        await Future<void>.delayed(Duration.zero);
        if (!mounted || version != _searchVersion) return;
      }
    }
    if (mounted && version == _searchVersion) {
      setState(() {
        _filteredIds = visible;
        _visibleRows = null;
        _searchCollapsed.clear();
        _searching = false;
        _searchLimited = limited;
      });
    }
  }

  String _displayPath(_DirectoryNode node) => node.archive == null
      ? widget.controller.directoryDisplayPath(node.directory!)
      : '${widget.controller.directoryDisplayPath(node.parent!)}/${node.name}';

  Future<void> _toggle(_DirectoryNode node) async {
    if (_filteredIds != null) {
      setState(() {
        if (!_searchCollapsed.remove(node.id)) _searchCollapsed.add(node.id);
        _visibleRows = null;
      });
      if (_isExpanded(node)) await _load(node);
      return;
    }
    if (widget.expandedPaths.remove(node.id)) {
      setState(() => _visibleRows = null);
      return;
    }
    setState(() {
      widget.expandedPaths.add(node.id);
      _visibleRows = null;
    });
    await _load(node);
  }

  bool _isExpanded(_DirectoryNode node) => _filteredIds != null
      ? !_searchCollapsed.contains(node.id)
      : widget.expandedPaths.contains(node.id);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = ViewerThemeTokens.of(context);
    final rows = _rows();
    final root = _root;
    final leaf =
        root != null &&
        rows.length == 1 &&
        _indices.containsKey(_childrenPath(root)) &&
        _children(root).isEmpty &&
        !_errors.contains(_childrenPath(root)) &&
        _pending.isEmpty &&
        !_searching &&
        _filteredIds == null;
    return Material(
      key: const ValueKey('directory.panel'),
      // DirectoryPanelRegion owns the docked or frosted background.
      type: MaterialType.transparency,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                if (!widget.controller.isArchiveView &&
                    widget.controller.parentFolderPath != null)
                  AppIconButton(
                    key: const ValueKey('directory.parent'),
                    icon: FluentIcons.arrow_up_20_regular,
                    tooltip: l10n.parentFolder,
                    size: 32,
                    iconSize: 18,
                    onPressed: widget.onOpenParent == null
                        ? null
                        : () => unawaited(
                            widget.onOpenParent!(
                              widget.controller.parentFolderPath!,
                            ),
                          ),
                  ),
                Expanded(
                  child: Text(
                    widget.controller.directoryRoot?.isArchive == true
                        ? l10n.chapterDirectory
                        : l10n.browseDirectory,
                    style: AppTextStyles.compactTitle,
                  ),
                ),
                AppIconButton(
                  key: const ValueKey('directory.pin'),
                  icon: widget.pinned
                      ? FluentIcons.pin_20_filled
                      : FluentIcons.pin_20_regular,
                  tooltip: widget.pinned
                      ? l10n.unpinDirectory
                      : l10n.pinDirectory,
                  color: widget.pinned ? tokens.accent : null,
                  onPressed: widget.onTogglePinned,
                  size: 32,
                  iconSize: 18,
                ),
                AppIconButton(
                  key: const ValueKey('directory.close'),
                  icon: FluentIcons.dismiss_20_regular,
                  tooltip: l10n.close,
                  onPressed: widget.onClose,
                  size: 32,
                  iconSize: 18,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: AppInput(
              key: const ValueKey('directory.search'),
              focusNode: widget.searchFocusNode,
              controller: _search,
              enabled: root != null,
              hint: l10n.searchDirectory,
              leadingIcon: FluentIcons.search_20_regular,
              onChanged: _scheduleSearch,
              clearable: true,
              clearTooltip: l10n.clearDirectorySearch,
            ),
          ),
          if (_searching) const LinearProgressIndicator(minHeight: 2),
          if (_searchLimited)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                l10n.recursiveScanLimit,
                style: AppTextStyles.caption.copyWith(color: tokens.warning),
              ),
            ),
          if (_errors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                l10n.directoryReadFailed,
                style: AppTextStyles.caption.copyWith(color: tokens.warning),
              ),
            ),
          if (_filteredIds != null && !_searching && rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l10n.noMatchingDirectory),
            ),
          Expanded(
            child: root == null
                ? Padding(
                    key: const ValueKey('directory.empty'),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.directoryNotOpened,
                          style: AppTextStyles.body.copyWith(
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.directoryNotOpenedDescription,
                          style: AppTextStyles.caption.copyWith(
                            color: tokens.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        AppButton(
                          label: l10n.openFolder,
                          onPressed: widget.onChooseFolder,
                          variant: AppButtonVariant.neutral,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    key: const ValueKey('directory.rows'),
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    itemExtent: 36,
                    itemCount: rows.length + (leaf ? 1 : 0),
                    itemBuilder: (context, index) => index == rows.length
                        ? Padding(
                            key: const ValueKey('directory.noChildren'),
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              l10n.directoryNoChildren,
                              style: AppTextStyles.caption.copyWith(
                                color: tokens.textTertiary,
                              ),
                            ),
                          )
                        : _buildRow(rows[index].$1, rows[index].$2, l10n),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(_DirectoryNode node, int depth, AppLocalizations l10n) {
    final tokens = ViewerThemeTokens.of(context);
    final path = _childrenPath(node);
    final selected = _isSelected(node);
    final archiveState = node.archive == null
        ? null
        : widget.controller.archiveStateForEntry(node.archive!);
    final knownLeaf =
        node.hasChildren == false ||
        (path != null && _indices.containsKey(path) && _children(node).isEmpty);
    final canExpand = path != null && !node.images && !knownLeaf;
    final label = node.images ? l10n.directoryImages : node.name;
    final error = archiveState?.failure;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: error == null
            ? _displayPath(node)
            : localizedArchiveFailure(l10n, error),
        child: Semantics(
          selected: selected,
          button: true,
          child: AppInteractiveSurface(
            key: ValueKey('directory.item:${node.id}'),
            selected: selected,
            radius: 4,
            onTap: archiveState?.isOpening == true
                ? null
                : () {
                    if (node.archive case final entry?) {
                      final opened = widget.controller.openedArchiveFor(entry);
                      if (opened == null) {
                        unawaited(widget.onOpenArchive(entry));
                      } else {
                        unawaited(widget.onOpenFolder(opened.extractionRoot));
                      }
                    } else {
                      unawaited(widget.onOpenFolder(node.directory!));
                    }
                  },
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  SizedBox(width: math.min(depth, 6) * 14.0),
                  if (canExpand)
                    AppIconButton(
                      key: ValueKey('directory.expand:${node.id}'),
                      size: 28,
                      iconSize: 14,
                      icon: _isExpanded(node)
                          ? FluentIcons.chevron_down_16_regular
                          : FluentIcons.chevron_right_16_regular,
                      tooltip: label,
                      onPressed: () => unawaited(_toggle(node)),
                    )
                  else
                    const SizedBox(width: 28),
                  if (archiveState?.isOpening == true)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  else
                    Icon(
                      error != null
                          ? FluentIcons.warning_20_regular
                          : node.images
                          ? FluentIcons.image_20_regular
                          : node.archive != null || node.rootArchive
                          ? FluentIcons.archive_20_regular
                          : FluentIcons.folder_20_regular,
                      size: 16,
                      color: error != null
                          ? tokens.warning
                          : selected
                          ? tokens.accentStrong
                          : tokens.textSecondary,
                    ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall,
                    ),
                  ),
                  if (selected)
                    Icon(
                      FluentIcons.checkmark_16_regular,
                      size: 14,
                      color: tokens.accentStrong,
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

class _DirectoryNode {
  const _DirectoryNode(
    this.id,
    this.name, {
    this.directory,
    this.archive,
    this.parent,
    this.images = false,
    this.rootArchive = false,
    this.hasChildren,
  });
  final String id;
  final String name;
  final String? directory;
  final ImageEntry? archive;
  final String? parent;
  final bool images;
  final bool rootArchive;
  final bool? hasChildren;
}
