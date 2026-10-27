import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as paths;

import '../domain/archive_context.dart';
import '../domain/archive_failure.dart';
import '../domain/archive_open_state.dart';
import '../domain/folder_browse_mode.dart';
import '../domain/folder_entry.dart';
import '../domain/folder_index_result.dart';
import '../domain/image_entry.dart';
import '../domain/reading_state.dart';
import '../domain/viewer_settings.dart';
import '../domain/viewer_location.dart';
import 'app_config_store.dart';
import 'reading_state_store.dart';
import 'archive_service.dart';
import 'archive_image_source.dart';
import 'archive_index.dart';
import 'decode_request.dart';
import 'folder_change_watcher.dart';
import 'folder_index_service.dart';
import 'format_detector.dart';
import 'recent_open_store.dart';

enum ArchiveOpenOutcome { opened, empty, failed, cancelled }

class ViewerController extends ChangeNotifier {
  ViewerController({
    FolderIndexService? indexService,
    AppConfigStore? configStore,
    ArchiveService? archiveService,
    ReadingStateStore? readingStates,
    FolderChangeWatcher? folderChangeWatcher,
  }) : _indexService = indexService ?? FolderIndexService(),
       _configStore = configStore ?? AppConfigStore(),
       readingStates =
           readingStates ?? ReadingStateStore(configStore ?? AppConfigStore()),
       _archiveService = archiveService ?? ArchiveService(),
       _folderWatcher = folderChangeWatcher ?? FolderChangeWatcher() {
    _folderWatcher
      ..onChanged = _handleFolderChangeBatch
      ..onError = _handleFolderWatchError;
  }

  final FolderIndexService _indexService;
  final AppConfigStore _configStore;
  final ArchiveService _archiveService;
  final ReadingStateStore readingStates;
  late final RecentOpenStore recentOpen = RecentOpenStore(_configStore);

  String? get readingScopeKey {
    final context = archiveContext;
    if (context != null) {
      if (context.session?.encrypted == true) return null;
      return ReadingStateStore.archiveKey(
        context.archiveFile.path,
        innerPath: context.parent == null ? null : context.displayName,
      );
    }
    return folderPath == null ? null : ReadingStateStore.folderKey(folderPath!);
  }

  String? readingEntryPath(ImageEntry entry) {
    if (archiveContext != null) return entry.relativePath;
    if (folderPath == null) return null;
    return paths.relative(entry.id, from: folderPath!).replaceAll('\\', '/');
  }

  List<ImageEntry> entries = const [];
  List<ImageEntry> containers = const [];
  List<FolderEntry> childFolders = const [];
  String? folderPath;
  String? _folderRootPath;
  String? _archiveLocation;
  String? _navigationPath;
  FolderIndexResult? _navigationIndex;
  final Map<String, FolderIndexResult> _folderNavigationIndices = {};
  int currentIndex = -1;
  bool isIndexing = false;
  String? errorMessage;
  bool indexTruncated = false;
  ScanTruncationReason? truncationReason;
  List<String> skippedFolders = const [];
  FolderScanProgress? scanProgress;
  FolderBrowseMode browseMode = FolderBrowseMode.currentFolder;
  bool scanUnknownExtensions = false;
  bool recentOpenEnabled = true;
  int recentOpenLimit = 20;

  /// Watches the open folder and refreshes the list after external changes.
  /// Disabled keeps the process from touching the file system watcher at all.
  bool watchFolderChanges = false;
  SortOrder sortOrder = SortOrder.nameAscending;
  FileNameSortMode fileNameSortMode = FileNameSortMode.natural;
  ArchiveContext? archiveContext;
  bool archiveContinuousReading = true;
  bool isPreparingArchivePage = false;
  SortOrder archiveSortOrder = SortOrder.nameAscending;
  List<ImageEntry> _originContainers = const [];
  Timer? _archiveReadingTimer;
  Future<void> Function(ImageEntry entry, DecodeRequest request)?
  prepareArchiveEntry;

  ArchiveFailureKind? _lastArchiveFailure;

  final Map<String, ArchiveOpenState> _archiveStates = {};
  int _openGeneration = 0;
  int _optionsGeneration = 0;
  bool _disposed = false;
  DecodeRequest? _indexRequest;
  DecodeRequest? _archiveRequest;
  Future<void> _persistence = Future<void>.value();

  FolderIndexResult? _cachedBaseResult;
  String? _cachedPath;
  FolderBrowseMode? _cachedMode;
  bool? _cachedUnknown;

  final FolderChangeWatcher _folderWatcher;
  static const _ignoredFolderChangeExtensions = <String>{
    'tmp',
    'temp',
    'part',
    'partial',
    'crdownload',
    'download',
    'bak',
    'swp',
    'swo',
    'lock',
    'log',
    'db',
    'db-journal',
    'db-wal',
    'ini',
    'lnk',
    'nfo',
    'txt',
    'json',
    'yaml',
    'yml',
  };

  /// Upper bound for changes accumulated while a refresh is still running.
  static const _maxPendingChanges = 1024;
  final Set<String> _watchPending = <String>{};
  bool _watchOverflowed = false;
  bool _watchRefreshRunning = false;
  bool _windowFocused = true;
  bool _watchUnavailable = false;
  (String, bool)? _watchScope;
  int _watchEpoch = 0;
  final Set<String> _knownFolderPaths = <String>{};
  Timer? _watchRefreshRetry;

  ImageEntry? get currentEntry =>
      currentIndex >= 0 && currentIndex < entries.length
      ? entries[currentIndex]
      : null;

  bool get isArchiveView => archiveContext != null;
  bool get isReadOnlyArchive => archiveContext != null;
  bool get isOpeningArchive =>
      _archiveStates.values.any((state) => state.isOpening);
  ArchiveFailureKind? get lastArchiveFailure => _lastArchiveFailure;

  FolderBrowseMode get _archiveIndexMode => FolderBrowseMode.recursiveFolders;

  FolderBrowseMode get activeBrowseMode =>
      archiveContext == null ? browseMode : _archiveIndexMode;

  List<FolderEntry> get navigationFolders =>
      _navigationIndex?.childFolders ?? childFolders;
  List<ImageEntry> get navigationContainers =>
      _navigationIndex?.containers ?? containers;
  String? get navigationImageDirectory =>
      (_navigationIndex?.images.isNotEmpty ?? false) ? _navigationPath : null;

  String? get currentDirectoryPath {
    final entry = currentEntry;
    if (entry == null) return _archiveLocation ?? folderPath;
    return paths.normalize(
      paths.dirname(
        archiveContext == null
            ? entry.file.path
            : paths.join(archiveContext!.extractionRoot, entry.relativePath),
      ),
    );
  }

  ViewerLocation? get directoryRoot {
    if (_folderRootPath != null) {
      return ViewerLocation(
        path: _folderRootPath!,
        name: paths.basename(_folderRootPath!),
      );
    }
    var context = archiveContext;
    if (context == null) return null;
    while (context!.parent != null) {
      context = context.parent;
    }
    return ViewerLocation(
      path: context.extractionRoot,
      name: context.displayName,
      isArchive: true,
    );
  }

  ArchiveContext? openedArchiveFor(ImageEntry entry) {
    var context = archiveContext;
    while (context != null) {
      if (context.entryId == entry.id ||
          (context.parent == null && context.archiveFile.path == entry.id)) {
        return context;
      }
      context = context.parent;
    }
    return null;
  }

  String directoryDisplayPath(String path) {
    var context = archiveContext;
    while (context != null) {
      if (context.contains(path)) return context.displayPath(path);
      context = context.parent;
    }
    final root = _folderRootPath;
    if (root == null) return '';
    final relative = paths.relative(path, from: root);
    return relative == '.'
        ? paths.basename(root)
        : paths.join(paths.basename(root), relative);
  }

