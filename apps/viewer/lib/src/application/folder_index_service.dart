import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/folder_browse_mode.dart';
import '../domain/folder_entry.dart';
import '../domain/file_name_comparator.dart';
import '../domain/folder_index_result.dart';
import '../domain/image_entry.dart';
import '../domain/image_format.dart';
import '../domain/sort_order.dart';
import 'decode_request.dart';
import 'folder_order_provider.dart';
import 'format_detector.dart';

class FolderIndexService {
  static const defaultMaxDepth = 3;
  static const defaultMaxImages = 5000;
  static const defaultMaxDirectories = 1000;

  /// Bounded file metadata concurrency. The scan itself runs in a background
  /// isolate, so this only controls how many files are probed at once.
  static const _fileConcurrency = 8;
  static const _folderOrderCacheTtl = Duration(seconds: 5);

  FolderIndexService({FolderOrderProvider? folderOrderProvider})
    : _folderOrderProvider =
          folderOrderProvider ?? const PlatformFolderOrderProvider();
  final FolderOrderProvider _folderOrderProvider;
  final Map<String, _CachedFolderOrder> _folderOrderCache = {};
  final Map<String, Future<List<String>?>> _folderOrderRequests = {};

  Future<List<ImageEntry>> index(
    String folderPath, {
    SortOrder sortOrder = SortOrder.nameAscending,
    FileNameSortMode fileNameSortMode = FileNameSortMode.natural,
    FolderBrowseMode browseMode = FolderBrowseMode.currentFolder,
    bool scanUnknownExtensions = false,
    int maxDepth = defaultMaxDepth,
    int maxImages = defaultMaxImages,
    int maxDirectories = defaultMaxDirectories,
    DecodeRequest? request,
    void Function(FolderScanProgress)? onProgress,
  }) async {
    final result = await indexResult(
      folderPath,
      sortOrder: sortOrder,
      fileNameSortMode: fileNameSortMode,
      browseMode: browseMode,
      scanUnknownExtensions: scanUnknownExtensions,
      maxDepth: maxDepth,
      maxImages: maxImages,
      maxDirectories: maxDirectories,
      request: request,
      onProgress: onProgress,
    );
    return result.images;
  }

  Future<FolderIndexResult> indexResult(
    String folderPath, {
    SortOrder sortOrder = SortOrder.nameAscending,
    FileNameSortMode fileNameSortMode = FileNameSortMode.natural,
    FolderBrowseMode browseMode = FolderBrowseMode.currentFolder,
    bool scanUnknownExtensions = false,
    int maxDepth = defaultMaxDepth,
    int maxImages = defaultMaxImages,
    int maxDirectories = defaultMaxDirectories,
    bool resolveFolderOrder = true,
    DecodeRequest? request,
    void Function(FolderScanProgress)? onProgress,
  }) async {
    request?.throwIfCancelled();
    final directory = Directory(folderPath);
    if (!await directory.exists()) {
      return const FolderIndexResult(
        images: [],
        containers: [],
        childFolders: [],
        truncated: false,
        scannedDirectoryCount: 0,
      );
    }
    final raw = await _scanInIsolate(
      <String, Object?>{
        'root': folderPath,
        'mode': browseMode.name,
        'unknown': scanUnknownExtensions,
        'maxDepth': maxDepth,
        'maxImages': maxImages,
        'maxDirectories': maxDirectories,
      },
      request: request,
      onProgress: onProgress,
    );
    request?.throwIfCancelled();
    final result = sortResult(
      _toResult(raw),
      sortOrder,
      browseMode,
      fileNameSortMode: fileNameSortMode,
    );
    if (sortOrder == SortOrder.fileSystem && resolveFolderOrder) {
      final order = await folderOrderFor(folderPath);
      request?.throwIfCancelled();
      if (order != null) {
        return applyFolderOrder(result, order);
      }
    }
    return result;
  }

