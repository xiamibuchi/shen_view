import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../domain/image_entry.dart';
import '../domain/image_format.dart';
import '../domain/image_resource_key.dart';
import 'decode_scheduler.dart';
import 'apng_codec.dart';
import 'avif_codec.dart';
import 'photo_media_codec.dart';
import 'media_container.dart';
import 'indexed_animation_codec.dart';
import 'decoder_registry.dart';
import 'metadata_service.dart';
import 'ico_file.dart';
import 'native_decoder.dart';
import 'hdr_decoder.dart';
import 'hdr_input_metadata.dart';
import 'hdr_frame.dart';
import 'hdr_frame_cache.dart';
import 'hdr_video_worker.dart';
import 'raw_developer.dart';
import 'prefetch_planner.dart';
import 'prefetch_policy.dart';
import 'resource_budget.dart';
import 'decode_fallback.dart';
import 'thumbnail_prefetch_service.dart';
import '../domain/thumbnail_prefetch_mode.dart';

class ImageResourceUnavailable extends StateError {
  ImageResourceUnavailable() : super('当前图像资源不足，请稍后重试。');
}

class ImageResourceService {
  ImageResourceService({
    MetadataService? metadataService,
    NativeDecoder? decoder,
    HdrDecoder? hdrDecoder,
    DecodeScheduler? scheduler,
    AdaptivePrefetchPolicy? prefetchPolicy,
    this.maxMetadataEntries = 512,
  }) : _metadataService = metadataService ?? MetadataService(),
       _decoder = decoder ?? NativeDecoder(),
       _hdrDecoder = hdrDecoder ?? HdrDecoder(decoder: decoder),
       _scheduler = scheduler ?? DecodeScheduler(),
       policy = prefetchPolicy ?? AdaptivePrefetchPolicy() {
    _inflightBudget.onChanged = () {
      scheduleMicrotask(() {
        if (!_disposed) {
          _scheduler.refresh();
          thumbnails.capacityChanged();
          _signalRecovery();
        }
      });
    };
  }

  static const maxDecodedPixels = 16 * 1024 * 1024;
  static const maxEncodedBytes = 128 * 1024 * 1024;
  final int maxMetadataEntries;
  final MetadataService _metadataService;
  final NativeDecoder _decoder;
  final HdrDecoder _hdrDecoder;
  late final _hdrFrames = HdrFrameCache(onChanged: _updateResidentBudget);
  final DecodeScheduler _scheduler;
  final AdaptivePrefetchPolicy policy;
  final _inflightBudget = ResourceBudget(limitBytes: 32 * 1024 * 1024);
  final _requestPriorities = <DecodeRequest, DecodePriority>{};
  final _codecRequests = <ImageResourceKey, DecodeRequest>{};
  final _prefetches = <ImageResourceKey, _PrefetchHandle>{};
  Set<String> _protectedIds = {};
  Set<String>? _retainedIds;
  int? _memoryBudgetOverride;
  final _metadata = <ImageFileVersion, ImageMetadata>{};
  final _icoSelections = <ImageFileVersion, int>{};
  final _metadataPending = <ImageFileVersion, Future<ImageMetadata>>{};
  final _metadataRequests = <ImageFileVersion, DecodeRequest>{};
  final _requests = <DecodeRequest, String>{};
  final _revisions = <String, int>{};
  final _imageKeys = <ImageResourceKey>{};
  final _thumbnailKeys = <ImageResourceKey>{};
  final _rawPreviewRejected = <ImageResourceKey>{};
  final _entries = <String, ImageEntry>{};
  bool _disposed = false;
  final recovery = ValueNotifier<int>(0);
  final _visibleThumbnails = <String, int>{};
  bool _recoveryScheduled = false;
  ThumbnailPrefetchMode _thumbnailMode = ThumbnailPrefetchMode.automatic;
  Set<ImageResourceKey> _plannedThumbnails = {};
  Set<String> _thumbnailCollectionIds = {};
  final _thumbnailLru = <ImageResourceKey, int>{};
  final _failures = <ImageResourceKey, ({Object error, bool speculative})>{};
  Object? _thumbnailCollection;
  List<ImageEntry>? _thumbnailEntries;
  late final thumbnails = ThumbnailPrefetchService(
    version: version,
    load: _prefetchThumbnail,
    isCached: (key) => PaintingBinding.instance.imageCache.containsKey(key),
    onRetainedChanged: (keys) {
      _plannedThumbnails = keys;
      for (final request in _requests.keys.toList()) {
        if (_requestPriorities[request] == DecodePriority.thumbnail &&
            !_codecRequests.entries.any(
              (entry) =>
                  identical(entry.value, request) && keys.contains(entry.key),
            )) {
          request.cancel();
        }
      }
    },
  );

  void configureThumbnails(ThumbnailPrefetchMode mode) {
    _thumbnailMode = mode;
    thumbnails.configure(mode, policy.resourceLevel);
  }

  void setThumbnailCollection(Object collection, List<ImageEntry> entries) {
    if (_thumbnailCollection == collection &&
        identical(_thumbnailEntries, entries)) {
      return;
    }
    _thumbnailCollection = collection;
    _thumbnailEntries = entries;
    _thumbnailCollectionIds = entries.map((entry) => entry.id).toSet();
    thumbnails.setCollection(collection);
    thumbnails.replaceEntries(entries);
    _failures.removeWhere(
      (key, _) => !_thumbnailCollectionIds.contains(key.version.path),
    );
    _trimThumbnails();
  }

