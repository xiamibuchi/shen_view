import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as imaging;

import '../domain/image_entry.dart';
import 'codec_process.dart';
import 'decode_request.dart';
import 'svg_document.dart';

export 'svg_document.dart';

SvgVersion svgVersion(ImageEntry entry) => (
  id: entry.id,
  modified: entry.modifiedAt.microsecondsSinceEpoch,
  bytes: entry.byteLength,
);

typedef SvgRasterize = Future<Uint8List> Function(
  SvgDocument document,
  int edge,
  DecodeRequest request,
);
typedef SvgRasterKey = ({SvgVersion version, int edge});

class SvgResource {
  const SvgResource(this.version, this.document);
  final SvgVersion version;
  final SvgDocument document;
}

/// SVG consumers share source versions and bounded PNG caches. No method in
/// this class creates a browser: only an active main-view widget may do that.
class SvgResources extends ChangeNotifier {
  SvgResources({
    SvgRasterize? rasterize,
    this.maxRasterBytes = 24 * 1024 * 1024,
    this.maxDocumentBytes = 32 * 1024 * 1024,
  }) : _rasterize = rasterize ?? rasterizeSvg;
  static final shared = SvgResources();
  final SvgRasterize _rasterize;
  final int maxRasterBytes, maxDocumentBytes;
  final _documents = <SvgVersion, SvgResource>{};
  final _reading = <SvgVersion, Future<SvgResource>>{};
  final _rasters = <SvgRasterKey, Uint8List>{};
  final _rendering = <SvgRasterKey, _SvgRasterTask>{};
  final _snapshots = <SvgVersion, Uint8List>{};
  int _documentBytes = 0, _rasterBytes = 0;
  bool _disposed = false;
  int get rasterBytes => _rasterBytes;

  Future<SvgResource> read(File file, {SvgVersion? version}) async {
    final stat = await file.stat();
    final key = version != null && version.id != file.path
        ? version
        : (
            id: file.absolute.path,
            modified: stat.modified.microsecondsSinceEpoch,
            bytes: stat.size,
          );
    final cached = _documents.remove(key);
    if (cached != null) {
      _documents[key] = cached;
      return cached;
    }
    return _reading.putIfAbsent(key, () async {
      try {
        final bytes = await readSvgBytes(file);
        final document = await compute(_parseSvgBytes, bytes);
        final resource = SvgResource(key, document);
        if (!_disposed) {
          // A refreshed local file must not keep publishing the old version.
          for (final old
              in _documents.keys
                  .where((v) => v.id == key.id && v != key)
                  .toList()) {
            _documentBytes -=
                _documents.remove(old)!.document.source.length * 2;
          }
          _documents[key] = resource;
          _documentBytes += document.source.length * 2;
          while (_documents.isNotEmpty &&
              (_documents.length > 32 || _documentBytes > maxDocumentBytes)) {
            _documentBytes -=
                _documents
                    .remove(_documents.keys.first)!
                    .document
                    .source
                    .length *
                2;
          }
        }
        return resource;
      } finally {
        _reading.remove(key);
      }
    });
  }

  Uint8List? snapshot(SvgVersion version) {
    final bytes = _snapshots.remove(version);
    if (bytes != null) _snapshots[version] = bytes;
    return bytes;
  }

  Future<Uint8List> raster(
    SvgResource resource,
    int edge, {
    DecodeRequest? request,
    bool thumbnail = false,
  }) async {
    request?.throwIfCancelled();
    if (thumbnail) {
      final shot = snapshot(resource.version);
      if (shot != null) return shot;
    }
    final key = (version: resource.version, edge: edge.clamp(1, 4096));
    final cached = _rasters.remove(key);
    if (cached != null) {
      _rasters[key] = cached;
      return cached;
    }
    var task = _rendering[key];
    if (task == null) {
      task = _SvgRasterTask();
      _rendering[key] = task;
      final work = task;
      work.future =
          Future.sync(
                () => _rasterize(resource.document, key.edge, work.request),
              )
              .then((bytes) {
                if (!_disposed &&
                    !work.request.cancelled &&
                    bytes.length <= maxRasterBytes) {
                  _rasters[key] = bytes;
                  _rasterBytes += bytes.length;
                  _trim();
                }
                return bytes;
              })
              .whenComplete(() {
                work.complete = true;
                if (identical(_rendering[key], work)) _rendering.remove(key);
              });
    }
    final work = task;
    work.users++;
    var released = false;
    void release() {
      if (released) return;
      released = true;
      work.users--;
      if (work.users == 0 && !work.complete) {
        work.request.cancel();
        if (identical(_rendering[key], work)) _rendering.remove(key);
      }
    }

    request?.addCancelListener(release);
    try {
      final result = await work.future;
      request?.throwIfCancelled();
      return thumbnail ? snapshot(resource.version) ?? result : result;
    } finally {
      request?.removeCancelListener(release);
      release();
    }
  }