  /// Sorts an already indexed result without touching the file system.
  FolderIndexResult sortResult(
    FolderIndexResult result,
    SortOrder sortOrder,
    FolderBrowseMode browseMode, {
    FileNameSortMode fileNameSortMode = FileNameSortMode.natural,
  }) {
    if (sortOrder == SortOrder.fileSystem) return result;
    var images = <ImageEntry>[...result.images];
    if (browseMode.isFlat) {
      final groups = <String, List<ImageEntry>>{};
      final groupOrder = <String>[];
      for (final entry in images) {
        final key = entry.relativeFolder ?? '';
        groups
            .putIfAbsent(key, () {
              groupOrder.add(key);
              return <ImageEntry>[];
            })
            .add(entry);
      }
      final sorted = <ImageEntry>[];
      for (final key in groupOrder) {
        sorted.addAll(
          groups[key]!..sort(_compareImages(sortOrder, fileNameSortMode)),
        );
      }
      images = sorted;
    } else {
      images.sort(_compareImages(sortOrder, fileNameSortMode));
    }
    final containers = <ImageEntry>[...result.containers]
      ..sort(_compareImages(sortOrder, fileNameSortMode));
    final childFolders = <FolderEntry>[...result.childFolders];
    if (sortOrder != SortOrder.sizeAscending &&
        sortOrder != SortOrder.sizeDescending) {
      childFolders.sort(_compareFolders(sortOrder, fileNameSortMode));
    }
    return result.copyWith(
      images: images,
      containers: containers,
      childFolders: childFolders,
    );
  }

  /// Applies the order of the platform folder view. Paths that are not in the
  /// folder view keep their current relative order after the known entries.
  FolderIndexResult applyFolderOrder(
    FolderIndexResult result,
    List<String> orderedPaths,
  ) {
    final images = <ImageEntry>[...result.images];
    final containers = <ImageEntry>[...result.containers];
    final childFolders = <FolderEntry>[...result.childFolders];
    _applyFolderOrder(images, orderedPaths, (entry) => entry.file.path);
    _applyFolderOrder(containers, orderedPaths, (entry) => entry.file.path);
    _applyFolderOrder(
      childFolders,
      orderedPaths,
      (entry) => entry.directory.path,
    );
    return result.copyWith(
      images: images,
      containers: containers,
      childFolders: childFolders,
    );
  }

