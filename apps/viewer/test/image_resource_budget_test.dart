import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/decode_scheduler.dart';
import 'package:shen_view/src/application/decode_fallback.dart';
import 'package:shen_view/src/application/image_resource_service.dart';
import 'package:shen_view/src/application/hdr_decoder.dart';
import 'package:shen_view/src/application/hdr_frame.dart';
import 'package:shen_view/src/application/hdr_input_metadata.dart';
import 'package:shen_view/src/application/image_source.dart';
import 'package:shen_view/src/application/native_decoder.dart';
import 'package:shen_view/src/application/platform_image_decoder.dart';
import 'package:shen_view/src/application/prefetch_planner.dart';
import 'package:shen_view/src/application/prefetch_policy.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';

class _Source implements ImageSource {
  _Source(
    this.id, {
    this.gate,
    this.releaseGate,
    this.filePath = 'testdata/formats/format_static.png',
  });
  final String filePath;
  final Completer<void>? gate;
  final Completer<void>? releaseGate;
  @override
  final String id;
  @override
  String get name => 'page.png';
  @override
  String get relativePath => 'chapter/page.png';
  @override
  bool get sensitive => false;
  int acquisitions = 0;
  int releases = 0;
  final started = Completer<void>();
  DecodeRequest? request;
  @override
  Future<SourceFileLease> acquireFile({DecodeRequest? request}) async {
    this.request = request;
    acquisitions++;
    if (!started.isCompleted) started.complete();
    await gate?.future;
    // Deliberately return a lease even after cancellation to verify cleanup.
    return SourceFileLease(
      File(filePath),
      onRelease: () async {
        releases++;
        await releaseGate?.future;
      },
    );
  }
}

class _PreviewDecoder extends NativeDecoder {
  int calls = 0;
  int? width;
  int? height;
  @override
  Future<PlatformDecodedImage?> decodePlatform(
    String path, {
    int? targetWidth,
    int? targetHeight,
    Map<String, int>? region,
    bool preserveHdr = false,
    DecodeRequest? request,
  }) async {
    calls++;
    width = targetWidth;
    height = targetHeight;
    return PlatformDecodedImage(
      width: 1,
      height: 1,
      pixels: Uint8List.fromList([1, 2, 3, 255]),
    );
  }
}

class _HeldHdrDecoder extends HdrDecoder {
  final started = Completer<void>();
  final release = Completer<HdrFrame>();
  int calls = 0;
  @override
  Future<HdrFrame> decode(
    String path,
    DecodeRequest request, {
    HdrInputMetadata? metadata,
  }) {
    calls++;
    if (!started.isCompleted) started.complete();
    return release.future;
  }
}

class _HeldPreviewDecoder extends _PreviewDecoder {
  final started = Completer<DecodeRequest?>();
  final release = Completer<void>();
  @override
  Future<PlatformDecodedImage?> decodePlatform(
    String path, {
    int? targetWidth,
    int? targetHeight,
    Map<String, int>? region,
    bool preserveHdr = false,
    DecodeRequest? request,
  }) async {
    started.complete(request);
    await release.future;
    return super.decodePlatform(
      path,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      request: request,
    );
  }
}

class _FallbackDecoder extends NativeDecoder {
  bool success = false;
  bool timeout = false;
  int platforms = 0;
  int compatible = 0;
  @override
  Future<PlatformDecodedImage?> decodePlatform(
    String path, {
    int? targetWidth,
    int? targetHeight,
    Map<String, int>? region,
    bool preserveHdr = false,
    DecodeRequest? request,
  }) async {
    platforms++;
    return success
        ? PlatformDecodedImage(
            width: 1,
            height: 1,
            pixels: Uint8List.fromList([1, 2, 3, 255]),
          )
        : null;
  }

  @override
  Future<Uint8List> decode(
    String path, {
    int? targetWidth,
    int? targetHeight,
    DecodeRequest? request,
    int frame = 0,
    String? crop,
    bool Function()? allowTimeoutFallback,
  }) async {
    compatible++;
    if (timeout) throw DecodeTimedOut('test timeout');
    throw StateError('corrupt');
  }
}

ImageEntry _entry(_Source source) => ImageEntry.fromSource(
  source: source,
  format: ImageFormat.png,
  width: 32,
  height: 32,
  byteLength: 1024,
  modifiedAt: DateTime(2026, 10, 20),
);

