import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'decode_request.dart';
import 'format_detector.dart';

enum PhotoMediaKind { heifSequence, motionPhoto }

class PhotoMediaLocation {
  const PhotoMediaLocation(
    this.kind,
    this.offset,
    this.length, {
    this.tracks = const [],
  });
  final PhotoMediaKind kind;
  final int offset, length;
  final List<PhotoMediaTrack> tracks;

  Future<PhotoMediaLease> acquire(String path, {DecodeRequest? request}) async {
    if (offset == 0) return PhotoMediaLease(File(path), null);
    final source = File(path);
    final size = await source.length();
    if (offset < 0 || length <= 0 || offset + length > size) {
      throw const FormatException('Motion Photo video range');
    }
    final directory = await Directory.systemTemp.createTemp('shenview-motion-');
    final file = File('${directory.path}/motion.mp4');
    final input = await source.open();
    final output = await file.open(mode: FileMode.write);
    try {
      await input.setPosition(offset);
      var remaining = length;
      while (remaining > 0) {
        request?.throwIfCancelled();
        final bytes = await input.read(remaining.clamp(0, 1024 * 1024));
        if (bytes.isEmpty) {
          throw const FormatException('Truncated Motion Photo');
        }
        await output.writeFrom(bytes);
        remaining -= bytes.length;
      }
    } catch (_) {
      await output.close();
      await input.close();
      await directory.delete(recursive: true);
      rethrow;
    }
    await output.close();
    await input.close();
    return PhotoMediaLease(file, directory);
  }
}

class PhotoMediaLease {
  PhotoMediaLease(this.file, this._directory);
  final File file;
  final Directory? _directory;
  bool _released = false;
  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _directory?.delete(recursive: true);
  }
}

class PhotoMediaTrack {
  const PhotoMediaTrack(
    this.id,
    this.handler,
    this.references,
    this.auxiliaryType,
  );
  final int id;
  final String handler, auxiliaryType;
  final Map<String, List<int>> references;
  bool get auxiliary =>
      handler == 'auxv' ||
      references.containsKey('auxl') ||
      auxiliaryType.isNotEmpty;
  bool get thumbnail => references.containsKey('thmb');
  bool get alpha =>
      auxiliaryType.contains('alpha') || auxiliaryType.contains('auxid:1');
}

class MediaContainer {
  static bool candidate(String path) => const {
    'jpg',
    'jpeg',
    'jpe',
    'jfif',
    'heic',
    'heif',
    'heics',
    'heifs',
    'hif',
  }.contains(FormatDetector.extensionOf(path));

  static Future<PhotoMediaLocation?> inspect(
    String path, {
    DecodeRequest? request,
  }) async {
    if (!candidate(path)) return null;
    final file = await File(path).open();
    try {
      final size = await file.length();
      final header = await file.read(16);
      request?.throwIfCancelled();
      if (header.length >= 3 && header[0] == 255 && header[1] == 216) {
        return await _jpeg(file, size, request);
      }
      if (header.length < 12 || _tag(header, 4) != 'ftyp') return null;
      var at = 0;
      List<PhotoMediaTrack> tracks = const [];
      for (var count = 0; at + 8 <= size && count < 10000; count++) {
        request?.throwIfCancelled();
        await file.setPosition(at);
        final box = _fileBox(await file.read(16), at, size);
        if (box == null) break;
        if (box.type == 'mpvd') {
          final offset = at + box.header;
          if (await _videoAt(file, offset, box.end - offset)) {
            return PhotoMediaLocation(
              PhotoMediaKind.motionPhoto,
              offset,
              box.end - offset,
            );
          }
        }
        if (box.type == 'ftyp' &&
            at > 0 &&
            await _videoAt(file, at, size - at)) {
          return PhotoMediaLocation(PhotoMediaKind.motionPhoto, at, size - at);
        }
        if (box.type == 'moov' && box.end - at <= 16 * 1024 * 1024) {
          await file.setPosition(at + box.header);
          tracks = _tracks(await file.read(box.end - at - box.header));
        }
        at = box.end;
      }
      return tracks.any(
            (track) => track.handler == 'vide' || track.handler == 'pict',
          )
          ? PhotoMediaLocation(
              PhotoMediaKind.heifSequence,
              0,
              size,
              tracks: tracks,
            )
          : null;
    } finally {
      await file.close();
    }
  }