  Future<List<String>?> folderOrderFor(String folderPath) async {
    final key = _pathKey(folderPath);
    final cached = _folderOrderCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.cachedAt) < _folderOrderCacheTtl) {
      return cached.order;
    }
    final pending = _folderOrderRequests[key];
    if (pending != null) return pending;
    final future = _loadFolderOrder(folderPath, key);
    _folderOrderRequests[key] = future;
    try {
      return await future;
    } finally {
      _folderOrderRequests.remove(key);
    }
  }

  Future<List<String>?> _loadFolderOrder(String folderPath, String key) async {
    try {
      final order = await _folderOrderProvider.orderFor(folderPath);
      _folderOrderCache[key] = _CachedFolderOrder(order, DateTime.now());
      return order;
    } catch (_) {
      // A missing or broken Explorer view must never fail the scan.
      _folderOrderCache[key] = _CachedFolderOrder(null, DateTime.now());
      return null;
    }
  }

  Future<_RawScan> _scanInIsolate(
    Map<String, Object?> scanRequest, {
    DecodeRequest? request,
    void Function(FolderScanProgress)? onProgress,
  }) async {
    request?.throwIfCancelled();
    final messages = ReceivePort();
    final errors = ReceivePort();
    final completion = Completer<_RawScan>();
    Isolate? isolate;
    late StreamSubscription<Object?> messageSubscription;
    late StreamSubscription<Object?> errorSubscription;

    void cancel() {
      isolate?.kill(priority: Isolate.immediate);
      if (!completion.isCompleted) {
        completion.completeError(DecodeCancelled());
      }
    }

    messageSubscription = messages.listen((message) {
      if (message is! List || message.isEmpty) return;
      switch (message[0]) {
        case 0:
          onProgress?.call(
            FolderScanProgress(
              scannedDirectories: message[1] as int,
              foundImages: message[2] as int,
            ),
          );
        case 1:
          if (!completion.isCompleted) {
            completion.complete(_RawScan.fromMessage(message));
          }
        case 2:
          if (!completion.isCompleted) {
            completion.completeError(StateError(message[1] as String));
          }
      }
    });
    errorSubscription = errors.listen((message) {
      if (completion.isCompleted) return;
      final text = message is List && message.isNotEmpty
          ? message.first.toString()
          : message.toString();
      completion.completeError(StateError(text));
    });

    try {
      isolate = await Isolate.spawn(
        _scanWorker,
        (scanRequest, messages.sendPort),
        onError: errors.sendPort,
        errorsAreFatal: true,
      );
      request?.addCancelListener(cancel);
      request?.throwIfCancelled();
      return await completion.future;
    } finally {
      request?.removeCancelListener(cancel);
      isolate?.kill(priority: Isolate.immediate);
      await messageSubscription.cancel();
      await errorSubscription.cancel();
      messages.close();
      errors.close();
    }
  }

  FolderIndexResult _toResult(_RawScan raw) {
    final images = raw.images.map(_toImageEntry).toList(growable: false);
    final containers = raw.containers
        .map(_toImageEntry)
        .toList(growable: false);
    final folders = raw.folders
        .map(
          (record) => FolderEntry(
            directory: Directory(record[0] as String),
            modifiedAt: DateTime.fromMillisecondsSinceEpoch(record[1] as int),
            imageCount: record[2] as int,
            archiveCount: record[3] as int,
            hasNavigableChildren: record[4] as bool?,
          ),
        )
        .toList(growable: false);
    return FolderIndexResult(
      images: images,
      containers: containers,
      childFolders: folders,
      truncated: raw.truncationReason != null,
      scannedDirectoryCount: raw.scannedDirectoryCount,
      truncationReason: raw.truncationReason,
      skippedFolders: raw.skippedFolders,
      headerProbeCount: raw.headerProbeCount,
    );
  }

  ImageEntry _toImageEntry(List<Object?> record) {
    final relative = record[4] as String?;
    return ImageEntry(
      file: File(record[0] as String),
      format: ImageFormat.values[record[1] as int],
      width: null,
      height: null,
      byteLength: record[2] as int,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(record[3] as int),
      relativeFolder: relative == null || relative.isEmpty ? null : relative,
    );
  }

  void _applyFolderOrder<T>(
    List<T> values,
    List<String> orderedPaths,
    String Function(T value) pathOf,
  ) {
    final ranks = <String, int>{};
    for (var index = 0; index < orderedPaths.length; index++) {
      ranks[_pathKey(orderedPaths[index])] = index;
    }
    var fallback = orderedPaths.length;
    final original = <T>[...values];
    final rankOf = <T, int>{};
    for (final value in original) {
      rankOf[value] = ranks[_pathKey(pathOf(value))] ?? fallback++;
    }
    values.sort((left, right) => rankOf[left]!.compareTo(rankOf[right]!));
  }

  String _pathKey(String value) =>
      File(value).absolute.path.replaceAll('\\', '/').toLowerCase();

  int Function(ImageEntry, ImageEntry) _compareImages(
    SortOrder sortOrder,
    FileNameSortMode mode,
  ) {
    return (left, right) {
      if (sortOrder == SortOrder.fileSystem) return 0;
      final name = compareFileNames(left.name, right.name, mode);
      final order = switch (sortOrder) {
        SortOrder.nameAscending => name,
        SortOrder.nameDescending => -name,
        SortOrder.modifiedNewest => right.modifiedAt.compareTo(left.modifiedAt),
        SortOrder.modifiedOldest => left.modifiedAt.compareTo(right.modifiedAt),
        SortOrder.sizeAscending => left.byteLength.compareTo(right.byteLength),
        SortOrder.sizeDescending => right.byteLength.compareTo(left.byteLength),
        SortOrder.fileSystem => 0,
      };
      if (order != 0) return order;
      return name != 0 ? name : left.id.compareTo(right.id);
    };
  }

  int Function(FolderEntry, FolderEntry) _compareFolders(
    SortOrder sortOrder,
    FileNameSortMode mode,
  ) {
    return (left, right) {
      if (sortOrder == SortOrder.fileSystem ||
          sortOrder == SortOrder.sizeAscending ||
          sortOrder == SortOrder.sizeDescending) {
        return 0;
      }
      final name = compareNames(left.name, right.name, mode);
      final order = switch (sortOrder) {
        SortOrder.nameAscending => name,
        SortOrder.nameDescending => -name,
        SortOrder.modifiedNewest => right.modifiedAt.compareTo(left.modifiedAt),
        SortOrder.modifiedOldest => left.modifiedAt.compareTo(right.modifiedAt),
        _ => 0,
      };
      if (order != 0) return order;
      return name != 0
          ? name
          : left.directory.path.compareTo(right.directory.path);
    };
  }
}