  /// Reads directory metadata only. Unopened inner archives remain opaque.
  Future<FolderIndexResult> listNavigationDirectory(
    String path, {
    DecodeRequest? request,
  }) async {
    request?.throwIfCancelled();
    var context = archiveContext;
    while (context != null) {
      if (context.contains(path) && context.session != null) {
        final relative = paths
            .relative(path, from: context.extractionRoot)
            .replaceAll('\\', '/');
        return archiveIndex(
          context.session!,
          root: context.extractionRoot,
          prefix: relative == '.' ? '' : relative,
          continuous: false,
          sort: archiveSortOrder,
          fileNameSortMode: fileNameSortMode,
        );
      }
      context = context.parent;
    }
    final root = _folderRootPath;
    if (root == null ||
        (!paths.equals(root, path) && !paths.isWithin(root, path))) {
      throw ArgumentError('Directory is outside the reading root');
    }
    final cached = _folderNavigationIndices[paths.normalize(path)];
    if (cached != null) {
      return _indexService.sortResult(
        cached,
        sortOrder,
        FolderBrowseMode.recursiveFolders,
        fileNameSortMode: fileNameSortMode,
      );
    }
    final result = _directFolderIndex(
      await _indexService.indexResult(
        path,
        browseMode: FolderBrowseMode.recursiveFolders,
        sortOrder: sortOrder,
        fileNameSortMode: fileNameSortMode,
        scanUnknownExtensions: scanUnknownExtensions,
        resolveFolderOrder: false,
        request: request,
      ),
      path,
    );
    request?.throwIfCancelled();
    if (!_disposed &&
        _folderRootPath == root &&
        _folderNavigationIndices.length < 128) {
      _folderNavigationIndices[paths.normalize(path)] = result;
      _rememberFolderPaths(result, path);
    }
    return result;
  }

  List<ViewerLocation> get chapterChoices => [
    if (navigationImageDirectory case final path?)
      ViewerLocation(path: path, name: ''),
    for (final folder in navigationFolders)
      ViewerLocation(path: folder.directory.path, name: folder.name),
    for (final archive in navigationContainers)
      ViewerLocation(path: archive.id, name: archive.name, isArchive: true),
  ];

  String? get selectedChapterPath {
    var context = archiveContext;
    while (context != null) {
      final id = context.entryId ?? context.archiveFile.path;
      if (navigationContainers.any((entry) => entry.id == id)) return id;
      context = context.parent;
    }
    if (navigationDirectorySelected) return navigationImageDirectory;
    return navigationFolders
        .where((folder) => isNavigationFolderSelected(folder.directory.path))
        .firstOrNull
        ?.directory
        .path;
  }

  Future<void> openChapter(String path) async {
    final archive = navigationContainers
        .where((entry) => entry.id == path)
        .firstOrNull;
    if (archive != null) {
      await openArchiveEntry(archive);
      return;
    }
    if (archiveContext != null && !archiveContext!.contains(path)) {
      await navigateToFolder(path);
      return;
    }
    final index = await listNavigationDirectory(path);
    await navigateToFolder(
      path,
      preferredFilePath: index.images.firstOrNull?.id,
    );
  }

  bool isNavigationFolderSelected(String path) {
    final entry = currentEntry;
    if (entry == null) return false;
    final context = archiveContext;
    final imagePath = context == null
        ? entry.file.path
        : paths.join(context.extractionRoot, entry.relativePath);
    return paths.equals(path, paths.dirname(imagePath)) ||
        paths.isWithin(path, imagePath);
  }

  bool get navigationDirectorySelected {
    final context = archiveContext;
    final entry = currentEntry;
    return entry != null &&
        paths.equals(
          _navigationPath ?? '',
          paths.dirname(
            context == null
                ? entry.file.path
                : paths.join(context.extractionRoot, entry.relativePath),
          ),
        );
  }

  List<ViewerLocation> get navigationLocations {
    final result = <ViewerLocation>[];
    void appendDirectories(String root, String target) {
      if (!paths.equals(root, target) && !paths.isWithin(root, target)) return;
      var path = root;
      final relative = paths.relative(target, from: root);
      if (relative == '.') return;
      for (final part in paths.split(relative)) {
        path = paths.join(path, part);
        result.add(ViewerLocation(path: path, name: part));
      }
    }

    void appendArchive(ArchiveContext context, String target) {
      final parent = context.parent;
      if (parent != null) {
        appendArchive(
          parent,
          context.parentEntryDirectory ??
              context.parentFolderPath ??
              parent.extractionRoot,
        );
      }
      result.add(
        ViewerLocation(
          path: context.extractionRoot,
          name: context.displayName.split('/').last,
          isArchive: true,
        ),
      );
      appendDirectories(context.extractionRoot, target);
    }

    final context = archiveContext;
    if (context != null) {
      if (_folderRootPath case final root?) {
        var outer = context;
        while (outer.parent != null) {
          outer = outer.parent!;
        }
        result.add(ViewerLocation(path: root, name: paths.basename(root)));
        appendDirectories(root, outer.archiveFile.parent.path);
      }
      appendArchive(context, _navigationPath ?? context.extractionRoot);
    } else if (_folderRootPath != null && folderPath != null) {
      result.add(
        ViewerLocation(
          path: _folderRootPath!,
          name: paths.basename(_folderRootPath!),
        ),
      );
      appendDirectories(_folderRootPath!, _navigationPath ?? folderPath!);
    }
    return result;
  }

  bool get hasFolderNavigation {
    if (archiveContext == null &&
        !browseMode.isRecursive &&
        !isOpeningArchive) {
      return false;
    }
    final enabled =
        activeBrowseMode.isRecursive ||
        navigationContainers.isNotEmpty ||
        archiveContext != null ||
        isOpeningArchive;
    return enabled &&
        (isOpeningArchive ||
            (archiveContext != null && _folderRootPath != null) ||
            parentFolderPath != null ||
            navigationFolders.isNotEmpty ||
            navigationContainers.isNotEmpty ||
            indexTruncated ||
            skippedFolders.isNotEmpty ||
            isIndexing);
  }

  ArchiveOpenState archiveStateFor(File file) =>
      _archiveStates[file.path] ?? const ArchiveOpenState();
  ArchiveOpenState archiveStateForEntry(ImageEntry entry) =>
      _archiveStates[entry.id] ?? const ArchiveOpenState();

  String? get parentFolderPath {
    final current = folderPath;
    if (current == null) return null;
    final context = archiveContext;
    if (context != null) {
      final normalizedCurrent = paths.normalize(_archiveLocation ?? current);
      final normalizedRoot = paths.normalize(context.extractionRoot);
      if (paths.equals(normalizedCurrent, normalizedRoot)) {
        return context.parent == null ? null : context.parentFolderPath;
      }
      return Directory(normalizedCurrent).parent.path;
    }
    if (_folderRootPath == null || paths.equals(current, _folderRootPath!)) {
      return null;
    }
    final parent = Directory(current).parent.path;
    final normalizedPath = current.replaceAll('\\', '/').toLowerCase();
    final normalizedParent = parent.replaceAll('\\', '/').toLowerCase();
    return normalizedPath == normalizedParent ? null : parent;
  }

  String displayPathFor(ImageEntry entry) {
    final context = archiveContext;
    if (context != null && entry.source != null) {
      return '${context.displayName}/${entry.relativePath}';
    }
    if (context != null && context.contains(entry.id)) {
      return context.displayPath(entry.id);
    }
    return entry.file.absolute.path;
  }

  Future<void> sweepStaleArchives() => _archiveService.sweepStale();

  Future<void> flushPersistence() async {
    await _writeArchiveReadingState().catchError((Object _) {});
    await _persistence;
  }

  Future<bool> restoreRecentFolder() async {
    try {
      return await _restoreRecentFolder();
    } catch (_) {
      // An invalid or inaccessible remembered path is optional startup state.
      return false;
    }
  }

  Future<bool> _restoreRecentFolder() async {
    final config = await _configStore.readOrEmpty();
    final session = _asMap(config['session']);
    final recentPath = session['recentReadingPath'];
    if (recentPath is String && await File(recentPath).exists()) {
      final outcome = await openArchive(File(recentPath));
      if (outcome == ArchiveOpenOutcome.opened) return true;
    }
    final path = session['recentFolder'];
    if (path is String && await Directory(path).exists()) {
      await openFolder(path);
      return true;
    }
    return false;
  }

  Future<List<RecentOpenEntry>> loadRecentOpen() =>
      recentOpen.load(limit: recentOpenLimit);

  Future<void> clearRecentOpen() async {
    await _persistence;
    await recentOpen.clear();
  }

  Future<void> recordRecentImage(String path) =>
      _recordRecent(path, RecentOpenKind.image);