  static Future<PhotoMediaLocation?> _jpeg(
    RandomAccessFile file,
    int size,
    DecodeRequest? request,
  ) async {
    var at = 2;
    var marked = false;
    // Skip APP segments, including EXIF thumbnails, before looking for primary EOI.
    while (at + 4 <= size) {
      request?.throwIfCancelled();
      await file.setPosition(at);
      final header = await file.read(4);
      if (header.length != 4 || header[0] != 255) return null;
      if (header[1] == 0xda || header[1] == 0xd9) break;
      if (header[1] == 255) {
        at++;
        continue;
      }
      final length = header[2] * 256 + header[3];
      if (length < 2 || at + 2 + length > size) return null;
      if (header[1] == 0xe1) {
        final bytes = await file.read(length - 2);
        final marker = bytes.indexOf(0);
        if (marker > 0 &&
            ascii
                .decode(bytes.sublist(0, marker), allowInvalid: true)
                .contains('ns.adobe.com/xap/')) {
          final xml = utf8.decode(
            bytes.sublist(marker + 1),
            allowMalformed: true,
          );
          marked =
              marked ||
              xml.contains('MotionPhoto') ||
              xml.contains('MicroVideo');
          final range = _xmpRange(xml, size);
          if (range != null && await _videoAt(file, range.$1, range.$2)) {
            return PhotoMediaLocation(
              PhotoMediaKind.motionPhoto,
              range.$1,
              range.$2,
            );
          }
        }
      }
      at += length + 2;
    }
    if (!marked) {
      await file.setPosition((size - 256).clamp(0, size));
      final footer = latin1.decode(await file.read(256));
      if (!footer.contains('SEFT') && !footer.contains('MotionPhoto')) {
        return null;
      }
    }
    await file.setPosition(at);
    var previous = -1;
    while (at < size) {
      request?.throwIfCancelled();
      final chunk = await file.read(64 * 1024);
      if (chunk.isEmpty) break;
      for (var i = 0; i < chunk.length; i++) {
        if (previous == 255 && chunk[i] == 217) {
          final end = at + i + 1;
          await file.setPosition(end);
          final tail = await file.read((size - end).clamp(0, 64 * 1024));
          for (var p = 0; p + 12 <= tail.length; p++) {
            if (_tag(tail, p + 4) == 'ftyp' &&
                await _videoAt(file, end + p, size - end - p)) {
              return PhotoMediaLocation(
                PhotoMediaKind.motionPhoto,
                end + p,
                size - end - p,
              );
            }
          }
          return null;
        }
        previous = chunk[i];
      }
      at += chunk.length;
    }
    return null;
  }

  static (int, int)? _xmpRange(String xml, int size) {
    try {
      final document = XmlDocument.parse(xml);
      final attributes = document.descendants.whereType<XmlElement>().expand(
        (e) => e.attributes,
      );
      for (final attribute in attributes) {
        if (attribute.name.local == 'MicroVideoOffset') {
          final offset = int.tryParse(attribute.value);
          if (offset != null && offset > 0 && offset < size) {
            return (size - offset, offset);
          }
        }
      }
      final items = <(String, int, int)>[];
      for (final element in document.descendants.whereType<XmlElement>()) {
        final attrs = {
          for (final attr in element.attributes) attr.name.local: attr.value,
        };
        if (!attrs.containsKey('Semantic')) continue;
        final length = int.tryParse(attrs['Length'] ?? '0'),
            padding = int.tryParse(attrs['Padding'] ?? '0');
        if (length == null || padding == null || length < 0 || padding < 0) {
          return null;
        }
        items.add((attrs['Semantic']!, length, padding));
      }
      var cursor = size;
      for (final item in items.reversed) {
        cursor -= item.$2 + item.$3;
        if (cursor < 0) return null;
        if (item.$1 == 'MotionPhoto' && item.$2 > 0) return (cursor, item.$2);
      }
    } on XmlParserException {
      return null;
    }
    return null;
  }