class _CachedFolderOrder {
  const _CachedFolderOrder(this.order, this.cachedAt);
  final List<String>? order;
  final DateTime cachedAt;
}

class _RawScan {
  const _RawScan({
    required this.images,
    required this.containers,
    required this.folders,
    required this.truncationReason,
    required this.scannedDirectoryCount,
    required this.skippedFolders,
    required this.headerProbeCount,
  });

  final List<List<Object?>> images;
  final List<List<Object?>> containers;
  final List<List<Object?>> folders;
  final ScanTruncationReason? truncationReason;
  final int scannedDirectoryCount;
  final List<String> skippedFolders;
  final int headerProbeCount;

  static _RawScan fromMessage(List<Object?> message) {
    final reason = message[4] as int;
    return _RawScan(
      images: _records(message[1]),
      containers: _records(message[2]),
      folders: _records(message[3]),
      truncationReason: reason < 0 ? null : ScanTruncationReason.values[reason],
      scannedDirectoryCount: message[5] as int,
      skippedFolders: (message[6] as List).cast<String>(),
      headerProbeCount: message[7] as int,
    );
  }

  static List<List<Object?>> _records(Object? value) => (value as List)
      .map((record) => (record as List).cast<Object?>())
      .toList(growable: false);
}

void _scanWorker((Map<String, Object?>, SendPort) arguments) async {
  final (request, messages) = arguments;
  try {
    final result = await _runScan(
      request,
      (scannedDirectories, foundImages) =>
          messages.send(<Object?>[0, scannedDirectories, foundImages]),
    );
    messages.send(<Object?>[
      1,
      result.images,
      result.containers,
      result.folders,
      result.truncationReason?.index ?? -1,
      result.scannedDirectoryCount,
      result.skippedFolders,
      result.headerProbeCount,
    ]);
  } catch (error) {
    messages.send(<Object?>[2, error.toString()]);
  }
}