Future<ui.Image> load(ImageProvider<Object> provider) {
  final done = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      done.complete(info.image.clone());
      stream.removeListener(listener);
    },
    onError: (Object error, StackTrace? stack) {
      done.completeError(error, stack);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return done.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  test(
    'successful main images survive leaving the prefetch working set',
    () async {
      final decoder = _PreviewDecoder();
      final resources = ImageResourceService(decoder: decoder);
      addTearDown(resources.dispose);
      final source = _Source('cached-main');
      final entry = ImageEntry.fromSource(
        source: source,
        format: ImageFormat.psd,
        width: 32,
        height: 32,
        byteLength: 100,
        modifiedAt: DateTime(2026),
      );
      (await load(
        resources.provider(entry, targetWidth: 256, targetHeight: 256),
      )).dispose();
      resources.applyWorkingSet(
        protectedIds: {'far-away'},
        retainedIds: {'far-away'},
      );
      expect(resources.cachedIds, contains(entry.id));
      (await load(
        resources.provider(entry, targetWidth: 256, targetHeight: 256),
      )).dispose();
      expect(decoder.calls, 1);
      expect(source.acquisitions, 1);
      expect(resources.inflightBytes, 0);
    },
  );

  test(
    'cached SDR main supplies a thumbnail immediately while HDR is pending',
    () async {
      final hdr = _HeldHdrDecoder();
      final decoder = _PreviewDecoder();
      final resources = ImageResourceService(decoder: decoder, hdrDecoder: hdr);
      addTearDown(resources.dispose);
      final source = _Source('cached-sdr');
      final entry = ImageEntry.fromSource(
        source: source,
        format: ImageFormat.psd,
        width: 32,
        height: 32,
        byteLength: 100,
        modifiedAt: DateTime(2026),
      );
      (await load(
        resources.provider(entry, targetWidth: 256, targetHeight: 256),
      )).dispose();
      final hdrRequest = DecodeRequest();
      final pending = resources.runHdrTask(entry, hdrRequest, () async {
        await resources.hdrFrame(entry, hdrRequest);
        return true;
      });
      await hdr.started.future;
      final thumbnail = await load(
        resources.provider(
          entry,
          targetWidth: 96,
          targetHeight: 72,
          priority: DecodePriority.visibleThumbnail,
        ),
      ).timeout(const Duration(seconds: 1));
      thumbnail.dispose();
      expect(hdr.release.isCompleted, false);
      expect(decoder.calls, 1);
      hdr.release.complete(HdrFrame(1, 1, Uint8List(16)));
      await pending;
      expect(
        PaintingBinding.instance.imageCache.maximumSizeBytes,
        resources.memoryBudgetBytes ~/ 2 - 16,
      );
    },
  );

  test(
    'thumbnail without SDR fallback joins an existing HDR source decode',
    () async {
      final hdr = _HeldHdrDecoder();
      final resources = ImageResourceService(hdrDecoder: hdr);
      addTearDown(resources.dispose);
      final source = _Source(
        'uncached-hdr',
        filePath: 'testdata/formats/hdr_hlg.avif',
      );
      final entry = ImageEntry.fromSource(
        source: source,
        format: ImageFormat.avif,
        width: 32,
        height: 32,
        byteLength: 100,
        modifiedAt: DateTime(2026),
      );
      resources.setThumbnailCollection('hdr', [entry]);
      final main = resources.hdrFrame(entry, DecodeRequest());
      await hdr.started.future;
      final thumbnail = load(
        resources.provider(
          entry,
          targetWidth: 96,
          targetHeight: 72,
          priority: DecodePriority.visibleThumbnail,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      hdr.release.complete(HdrFrame(1, 1, Uint8List(16)));
      await main;
      (await thumbnail).dispose();
      expect(hdr.calls, 1);
      expect(source.acquisitions, source.releases);
      expect(resources.inflightBytes, 0);
    },
  );

  test('large encoded preview preserves foreground memory and cancellation holds actual work', () async {
    final decoder = _HeldPreviewDecoder();
    final resources = ImageResourceService(
      decoder: decoder,
      prefetchPolicy: AdaptivePrefetchPolicy(
        physicalMemoryBytes: 16 * 1024 * 1024 * 1024,
        availableMemoryBytes: 8 * 1024 * 1024 * 1024,
      ),
    );
    addTearDown(resources.dispose);
    final source = _Source('archive:large-png-preview');
    final entry = ImageEntry.fromSource(
      source: source,
      format: ImageFormat.png,
      width: 12000,
      height: 8000,
      byteLength: 120 * 1024 * 1024,
      modifiedAt: DateTime(2026, 10, 24),
    );
    resources.applyWorkingSet(
      protectedIds: {},
      retainedIds: {source.id},
      memoryBudgetBytes: 8 * 1024 * 1024,
    );
    resources.retainThumbnail(source.id);
    final pending = load(
      resources.provider(
        entry,
        targetWidth: 256,
        targetHeight: 144,
        priority: DecodePriority.visibleThumbnail,
      ),
    );
    final cancelled = expectLater(pending, throwsA(isA<DecodeCancelled>()));
    try {
      final request = await decoder.started.future.timeout(
        const Duration(seconds: 5),
      );
      expect(request!.priority, DecodePriority.visibleThumbnail);
      expect(resources.inflightBytes, inInclusiveRange(1, 2 * 1024 * 1024));
      final main = await load(
        resources.provider(_entry(_Source('archive:main-during-preview'))),
      ).timeout(const Duration(seconds: 5));
      main.dispose();
      resources.releaseThumbnail(source.id);
      expect(request.cancelled, true);
      expect(resources.inflightBytes, greaterThan(0));
    } finally {
      decoder.release.complete();
    }
    await cancelled;
    expect(resources.inflightBytes, 0);
  });

  test(
    'source cleanup does not hold a decoded frame or the only decode slot',
    () async {
      final release = Completer<void>();
      final scheduler = DecodeScheduler(maxConcurrent: 1);
      final resources = ImageResourceService(scheduler: scheduler);
      addTearDown(resources.dispose);
      final first = _Source('archive:cleanup-first', releaseGate: release);
      final second = _Source('archive:cleanup-second');
      try {
        final frame = await load(resources.provider(_entry(first)))
            .timeout(const Duration(seconds: 5));
        frame.dispose();
        expect(first.releases, 1);
        expect(release.isCompleted, isFalse);
        final next = await load(resources.provider(_entry(second)))
            .timeout(const Duration(seconds: 5));
        next.dispose();
        expect(scheduler.runningCount, 0);
      } finally {
        release.complete();
      }
    },
  );

  test('failed background decode is retried once for visible demand and caches the result', () async {
    final decoder = _FallbackDecoder()..timeout = true;
    final resources = ImageResourceService(decoder: decoder);
    addTearDown(resources.dispose);
    final source = _Source('archive:fallback');
    final entry = ImageEntry.fromSource(
      source: source,
      format: ImageFormat.dds,
      width: 32,
      height: 32,
      byteLength: 1024,
      modifiedAt: DateTime(2026),
    );
    resources.setThumbnailCollection('fallback', [entry]);
    await expectLater(
      load(
        resources.provider(
          entry,
          targetWidth: 96,
          targetHeight: 72,
          priority: DecodePriority.thumbnail,
        ),
      ),
      throwsA(isA<DecodeTimedOut>()),
    );
    decoder.success = true;
    final image = await load(
      resources.provider(
        entry,
        targetWidth: 96,
        targetHeight: 72,
        priority: DecodePriority.visibleThumbnail,
      ),
    );
    expect(image.width, 1);
    image.dispose();
    for (var repeat = 0; repeat < 3; repeat++) {
      final cached = await load(
        resources.provider(
          entry,
          targetWidth: 96,
          targetHeight: 72,
          priority: DecodePriority.visibleThumbnail,
        ),
      );
      cached.dispose();
    }
    expect(decoder.platforms, 2);
    expect(decoder.compatible, 1);
    expect(source.acquisitions, source.releases);
    expect(resources.inflightBytes, 0);
  });

  test('terminal failures stay cached until manual retry changes the file revision', () async {
    final decoder = _FallbackDecoder();
    final resources = ImageResourceService(decoder: decoder);
    addTearDown(resources.dispose);
    final source = _Source('archive:corrupt');
    final entry = ImageEntry.fromSource(
      source: source,
      format: ImageFormat.dds,
      width: 32,
      height: 32,
      byteLength: 1024,
      modifiedAt: DateTime(2026),
    );
    for (var i = 0; i < 2; i++) {
      await expectLater(
        load(resources.provider(entry)),
        throwsA(isA<ImageDecodeFailure>()),
      );
    }
    expect(decoder.platforms, 1);
    expect(decoder.compatible, 1);
    resources.invalidate(entry.id);
    decoder.success = true;
    final image = await load(resources.provider(entry));
    image.dispose();
    expect(decoder.platforms, 2);
    expect(resources.inflightBytes, 0);
  });

  testWidgets(
    'viewer teardown cancels queued codecs without unhandled image errors',
    (tester) async {
      final scheduler = DecodeScheduler(maxConcurrent: 1);
      final resources = ImageResourceService(scheduler: scheduler);
      final gate = Completer<void>();
      final blocker = scheduler.schedule(
        () => gate.future,
        request: DecodeRequest(),
      );
      final blockerCancelled = expectLater(
        blocker,
        throwsA(isA<DecodeCancelled>()),
      );
      final sources = [
        _Source('archive:queued-1'),
        _Source('archive:queued-2'),
      ];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              for (final source in sources)
                Image(image: resources.provider(_entry(source))),
            ],
          ),
        ),
      );
      expect(scheduler.queuedCount, 2);
      expect(sources.every((source) => source.acquisitions == 0), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      resources.dispose();
      gate.complete();
      await tester.pump();
      await blockerCancelled;
      expect(scheduler.queuedCount, 0);
      expect(tester.takeException(), isNull);
      expect(PaintingBinding.instance.imageCache.pendingImageCount, 0);
    },
  );

  test(
    'queued cancellation still reaches active image error listeners',
    () async {
      final scheduler = DecodeScheduler(maxConcurrent: 1);
      final resources = ImageResourceService(scheduler: scheduler);
      final gate = Completer<void>();
      final blocker = scheduler.schedule(
        () => gate.future,
        request: DecodeRequest(),
      );
      final blockerCancelled = expectLater(
        blocker,
        throwsA(isA<DecodeCancelled>()),
      );
      final imageCancelled = expectLater(
        load(resources.provider(_entry(_Source('archive:listened-cancel')))),
        throwsA(isA<DecodeCancelled>()),
      );
      expect(scheduler.queuedCount, 1);
      resources.dispose();
      gate.complete();
      await Future.wait([blockerCancelled, imageCancelled]);
      expect(PaintingBinding.instance.imageCache.pendingImageCount, 0);
    },
  );

  test('large native source uses bounded preview output without reserving source file bytes', () async {
    final decoder = _PreviewDecoder();
    final resources = ImageResourceService(decoder: decoder);
    addTearDown(resources.dispose);
    final source = _Source('archive:large-psd');
    final imageEntry = ImageEntry.fromSource(
      source: source,
      format: ImageFormat.psd,
      width: 4096,
      height: 2160,
      byteLength: 53 * 1024 * 1024,
      modifiedAt: DateTime(2026, 10, 20),
    );
    resources.applyWorkingSet(
      protectedIds: {source.id},
      retainedIds: {source.id},
      memoryBudgetBytes: 2 * 1024 * 1024,
    );
    final image = await load(
      resources.provider(imageEntry, targetWidth: 256, targetHeight: 144),
    );
    image.dispose();
    expect((decoder.width, decoder.height), (256, 135));
    expect(resources.memoryBudgetBytes, 2 * 1024 * 1024);
    expect(resources.inflightBytes, 0);
    expect(source.releases, 1);
  });

  test(
    'full Flutter encoded buffers still require their actual byte cost',
    () async {
      final resources = ImageResourceService();
      addTearDown(resources.dispose);
      final source = _Source('archive:large-png');
      final imageEntry = ImageEntry.fromSource(
        source: source,
        format: ImageFormat.png,
        width: 4096,
        height: 2160,
        byteLength: 53 * 1024 * 1024,
        modifiedAt: DateTime(2026, 10, 20),
      );
      resources.applyWorkingSet(
        protectedIds: {source.id},
        retainedIds: {source.id},
        memoryBudgetBytes: 2 * 1024 * 1024,
      );
      await expectLater(
        load(
          resources.provider(imageEntry, targetWidth: 256, targetHeight: 144),
        ),
        throwsStateError,
      );
      expect(source.acquisitions, 0);
      expect(resources.inflightBytes, 0);
    },
  );

  test('foreground joins prefetched output and keeps its source lease until decoding finishes', () async {
    final resources = ImageResourceService();
    addTearDown(resources.dispose);
    final gate = Completer<void>();
    final source = _Source('archive:1', gate: gate);
    final imageEntry = _entry(source);
    resources.applyWorkingSet(
      protectedIds: {},
      retainedIds: {source.id},
      tasks: {
        source.id: const PrefetchTask(
          index: 1,
          priority: DecodePriority.adjacent,
          distance: 1,
        ),
      },
      memoryBudgetBytes: 8 * 1024 * 1024,
    );
    final preload = resources.prefetch(
      imageEntry,
      targetWidth: 16,
      targetHeight: 16,
    );
    await source.started.future;
    expect(source.releases, 0);
    expect(resources.inflightBytes, greaterThan(0));
    resources.applyWorkingSet(
      protectedIds: {source.id},
      retainedIds: {source.id},
      memoryBudgetBytes: 8 * 1024 * 1024,
    );
    final visible = load(
      resources.provider(imageEntry, targetWidth: 16, targetHeight: 16),
    );
    gate.complete();
    final image = await visible;
    image.dispose();
    await preload;
    expect(source.acquisitions, 1);
    expect(source.releases, 1);
    expect(resources.inflightBytes, 0);
    expect(resources.cachedIds, contains(source.id));
    expect(
      PaintingBinding.instance.imageCache.maximumSizeBytes,
      4 * 1024 * 1024,
    );
  });

  test('fast jump cancels stale prefetch, releases late lease, and never repopulates cache', () async {
    final resources = ImageResourceService();
    addTearDown(resources.dispose);
    final gate = Completer<void>();
    final source = _Source('archive:stale', gate: gate);
    resources.applyWorkingSet(
      protectedIds: {},
      retainedIds: {source.id},
      tasks: {
        source.id: const PrefetchTask(
          index: 1,
          priority: DecodePriority.adjacent,
          distance: 1,
        ),
      },
    );
    final preload = resources.prefetch(
      _entry(source),
      targetWidth: 16,
      targetHeight: 16,
    );
    await source.started.future;
    resources.applyWorkingSet(
      protectedIds: {'archive:new'},
      retainedIds: {'archive:new'},
    );
    expect(source.request!.cancelled, true);
    gate.complete();
    await preload;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(source.releases, 1);
    expect(resources.inflightBytes, 0);
    expect(resources.cachedIds, isNot(contains(source.id)));
  });

  test('memory pressure keeps visible cached frame but removes remote cache and blocks prefetch', () async {
    final resources = ImageResourceService();
    addTearDown(resources.dispose);
    final visibleSource = _Source('archive:visible');
    final remoteSource = _Source('archive:remote');
    final current = await load(
      resources.provider(
        _entry(visibleSource),
        targetWidth: 16,
        targetHeight: 16,
      ),
    );
    final remote = await load(
      resources.provider(
        _entry(remoteSource),
        targetWidth: 16,
        targetHeight: 16,
      ),
    );
    current.dispose();
    remote.dispose();
    resources.applyWorkingSet(
      protectedIds: {visibleSource.id},
      retainedIds: {visibleSource.id, remoteSource.id},
    );
    resources.memoryPressure();
    expect(resources.policy.level, PrefetchLevel.onDemand);
    expect(resources.cachedIds, contains(visibleSource.id));
    expect(resources.cachedIds, isNot(contains(remoteSource.id)));
    final next = _Source('archive:next');
    await resources.prefetch(_entry(next));
    expect(next.acquisitions, 0);
  });

  test(
    'custom animation codec retains its byte reservation until disposal',
    () async {
      final resources = ImageResourceService();
      addTearDown(resources.dispose);
      final source = _Source('archive:animated');
      final codec = await resources.animationCodec(
        _entry(source),
        targetWidth: 16,
        targetHeight: 16,
        request: DecodeRequest(),
      );
      expect(resources.inflightBytes, greaterThan(0));
      codec.dispose();
      codec.dispose();
      expect(resources.inflightBytes, 0);
      expect(source.releases, 1);
    },
  );

  test('mounted thumbnails remain demand outside the main working set while inactive', () async {
    final resources = ImageResourceService();
    addTearDown(resources.dispose);
    final gate = Completer<void>();
    final source = _Source('archive:strip-visible', gate: gate);
    resources.retainThumbnail(source.id);
    final result = load(
      resources.provider(
        _entry(source),
        targetWidth: 100,
        targetHeight: 72,
        priority: DecodePriority.visibleThumbnail,
      ),
    );
    await source.started.future;
    resources.setActive(false);
    resources.applyWorkingSet(protectedIds: {'other'}, retainedIds: {'other'});
    resources.memoryPressure();
    expect(source.request!.cancelled, isFalse);
    gate.complete();
    final image = await result;
    image.dispose();
    expect(resources.cachedIds, contains(source.id));
    resources.releaseThumbnail(source.id);

    final inactiveSource = _Source('archive:new-strip-visible');
    resources.retainThumbnail(inactiveSource.id);
    final next = await load(
      resources.provider(
        _entry(inactiveSource),
        targetWidth: 100,
        targetHeight: 72,
        priority: DecodePriority.visibleThumbnail,
      ),
    );
    next.dispose();
    resources.releaseThumbnail(inactiveSource.id);
    expect(inactiveSource.acquisitions, 1);
  });

  test('a tile leaving the strip cancels its pending decode and releases the late lease', () async {
    final resources = ImageResourceService();
    addTearDown(resources.dispose);
    final gate = Completer<void>();
    final source = _Source('archive:strip-scrolled-away', gate: gate);
    resources.retainThumbnail(source.id);
    final cancelled = expectLater(
      load(
        resources.provider(
          _entry(source),
          targetWidth: 100,
          targetHeight: 72,
          priority: DecodePriority.visibleThumbnail,
        ),
      ),
      throwsA(isA<DecodeCancelled>()),
    );
    await source.started.future;
    resources.releaseThumbnail(source.id);
    expect(source.request!.cancelled, isTrue);
    gate.complete();
    await cancelled;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(source.releases, 1);
    expect(resources.inflightBytes, 0);
  });

  test(
    'temporary budget contention waits for a codec release instead of failing',
    () async {
      final resources = ImageResourceService();
      addTearDown(resources.dispose);
      final source = _Source('archive:held-animation');
      final codec = await resources.animationCodec(
        ImageEntry.fromSource(
          source: source,
          format: ImageFormat.png,
          byteLength: 1024,
          modifiedAt: DateTime(2026),
        ),
        targetWidth: 1024,
        targetHeight: 1024,
        request: DecodeRequest(),
      );
      expect(resources.inflightBytes, greaterThan(2 * 1024 * 1024));
      final next = _Source('archive:waiting-visible');
      resources.applyWorkingSet(
        protectedIds: {next.id},
        retainedIds: {next.id},
        memoryBudgetBytes: 4 * 1024 * 1024,
      );
      final result = load(resources.provider(_entry(next)));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(next.acquisitions, 0);
      codec.dispose();
      final image = await result;
      image.dispose();
      expect(next.acquisitions, 1);
      expect(resources.inflightBytes, 0);
    },
  );

  test(
    'leaving a page cancels its budget wait without leaking reservations',
    () async {
      final resources = ImageResourceService();
      addTearDown(resources.dispose);
      final held = await resources.animationCodec(
        ImageEntry.fromSource(
          source: _Source('held'),
          format: ImageFormat.png,
          byteLength: 1024,
          modifiedAt: DateTime(2026),
        ),
        targetWidth: 1024,
        targetHeight: 1024,
        request: DecodeRequest(),
      );
      final next = _Source('waiting');
      resources.applyWorkingSet(
        protectedIds: {next.id},
        retainedIds: {next.id},
        memoryBudgetBytes: 4 * 1024 * 1024,
      );
      final cancelled = expectLater(
        load(resources.provider(_entry(next))),
        throwsA(isA<DecodeCancelled>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      resources.applyWorkingSet(
        protectedIds: {'other'},
        retainedIds: {'other'},
        memoryBudgetBytes: 4 * 1024 * 1024,
      );
      await cancelled;
      expect(next.acquisitions, 0);
      held.dispose();
      expect(resources.inflightBytes, 0);
    },
  );
}