  Future<void> publishSnapshot(
    SvgVersion version,
    Uint8List png, {
    bool Function()? isCurrent,
  }) async {
    if (_disposed || png.length > 32 * 1024 * 1024) return;
    final resized = await compute(resizeSvgSnapshot, png);
    if (_disposed || resized == null || !(isCurrent?.call() ?? true)) return;
    _rasterBytes -= _snapshots.remove(version)?.length ?? 0;
    if (resized.length > maxRasterBytes) return;
    _snapshots[version] = resized;
    _rasterBytes += resized.length;
    _trim();
    notifyListeners();
  }

  void _trim() {
    while (_rasters.isNotEmpty &&
        (_rasterBytes > maxRasterBytes || _rasters.length > 96)) {
      _rasterBytes -= _rasters.remove(_rasters.keys.first)!.length;
    }
    while (_snapshots.isNotEmpty &&
        (_rasterBytes > maxRasterBytes || _snapshots.length > 64)) {
      _rasterBytes -= _snapshots.remove(_snapshots.keys.first)!.length;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final task in _rendering.values) {
      task.request.cancel();
    }
    _rendering.clear();
    _documents.clear();
    _rasters.clear();
    _snapshots.clear();
    super.dispose();
  }
}

class _SvgRasterTask {
  final request = DecodeRequest();
  late Future<Uint8List> future;
  int users = 0;
  bool complete = false;
}

Uint8List? resizeSvgSnapshot(Uint8List png) {
  final decoder = imaging.PngDecoder();
  final info = decoder.startDecode(png);
  if (info == null || info.width * info.height > 8 * 1024 * 1024) return null;
  final image = decoder.decodeFrame(0);
  if (image == null) return null;
  final scale = math.min(1.0, 512 / math.max(image.width, image.height));
  final resized = imaging.copyResize(
    image,
    width: math.max(1, (image.width * scale).round()),
    height: math.max(1, (image.height * scale).round()),
    interpolation: imaging.Interpolation.average,
  );
  return Uint8List.fromList(imaging.encodePng(resized));
}

double svgPngScale(Uint8List bytes, SvgDocument document) {
  if (bytes.length < 24) return 1;
  final width = ByteData.sublistView(bytes).getUint32(16);
  return width > 0 ? width / document.width : 1;
}

Future<Uint8List> rasterizeSvg(
  SvgDocument document,
  int edge,
  DecodeRequest request,
) async {
  final executable = await CodecProcess.locate('resvg', 'SHENVIEW_RESVG');
  final maxSource = math.max(document.width, document.height);
  final scale = math.min(
    edge / maxSource,
    math.sqrt(4 * 1024 * 1024 / (document.width * document.height)),
  );
  final width = math.max(1, (document.width * scale).round());
  return CodecProcess.run(
    executable,
    ['--width', '$width', '-', '-c'],
    input: Uint8List.fromList(utf8.encode(normalizeSvgSource(document.source))),
    request: request,
    timeout: const Duration(seconds: 20),
    maxOutput: 24 * 1024 * 1024,
  );
}

/// Approximate static posters only. Browser routing always analyzes raw CSS
/// before this legacy normalization; it is never applied to the live document.
String normalizeSvgSource(String source) {
  final variables = <String, String>{};
  for (final match in RegExp(
    r'--([A-Za-z0-9_-]+)\s*:\s*([^;{}]+)',
  ).allMatches(source)) {
    variables['--${match.group(1)}'] = match.group(2)!.trim();
  }
  return source
      .replaceAllMapped(
        RegExp(r'var\(\s*(--[A-Za-z0-9_-]+)(?:\s*,\s*([^)]*))?\s*\)'),
        (match) =>
            variables[match.group(1)] ?? match.group(2)?.trim() ?? 'none',
      )
      .replaceAll(RegExp(r'@font-face\s*\{.*?\}', dotAll: true), '');
}

SvgDocument _parseSvgBytes(Uint8List bytes) =>
    SvgDocument.parse(utf8.decode(bytes));