Future<_RawScan> _runScan(
  Map<String, Object?> request,
  void Function(int scannedDirectories, int foundImages) sendProgress,
) async {
  final rootPath = request['root'] as String;
  final modeName = request['mode'] as String;
  final mode = FolderBrowseMode.values.firstWhere(
    (value) => value.name == modeName,
    orElse: () => FolderBrowseMode.currentFolder,
  );
  final scanUnknownExtensions = request['unknown'] as bool;
  final maxDepth = request['maxDepth'] as int;
  final maxImages = request['maxImages'] as int;
  final maxDirectories = request['maxDirectories'] as int;

  final detector = FormatDetector();
  final images = <List<Object?>>[];
  final containers = <List<Object?>>[];
  final folders = <List<Object?>>[];
  final skippedFolders = <String>[];
  var scannedDirectories = 0;
  var headerProbes = 0;
  ScanTruncationReason? truncationReason;
  final stopwatch = Stopwatch()..start();
  var lastProgressAt = -1000;

  void reportProgress({bool force = false}) {
    final now = stopwatch.elapsedMilliseconds;
    if (!force && now - lastProgressAt < 100) return;
    lastProgressAt = now;
    sendProgress(scannedDirectories, images.length);
  }

  Future<_DirectoryCounts> visit(
    Directory directory,
    int depth,
    String relativeFolder,
  ) async {
    if (truncationReason == ScanTruncationReason.imageLimit) {
      return const _DirectoryCounts();
    }
    if (images.length >= maxImages) {
      truncationReason ??= ScanTruncationReason.imageLimit;
      return const _DirectoryCounts();
    }
    if (scannedDirectories >= maxDirectories) {
      truncationReason ??= ScanTruncationReason.directoryLimit;
      return const _DirectoryCounts();
    }
    scannedDirectories++;
    List<FileSystemEntity> entries;
    try {
      entries = await directory.list(followLinks: false).toList();
    } on FileSystemException {
      skippedFolders.add(directory.path);
      return const _DirectoryCounts();
    }
    final files = <File>[];
    final directories = <Directory>[];
    for (final entity in entries) {
      if (entity is File) {
        files.add(entity);
      } else if (entity is Directory) {
        directories.add(entity);
      }
    }

    var counts = _DirectoryCounts();
    final records = List<_FileRecord?>.filled(files.length, null);
    await _forEachConcurrent(
      files.length,
      FolderIndexService._fileConcurrency,
      (index) async {
        records[index] = await _inspectFile(
          files[index],
          depth,
          relativeFolder,
          scanUnknownExtensions,
          detector,
          () => headerProbes++,
        );
      },
    );
    for (final record in records) {
      if (record == null) continue;
      if (record.isArchive) {
        counts = counts.addArchives(1);
        if (record.message != null && depth == 0) {
          containers.add(record.message!);
        }
        continue;
      }
      if (images.length >= maxImages) {
        truncationReason ??= ScanTruncationReason.imageLimit;
        break;
      }
      final message = record.message;
      if (message == null) continue;
      images.add(message);
      counts = counts.addImages(1);
    }
    reportProgress();

    if (!mode.isRecursive) {
      return counts;
    }
    for (final child in directories) {
      if (truncationReason == ScanTruncationReason.imageLimit) break;
      if (depth >= maxDepth) {
        if (await _hasCandidate(child, scanUnknownExtensions)) {
          truncationReason ??= ScanTruncationReason.depthLimit;
        }
        continue;
      }
      final name = _baseName(child.path);
      final childRelative = relativeFolder.isEmpty
          ? name
          : '$relativeFolder/$name';
      final childCounts = await visit(child, depth + 1, childRelative);
      counts = counts.add(childCounts);
      if (depth == 0 && mode.isRecursive && childCounts.hasContent) {
        folders.add(<Object?>[
          child.path,
          (await _modifiedAt(child)).millisecondsSinceEpoch,
          childCounts.images,
          childCounts.archives,
          truncationReason == null ? childCounts.hasNavigableChildren : null,
        ]);
      }
    }
    reportProgress();
    return counts;
  }

  await visit(Directory(rootPath), 0, '');
  reportProgress(force: true);
  return _RawScan(
    images: images,
    containers: containers,
    folders: folders,
    truncationReason: truncationReason,
    scannedDirectoryCount: scannedDirectories,
    skippedFolders: skippedFolders,
    headerProbeCount: headerProbes,
  );
}

Future<void> _forEachConcurrent(
  int length,
  int concurrency,
  Future<void> Function(int index) action,
) async {
  if (length == 0) return;
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final index = next++;
      if (index >= length) return;
      await action(index);
    }
  }

  await Future.wait(
    List.generate(math.min(concurrency, length), (_) => worker()),
  );
}