  static Future<bool> _videoAt(
    RandomAccessFile file,
    int offset,
    int length,
  ) async {
    if (offset <= 0 || length < 16 || offset + length > await file.length()) {
      return false;
    }
    await file.setPosition(offset);
    final data = await file.read(16);
    final box = _fileBox(data, 0, length);
    if (box?.type != 'ftyp' || box!.end < 16) return false;
    return const {
      'isom',
      'iso2',
      'iso4',
      'iso5',
      'iso6',
      'iso8',
      'mp41',
      'mp42',
      'avc1',
      'qt  ',
      'MSNV',
    }.contains(_tag(data, 8));
  }

  static List<PhotoMediaTrack> _tracks(Uint8List moov) {
    final tracks = <PhotoMediaTrack>[];
    for (final trak in _boxes(
      moov,
      0,
      moov.length,
    ).where((box) => box.type == 'trak')) {
      var id = 0, handler = '', auxiliary = '';
      final references = <String, List<int>>{};
      for (final box in _boxes(moov, trak.start + trak.header, trak.end)) {
        final p = box.start + box.header;
        if (box.type == 'tkhd' && p < box.end) {
          final position = p + (moov[p] == 1 ? 20 : 12);
          if (position + 4 <= box.end) {
            id = ByteData.sublistView(moov).getUint32(position);
          }
        }
        if (box.type == 'tref') {
          for (final ref in _boxes(moov, p, box.end)) {
            references[ref.type] = [
              for (var i = ref.start + ref.header; i + 4 <= ref.end; i += 4)
                ByteData.sublistView(moov).getUint32(i),
            ];
          }
        }
        if (box.type == 'mdia') {
          for (final child in _boxes(moov, p, box.end)) {
            if (child.type == 'hdlr' &&
                child.end - child.start >= child.header + 12) {
              handler = _tag(moov, child.start + child.header + 8);
            }
          }
          final data = latin1.decode(moov.sublist(p, box.end));
          for (final type in const [
            'urn:mpeg:hevc:2015:auxid:1',
            'urn:mpeg:hevc:2015:auxid:2',
            'urn:mpeg:mpegB:cicp:systems:auxiliary:alpha',
            'urn:mpeg:mpegB:cicp:systems:auxiliary:depth',
          ]) {
            if (data.contains(type)) auxiliary = type;
          }
        }
      }
      if (id != 0) {
        tracks.add(PhotoMediaTrack(id, handler, references, auxiliary));
      }
    }
    return tracks;
  }
}

class _Box {
  const _Box(this.type, this.start, this.end, this.header);
  final String type;
  final int start, end, header;
}

String _tag(List<int> bytes, int offset) => offset + 4 <= bytes.length
    ? String.fromCharCodes(bytes.sublist(offset, offset + 4))
    : '';

_Box? _fileBox(Uint8List bytes, int start, int end) {
  if (bytes.length < 8) return null;
  final data = ByteData.sublistView(bytes);
  var size = data.getUint32(0), header = 8;
  if (size == 1) {
    if (bytes.length < 16) return null;
    size = data.getUint64(8);
    header = 16;
  } else if (size == 0) {
    size = end - start;
  }
  if (size < header || size > end - start) return null;
  return _Box(_tag(bytes, 4), start, start + size, header);
}

Iterable<_Box> _boxes(Uint8List bytes, int start, int end) sync* {
  var at = start;
  for (var count = 0; at + 8 <= end && count < 10000; count++) {
    final box = _fileBox(
      Uint8List.sublistView(bytes, at, (at + 16).clamp(at, end)),
      at,
      end,
    );
    if (box == null) return;
    yield box;
    at = box.end;
  }
}