  Future<void> _recordRecent(String path, RecentOpenKind kind) {
    _persistence = _persistence
        .then((_) async {
          if (!recentOpenEnabled) return;
          await recentOpen.record(path, kind, limit: recentOpenLimit);
        })
        .catchError((Object _) {});
    return _persistence;
  }

  Future<void> setOptions({
    SortOrder? sortOrder,
    FileNameSortMode? fileNameSortMode,
    FolderBrowseMode? browseMode,
    bool? scanUnknownExtensions,
    bool? watchFolderChanges,
  }) async {
    final sortChanged = sortOrder != null && this.sortOrder != sortOrder;
    final nameModeChanged =
        fileNameSortMode != null && this.fileNameSortMode != fileNameSortMode;
    final modeChanged = browseMode != null && this.browseMode != browseMode;
    final unknownChanged =
        scanUnknownExtensions != null &&
        this.scanUnknownExtensions != scanUnknownExtensions;
    final watchChanged =
        watchFolderChanges != null &&
        this.watchFolderChanges != watchFolderChanges;
    if (!sortChanged &&
        !nameModeChanged &&
        !modeChanged &&
        !unknownChanged &&
        !watchChanged) {
      return;
    }
    final generation = ++_optionsGeneration;
    final selectedPath = currentEntry?.id;
    if (sortOrder != null) this.sortOrder = sortOrder;
    if (fileNameSortMode != null) this.fileNameSortMode = fileNameSortMode;
    if (browseMode != null) this.browseMode = browseMode;
    if (scanUnknownExtensions != null) {
      this.scanUnknownExtensions = scanUnknownExtensions;
    }
    if (watchFolderChanges != null) {
      this.watchFolderChanges = watchFolderChanges;
    }
    if (watchChanged) _syncFolderWatch();
    if (!sortChanged && !nameModeChanged && !modeChanged && !unknownChanged) {
      return;
    }
    if (sortChanged || nameModeChanged) _resortFolderNavigation();
    await _persistOptions(
      sortChanged: sortChanged,
      nameModeChanged: nameModeChanged,
      modeChanged: modeChanged,
      unknownChanged: unknownChanged,
    );
    if (_disposed || generation != _optionsGeneration) return;
    final path = folderPath;
    if (path == null) return;
    if (archiveContext?.session != null) {
      if (nameModeChanged) {
        _navigateArchiveDirectory(
          _archiveLocation ?? path,
          selectedId: selectedPath,
        );
      }
      return;
    }
    if (modeChanged || unknownChanged) {
      if (unknownChanged) _folderNavigationIndices.clear();
      final target = this.browseMode.isFlat
          ? _folderRootPath ?? path
          : selectedPath == null
          ? path
          : paths.dirname(selectedPath);
      await openFolder(
        target,
        preferredFilePath: selectedPath,
        keepArchiveContext: archiveContext != null,
        persistRecent: false,
        establishRoot: false,
      );
      return;
    }
    if (sortChanged || nameModeChanged) {
      final mode = activeBrowseMode;
      final expectedUnknown =
          archiveContext != null || this.scanUnknownExtensions;
      final base = _cachedBaseResult;
      if (base != null &&
          _cachedPath == path &&
          _cachedMode == mode &&
          _cachedUnknown == expectedUnknown) {
        _replaceEntries(
          _indexService.sortResult(
            base,
            this.sortOrder,
            mode,
            fileNameSortMode: this.fileNameSortMode,
          ),
          selectedPath,
        );
        if (!_disposed) notifyListeners();
      } else {
        await openFolder(
          path,
          preferredFilePath: selectedPath,
          keepArchiveContext: archiveContext != null,
          persistRecent: false,
          establishRoot: false,
        );
      }
    }
  }

  void configureOptions({
    required SortOrder sortOrder,
    FileNameSortMode fileNameSortMode = FileNameSortMode.natural,
    required FolderBrowseMode browseMode,
    required bool scanUnknownExtensions,
    bool watchFolderChanges = false,
    bool recentOpenEnabled = true,
    int recentOpenLimit = 20,
  }) {
    this.sortOrder = sortOrder;
    this.fileNameSortMode = fileNameSortMode;
    this.browseMode = browseMode;
    this.scanUnknownExtensions = scanUnknownExtensions;
    this.watchFolderChanges = watchFolderChanges;
    this.recentOpenEnabled = recentOpenEnabled;
    this.recentOpenLimit = recentOpenLimit;
  }

  Future<void> openFolder(
    String path, {
    String? preferredFilePath,
    bool keepArchiveContext = false,
    bool persistRecent = true,
    bool recordRecentOpen = true,
    bool establishRoot = true,
  }) async {
    if (_disposed) return;
    if (keepArchiveContext &&
        archiveContext?.session != null &&
        archiveContext!.contains(path)) {
      // Refreshing the flattened reading root must preserve the chapter being
      // browsed. Explicit directory navigation uses navigateToFolder instead.
      final location =
          preferredFilePath != null &&
              preferredFilePath == currentEntry?.id &&
              paths.equals(path, folderPath ?? '')
          ? _archiveLocation ?? path
          : path;
      _navigateArchiveDirectory(location, selectedId: preferredFilePath);
      return;
    }
    final targetArchive =
        keepArchiveContext && archiveContext?.contains(path) == true
        ? archiveContext
        : null;
    final leavingArchive = archiveContext != null && targetArchive == null;
    final generation = ++_openGeneration;
    _indexRequest?.cancel();
    _archiveRequest?.cancel();
    _archiveStates.updateAll(
      (_, state) => state.isOpening ? const ArchiveOpenState() : state,
    );
    final request = DecodeRequest();
    _indexRequest = request;
    isIndexing = true;
    errorMessage = null;
    scanProgress = null;
    // Subscribe before enumerating so changes during the initial scan are
    // retained and reconciled after the foreground operation commits.
    if (targetArchive == null) {
      _syncFolderWatch(
        targetPath: browseMode.isRecursive && !establishRoot
            ? _folderRootPath ?? path
            : path,
      );
    }
    notifyListeners();
    try {
      final mode = targetArchive != null ? _archiveIndexMode : browseMode;
      final unknownEnabled = targetArchive != null || scanUnknownExtensions;
      // Always index in file-system order and keep that result as the cache
      // base. Sorting is an in-memory operation, so switching back to folder
      // order does not need another scan.
      final rawIndexed = await _indexService.indexResult(
        path,
        sortOrder: SortOrder.fileSystem,
        browseMode: mode,
        scanUnknownExtensions: unknownEnabled,
        resolveFolderOrder: false,
        request: request,
        onProgress: (progress) {
          if (_disposed || generation != _openGeneration) return;
          scanProgress = progress;
          notifyListeners();
        },
      );
      if (_disposed || generation != _openGeneration) return;
      var selection = preferredFilePath;
      await readingStates.load();
      if (selection == null && targetArchive == null) {
        final remembered =
            readingStates[ReadingStateStore.folderKey(path)]?.entryPath;
        if (remembered != null) selection = paths.join(path, remembered);
      }
      if (selection == null && persistRecent && targetArchive == null) {
        final config = await _configStore.readOrEmpty();
        final session = _asMap(config['session']);
        final remembered = session['recentFile'];
        selection = remembered is String ? remembered : null;
      }
      if (_disposed || generation != _openGeneration) return;
      final indexed = _indexService.sortResult(
        rawIndexed,
        sortOrder,
        mode,
        fileNameSortMode: fileNameSortMode,
      );
      _cachedBaseResult = rawIndexed;
      _cachedPath = path;
      _cachedMode = mode;
      _cachedUnknown = unknownEnabled;
      if (leavingArchive) {
        await _writeArchiveReadingState().catchError((_) {});
        if (_disposed || generation != _openGeneration) return;
        final previous = archiveContext;
        archiveContext = null;
        if (previous != null) unawaited(_closeArchiveChain(previous));
      }
      if (targetArchive == null && (establishRoot || _folderRootPath == null)) {
        _folderRootPath = paths.normalize(path);
        _folderNavigationIndices.clear();
      }
      _applyIndexResult(
        indexed,
        path: path,
        selectedPath: selection,
        persistRecent: persistRecent,
      );
      if (persistRecent) {
        _persistSession('recentFolder', targetArchive?.originFolder ?? path);
        if (targetArchive == null) _persistSession('recentReadingPath', path);
        if (recentOpenEnabled && recordRecentOpen && targetArchive == null) {
          unawaited(_recordRecent(path, RecentOpenKind.folder));
        }
      }
      if (targetArchive == null &&
          establishRoot &&
          browseMode == FolderBrowseMode.recursiveFolders &&
          entries.isEmpty &&
          indexed.images.isNotEmpty) {
        final first = indexed.images.first;
        await openFolder(
          paths.dirname(first.id),
          preferredFilePath: first.id,
          persistRecent: false,
          establishRoot: false,
        );
        return;
      }
      if (targetArchive == null && browseMode.isRecursive) {
        await _refreshFolderNavigation(currentDirectoryPath ?? path);
      }
      notifyListeners();
      if (targetArchive == null && sortOrder == SortOrder.fileSystem) {
        unawaited(_applyFolderOrderAfterScan(generation, path, mode));
      }
    } on DecodeCancelled {
      return;
    } catch (error) {
      if (_disposed || generation != _openGeneration) return;
      errorMessage = error.toString();
    } finally {
      if (!_disposed && generation == _openGeneration) {
        isIndexing = false;
        scanProgress = null;
        _syncFolderWatch();
        if (_watchPending.isNotEmpty || _watchOverflowed) {
          _scheduleFolderRefreshRetry();
        }
        notifyListeners();
      }
    }
  }