  Future<void> _prefetchThumbnail(
    ThumbnailPrefetchTask task,
    DecodeRequest request,
  ) async {
    if (task.entry.format == ImageFormat.svg) return;
    final image = provider(
      task.entry,
      targetWidth: task.key.targetWidth,
      targetHeight: task.key.targetHeight,
      priority: DecodePriority.thumbnail,
      distance: task.distance,
    );
    final stream = image.resolve(ImageConfiguration.empty);
    final done = Completer<void>();
    late final ImageStreamListener listener;
    void cancel() {
      final worker = _codecRequests[task.key];
      if (worker != null &&
          _requestPriorities[worker] == DecodePriority.thumbnail) {
        worker.cancel();
      }
      if (!done.isCompleted) done.completeError(DecodeCancelled());
    }

    listener = ImageStreamListener(
      (info, _) {
        if (!done.isCompleted) done.complete();
      },
      onError: (Object error, StackTrace? stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    request.addCancelListener(cancel);
    try {
      await done.future;
    } on ImageResourceUnavailable {
      throw ThumbnailPrefetchDeferred();
    } finally {
      request.removeCancelListener(cancel);
      stream.removeListener(listener);
      _trimThumbnails();
    }
  }

  void _rememberThumbnail(ImageResourceKey key, ui.Image image) {
    _thumbnailLru.remove(key);
    _thumbnailLru[key] = image.width * image.height * 4;
    _trimThumbnails();
  }

  void _trimThumbnails({bool pressure = false}) {
    final limit = pressure
        ? 0
        : math.min(32 * 1024 * 1024, memoryBudgetBytes ~/ 8);
    var used = _thumbnailLru.values.fold(0, (a, b) => a + b);
    for (final key in _thumbnailLru.keys.toList()) {
      if (_visibleThumbnails.containsKey(key.version.path)) continue;
      if (used <= limit && _thumbnailCollectionIds.contains(key.version.path)) {
        continue;
      }
      used -= _thumbnailLru.remove(key)!;
      PaintingBinding.instance.imageCache.evict(key, includeLive: false);
      _imageKeys.remove(key);
      _thumbnailKeys.remove(key);
    }
  }

  void _signalRecovery() {
    if (_disposed || _recoveryScheduled) return;
    _recoveryScheduled = true;
    scheduleMicrotask(() {
      _recoveryScheduled = false;
      if (!_disposed) recovery.value++;
    });
  }

  /// A mounted strip tile is visible demand, independently of the canvas.
  void retainThumbnail(String id) {
    _visibleThumbnails.update(id, (count) => count + 1, ifAbsent: () => 1);
  }

  void releaseThumbnail(String id) {
    final count = _visibleThumbnails[id] ?? 0;
    if (count > 1) {
      _visibleThumbnails[id] = count - 1;
      return;
    }
    _visibleThumbnails.remove(id);
    for (final request in _requests.keys.toList()) {
      if (_requests[request] == id &&
          _requestPriorities[request] == DecodePriority.visibleThumbnail) {
        request.cancel();
      }
    }
    _trimThumbnails();
  }

  int get memoryBudgetBytes => math.min(
    policy.memoryBudgetBytes,
    _memoryBudgetOverride ?? policy.memoryBudgetBytes,
  );
  int get inflightBytes => _inflightBudget.usedBytes;
  Set<String> get cachedIds => _imageKeys
      .where((key) => PaintingBinding.instance.imageCache.containsKey(key))
      .map((key) => key.version.path)
      .toSet();

  /// Viewport changes update shared requests, not just newly-created providers.
  void applyWorkingSet({
    required Set<String> protectedIds,
    required Set<String> retainedIds,
    Map<String, PrefetchTask> tasks = const {},
    int? memoryBudgetBytes,
  }) {
    final changed = !setEquals(_protectedIds, protectedIds);
    _protectedIds = Set.of(protectedIds);
    _retainedIds = {...retainedIds, ...protectedIds};
    _memoryBudgetOverride = memoryBudgetBytes == null
        ? null
        : math.max(0, memoryBudgetBytes);
    _syncPolicy();
    for (final request in _requests.keys.toList()) {
      final id = _requests[request]!;
      if (_requestPriorities[request] == DecodePriority.visibleThumbnail &&
          _visibleThumbnails.containsKey(id)) {
        continue;
      }
      if (_requestPriorities[request] == DecodePriority.thumbnail &&
          _codecRequests.entries.any(
            (entry) =>
                identical(entry.value, request) &&
                _plannedThumbnails.contains(entry.key),
          )) {
        continue;
      }
      if (!_retainedIds!.contains(id) ||
          (!_protectedIds.contains(id) &&
              !tasks.containsKey(id) &&
              (_requestPriorities[request]?.index ?? 0) >=
                  DecodePriority.adjacent.index)) {
        request.cancel();
        continue;
      }
      final task = tasks[id];
      if (_protectedIds.contains(id)) {
        _requestPriorities[request] = DecodePriority.foreground;
        _scheduler.updatePriority(request, priority: DecodePriority.foreground);
      } else if (task != null) {
        _requestPriorities[request] = task.priority;
        _scheduler.updatePriority(
          request,
          priority: task.priority,
          distance: task.distance,
        );
      }
    }
    for (final key in _prefetches.keys.toList()) {
      if (!_retainedIds!.contains(key.version.path)) _cancelPrefetch(key);
    }
    // The working set admits speculative work. Successful images belong to
    // the byte-bounded ImageCache LRU even after they leave the prefetch range.
    for (final key in _imageKeys.toList()) {
      final status = PaintingBinding.instance.imageCache.statusForKey(key);
      if (!status.pending && !status.live && !status.keepAlive) {
        _imageKeys.remove(key);
        _thumbnailKeys.remove(key);
        _thumbnailLru.remove(key);
      }
    }
    if (changed) _signalRecovery();
  }

  void configurePrefetch(PrefetchLevel maxLevel) {
    policy.configure(maxLevel: maxLevel);
    _syncPolicy();
  }

  /// Apply new telemetry even while navigation is waiting for decode capacity.
  void refreshPolicy() => _syncPolicy();

  void setActive(bool active) {
    policy.setActive(active);
    _syncPolicy();
    if (active) _signalRecovery();
  }

  void memoryPressure() {
    HdrVideoWorker.shared.releaseGpu();
    policy.pressure();
    _hdrFrames.retainPaths(_protectedIds);
    _syncPolicy();
    _trimThumbnails(pressure: true);
    _evictOutside(_protectedIds);
    _metadata.removeWhere((key, _) => !_protectedIds.contains(key.path));
  }

  void recordFrame({required Duration elapsed, required Duration frameBudget}) {
    policy.recordFrame(
      elapsed: elapsed,
      frameBudget: frameBudget,
      hasSpeculativeWork: _requestPriorities.values.any(
        (value) => value.index >= DecodePriority.adjacent.index,
      ),
    );
    _syncPolicy();
  }

  void _syncPolicy() {
    policy.tick();
    _scheduler.setLimits(
      maxConcurrent: policy.maxConcurrent,
      maxBackgroundConcurrent: policy.resourceLevel == PrefetchLevel.onDemand
          ? 0
          : 1,
    );
    // The other half is reserved for encoded input, conversion and in-flight
    // output. Cache occupancy alone is not the image subsystem's peak usage.
    _hdrFrames.configure(memoryBudgetBytes ~/ 4);
    _updateResidentBudget();
    final previousBudget = _inflightBudget.limitBytes;
    _inflightBudget.limitBytes = memoryBudgetBytes ~/ 2;
    if (_inflightBudget.limitBytes > previousBudget) _signalRecovery();
    thumbnails.configure(_thumbnailMode, policy.resourceLevel);
    if (policy.level == PrefetchLevel.onDemand) {
      for (final request in _requests.keys.toList()) {
        if (!_protectedIds.contains(_requests[request]) &&
            !(_requestPriorities[request] == DecodePriority.thumbnail &&
                policy.resourceLevel != PrefetchLevel.onDemand) &&
            (_requestPriorities[request]?.index ?? 0) >=
                DecodePriority.adjacent.index) {
          request.cancel();
        }
      }
      for (final key in _prefetches.keys.toList()) {
        if (!_protectedIds.contains(key.version.path)) _cancelPrefetch(key);
      }
    }
  }

  void _updateResidentBudget() {
    PaintingBinding.instance.imageCache.maximumSizeBytes = math.max(
      0,
      memoryBudgetBytes ~/ 2 - _hdrFrames.currentBytes,
    );
  }

  void _evictOutside(Set<String> retained) {
    for (final key in _imageKeys.toList()) {
      if (retained.contains(key.version.path) ||
          (_thumbnailKeys.contains(key) &&
              _thumbnailCollectionIds.contains(key.version.path)) ||
          (_thumbnailKeys.contains(key) &&
              _visibleThumbnails.containsKey(key.version.path))) {
        continue;
      }
      // Listeners own live images; removing the cache's ownership must not
      // dispose a frame still being displayed during the page hand-off.
      PaintingBinding.instance.imageCache.evict(key, includeLive: false);
      _imageKeys.remove(key);
      _thumbnailKeys.remove(key);
    }
  }

  void _cancelPrefetch(ImageResourceKey key) {
    final handle = _prefetches.remove(key);
    handle?.cancel();
  }

  /// Native HDR/RAW/composite helpers need their own peak allocation limits;
  /// they are prepared on demand instead of starting speculative conversions.
  bool canPrefetch(ImageEntry entry) {
    if (isAnimated(entry) ||
        !{
          ImageFormat.jpeg,
          ImageFormat.png,
          ImageFormat.bmp,
          ImageFormat.ico,
          ImageFormat.tiff,
          ImageFormat.heic,
          ImageFormat.heif,
          ImageFormat.avif,
          ImageFormat.jxl,
          ImageFormat.dds,
        }.contains(entry.format)) {
      return false;
    }
    final metadata = _metadata[version(entry)];
    return metadata == null ||
        !metadata.isHdr ||
        metadata.hdrEncoding == HdrEncoding.gainMap;
  }

  Future<void> prefetch(
    ImageEntry entry, {
    int? targetWidth,
    int? targetHeight,
    DecodePriority priority = DecodePriority.adjacent,
    double distance = 0,
  }) {
    if (_disposed ||
        !canPrefetch(entry) ||
        policy.level == PrefetchLevel.onDemand ||
        (_retainedIds != null && !_retainedIds!.contains(entry.id))) {
      return Future.value();
    }
    final image = provider(
      entry,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      priority: priority,
      distance: distance,
    ) as _ResourceImageProvider;
    final existing = _prefetches[image.key];
    if (existing != null) return existing.completer.future;
    final stream = image.resolve(ImageConfiguration.empty);
    final handle = _PrefetchHandle(stream);
    _prefetches[image.key] = handle;
    void finish() {
      if (identical(_prefetches[image.key], handle)) {
        _prefetches.remove(image.key);
      }
      handle.cancel();
    }

    handle.listener = ImageStreamListener(
      (_, _) => finish(),
      onError: (Object _, StackTrace? _) => finish(),
    );
    stream.addListener(handle.listener);
    return handle.completer.future;
  }

  ImageFileVersion version(ImageEntry entry) {
    _entries[entry.id] = entry;
    return ImageFileVersion(
      path: entry.id,
      modifiedMicroseconds: entry.modifiedAt.microsecondsSinceEpoch,
      byteLength: entry.byteLength,
      revision: _revisions[entry.id] ?? 0,
    );
  }

  ImageMetadata? cachedMetadata(ImageEntry entry) {
    final key = version(entry);
    final value = _metadata.remove(key);
    if (value != null) _metadata[key] = value;
    return value == null ? null : _selectedMetadata(key, value);
  }

  int? selectedIcoIndex(ImageEntry entry) =>
      _icoSelections[version(entry)] ?? _metadata[version(entry)]?.icoIndex;

  int? icoCacheIndex(ImageEntry entry, DecodePriority priority) =>
      entry.format == ImageFormat.ico &&
          priority != DecodePriority.thumbnail &&
          priority != DecodePriority.visibleThumbnail
      ? _icoSelections[version(entry)]
      : null;

  void selectIcoVariant(ImageEntry entry, int index) {
    final key = version(entry);
    final variants = _metadata[key]?.icoVariants;
    if (entry.format != ImageFormat.ico ||
        variants == null ||
        index < 0 ||
        index >= variants.length) {
      throw ArgumentError.value(index, 'index', 'Invalid ICO variant');
    }
    _icoSelections[key] = index;
  }

  ImageMetadata _selectedMetadata(ImageFileVersion key, ImageMetadata value) {
    final index = _icoSelections[key];
    return index == null || value.icoVariants.isEmpty
        ? value
        : value.selectIco(index);
  }

  /// Includes decode, float transfer and upload in the same admission. The
  /// overlay keeps its SDR child whenever the requested HDR peak does not fit.
  Future<bool> runHdrTask(
    ImageEntry entry,
    DecodeRequest request,
    Future<bool> Function() operation,
  ) async {
    _syncPolicy();
    final metadata = cachedMetadata(entry);
    final pixels = math.min(
      HdrFrame.maxPixels,
      (metadata?.width ?? entry.width ?? 2048) *
          (metadata?.height ?? entry.height ?? 2048),
    );
    final bytes = math.max(1, pixels) * 32;
    _requests[request] = entry.id;
    _requestPriorities[request] = DecodePriority.foreground;
    try {
      return await _scheduler.schedule(
        () async {
          final reservation = _inflightBudget.reserve(bytes);
          if (reservation == null) throw ImageResourceUnavailable();
          try {
            return await operation();
          } finally {
            reservation.release();
          }
        },
        request: request,
        canStart: () =>
            bytes > _inflightBudget.limitBytes ||
            bytes <= _inflightBudget.availableBytes,
      );
    } finally {
      _requests.remove(request);
      _requestPriorities.remove(request);
    }
  }

  Future<HdrFrame> hdrFrame(
    ImageEntry entry,
    DecodeRequest request, {
    HdrInputMetadata? metadata,
  }) {
    _syncPolicy();
    return _hdrFrames.load(version(entry), request, (worker) async {
      final lease = await entry.acquireFile(request: worker);
      try {
        worker.throwIfCancelled();
        return await _hdrDecoder.decode(
          lease.file.path,
          worker,
          metadata: metadata,
        );
      } finally {
        await lease.release();
      }
    });
  }

  Future<Uint8List> printBytes(ImageEntry entry) async {
    final lease = await entry.acquireFile();
    try {
      if (entry.format == ImageFormat.ico) {
        return await IcoFile.decode(
          lease.file.path,
          index: selectedIcoIndex(entry),
        );
      }
      final bytes = await lease.file.readAsBytes();
      if (entry.format == ImageFormat.jpeg || entry.format == ImageFormat.png) {
        return bytes;
      }
      return await _decoder.decode(lease.file.path);
    } finally {
      await lease.release();
    }
  }

  Future<ImageMetadata> metadata(
    ImageEntry entry, {
    DecodePriority priority = DecodePriority.metadata,
  }) {
    if (_disposed ||
        (policy.level == PrefetchLevel.onDemand &&
            !_protectedIds.contains(entry.id) &&
            priority.index >= DecodePriority.adjacent.index)) {
      return Future.error(DecodeCancelled());
    }
    final key = version(entry);
    final cached = cachedMetadata(entry);
    if (cached != null) return SynchronousFuture(cached);
    final pending = _metadataRequests[key];
    if (pending?.cancelled ?? false) {
      _metadataPending.remove(key);
      _metadataRequests.remove(key);
    }
    if (pending != null &&
        priority.index < (_requestPriorities[pending]?.index ?? 99)) {
      _requestPriorities[pending] = priority;
      _scheduler.updatePriority(pending, priority: priority);
    }
    return _metadataPending[key] ??= _readMetadata(key, priority);
  }

  Future<ImageMetadata> _readMetadata(
    ImageFileVersion key,
    DecodePriority priority,
  ) async {
    final request = DecodeRequest();
    _requests[request] = key.path;
    _requestPriorities[request] = priority;
    _metadataRequests[key] = request;
    try {
      final result = await _scheduler.schedule(
        () async {
          final entry = _entries[key.path];
          if (entry == null) throw DecodeCancelled();
          final lease = await entry.acquireFile(request: request);
          try {
            return await _metadataService.read(
              lease.file.path,
              request: request,
            );
          } finally {
            await lease.release();
          }
        },
        request: request,
        priority: priority,
      );
      if (!_disposed && key.revision == (_revisions[key.path] ?? 0)) {
        _metadata[key] = result;
        while (_metadata.length > maxMetadataEntries) {
          _metadata.remove(_metadata.keys.first);
        }
      }
      return _selectedMetadata(key, result);
    } finally {
      _requests.remove(request);
      _requestPriorities.remove(request);
      if (identical(_metadataRequests[key], request)) {
        _metadataRequests.remove(key);
        _metadataPending.remove(key);
      }
    }
  }

  ImageProvider<ImageResourceKey> provider(
    ImageEntry entry, {
    int? targetWidth,
    int? targetHeight,
    ImageRegion? region,
    DecodePriority priority = DecodePriority.foreground,
    double distance = 0,
  }) {
    final key = ImageResourceKey(
      version: version(entry),
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      region: region,
      icoIndex: icoCacheIndex(entry, priority),
      allowSmallRawPreview:
          entry.format == ImageFormat.raw &&
          (priority == DecodePriority.visibleThumbnail ||
              priority == DecodePriority.thumbnail),
    );
    final thumbnail =
        priority == DecodePriority.visibleThumbnail ||
        priority == DecodePriority.thumbnail;
    final request = _codecRequests[key];
    if ((_failures[key]?.speculative ?? false) &&
        priority.index < DecodePriority.adjacent.index) {
      PaintingBinding.instance.imageCache.evict(key);
    }
    if (thumbnail) {
      _thumbnailKeys.add(key);
      final size = _thumbnailLru.remove(key);
      if (size != null) _thumbnailLru[key] = size;
    }
    if (request?.cancelled ?? false) {
      PaintingBinding.instance.imageCache.evict(key, includeLive: false);
    }
    if (request != null) {
      final current = _requestPriorities[request] ?? DecodePriority.preload;
      if (priority.index <= current.index) {
        _requestPriorities[request] = priority;
        _scheduler.updatePriority(
          request,
          priority: priority,
          distance: distance,
        );
      }
    }
    return _ResourceImageProvider(
      service: this,
      key: key,
      format: entry.format,
      priority: priority,
      distance: distance,
    );
  }

  ImageResourceKey? _cachedThumbnailFallback(
    ImageEntry entry,
    ImageResourceKey requested,
  ) {
    if (isAnimated(entry) || entry.format == ImageFormat.raw) return null;
    final cache = PaintingBinding.instance.imageCache;
    bool ready(ImageResourceKey key) {
      final status = cache.statusForKey(key);
      return !status.pending && (status.keepAlive || status.live);
    }

    if (ready(requested)) return requested;
    for (final key in _imageKeys) {
      if (key.version == requested.version &&
          key.region == requested.region &&
          key.icoIndex == requested.icoIndex &&
          (key.targetWidth == null ||
              key.targetWidth! >= (requested.targetWidth ?? 0)) &&
          (key.targetHeight == null ||
              key.targetHeight! >= (requested.targetHeight ?? 0)) &&
          ready(key)) {
        return key;
      }
    }
    return null;
  }

  Future<Uint8List?> _cachedThumbnail(
    ImageEntry entry,
    ImageResourceKey key,
    DecodeRequest request,
  ) async {
    final fallback = _cachedThumbnailFallback(entry, key);
    if (fallback == null) return null;
    final stream = _ResourceImageProvider(
      service: this,
      key: fallback,
      format: entry.format,
      priority: DecodePriority.visibleThumbnail,
      distance: 0,
    ).resolve(ImageConfiguration.empty);
    final ready = Completer<ui.Image>();
    final listener = ImageStreamListener(
      (info, _) {
        if (!ready.isCompleted) ready.complete(info.image.clone());
      },
      onError: (Object error, StackTrace? stack) {
        if (!ready.isCompleted) ready.completeError(error, stack);
      },
    );
    void cancel() {
      if (!ready.isCompleted) ready.completeError(DecodeCancelled());
    }

    ui.Image? source;
    ui.Image? thumbnail;
    ui.Picture? picture;
    stream.addListener(listener);
    request.addCancelListener(cancel);
    try {
      source = await ready.future;
      request.throwIfCancelled();
      final scale = math.min(
        1.0,
        math.min(
          (key.targetWidth ?? source.width) / source.width,
          (key.targetHeight ?? source.height) / source.height,
        ),
      );
      final width = math.max(1, (source.width * scale).round());
      final height = math.max(1, (source.height * scale).round());
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        source,
        ui.Rect.fromLTWH(
          0,
          0,
          source.width.toDouble(),
          source.height.toDouble(),
        ),
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      picture = recorder.endRecording();
      thumbnail = await picture.toImage(width, height);
      request.throwIfCancelled();
      final bytes = await thumbnail.toByteData(format: ui.ImageByteFormat.png);
      request.throwIfCancelled();
      return bytes?.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
    } on DecodeCancelled {
      rethrow;
    } catch (_) {
      return null;
    } finally {
      stream.removeListener(listener);
      request.removeCancelListener(cancel);
      source?.dispose();
      thumbnail?.dispose();
      picture?.dispose();
    }
  }

  Future<ui.Codec?> _loadCachedThumbnail(
    ImageEntry entry,
    ImageResourceKey key,
    DecodeRequest request,
    ImageDecoderCallback decode,
  ) async {
    if (_cachedThumbnailFallback(entry, key) == null) return null;
    final prepared = await _reserveDecode(entry, key, request);
    var transferred = false;
    try {
      final bytes = await _cachedThumbnail(entry, prepared.key, request);
      if (bytes == null) return null;
      final codec = await decodeWithFallback([
        DecodeBackend(
          'cached SDR thumbnail',
          () async => _codecFromBuffer(
            await ui.ImmutableBuffer.fromUint8List(bytes),
            prepared.key,
            request,
            decode: decode,
          ),
        ),
      ], request: request);
      _rememberThumbnail(key, codec.firstImage!);
      transferred = true;
      return _ReservedCodec(
        codec,
        prepared.reservation,
        releaseStaticAfterFrame: true,
        firstFrameOnly: true,
      );
    } finally {
      if (!transferred) prepared.reservation.release();
    }
  }

  Future<ui.Codec> animationCodec(
    ImageEntry entry, {
    int? targetWidth,
    int? targetHeight,
    required DecodeRequest request,
  }) async {
    _syncPolicy();
    if (entry.format == ImageFormat.apng ||
        entry.format == ImageFormat.avif ||
        MediaContainer.candidate(entry.name)) {
      await metadata(entry, priority: DecodePriority.foreground);
      request.throwIfCancelled();
    }
    final key = ImageResourceKey(
      version: version(entry),
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    _requests[request] = entry.id;
    _requestPriorities[request] = DecodePriority.foreground;
    try {
      return await _scheduler.schedule(
        () async {
          request.throwIfCancelled();
          final prepared = await _reserveDecode(
            entry,
            key,
            request,
            animated: true,
          );
          var transferred = false;
          try {
            final lease = await entry.acquireFile(request: request);
            var leaseTransferred = false;
            try {
              request.throwIfCancelled();
              final media = cachedMetadata(entry)?.media;
              if (media == null &&
                  await lease.file.length() > maxEncodedBytes) {
                throw StateError('动图超过文件读取预算。');
              }
              if (entry.format == ImageFormat.avif || media != null) {
                leaseTransferred = true;
              }
              final codec = media != null
                  ? await PhotoMediaCodec.open(
                      lease.file.path,
                      media,
                      targetWidth: prepared.key.targetWidth,
                      targetHeight: prepared.key.targetHeight,
                      request: request,
                      releaseFile: lease.release,
                    )
                  : entry.format == ImageFormat.avif
                  ? await AvifCodec.open(
                      lease.file.path,
                      maxPixels:
                          cachedMetadata(entry)?.animation?.sourcePixelCount ??
                          maxDecodedPixels,
                      targetWidth: prepared.key.targetWidth,
                      targetHeight: prepared.key.targetHeight,
                      request: request,
                      releaseFile: lease.release,
                    )
                  : entry.format == ImageFormat.apng
                  ? await ApngCodec.open(
                      lease.file.path,
                      maxPixels: maxDecodedPixels,
                      targetWidth: prepared.key.targetWidth,
                      targetHeight: prepared.key.targetHeight,
                    )
                  : await _codecFromBuffer(
                      await ui.ImmutableBuffer.fromFilePath(lease.file.path),
                      prepared.key,
                      request,
                    );
              if (request.cancelled) {
                codec.dispose();
                request.throwIfCancelled();
              }
              transferred = true;
              return _ScheduledAnimationCodec(
                _ReservedCodec(codec, prepared.reservation),
                _scheduler,
                request,
              );
            } finally {
              if (!leaseTransferred) await lease.release();
            }
          } finally {
            if (!transferred) prepared.reservation.release();
          }
        },
        request: request,
        canStart: () => _decodeReady(key),
        onDiscard: (codec) => codec.dispose(),
      );
    } finally {
      _requests.remove(request);
      _requestPriorities.remove(request);
    }
  }

  Future<ui.Codec> _loadCodec(
    ImageResourceKey key,
    ImageFormat format,
    DecodePriority priority,
    ImageDecoderCallback decode,
    double distance,
  ) async {
    _syncPolicy();
    final previousFailure = _failures[key];
    final speculative = priority.index >= DecodePriority.adjacent.index;
    if (previousFailure != null &&
        (!previousFailure.speculative || speculative)) {
      throw previousFailure.error;
    }
    // Visible demand owns this retry. Keeping the old speculative failure would
    // evict its pending or successfully cached image on every provider rebuild.
    _failures.remove(key);
    final request = DecodeRequest();
    if (format == ImageFormat.raw && priority == DecodePriority.foreground) {
      for (final previous in _codecRequests.entries.toList()) {
        if (previous.key.version == key.version &&
            previous.key != key &&
            previous.key.region == key.region &&
            previous.value.priority == DecodePriority.foreground &&
            !previous.key.allowSmallRawPreview) {
          previous.value.cancel();
        }
      }
    }
    _requests[request] = key.version.path;
    _requestPriorities[request] = priority;
    _codecRequests[key] = request;
    _imageKeys.add(key);
    try {
      final cachedEntry = _entries[key.version.path];
      if (_thumbnailKeys.contains(key) && cachedEntry != null) {
        try {
          // Resizing resident SDR pixels needs no source decoder slot. Do not
          // queue an immediately usable cover behind a long HDR conversion.
          final cached = await _loadCachedThumbnail(
            cachedEntry,
            key,
            request,
            decode,
          );
          if (cached != null) return cached;
        } on ImageResourceUnavailable {
          // Normal admission below waits for temporary byte contention.
        }
      }
      if (format == ImageFormat.jpeg ||
          format == ImageFormat.tiff ||
          format == ImageFormat.raw ||
          format == ImageFormat.ico ||
          format == ImageFormat.heic ||
          format == ImageFormat.heif) {
        // Source color hints select the JPEG/TIFF backend. RAW IFD0 can be a
        // thumbnail, so resolve its true geometry and preview costs as well.
        final entry = _entries[key.version.path];
        if (entry == null) throw DecodeCancelled();
        await metadata(entry, priority: priority);
        request.throwIfCancelled();
      }
      return await _scheduler.schedule(
        () async {
          request.throwIfCancelled();
          final entry = _entries[key.version.path];
          if (entry == null) throw DecodeCancelled();
          var rawDevelopment =
              format == ImageFormat.raw &&
              (!key.allowSmallRawPreview ||
                  _rawPreviewRejected.contains(key) ||
                  _metadata[key.version]?.values['rawPreviewBytes'] == '0');
          var prepared = await _reserveDecode(
            entry,
            key,
            request,
            rawDevelopment: rawDevelopment,
          );
          final decodeKey = prepared.key;
          final stopwatch = Stopwatch()..start();
          var transferred = false;
          Future<ui.Codec> keep(ui.Codec codec) async {
            final primed = codec is FirstFrameCodec
                ? codec
                : await decodeWithFallback([
                    DecodeBackend('codec', () async => codec),
                  ], request: request);
            if (_thumbnailKeys.contains(key) && primed.firstImage != null) {
              _rememberThumbnail(key, primed.firstImage!);
            }
            transferred = true;
            return _ReservedCodec(
              primed,
              prepared.reservation,
              releaseStaticAfterFrame: true,
              firstFrameOnly: _thumbnailKeys.contains(key),
            );
          }

          try {
            final lease = await entry.acquireFile(request: request);
            final sourcePath = lease.file.path;
            try {
              request.throwIfCancelled();
              if (key.region == null &&
                  HdrInputMetadata.candidate(sourcePath) &&
                  !RawDeveloper.candidate(sourcePath) &&
                  format != ImageFormat.hdr &&
                  format != ImageFormat.exr) {
                try {
                  final info = await HdrInputMetadata.read(
                    sourcePath,
                    request: request,
                  );
                  // Gain-map formats already carry an authored SDR rendition.
                  // Keep it for Flutter, thumbnails and the HDR-off fallback.
                  // Reconstructing HDR and applying generic Reinhard here loses
                  // that rendition's contrast and can wash out the entire image.
                  // HdrImageView alone requests the alternate HDR rendition.
                  if (info.isHdr && info.encoding != HdrEncoding.gainMap) {
                    final currentPriority =
                        _requestPriorities[request] ?? priority;
                    if (!_protectedIds.contains(key.version.path) &&
                        currentPriority.index >=
                            DecodePriority.adjacent.index) {
                      throw ThumbnailPrefetchSkipped();
                    }
                    final frame = await hdrFrame(
                      entry,
                      request,
                      metadata: info,
                    );
                    final png = await HdrDecoder.sdrPng(frame);
                    request.throwIfCancelled();
                    return await keep(
                      await _codecFromBuffer(
                        await ui.ImmutableBuffer.fromUint8List(png),
                        decodeKey,
                        request,
                        decode: decode,
                      ),
                    );
                  }
                } on DecodeCancelled {
                  rethrow;
                } on DecodeBudgetExceeded {
                  rethrow;
                } on ThumbnailPrefetchSkipped {
                  rethrow;
                } catch (_) {
                  // Unsupported gain-map/Dolby variants retain the existing base
                  // decoder. Optional codec failure must not break folder browsing.
                }
              }
              return await keep(
                await _openStaticCodec(
                  entry,
                  sourcePath,
                  decodeKey,
                  request,
                  decode,
                  speculative: speculative,
                  thumbnail: _thumbnailKeys.contains(key),
                  preferPlatform: prepared.preferPlatform,
                  rawPreviewCoverage: prepared.rawPreviewCoverage,
                  skipRawPreview: rawDevelopment,
                  prepareRawDevelopment: () async {
                    if (!rawDevelopment) {
                      rawDevelopment = true;
                      _rawPreviewRejected.add(key);
                      if (_rawPreviewRejected.length > maxMetadataEntries) {
                        _rawPreviewRejected.remove(_rawPreviewRejected.first);
                      }
                      prepared.reservation.release();
                      prepared = await _reserveDecode(
                        entry,
                        key,
                        request,
                        rawDevelopment: true,
                      );
                    }
                    return prepared.key;
                  },
                ),
              );
            } finally {
              // First-frame decoding has consumed the source bytes. Releasing
              // an archive lease may queue behind cache maintenance; publishing
              // the frame and freeing its decode slot must not wait for that.
              unawaited(
                lease.release().catchError((Object error, StackTrace stack) {
                  FlutterError.reportError(
                    FlutterErrorDetails(
                      exception: error,
                      stack: stack,
                      library: 'image resource service',
                      context: ErrorDescription('while releasing source bytes'),
                      silent: true,
                    ),
                  );
                }),
              );
            }
          } finally {
            if (!transferred) prepared.reservation.release();
            policy.recordDecode(
              elapsed: stopwatch.elapsed,
              hasSpeculativeWork: _requestPriorities.values.any(
                (value) => value.index >= DecodePriority.adjacent.index,
              ),
              foregroundWaiting: _scheduler.foregroundWaiting,
            );
          }
        },
        request: request,
        priority: priority,
        distance: distance,
        canStart: () => _decodeReady(key),
        onDiscard: (codec) => codec.dispose(),
      );
    } on DecodeCancelled {
      // ImageCache's pending listener only observes successful frames. A
      // cancelled speculative codec must not remain reusable as a live stream.
      if (identical(_codecRequests[key], request)) {
        PaintingBinding.instance.imageCache.evict(key);
      }
      rethrow;
    } catch (error) {
      if (error is! ImageResourceUnavailable &&
          error is! DecodeBudgetExceeded) {
        _failures[key] = (
          error: error,
          speculative:
              (_requestPriorities[request] ?? priority).index >=
              DecodePriority.adjacent.index,
        );
        while (_failures.length > maxMetadataEntries) {
          _failures.remove(_failures.keys.first);
        }
      }
      rethrow;
    } finally {
      _requests.remove(request);
      _requestPriorities.remove(request);
      if (identical(_codecRequests[key], request)) _codecRequests.remove(key);
    }
  }

  ImageDecodeRoute _decodeRoute(ImageEntry entry, ImageResourceKey key) {
    // Flutter's JPEG codec has no inferred Adobe RGB source profile. Only an
    // explicit embedded hint selects this route; sidecars never recolor pixels.
    if ((entry.format == ImageFormat.jpeg ||
            entry.format == ImageFormat.tiff) &&
        _metadata[key.version]?.values['unprofiledAdobeRgb'] == 'true') {
      return ImageDecodeRoute.imageMagick;
    }
    return decodeRouteFor(entry.format, hasRegion: key.region != null);
  }

  bool _decodeReady(ImageResourceKey key) {
    final entry = _entries[key.version.path];
    if (entry == null) return true;
    final encoded =
        _decodeRoute(entry, key) == ImageDecodeRoute.flutter &&
            !_preferPlatform(entry, key, _codecRequests[key])
        ? math.max(0, entry.byteLength)
        : _nativeOverhead(entry);
    final minimum =
        encoded +
        math.min(256, key.targetWidth ?? entry.width ?? 256) *
            math.min(256, key.targetHeight ?? entry.height ?? 256) *
            12;
    // Permanent budget rejection must run to report the classified failure.
    final request = _codecRequests[key];
    final auxiliary =
        request != null &&
        request.priority.index >= DecodePriority.visibleThumbnail.index;
    final headroom = auxiliary ? _inflightBudget.limitBytes ~/ 2 : 0;
    return minimum > _inflightBudget.limitBytes - headroom ||
        minimum + headroom <= _inflightBudget.availableBytes;
  }

  // Large encoded inputs would consume the foreground reserve even for tiny
  // previews. Native backends receive a path and return bounded output instead.
  bool _preferPlatform(
    ImageEntry entry,
    ImageResourceKey key,
    DecodeRequest? request,
  ) {
    if (request == null ||
        request.priority.index < DecodePriority.visibleThumbnail.index ||
        _decodeRoute(entry, key) != ImageDecodeRoute.flutter) {
      return false;
    }
    final minimumPixels =
        math.min(256, key.targetWidth ?? entry.width ?? 256) *
        math.min(256, key.targetHeight ?? entry.height ?? 256);
    return entry.byteLength + minimumPixels * 12 >
        _inflightBudget.limitBytes ~/ 2;
  }

  int _nativeOverhead(ImageEntry entry, {bool rawDevelopment = false}) =>
      entry.format == ImageFormat.ico
      ? (_metadata[version(entry)]?.icoVariants.fold<int>(
                      0,
                      (largest, variant) =>
                          math.max(largest, variant.byteLength),
                    ) ??
                    IcoFile.maxEntryBytes) *
                3 +
            1024 * 1024
      : entry.format == ImageFormat.raw
      ? rawDevelopment
            ? 32 * 1024 * 1024
            : math.max(
                256 * 1024,
                math.min(
                  RawDeveloper.maxPreviewBytes,
                  (int.tryParse(
                            _metadata[version(entry)]
                                    ?.values['rawPreviewBytes'] ??
                                '',
                          ) ??
                          RawDeveloper.maxPreviewBytes) +
                      2048,
                ),
              )
      : entry.format == ImageFormat.hdr || entry.format == ImageFormat.exr
      ? 16 * 1024 * 1024
      : 256 * 1024;

  bool isAnimated(ImageEntry entry) =>
      entry.isAnimated ||
      (cachedMetadata(entry)?.animation?.frameCount ?? 0) > 1;

  Future<ui.Codec> _openStaticCodec(
    ImageEntry entry,
    String path,
    ImageResourceKey key,
    DecodeRequest request,
    ImageDecoderCallback decode, {
    required bool speculative,
    required bool thumbnail,
    bool preferPlatform = false,
    ui.Size? rawPreviewCoverage,
    bool skipRawPreview = false,
    Future<ImageResourceKey> Function()? prepareRawDevelopment,
  }) async {
    final media = cachedMetadata(entry)?.media;
    if (media != null && media.location.kind == PhotoMediaKind.heifSequence) {
      return PhotoMediaCodec.open(
        path,
        media,
        targetWidth: key.targetWidth,
        targetHeight: key.targetHeight,
        request: request,
      );
    }
    if (entry.format == ImageFormat.ico) {
      final bytes = await IcoFile.decode(
        path,
        index: key.icoIndex,
        region: key.region,
        request: request,
      );
      return _codecFromBuffer(
        await ui.ImmutableBuffer.fromUint8List(bytes),
        key,
        request,
        decode: decode,
      );
    }
    final route = _decodeRoute(entry, key);
    Future<ui.Codec> flutter() async {
      if (await File(path).length() > maxEncodedBytes) {
        throw DecodeBudgetExceeded('图片文件超过读取预算，请使用长图模式或较小的图片。');
      }
      return _codecFromBuffer(
        await ui.ImmutableBuffer.fromFilePath(path),
        key,
        request,
        decode: decode,
      );
    }

    Future<ui.Codec?> platform() async {
      final native = await _decoder.decodePlatform(
        path,
        targetWidth: key.targetWidth,
        targetHeight: key.targetHeight,
        region: key.region?.toMap(),
        preserveHdr:
            Platform.isMacOS &&
            (entry.format == ImageFormat.hdr ||
                entry.format == ImageFormat.exr),
        request: request,
      );
      request.throwIfCancelled();
      return native?.toCodec(request: request);
    }

    Future<ui.Codec> compatible() async {
      final outputKey =
          RawDeveloper.candidate(path) && prepareRawDevelopment != null
          ? await prepareRawDevelopment()
          : key;
      final bytes = await _decoder.decode(
        path,
        targetWidth: outputKey.targetWidth,
        targetHeight: outputKey.targetHeight,
        crop: outputKey.region?.crop,
        request: request,
        allowTimeoutFallback: () =>
            (_requestPriorities[request]?.index ?? 0) <
            DecodePriority.adjacent.index,
      );
      return _codecFromBuffer(
        await ui.ImmutableBuffer.fromUint8List(bytes),
        outputKey,
        request,
        decode: decode,
      );
    }

    Future<ui.Codec?> rawPreview() async {
      final preview = await _decoder.rawPreview(
        path,
        targetWidth: key.targetWidth,
        targetHeight: key.targetHeight,
        request: request,
      );
      if (preview == null) return null;
      final source = _metadata[key.version];
      final width =
          source?.width ?? entry.width ?? key.targetWidth ?? preview.width;
      final height =
          source?.height ?? entry.height ?? key.targetHeight ?? preview.height;
      final scale = math.min(
        1.0,
        math.min(
          (rawPreviewCoverage?.width ?? key.targetWidth ?? width) / width,
          (rawPreviewCoverage?.height ?? key.targetHeight ?? height) / height,
        ),
      );
      final requiredWidth = math.max(1, (width * scale).floor());
      final requiredHeight = math.max(1, (height * scale).floor());
      final smallAllowed = key.allowSmallRawPreview;
      if (!smallAllowed &&
          (preview.width + 1 < requiredWidth ||
              preview.height + 1 < requiredHeight ||
              ((preview.width / preview.height) / (width / height) - 1).abs() >
                  .02)) {
        return null;
      }
      final primed = await decodeWithFallback([
        DecodeBackend(
          '内嵌预览',
          () async => _codecFromBuffer(
            await ui.ImmutableBuffer.fromUint8List(preview.bytes),
            key,
            request,
            decode: decode,
          ),
        ),
      ], request: request);
      // A corrupt container can claim dimensions that its JPEG does not have.
      final actual = primed.firstImage!;
      final previewScale = math.min(
        1.0,
        math.min(
          (key.targetWidth ?? preview.width) / preview.width,
          (key.targetHeight ?? preview.height) / preview.height,
        ),
      );
      final decodedWidth = (preview.width * previewScale).round();
      final decodedHeight = (preview.height * previewScale).round();
      if (!smallAllowed &&
          (actual.width + 1 < decodedWidth ||
              actual.height + 1 < decodedHeight)) {
        primed.dispose();
        return null;
      }
      return primed;
    }

    final animated = isAnimated(entry);
    final usePlatform =
        !RawDeveloper.candidate(path) &&
        !(Platform.isWindows &&
            (entry.format == ImageFormat.hdr ||
                entry.format == ImageFormat.exr));
    try {
      return await decodeWithFallback(
        [
          if (RawDeveloper.candidate(path) &&
              // Camera JPEG exposure can differ from the corrected SDR/HDR
              // development. Keep it for thumbnails, never as the main frame
              // (including adjacent/preloaded frames later promoted to main).
              key.allowSmallRawPreview &&
              key.region == null &&
              !skipRawPreview)
            DecodeBackend('RAW 内嵌预览', rawPreview),
          if (route == ImageDecodeRoute.flutter && !preferPlatform)
            DecodeBackend('Flutter', flutter),
          if ((!animated || thumbnail) &&
              route != ImageDecodeRoute.imageMagick &&
              usePlatform)
            DecodeBackend('平台解码', platform),
          if ((!animated || thumbnail) || route != ImageDecodeRoute.flutter)
            DecodeBackend('兼容解码', compatible),
        ],
        request: request,
        speculative: speculative,
        speculativeNow: () =>
            (_requestPriorities[request]?.index ?? 0) >=
            DecodePriority.adjacent.index,
      );
    } on ImageDecodeFailure catch (failure) {
      for (final error in failure.attempts.values) {
        if (error is ImageResourceUnavailable) throw error;
      }
      rethrow;
    }
  }

  Future<
    ({
      ImageResourceKey key,
      ResourceReservation reservation,
      bool preferPlatform,
      ui.Size? rawPreviewCoverage,
    })
  >
  _reserveDecode(
    ImageEntry entry,
    ImageResourceKey key,
    DecodeRequest request, {
    bool animated = false,
    bool rawDevelopment = false,
  }) async {
    request.throwIfCancelled();
    final fileBytes = math.max(0, entry.byteLength);
    final route = _decodeRoute(entry, key);
    // Flutter receives the complete encoded buffer. Native routes receive a
    // file path, then return a resized pixel buffer or PNG: charging the whole
    // source here would reject e.g. a 53 MiB PSD even for a 256 px preview.
    // Their output/conversion buffers are charged in the pixel cost below.
    final apng = animated && entry.format == ImageFormat.apng;
    final avif = animated && entry.format == ImageFormat.avif;
    final photoMedia = _metadata[key.version]?.media;
    // Motion Photo thumbnails use the still cover, without a video decoder.
    final media =
        animated || photoMedia?.location.kind == PhotoMediaKind.heifSequence
        ? photoMedia
        : null;
    final mediaPixels = media == null ? 0 : media.width * media.height;
    if (mediaPixels > maxDecodedPixels) throw ImageResourceUnavailable();
    final preferPlatform = !animated && _preferPlatform(entry, key, request);
    final avifMetadata = avif ? _metadata[key.version] : null;
    // AV1 references and the full-resolution YUV/RGBA working set remain live
    // even when the displayed frame is small. Reserve them before spawning.
    final avifPixels =
        avifMetadata?.animation?.sourcePixelCount ??
        (avifMetadata?.width ?? 0) * (avifMetadata?.height ?? 0);
    if (avif && (avifPixels <= 0 || avifPixels > maxDecodedPixels)) {
      throw ImageResourceUnavailable();
    }
    final encoded = media != null
        ? mediaPixels * (media.alphaIndex != null ? 96 : 48) + 8 * 1024 * 1024
        : avif
        ? fileBytes + avifPixels * 96
        : (route == ImageDecodeRoute.flutter && !preferPlatform) || apng
        ? fileBytes
        : _nativeOverhead(entry, rawDevelopment: rawDevelopment);
    final bytesPerPixel = apng
        ? 24
        : Platform.isMacOS &&
              (entry.format == ImageFormat.hdr ||
                  entry.format == ImageFormat.exr)
        ? 48
        : 12;
    if (media == null &&
        route == ImageDecodeRoute.flutter &&
        !preferPlatform &&
        fileBytes > maxEncodedBytes) {
      throw DecodeBudgetExceeded('图片文件超过读取预算，请使用长图模式或较小的图片。');
    }
    final limit = _inflightBudget.limitBytes;
    if (limit <= encoded + bytesPerPixel) throw ImageResourceUnavailable();
    // Long-lived animation codecs must leave room for a spread partner and
    // the next requested page. Static tasks share the remaining decode pool.
    final available = _inflightBudget.availableBytes;
    final sourceMetadata = _metadata[key.version];
    final metadata =
        sourceMetadata == null || sourceMetadata.icoVariants.isEmpty
        ? sourceMetadata
        : sourceMetadata.selectIco(key.icoIndex ?? sourceMetadata.icoIndex!);
    final sourceWidth =
        key.region?.width ??
        (entry.format == ImageFormat.raw ? metadata?.width : null) ??
        entry.width ??
        metadata?.width;
    final sourceHeight =
        key.region?.height ??
        (entry.format == ImageFormat.raw ? metadata?.height : null) ??
        entry.height ??
        metadata?.height;
    final minimumPixels =
        math.min(256, key.targetWidth ?? sourceWidth ?? 256) *
        math.min(256, key.targetHeight ?? sourceHeight ?? 256);
    final apngPixels = (sourceWidth ?? 0) * (sourceHeight ?? 0);
    if (apng &&
        (apngPixels <= 0 ||
            apngPixels > maxDecodedPixels ||
            encoded + apngPixels * bytesPerPixel > limit)) {
      throw ImageResourceUnavailable();
    }
    final auxiliary =
        (_requestPriorities[request]?.index ?? 0) >=
        DecodePriority.visibleThumbnail.index;
    final headroom = auxiliary ? limit ~/ 2 : 0;
    final usable = auxiliary
        ? math.max(0, math.min(available - headroom, limit ~/ 2))
        : available;
    if (usable <= encoded + bytesPerPixel) throw ImageResourceUnavailable();
    final allocation = apng
        ? encoded + apngPixels * bytesPerPixel
        : animated
        ? math.min(limit, math.max(encoded * 2 + bytesPerPixel, limit ~/ 4))
        : auxiliary
        ? usable
        : usable >=
              math.min(
                limit,
                encoded + math.max(1, minimumPixels) * bytesPerPixel,
              )
        ? usable
        : limit;
    final fullRawOverhead = _nativeOverhead(entry, rawDevelopment: true);
    // Compare preview coverage with attainable sensor detail, but allocate the
    // preview using its own cost. Charging sensor overhead to preview output
    // needlessly discards detail from near-full-resolution camera JPEGs.
    final planningOverhead =
        entry.format == ImageFormat.raw &&
            !auxiliary &&
            allocation >=
                fullRawOverhead + math.max(1, minimumPixels) * bytesPerPixel
        ? math.max(encoded, fullRawOverhead)
        : encoded;
    final maxPixels = math.max(
      1,
      math.min(maxDecodedPixels, (allocation - encoded) ~/ bytesPerPixel),
    );
    final square = math.max(1, math.sqrt(maxPixels).floor());
    var width = math.max(1, sourceWidth ?? key.targetWidth ?? square);
    var height = math.max(1, sourceHeight ?? key.targetHeight ?? square);
    final scale = apng
        ? 1.0
        : math.min(
            1.0,
            math.min(
              (key.targetWidth ?? width) / width,
              (key.targetHeight ?? height) / height,
            ),
          );
    width = math.max(1, (width * scale).floor());
    height = math.max(1, (height * scale).floor());
    if (width * height > maxPixels) {
      final reduction = math.sqrt(maxPixels / (width * height));
      width = math.max(1, (width * reduction).floor());
      height = math.max(1, (height * reduction).floor());
    }
    var coverageWidth = width;
    var coverageHeight = height;
    final coveragePixels = math.max(
      1,
      math.min(
        maxDecodedPixels,
        (allocation - planningOverhead) ~/ bytesPerPixel,
      ),
    );
    if (coverageWidth * coverageHeight > coveragePixels) {
      final reduction = math.sqrt(
        coveragePixels / (coverageWidth * coverageHeight),
      );
      coverageWidth = math.max(1, (coverageWidth * reduction).floor());
      coverageHeight = math.max(1, (coverageHeight * reduction).floor());
    }
    final reservation = _inflightBudget.reserve(
      encoded + width * height * bytesPerPixel,
      headroomBytes: headroom,
    );
    if (reservation == null) {
      // Do not hold an execution slot while waiting for capacity. Visible
      // owners and the session plan retry when a reservation is released.
      throw ImageResourceUnavailable();
    }
    return (
      key: ImageResourceKey(
        version: key.version,
        targetWidth: width,
        targetHeight: height,
        region: key.region,
        allowSmallRawPreview: key.allowSmallRawPreview,
        icoIndex: key.icoIndex,
      ),
      reservation: reservation,
      preferPlatform: preferPlatform,
      rawPreviewCoverage: entry.format == ImageFormat.raw && !rawDevelopment
          ? ui.Size(coverageWidth.toDouble(), coverageHeight.toDouble())
          : null,
    );
  }

  Future<ui.Codec> _codecFromBuffer(
    ui.ImmutableBuffer buffer,
    ImageResourceKey key,
    DecodeRequest request, {
    ImageDecoderCallback? decode,
  }) async {
    if (request.cancelled) {
      buffer.dispose();
      throw DecodeCancelled();
    }
    final codec = key.targetWidth == null && key.targetHeight == null
        ? await (decode == null
              ? PaintingBinding.instance.instantiateImageCodecWithSize(buffer)
              : decode(buffer))
        : await PaintingBinding.instance.instantiateImageCodecWithSize(
            buffer,
            getTargetSize: (width, height) {
              final widthLimit = key.targetWidth?.toDouble() ?? width;
              final heightLimit = key.targetHeight?.toDouble() ?? height;
              final scale = math.min(
                1.0,
                math.min(widthLimit / width, heightLimit / height),
              );
              return ui.TargetImageSize(
                width: math.max(1, (width * scale).round()),
                height: math.max(1, (height * scale).round()),
              );
            },
          );
    if (request.cancelled) {
      codec.dispose();
      throw DecodeCancelled();
    }
    return codec;
  }

  void invalidate(String path) {
    _hdrFrames.invalidate(path);
    _icoSelections.removeWhere((key, _) => key.path == path);
    _rawPreviewRejected.removeWhere((key) => key.version.path == path);
    _failures.removeWhere((key, _) => key.version.path == path);
    _revisions[path] = (_revisions[path] ?? 0) + 1;
    _metadata.removeWhere((key, _) => key.path == path);
    _metadataPending.removeWhere((key, _) => key.path == path);
    for (final request in _requests.keys.toList()) {
      if (_requests[request] == path) request.cancel();
    }
    for (final key
        in _imageKeys.where((key) => key.version.path == path).toList()) {
      PaintingBinding.instance.imageCache.evict(key);
      _imageKeys.remove(key);
      _thumbnailKeys.remove(key);
      _thumbnailLru.remove(key);
    }
    thumbnails.retry(path);
    _signalRecovery();
  }

  void retainPaths(Set<String> paths) {
    _hdrFrames.retainPaths(paths);
    _icoSelections.removeWhere((key, _) => !paths.contains(key.path));
    _rawPreviewRejected.removeWhere((key) => !paths.contains(key.version.path));
    _entries.removeWhere((key, _) => !paths.contains(key));
    _metadata.removeWhere((key, _) => !paths.contains(key.path));
    for (final request in _requests.keys.toList()) {
      if (!paths.contains(_requests[request])) request.cancel();
    }
    for (final key in _prefetches.keys.toList()) {
      if (!paths.contains(key.version.path)) _cancelPrefetch(key);
    }
    _evictOutside(paths);
    _imageKeys.removeWhere(
      (key) => !PaintingBinding.instance.imageCache.containsKey(key),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _hdrFrames.dispose();
    HdrVideoWorker.shared.releaseGpu();
    thumbnails.dispose();
    _inflightBudget.onChanged = null;
    _failures.clear();
    _thumbnailCollectionIds.clear();
    _thumbnailLru.clear();
    recovery.dispose();
    _visibleThumbnails.clear();
    _scheduler.dispose();
    for (final key in _prefetches.keys.toList()) {
      _cancelPrefetch(key);
    }
    _metadata.clear();
    _icoSelections.clear();
    _metadataPending.clear();
    _metadataRequests.clear();
    _requestPriorities.clear();
    _codecRequests.clear();
    _evictOutside({});
    _imageKeys.clear();
    _thumbnailKeys.clear();
    _rawPreviewRejected.clear();
    _entries.clear();
  }
}

class _ResourceImageProvider extends ImageProvider<ImageResourceKey> {
  const _ResourceImageProvider({
    required this.service,
    required this.key,
    required this.format,
    required this.priority,
    required this.distance,
  });

  final ImageResourceService service;
  final ImageResourceKey key;
  final ImageFormat format;
  final DecodePriority priority;
  final double distance;

  @override
  Future<ImageResourceKey> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(key);

  @override
  ImageStreamCompleter loadImage(
    ImageResourceKey key,
    ImageDecoderCallback decode,
  ) => _ResourceImageStreamCompleter(
    codec: service._loadCodec(key, format, priority, decode, distance),
    scale: 1,
    debugLabel: key.version.path,
  );
}

class _ResourceImageStreamCompleter extends MultiFrameImageStreamCompleter {
  _ResourceImageStreamCompleter({
    required super.codec,
    required super.scale,
    super.debugLabel,
  });

  @override
  void reportError({
    DiagnosticsNode? context,
    required Object exception,
    StackTrace? stack,
    InformationCollector? informationCollector,
    bool silent = false,
  }) {
    // Navigation and focus changes may cancel speculative work while only the
    // cache's success listener remains. Cancellation is expected, but must still
    // reach error listeners so pending cache keys and visible owners can retry.
    if (exception is DecodeCancelled) {
      if (!hasListeners) return;
      addEphemeralErrorListener((_, _) {});
    }
    super.reportError(
      context: context,
      exception: exception,
      stack: stack,
      informationCollector: informationCollector,
      silent: silent,
    );
  }
}

class _PrefetchHandle {
  _PrefetchHandle(this.stream);
  final ImageStream stream;
  final completer = Completer<void>();
  late final ImageStreamListener listener;

  void cancel() {
    stream.removeListener(listener);
    if (!completer.isCompleted) completer.complete();
  }
}

/// Keeps encoded input and decoder working memory charged for animated codecs.
/// A static provider needs only its first frame, after which ImageCache owns the
/// decoded image and the decoder's buffers can be released immediately.
mixin _ForwardMediaPlayback implements MediaPlaybackCodec {
  ui.Codec get innerCodec;
  MediaPlaybackCodec? get _mediaCodec => innerCodec is MediaPlaybackCodec
      ? innerCodec as MediaPlaybackCodec
      : null;
  @override
  bool get realtime => _mediaCodec?.realtime ?? false;
  @override
  int get audioTrackCount => _mediaCodec?.audioTrackCount ?? 0;
  @override
  Object? get audioError => _mediaCodec?.audioError;
  @override
  void synchronizePlayback({
    required int positionMs,
    required double speed,
    required bool playing,
    required bool muted,
    required int audioTrack,
  }) => _mediaCodec?.synchronizePlayback(
    positionMs: positionMs,
    speed: speed,
    playing: playing,
    muted: muted,
    audioTrack: audioTrack,
  );
}

class _ReservedCodec
    with _ForwardMediaPlayback
    implements ui.Codec, IndexedAnimationCodec {
  _ReservedCodec(
    this._codec,
    this._reservation, {
    this.releaseStaticAfterFrame = false,
    bool firstFrameOnly = false,
  }) : frameCount = firstFrameOnly ? 1 : _codec.frameCount,
       repetitionCount = firstFrameOnly ? 0 : _codec.repetitionCount;

  final ui.Codec _codec;
  @override
  ui.Codec get innerCodec => _codec;
  final ResourceReservation _reservation;
  final bool releaseStaticAfterFrame;
  bool _disposed = false;
  @override
  final int frameCount;
  @override
  final int repetitionCount;

  @override
  Future<ui.FrameInfo> getNextFrame() async {
    try {
      final frame = await _codec.getNextFrame();
      if (releaseStaticAfterFrame && frameCount == 1) dispose();
      return frame;
    } catch (_) {
      // A bad frame must release its peak allocation too; otherwise unrelated
      // pages keep seeing a full budget after the failed image is gone.
      dispose();
      rethrow;
    }
  }

  @override
  bool get supportsFrameIndex =>
      _codec is IndexedAnimationCodec &&
      (_codec as IndexedAnimationCodec).supportsFrameIndex;

  @override
  Future<ui.FrameInfo> getFrame(int index) async {
    try {
      return await (_codec as IndexedAnimationCodec).getFrame(index);
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _codec.dispose();
    _reservation.release();
  }
}

/// Animated frames are decode work too. The long-lived codec owns its memory,
/// while each frame acquires a shared execution slot only for actual decoding.
class _ScheduledAnimationCodec
    with _ForwardMediaPlayback
    implements ui.Codec, IndexedAnimationCodec {
  _ScheduledAnimationCodec(this._codec, this._scheduler, this._request);
  @override
  ui.Codec get innerCodec => _codec;
  final ui.Codec _codec;
  final DecodeScheduler _scheduler;
  final DecodeRequest _request;
  bool _disposed = false;
  @override
  int get frameCount => _codec.frameCount;
  @override
  int get repetitionCount => _codec.repetitionCount;
  @override
  Future<ui.FrameInfo> getNextFrame() => _scheduler.schedule(
    () async {
      if (_disposed) throw DecodeCancelled();
      return _codec.getNextFrame();
    },
    request: _request,
    onDiscard: (frame) => frame.image.dispose(),
  );
  @override
  bool get supportsFrameIndex =>
      _codec is IndexedAnimationCodec &&
      (_codec as IndexedAnimationCodec).supportsFrameIndex;
  @override
  Future<ui.FrameInfo> getFrame(int index) => _scheduler.schedule(
    () async {
      if (_disposed) throw DecodeCancelled();
      return (_codec as IndexedAnimationCodec).getFrame(index);
    },
    request: _request,
    onDiscard: (frame) => frame.image.dispose(),
  );
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _codec.dispose();
  }
}