Future<_FileRecord?> _inspectFile(
  File file,
  int depth,
  String relativeFolder,
  bool scanUnknownExtensions,
  FormatDetector detector,
  void Function() onHeaderProbe,
) async {
  final extension = FormatDetector.extensionOf(file.path);
  final byExtension = FormatDetector.formatForPath(file.path);
  final archiveByExtension = FormatDetector.isArchivePath(file.path);

  if (archiveByExtension) {
    if (depth > 0) return const _FileRecord.archiveCountOnly();
    final stat = await _stat(file);
    if (stat == null) return null;
    return _FileRecord.archive(file.path, stat, relativeFolder);
  }

  ImageFormat? format = byExtension;
  var probeHeader = extension == 'png';
  if (format == null) {
    if (!scanUnknownExtensions) return null;
    probeHeader = true;
  }

  if (probeHeader) {
    final bytes = await _readHeader(file);
    if (bytes == null) return null;
    onHeaderProbe();
    final detected = detector.fromFileHeader(bytes, file.path);
    if (detected == ImageFormat.unknown) return null;
    if (detected == ImageFormat.archive) {
      if (depth > 0) return const _FileRecord.archiveCountOnly();
      final stat = await _stat(file);
      if (stat == null) return null;
      return _FileRecord.archive(file.path, stat, relativeFolder);
    }
    format = detected;
  }
  final resolved = format;
  if (resolved == null || resolved == ImageFormat.archive) return null;
  final stat = await _stat(file);
  if (stat == null) return null;
  return _FileRecord.image(file.path, resolved, stat, relativeFolder);
}

Future<FileStat?> _stat(File file) async {
  try {
    return await file.stat();
  } on FileSystemException {
    return null;
  }
}

Future<Uint8List?> _readHeader(File file) async {
  try {
    final bytes = await file
        .openRead(0, 128)
        .fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    return Uint8List.fromList(bytes);
  } on FileSystemException {
    return null;
  }
}

Future<DateTime> _modifiedAt(Directory directory) async {
  try {
    return (await directory.stat()).modified;
  } on FileSystemException {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

Future<bool> _hasCandidate(
  Directory directory,
  bool scanUnknownExtensions, [
  int level = 0,
]) async {
  try {
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is Directory) {
        // Avoid walking an arbitrarily deep tree just to decide whether the
        // depth limit hid any content. Three additional levels are enough to
        // cover normal photo libraries.
        if (level >= 3) return true;
        if (await _hasCandidate(entity, scanUnknownExtensions, level + 1)) {
          return true;
        }
        continue;
      }
      if (entity is! File) continue;
      if (FormatDetector.isKnownPath(entity.path) || scanUnknownExtensions) {
        return true;
      }
    }
  } on FileSystemException {
    return false;
  }
  return false;
}

String _baseName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final trimmed = normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  return trimmed.split('/').last;
}

class _DirectoryCounts {
  const _DirectoryCounts({
    this.images = 0,
    this.archives = 0,
    this.hasNavigableChildren = false,
  });
  final int images;
  final int archives;
  final bool hasNavigableChildren;

  bool get hasContent => images > 0 || archives > 0;

  _DirectoryCounts add(_DirectoryCounts other) => _DirectoryCounts(
    images: images + other.images,
    archives: archives + other.archives,
    hasNavigableChildren: hasNavigableChildren || other.hasContent,
  );

  _DirectoryCounts addImages(int count) => _DirectoryCounts(
    images: images + count,
    archives: archives,
    hasNavigableChildren: hasNavigableChildren,
  );

  _DirectoryCounts addArchives(int count) => _DirectoryCounts(
    images: images,
    archives: archives + count,
    hasNavigableChildren: hasNavigableChildren || count > 0,
  );
}

class _FileRecord {
  _FileRecord.image(
    String path,
    ImageFormat format,
    FileStat stat,
    String relativeFolder,
  ) : this._(
        isArchive: false,
        message: <Object?>[
          path,
          format.index,
          stat.size,
          stat.modified.millisecondsSinceEpoch,
          relativeFolder.isEmpty ? null : relativeFolder,
        ],
      );

  _FileRecord.archive(String path, FileStat stat, String relativeFolder)
    : this._(
        isArchive: true,
        message: <Object?>[
          path,
          ImageFormat.archive.index,
          stat.size,
          stat.modified.millisecondsSinceEpoch,
          relativeFolder.isEmpty ? null : relativeFolder,
        ],
      );

  const _FileRecord.archiveCountOnly() : this._(isArchive: true, message: null);

  const _FileRecord._({required this.isArchive, required this.message});

  final bool isArchive;
  final List<Object?>? message;
}