  /// Navigates to a folder entry while keeping the archive context when the
  /// target is still inside the active extraction root.
  Future<void> navigateToFolder(
    String path, {
    String? preferredFilePath,
  }) async {
    var context = archiveContext;
    final closing = <ArchiveContext>[];
    String? selectedId;
    while (context != null &&
        !context.contains(path) &&
        context.parent != null) {
      closing.add(context);
      selectedId = context.parentSelectedId;
      context = context.parent;
    }
    if (context != null && context.contains(path)) {
      archiveContext = context;
      _navigateArchiveDirectory(
        path,
        selectedId: preferredFilePath ?? selectedId,
      );
      for (final previous in closing) {
        await previous.session?.close();
      }
      return;
    }
    final root = _folderRootPath;
    if (root == null ||
        (!paths.equals(root, path) && !paths.isWithin(root, path))) {
      return;
    }
    if (browseMode.isFlat) {
      final base = _cachedBaseResult;
      if (base != null &&
          paths.equals(_cachedPath ?? '', root) &&
          _cachedMode == browseMode &&
          _cachedUnknown == scanUnknownExtensions) {
        final indexed = _indexService.sortResult(
          base,
          sortOrder,
          browseMode,
          fileNameSortMode: fileNameSortMode,
        );
        final selected =
            preferredFilePath ??
            indexed.images
                .where(
                  (entry) =>
                      paths.equals(paths.dirname(entry.id), path) ||
                      paths.isWithin(path, entry.id),
                )
                .firstOrNull
                ?.id;
        _applyIndexResult(
          indexed,
          path: root,
          selectedPath: selected,
          persistRecent: false,
        );
        await _refreshFolderNavigation(currentDirectoryPath ?? path);
        return;
      }
      await openFolder(
        root,
        establishRoot: false,
        preferredFilePath: preferredFilePath,
      );
      if (preferredFilePath == null) {
        final index = entries.indexWhere(
          (entry) => paths.isWithin(path, entry.id),
        );
        if (index >= 0) select(index);
      }
      await _refreshFolderNavigation(currentDirectoryPath ?? path);
    } else {
      await openFolder(
        path,
        establishRoot: false,
        preferredFilePath: preferredFilePath,
      );
    }
  }

  Future<ArchiveOpenOutcome> openArchive(File file, {String? password}) =>
      _openArchiveSession(file, password: password);

  Future<ArchiveOpenOutcome> openArchiveEntry(
    ImageEntry entry, {
    String? password,
  }) async {
    final source = entry.source;
    if (source is! ArchiveImageSource) {
      return _openArchiveSession(
        entry.file,
        password: password,
        fromFolder: true,
      );
    }
    var parent = archiveContext;
    while (parent != null && !identical(parent.session, source.session)) {
      parent = parent.parent;
    }
    if (parent == null || _disposed) return ArchiveOpenOutcome.cancelled;
    final generation = ++_openGeneration;
    _archiveRequest?.cancel();
    _indexRequest?.cancel();
    final request = _archiveRequest = DecodeRequest();
    _archiveStates.updateAll(
      (_, state) => state.isOpening ? const ArchiveOpenState() : state,
    );
    _archiveStates[entry.id] = const ArchiveOpenState(
      phase: ArchiveOpenPhase.opening,
    );
    isPreparingArchivePage = true;
    isIndexing = true;
    notifyListeners();
    ArchiveFileLease? lease;
    try {
      if (source.session.depth >= _archiveService.limits.maxDepth) {
        throw const ArchiveOpenException(ArchiveFailureKind.limit);
      }
      lease = await source.session.acquireFile(source.entry, request: request);
      request.throwIfCancelled();
      if (_disposed || generation != _openGeneration) throw DecodeCancelled();
      return await _openArchiveSession(
        lease.file,
        password: password,
        parent: parent,
        parentLease: lease,
        displayName: '${parent.displayName}/${entry.relativePath}',
        stateKey: entry.id,
        parentEntryDirectory: paths.join(
          parent.extractionRoot,
          paths.posix.dirname(entry.relativePath),
        ),
      );
    } on DecodeCancelled {
      await lease?.release();
      if (generation == _openGeneration) {
        _archiveStates[entry.id] = const ArchiveOpenState();
      }
      return ArchiveOpenOutcome.cancelled;
    } catch (error) {
      await lease?.release();
      if (_disposed || generation != _openGeneration) {
        return ArchiveOpenOutcome.cancelled;
      }
      _lastArchiveFailure = error is ArchiveOpenException
          ? error.kind
          : ArchiveFailureKind.io;
      _archiveStates[entry.id] = ArchiveOpenState(
        phase: ArchiveOpenPhase.failed,
        failure: _lastArchiveFailure,
      );
      notifyListeners();
      return ArchiveOpenOutcome.failed;
    } finally {
      if (identical(_archiveRequest, request)) {
        _archiveRequest = null;
        isIndexing = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  Future<ArchiveOpenOutcome> _openArchiveSession(
    File file, {
    String? password,
    ArchiveContext? parent,
    ArchiveFileLease? parentLease,
    String? displayName,
    String? stateKey,
    bool fromFolder = false,
    String? parentEntryDirectory,
  }) async {
    if (_disposed) {
      await parentLease?.release();
      return ArchiveOpenOutcome.cancelled;
    }
    final key = stateKey ?? file.path;
    final generation = ++_openGeneration;
    _indexRequest?.cancel();
    _archiveRequest?.cancel();
    final request = _archiveRequest = DecodeRequest();
    _lastArchiveFailure = null;
    isPreparingArchivePage = false;
    _archiveStates.updateAll(
      (_, state) => state.isOpening ? const ArchiveOpenState() : state,
    );
    _archiveStates[key] = const ArchiveOpenState(
      phase: ArchiveOpenPhase.opening,
    );
    isIndexing = true;
    errorMessage = null;
    notifyListeners();
    ArchiveSession? session;
    var committed = false;
    try {
      session = await _archiveService.open(
        file,
        request: request,
        password: password,
        parent: parent?.session,
        parentLease: parentLease,
        sensitive: parent?.session?.encrypted ?? false,
      );
      request.throwIfCancelled();
      final root = paths.join(
        Directory.systemTemp.path,
        'shenview_virtual_${session.identity}',
      );
      final result = archiveIndex(
        session,
        root: root,
        continuous: archiveContinuousReading,
        sort: archiveSortOrder,
        fileNameSortMode: fileNameSortMode,
      );
      if (result.images.isEmpty &&
          result.containers.isEmpty &&
          result.childFolders.isEmpty) {
        await session.close();
        session = null;
        _lastArchiveFailure = ArchiveFailureKind.empty;
        _archiveStates[key] = const ArchiveOpenState(
          phase: ArchiveOpenPhase.empty,
          failure: ArchiveFailureKind.empty,
        );
        return ArchiveOpenOutcome.empty;
      }
      String? selectedId;
      String initialDirectory = root;
      await readingStates.load();
      final readingKey = ReadingStateStore.archiveKey(
        parent?.archiveFile.path ?? file.path,
        innerPath: parent == null ? null : displayName,
      );
      final readingEntry = session.encrypted
          ? null
          : readingStates[readingKey]?.entryPath;
      if (readingEntry != null) {
        final prefix = paths.posix.dirname(readingEntry);
        final readingIndex = archiveContinuousReading
            ? result
            : archiveIndex(
                session,
                root: root,
                prefix: prefix == '.' ? '' : prefix,
                continuous: false,
                sort: archiveSortOrder,
                fileNameSortMode: fileNameSortMode,
              );
        final remembered = readingIndex.images
            .where((entry) => entry.relativePath == readingEntry)
            .firstOrNull;
        if (remembered != null) {
          selectedId = remembered.id;
          initialDirectory = paths.join(
            root,
            paths.posix.dirname(readingEntry),
          );
        }
      }
      var indexed = result;
      if (archiveContinuousReading) initialDirectory = root;
      if (initialDirectory != root) {
        indexed = archiveIndex(
          session,
          root: root,
          prefix: paths
              .relative(initialDirectory, from: root)
              .replaceAll('\\', '/'),
          continuous: archiveContinuousReading,
          sort: archiveSortOrder,
          fileNameSortMode: fileNameSortMode,
        );
        if (indexed.images.isEmpty &&
            indexed.containers.isEmpty &&
            indexed.childFolders.isEmpty) {
          initialDirectory = root;
          indexed = result;
        }
      }
      final target =
          indexed.images.where((entry) => entry.id == selectedId).firstOrNull ??
          indexed.images.firstOrNull;
      if (target != null) {
        isPreparingArchivePage = true;
        notifyListeners();
        final lease = await target.acquireFile(request: request);
        try {
          await prepareArchiveEntry?.call(target.withFile(lease.file), request);
        } on DecodeCancelled {
          rethrow;
        } on ArchiveOpenException {
          rethrow;
        } catch (_) {
          // Preparation only warms the first image. A corrupt image or codec
          // resource failure must not prevent browsing a readable archive; the
          // selected page renders its own error and other pages remain usable.
        } finally {
          await lease.release();
        }
      }
      request.throwIfCancelled();
      if (_disposed || generation != _openGeneration) throw DecodeCancelled();
      final previous = archiveContext;
      if (previous != null) {
        final historyWrite = _writeArchiveReadingState().catchError((_) {});
        if (parent == null) {
          await historyWrite;
        } else {
          // Entering a nested book keeps its parent session alive. Its
          // reading state is captured before switching to the nested book.
          unawaited(historyWrite);
        }
      }
      if (parent == null && fromFolder) {
        final origin = await listNavigationDirectory(
          file.parent.path,
          request: request,
        );
        _originContainers = origin.containers;
      }
      request.throwIfCancelled();
      if (_disposed || generation != _openGeneration) throw DecodeCancelled();
      archiveContext = ArchiveContext(
        archiveFile: parent?.archiveFile ?? file,
        extractionRoot: root,
        originFolder: parent?.originFolder ?? file.parent.path,
        displayName: displayName ?? paths.basename(file.path),
        session: session,
        parent: parent,
        parentFolderPath: parent == null
            ? null
            : _archiveLocation ?? folderPath,
        parentSelectedId: currentEntry?.id,
        parentEntryDirectory: parentEntryDirectory,
        entryId: key,
      );
      if (parent == null) {
        if (!fromFolder) {
          _folderRootPath = null;
          _folderNavigationIndices.clear();
          _originContainers = const [];
        }
      }
      _cachedBaseResult = indexed;
      _cachedPath = initialDirectory;
      _cachedMode = _archiveIndexMode;
      _cachedUnknown = true;
      _applyIndexResult(
        indexed,
        path: initialDirectory,
        selectedPath: selectedId,
        persistRecent: false,
      );
      final initialEntry = currentEntry;
      _syncArchiveNavigation(
        initialEntry == null
            ? initialDirectory
            : paths.join(root, paths.posix.dirname(initialEntry.relativePath)),
      );
      _archiveStates[key] = ArchiveOpenState(
        phase: ArchiveOpenPhase.ready,
        imageCount: indexed.images.length,
      );
      _persistSession('recentFolder', archiveContext!.originFolder);
      if (parent == null) {
        if (recentOpenEnabled && !archiveContext!.session!.encrypted) {
          unawaited(_recordRecent(file.path, RecentOpenKind.archive));
        }
        _persistSession(
          'recentReadingPath',
          archiveContext!.session!.encrypted
              ? archiveContext!.originFolder
              : file.absolute.path,
        );
      }
      _scheduleArchiveReadingState();
      if (previous != null && !identical(previous, parent)) {
        unawaited(_closeArchiveChain(previous, keep: parent));
      }
      committed = true;
      session = null;
      notifyListeners();
      return ArchiveOpenOutcome.opened;
    } on DecodeCancelled {
      if (generation == _openGeneration) {
        _archiveStates[key] = const ArchiveOpenState();
      }
      return ArchiveOpenOutcome.cancelled;
    } catch (error) {
      if (_disposed || generation != _openGeneration) {
        return ArchiveOpenOutcome.cancelled;
      }
      final kind = error is ArchiveOpenException
          ? error.kind
          : ArchiveFailureKind.io;
      _lastArchiveFailure = kind;
      _archiveStates[key] = ArchiveOpenState(
        phase: ArchiveOpenPhase.failed,
        failure: kind,
      );
      return ArchiveOpenOutcome.failed;
    } finally {
      if (session != null) await session.close();
      if (!committed) {
        await parentLease?.release();
      }
      if (identical(_archiveRequest, request)) _archiveRequest = null;
      if (!_disposed && generation == _openGeneration) {
        isPreparingArchivePage = false;
        isIndexing = false;
        scanProgress = null;
        notifyListeners();
      }
    }
  }

  void cancelArchiveOpen() => _archiveRequest?.cancel();

  void configureArchive(ViewerSettings settings) {
    final wasContinuous = archiveContinuousReading;
    final nameModeChanged = fileNameSortMode != settings.fileNameSortMode;
    final changed =
        archiveContinuousReading != settings.archiveContinuousReading ||
        archiveSortOrder !=
            normalizeArchiveSortOrder(settings.archiveSortOrder) ||
        nameModeChanged;
    archiveContinuousReading = settings.archiveContinuousReading;
    archiveSortOrder = normalizeArchiveSortOrder(settings.archiveSortOrder);
    fileNameSortMode = settings.fileNameSortMode;
    if (nameModeChanged) _resortFolderNavigation();
    _archiveService.configureCache(
      ArchiveCachePolicy(
        directory: _archiveService.cachePolicy.directory,
        persistent: settings.archivePersistCache,
        solidCacheEntries: switch (settings.archivePrefetchMode) {
          ArchivePrefetchMode.off => 0,
          ArchivePrefetchMode.conservative => 1,
          ArchivePrefetchMode.automatic => 3,
        },
        maxBytes: settings.archiveDiskBudgetMiB * 1024 * 1024,
        maxAge: Duration(days: settings.archiveCacheRetentionDays),
      ),
    );
    if (changed && archiveContext?.session != null) {
      var path = _archiveLocation ?? folderPath!;
      final selected = currentEntry;
      if (wasContinuous &&
          !archiveContinuousReading &&
          selected?.source != null) {
        final directory = paths.posix.dirname(selected!.relativePath);
        path = paths.join(
          archiveContext!.extractionRoot,
          directory == '.' ? '' : directory,
        );
      }
      _navigateArchiveDirectory(path, selectedId: selected?.id);
    }
  }

  Future<ArchiveCacheStats> archiveCacheStats() => _archiveService.cacheStats();
  Future<void> clearArchiveCache() => _archiveService.clearCache();

  void _resortFolderNavigation() {
    _folderNavigationIndices.updateAll(
      (path, index) => _indexService.sortResult(
        index,
        sortOrder,
        FolderBrowseMode.recursiveFolders,
        fileNameSortMode: fileNameSortMode,
      ),
    );
    final navigation = _folderNavigationIndices[_navigationPath];
    if (navigation != null) _navigationIndex = navigation;
    if (_originContainers.isNotEmpty) {
      final originPath = paths.normalize(
        paths.dirname(_originContainers.first.id),
      );
      final origin = _folderNavigationIndices[originPath];
      if (origin != null) _originContainers = origin.containers;
    }
  }

  FolderIndexResult _directFolderIndex(FolderIndexResult index, String path) =>
      index.copyWith(
        images: index.images
            .where((entry) => paths.equals(paths.dirname(entry.id), path))
            .toList(),
        containers: index.containers
            .where((entry) => paths.equals(paths.dirname(entry.id), path))
            .toList(),
      );

  Future<void> _refreshFolderNavigation(String location) async {
    final root = _folderRootPath;
    final generation = _openGeneration;
    final selected = currentEntry?.id;
    if (_disposed || archiveContext != null || root == null) return;
    final local = await listNavigationDirectory(location);
    if (_disposed ||
        generation != _openGeneration ||
        selected != currentEntry?.id) {
      return;
    }
    if (!paths.equals(location, root) &&
        local.childFolders.isEmpty &&
        local.containers.isEmpty) {
      await listNavigationDirectory(paths.dirname(location));
    }
    if (_disposed ||
        archiveContext != null ||
        generation != _openGeneration ||
        root != _folderRootPath ||
        selected != currentEntry?.id) {
      return;
    }
    _syncFolderNavigation(location, local);
    notifyListeners();
  }

  void _syncFolderNavigation(String path, FolderIndexResult indexed) {
    path = paths.normalize(path);
    indexed = _directFolderIndex(indexed, path);
    if (!_folderNavigationIndices.containsKey(path) &&
        _folderNavigationIndices.length >= 128) {
      final oldest = _folderNavigationIndices.keys.firstWhere(
        (key) => !paths.equals(key, _folderRootPath ?? ''),
        orElse: () => _folderNavigationIndices.keys.first,
      );
      _folderNavigationIndices.remove(oldest);
    }
    _folderNavigationIndices[path] = indexed;
    final parent = paths.dirname(path);
    final peers = _folderNavigationIndices[parent];
    final showPeers =
        browseMode.isRecursive &&
        !paths.equals(path, _folderRootPath ?? path) &&
        indexed.childFolders.isEmpty &&
        indexed.containers.isEmpty &&
        peers != null;
    _navigationPath = showPeers ? parent : path;
    _navigationIndex = showPeers ? peers : indexed;
  }

  void _syncArchiveNavigation(String location) {
    final context = archiveContext;
    if (context?.session == null) return;
    location = paths.normalize(location);
    _archiveLocation = location;
    FolderIndexResult indexAt(String path) {
      final relative = paths
          .relative(path, from: context!.extractionRoot)
          .replaceAll('\\', '/');
      return archiveIndex(
        context.session!,
        root: context.extractionRoot,
        prefix: relative == '.' ? '' : relative,
        continuous: false,
        sort: archiveSortOrder,
        fileNameSortMode: fileNameSortMode,
      );
    }

    final local = indexAt(location);
    if (context!.parent == null &&
        _folderRootPath != null &&
        local.childFolders.isEmpty &&
        local.containers.isEmpty &&
        paths.equals(location, context.extractionRoot)) {
      final originPath = paths.normalize(context.archiveFile.parent.path);
      final origin = _folderNavigationIndices[originPath];
      if (origin != null) {
        _navigationPath = originPath;
        _navigationIndex = origin;
        return;
      }
    }
    final navigation =
        paths.equals(location, context.extractionRoot) ||
            local.childFolders.isNotEmpty ||
            local.containers.isNotEmpty
        ? location
        : paths.dirname(location);
    _navigationPath = navigation;
    _navigationIndex = paths.equals(navigation, location)
        ? local
        : indexAt(navigation);
  }

  void _navigateArchiveDirectory(String path, {String? selectedId}) {
    final context = archiveContext;
    if (context?.session == null || !context!.contains(path)) return;
    ++_openGeneration;
    _archiveRequest?.cancel();
    _indexRequest?.cancel();
    _archiveStates.updateAll(
      (_, state) => state.isOpening ? const ArchiveOpenState() : state,
    );
    isIndexing = false;
    final raw = paths
        .relative(path, from: context.extractionRoot)
        .replaceAll('\\', '/');
    final prefix = raw == '.' ? '' : raw;
    var indexed = archiveIndex(
      context.session!,
      root: context.extractionRoot,
      prefix: prefix,
      continuous: archiveContinuousReading,
      sort: archiveSortOrder,
      fileNameSortMode: fileNameSortMode,
    );
    var readingPath = path;
    var selection = selectedId ?? currentEntry?.id;
    if (archiveContinuousReading &&
        prefix.isNotEmpty &&
        indexed.images.isNotEmpty) {
      selection =
          selectedId != null &&
              indexed.images.any((entry) => entry.id == selectedId)
          ? selectedId
          : indexed.images.first.id;
      readingPath = context.extractionRoot;
      indexed = archiveIndex(
        context.session!,
        root: context.extractionRoot,
        continuous: true,
        sort: archiveSortOrder,
        fileNameSortMode: fileNameSortMode,
      );
    }
    _cachedBaseResult = indexed;
    _cachedPath = readingPath;
    _cachedMode = _archiveIndexMode;
    _cachedUnknown = true;
    _applyIndexResult(
      indexed,
      path: readingPath,
      selectedPath: selection,
      persistRecent: false,
    );
    _syncArchiveNavigation(path);
    notifyListeners();
    _scheduleArchiveReadingState();
  }

  ImageEntry? adjacentArchive(int direction) {
    final context = archiveContext;
    if (context == null || context.parent != null || _folderRootPath == null) {
      return null;
    }
    final index = _originContainers.indexWhere(
      (entry) => entry.id == context.archiveFile.path,
    );
    final next = index + direction;
    if (index < 0 || next < 0 || next >= _originContainers.length) return null;
    final entry = _originContainers[next];
    return paths.isWithin(_folderRootPath!, entry.file.path) ? entry : null;
  }

  void _scheduleArchiveReadingState() {
    _archiveReadingTimer?.cancel();
    _archiveReadingTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_writeArchiveReadingState().catchError((_) {})),
    );
  }

  Future<void> _writeArchiveReadingState() async {
    final context = archiveContext;
    final entry = currentEntry;
    if (context?.session == null ||
        context!.session!.encrypted ||
        context.parent != null ||
        entry == null) {
      return;
    }
    final key = readingScopeKey!;
    await readingStates.save(
      key,
      ReadingState.fromJson({
        ...?readingStates[key]?.toJson(),
        'entryPath': entry.relativePath,
      }),
    );
  }

  Future<void> _closeArchiveChain(
    ArchiveContext context, {
    ArchiveContext? keep,
  }) async {
    if (identical(context, keep)) return;
    await context.session?.close();
    if (context.parent != null) {
      await _closeArchiveChain(context.parent!, keep: keep);
    }
  }

  void select(int index) {
    if (_disposed ||
        index < 0 ||
        index >= entries.length ||
        index == currentIndex) {
      return;
    }
    currentIndex = index;
    if (archiveContext == null) {
      _persistSession('recentFile', entries[index].id);
      if (browseMode.isRecursive) {
        unawaited(
          _refreshFolderNavigation(currentDirectoryPath!).catchError((_) {}),
        );
      }
    } else {
      _scheduleArchiveReadingState();
      final context = archiveContext!;
      final location = paths.dirname(
        paths.join(context.extractionRoot, entries[index].relativePath),
      );
      if (_archiveLocation == null ||
          !paths.equals(_archiveLocation!, location)) {
        _syncArchiveNavigation(location);
      }
    }
    notifyListeners();
  }

  void move(int offset) {
    if (entries.isEmpty) return;
    select((currentIndex + offset).clamp(0, entries.length - 1));
  }

  void _applyIndexResult(
    FolderIndexResult result, {
    required String path,
    required String? selectedPath,
    required bool persistRecent,
    int? fallbackIndex,
    bool preserveUnchangedEntries = false,
  }) {
    final navigation = result;
    if (archiveContext == null &&
        browseMode == FolderBrowseMode.recursiveFolders) {
      result = _directFolderIndex(result, path);
    }
    final keepEntries =
        preserveUnchangedEntries &&
        paths.equals(folderPath ?? '', path) &&
        _sameFolderImages(entries, result.images);
    folderPath = path;
    if (!keepEntries) entries = List.unmodifiable(result.images);
    containers = List.unmodifiable(result.containers);
    childFolders = List.unmodifiable(result.childFolders);
    if (archiveContext == null) _syncFolderNavigation(path, navigation);
    indexTruncated = result.truncated;
    truncationReason = result.truncationReason;
    skippedFolders = result.skippedFolders;
    scanProgress = null;
    final index = selectedPath == null
        ? -1
        : entries.indexWhere((entry) => entry.id == selectedPath);
    currentIndex = index >= 0
        ? index
        : entries.isEmpty
        ? -1
        : (fallbackIndex ?? 0).clamp(0, entries.length - 1);
    if (persistRecent && archiveContext == null && currentIndex >= 0) {
      _persistSession('recentFile', entries[currentIndex].id);
    }
    _syncFolderWatch();
    if (archiveContext == null) _rememberFolderPaths(navigation, path);
  }

  void _replaceEntries(FolderIndexResult result, String? selectedPath) {
    final navigation = result;
    if (archiveContext == null &&
        browseMode == FolderBrowseMode.recursiveFolders &&
        folderPath != null) {
      result = _directFolderIndex(result, folderPath!);
    }
    entries = List.unmodifiable(result.images);
    containers = List.unmodifiable(result.containers);
    childFolders = List.unmodifiable(result.childFolders);
    if (archiveContext == null && folderPath != null) {
      _syncFolderNavigation(folderPath!, navigation);
    }
    indexTruncated = result.truncated;
    truncationReason = result.truncationReason;
    skippedFolders = result.skippedFolders;
    final index = selectedPath == null
        ? -1
        : entries.indexWhere((entry) => entry.id == selectedPath);
    if (index >= 0) {
      currentIndex = index;
    } else if (currentIndex >= entries.length) {
      currentIndex = entries.isEmpty ? -1 : entries.length - 1;
    }
    if (archiveContext == null &&
        browseMode.isRecursive &&
        currentDirectoryPath != null) {
      unawaited(
        _refreshFolderNavigation(currentDirectoryPath!).catchError((_) {}),
      );
    }
  }

  // Stable lists preserve spread anchors and continuous-reading geometry when
  // a directory notification did not actually change any indexed image.
  bool _sameFolderImages(List<ImageEntry> previous, List<ImageEntry> next) {
    if (previous.length != next.length) return false;
    for (var index = 0; index < previous.length; index++) {
      final a = previous[index];
      final b = next[index];
      if (!paths.equals(a.id, b.id) ||
          a.name != b.name ||
          a.modifiedAt != b.modifiedAt ||
          a.byteLength != b.byteLength ||
          a.format != b.format ||
          a.relativeFolder != b.relativeFolder) {
        return false;
      }
    }
    return true;
  }

  Future<void> _applyFolderOrderAfterScan(
    int generation,
    String path,
    FolderBrowseMode mode,
  ) async {
    final order = await _indexService.folderOrderFor(path);
    if (order == null ||
        _disposed ||
        generation != _openGeneration ||
        _cachedPath != path ||
        _cachedMode != mode) {
      return;
    }
    final base = _cachedBaseResult;
    if (base == null) return;
    final ordered = _indexService.applyFolderOrder(base, order);
    _cachedBaseResult = ordered;
    final selectedPath = currentEntry?.id;
    _replaceEntries(
      _indexService.sortResult(
        ordered,
        sortOrder,
        mode,
        fileNameSortMode: fileNameSortMode,
      ),
      selectedPath,
    );
    notifyListeners();
  }

  /// True while the file system watcher is subscribed to a folder.
  bool get isWatchingFolder => _folderWatcher.isActive;

  /// Pauses folder watching while the window is in the background so a copy
  /// that takes minutes is applied once, when the window returns.
  void setWindowFocused(bool focused) {
    if (_disposed || _windowFocused == focused) return;
    _windowFocused = focused;
    _folderWatcher.setPaused(!focused);
    if (!focused) {
      _watchRefreshRetry?.cancel();
      _watchRefreshRetry = null;
      return;
    }
    if (_watchUnavailable && watchFolderChanges) {
      // A directory mtime cannot detect descendant changes or file overwrites.
      // Reconcile once per focus using the indexer's existing scan limits.
      final target = _watchTargetPath;
      if (target != null) {
        _syncFolderWatch(retry: true);
        _watchPending.add(paths.normalize(target));
        _watchOverflowed = true;
      }
    }
    _folderWatcher.flushNow();
    unawaited(_applyFolderChanges());
  }

  String? get _watchTargetPath {
    if (archiveContext != null) return null;
    final root = _folderRootPath;
    if (root == null) return null;
    return browseMode.isRecursive ? root : folderPath ?? root;
  }

  void _syncFolderWatch({String? targetPath, bool retry = false}) {
    if (_disposed) return;
    final target = targetPath ?? _watchTargetPath;
    final scope = watchFolderChanges && target != null
        ? (paths.normalize(target), browseMode.isRecursive)
        : null;
    if (scope != _watchScope) {
      _watchScope = scope;
      _watchEpoch++;
      _knownFolderPaths.clear();
      _watchPending.clear();
      _watchOverflowed = false;
      _watchUnavailable = false;
      _watchRefreshRetry?.cancel();
      _watchRefreshRetry = null;
    }
    if (!watchFolderChanges || target == null) {
      _folderWatcher.stop();
      _watchPending.clear();
      _watchOverflowed = false;
      _watchRefreshRetry?.cancel();
      _watchRefreshRetry = null;
      return;
    }
    if (_watchUnavailable && !retry) return;
    _watchUnavailable = false;
    _folderWatcher.watch(
      target,
      recursive: browseMode.isRecursive,
      includePath: _isRelevantFolderChange,
    );
  }

  /// Filters changes that cannot change the image list. A copy of unrelated
  /// files therefore never delays or triggers a rescan of a large folder.
  bool _isRelevantFolderChange(String path) {
    // Deleted and moved directories may report isDirectory=false on Windows.
    if (_knownFolderPaths.contains(paths.normalize(path)) ||
        paths.equals(path, _watchScope?.$1 ?? '')) {
      return true;
    }
    final name = paths.basename(path);
    if (name.isEmpty) return false;
    final lower = name.toLowerCase();
    if (lower == 'thumbs.db' ||
        lower == 'desktop.ini' ||
        lower == '.ds_store') {
      return false;
    }
    if (lower.startsWith('~\$') || lower.startsWith('._')) return false;
    final dot = name.lastIndexOf('.');
    // Folders and extensionless files can change the tree itself.
    if (dot <= 0 || dot == name.length - 1) return true;
    final extension = name.substring(dot + 1).toLowerCase();
    if (_ignoredFolderChangeExtensions.contains(extension)) return false;
    return FormatDetector.extensionMap.containsKey(extension) ||
        FormatDetector.archiveExtensions.contains(extension) ||
        scanUnknownExtensions;
  }

  void _handleFolderChangeBatch(FolderChangeBatch batch) {
    if (_disposed || !watchFolderChanges) return;
    _handleDeferredFolderChanges(batch.paths, overflowed: batch.overflowed);
    unawaited(_applyFolderChanges());
  }

  void _handleFolderWatchError(Object error, StackTrace? stackTrace) {
    if (_disposed) return;
    _watchUnavailable = true;
  }

  void _rememberFolderPaths(FolderIndexResult result, String directory) {
    final root = _watchScope?.$1;
    if (root == null) return;
    void remember(String path) {
      path = paths.normalize(path);
      if (!paths.equals(path, root) && !paths.isWithin(root, path)) return;
      if (_knownFolderPaths.contains(path)) return;
      // Keep directory recognition bounded even when visiting many chapters.
      if (_knownFolderPaths.length >=
          FolderIndexService.defaultMaxDirectories * 2) {
        _knownFolderPaths.remove(_knownFolderPaths.first);
      }
      _knownFolderPaths.add(path);
    }

    remember(directory);
    for (final child in result.childFolders) {
      remember(child.directory.path);
    }
    for (final entry in result.images.followedBy(result.containers)) {
      var parent = paths.dirname(entry.id);
      while (paths.isWithin(root, parent)) {
        remember(parent);
        parent = paths.dirname(parent);
      }
    }
  }

  /// Applies the accumulated folder changes with a single quiet rescan.
  Future<void> _applyFolderChanges() async {
    if (_disposed || !watchFolderChanges) return;
    if (!_windowFocused) return;
    if (_watchPending.isEmpty && !_watchOverflowed) return;
    if (isIndexing || _watchRefreshRunning) {
      _scheduleFolderRefreshRetry();
      return;
    }
    if (archiveContext != null) {
      _watchPending.clear();
      _watchOverflowed = false;
      return;
    }
    final root = _folderRootPath;
    final current = folderPath;
    if (root == null || current == null) {
      _watchPending.clear();
      _watchOverflowed = false;
      return;
    }
    _watchRefreshRunning = true;
    try {
      await _runFolderRefresh(root, current);
    } finally {
      _watchRefreshRunning = false;
      if (_watchPending.isNotEmpty || _watchOverflowed) {
        _scheduleFolderRefreshRetry();
      }
    }
  }

  Future<void> _runFolderRefresh(String root, String current) async {
    final generation = _openGeneration;
    final optionsGeneration = _optionsGeneration;
    final watchEpoch = _watchEpoch;
    final mode = browseMode;
    final unknown = scanUnknownExtensions;
    bool canCommit() =>
        !_disposed &&
        watchFolderChanges &&
        _windowFocused &&
        !isIndexing &&
        archiveContext == null &&
        generation == _openGeneration &&
        optionsGeneration == _optionsGeneration &&
        watchEpoch == _watchEpoch &&
        folderPath == current;
    final overflowed = _watchOverflowed;
    final dirty = <String>{
      for (final path in _watchPending)
        if (paths.equals(path, root) || paths.isWithin(root, path))
          paths.normalize(path),
    };
    _watchPending.clear();
    _watchOverflowed = false;
    void deferChanges() {
      if (_disposed || !watchFolderChanges || watchEpoch != _watchEpoch) return;
      _handleDeferredFolderChanges(dirty, overflowed: overflowed);
    }

    if (dirty.isEmpty && !overflowed) return;
    if (overflowed) {
      _folderNavigationIndices.clear();
    } else {
      for (final path in dirty) {
        _invalidateFolderNavigationPath(path, root);
      }
    }
    final target = paths.normalize(current);
    final affectsListing =
        overflowed || dirty.any((path) => _changeAffectsListing(path, target));
    if (!affectsListing) {
      // A sibling subtree changed: only the directory entries became stale.
      final location = currentDirectoryPath;
      if (location != null) {
        await _refreshFolderNavigation(location).catchError((_) {});
      }
      return;
    }
    // Keep the original path spelling. A watch event uses normalized paths,
    // while a user-opened path can contain mixed separators on Windows.
    final destination = await _refreshDestination(current, root);
    if (!canCommit()) {
      deferChanges();
      return;
    }
    final request = DecodeRequest();
    _indexRequest = request;
    try {
      final raw = await _indexService.indexResult(
        destination,
        sortOrder: SortOrder.fileSystem,
        browseMode: mode,
        scanUnknownExtensions: unknown,
        resolveFolderOrder: false,
        request: request,
      );
      if (!canCommit()) {
        deferChanges();
        return;
      }
      _cachedBaseResult = raw;
      _cachedPath = destination;
      _cachedMode = mode;
      _cachedUnknown = unknown;
      _applyIndexResult(
        _indexService.sortResult(
          raw,
          sortOrder,
          mode,
          fileNameSortMode: fileNameSortMode,
        ),
        path: destination,
        selectedPath: currentEntry?.id,
        fallbackIndex: paths.equals(destination, target) ? currentIndex : null,
        preserveUnchangedEntries: true,
        persistRecent: false,
      );
      notifyListeners();
      if (browseMode.isRecursive) {
        await _refreshFolderNavigation(currentDirectoryPath ?? destination);
      }
      if (sortOrder == SortOrder.fileSystem) {
        unawaited(_applyFolderOrderAfterScan(generation, destination, mode));
      }
    } on DecodeCancelled {
      deferChanges();
    } catch (_) {
      // A background refresh never replaces the view with an error banner.
    } finally {
      if (identical(_indexRequest, request)) _indexRequest = null;
    }
  }

  void _handleDeferredFolderChanges(
    Set<String> dirty, {
    required bool overflowed,
  }) {
    if (_watchPending.length + dirty.length > _maxPendingChanges) {
      _watchPending.clear();
      _watchOverflowed = true;
    } else {
      _watchPending.addAll(dirty);
    }
    _watchOverflowed = _watchOverflowed || overflowed;
  }

  void _scheduleFolderRefreshRetry() {
    if (_disposed || !_windowFocused || !watchFolderChanges) return;
    _watchRefreshRetry?.cancel();
    _watchRefreshRetry = Timer(const Duration(milliseconds: 500), () {
      _watchRefreshRetry = null;
      if (!_disposed) unawaited(_applyFolderChanges());
    });
  }

  /// Drops cached listings for a changed directory and every ancestor so the
  /// folder chips are rebuilt from disk when they are shown again.
  void _invalidateFolderNavigationPath(String path, String root) {
    var current = paths.normalize(path);
    _folderNavigationIndices.removeWhere(
      (key, _) => paths.equals(key, current) || paths.isWithin(current, key),
    );
    while (true) {
      final parent = paths.dirname(current);
      if (paths.equals(parent, current)) return;
      if (!paths.equals(parent, root) && !paths.isWithin(root, parent)) {
        return;
      }
      _folderNavigationIndices.remove(parent);
      if (paths.equals(parent, root)) return;
      current = parent;
    }
  }

  /// A change affects the listing when it happens inside the shown folder, at
  /// the folder itself, or in one of its ancestors (renamed or removed).
  bool _changeAffectsListing(String path, String target) =>
      paths.equals(path, target) ||
      paths.isWithin(target, path) ||
      paths.isWithin(path, target);

  Future<String> _refreshDestination(String target, String root) async {
    if (await Directory(target).exists()) return target;
    final parent = paths.dirname(target);
    if (!paths.equals(parent, target) &&
        (paths.equals(parent, root) || paths.isWithin(root, parent)) &&
        await Directory(parent).exists()) {
      return parent;
    }
    return root;
  }

  Future<void> _persistOptions({
    required bool sortChanged,
    required bool nameModeChanged,
    required bool modeChanged,
    required bool unknownChanged,
  }) {
    return _configStore.update((config) {
      config['schemaVersion'] ??= ViewerSettings.configSchemaVersion;
      final settings = _asMap(config['settings']);
      if (sortChanged) settings['sortOrder'] = sortOrder.name;
      if (nameModeChanged) settings['fileNameSortMode'] = fileNameSortMode.name;
      if (modeChanged) {
        settings['folderBrowseMode'] = browseMode.name;
        if (browseMode.isRecursive) {
          settings['folderContinuousReading'] = browseMode.isFlat;
        }
      }
      if (unknownChanged) {
        settings['scanUnknownExtensions'] = scanUnknownExtensions;
      }
      config['settings'] = settings;
      return config;
    });
  }

  void _persistSession(String key, String value) {
    _persistence = _persistence
        .then((_) async {
          if (_disposed) return;
          if (!recentOpenEnabled && key.startsWith('recent')) return;
          await _configStore.update((config) {
            final settings = config['settings'];
            if (key.startsWith('recent') &&
                settings is Map &&
                settings['recentOpenEnabled'] == false) {
              return config;
            }
            config['schemaVersion'] ??= ViewerSettings.configSchemaVersion;
            final session = _asMap(config['session']);
            session[key] = value;
            config['session'] = session;
            return config;
          });
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _archiveReadingTimer?.cancel();
    _watchRefreshRetry?.cancel();
    _watchRefreshRetry = null;
    _folderWatcher.dispose();
    final context = archiveContext;
    if (context != null) {
      unawaited(_writeArchiveReadingState().catchError((_) {}));
      unawaited(_closeArchiveChain(context));
    }
    _disposed = true;
    _openGeneration++;
    _optionsGeneration++;
    _indexRequest?.cancel();
    _archiveRequest?.cancel();
    super.dispose();
  }
}

Map<String, dynamic> _asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
