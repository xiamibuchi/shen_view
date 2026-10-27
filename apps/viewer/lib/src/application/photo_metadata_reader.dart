import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as paths;

import 'codec_process.dart';
import 'decode_request.dart';
import 'xmp_metadata.dart';

class PhotoMetadataReader {
  static const budget = 4 * 1024 * 1024;
  static const descriptiveKeys = {
    'title',
    'description',
    'creator',
    'copyright',
    'rating',
    'keywords',
  };

  /// Seeks over encoded pixels, so WebP/PNG metadata after the image data is
  /// still available without loading or decoding the image.
  static Map<String, String> read(String path, {bool includeSidecars = true}) {
    final values = <String, String>{};
    final input = _MetadataFile(File(path).openSync());
    try {
      final head = input.read(0, input.length.clamp(0, 16));
      if (head.length >= 2 && head[0] == 255 && head[1] == 216) {
        _jpeg(input, values);
      } else if (head.length >= 8 &&
          head[0] == 137 &&
          ascii.decode(head.sublist(1, 4)) == 'PNG') {
        _chunks(input, values, png: true);
      } else if (head.length >= 12 &&
          ascii.decode(head.sublist(8, 12)) == 'WEBP') {
        _chunks(input, values, png: false);
      } else if (head.length >= 8 &&
          (head[0] == 73 || head[0] == 77) &&
          head[0] == head[1]) {
        _Tiff(input.read, input.length, values).parse();
      }
    } on Object {
      // Optional, damaged or over-budget metadata must not hide a valid image.
    } finally {
      input.file.closeSync();
    }
    if (values['colorSpace'] == 'Adobe RGB (1998)') {
      values['unprofiledAdobeRgb'] = 'true';
    }
    if (includeSidecars) readSidecars(path, values);
    return values;
  }

  static void readSidecars(String path, Map<String, String> values) {
    for (final candidate in {
      paths.setExtension(path, '.xmp'),
      '$path.xmp',
      paths.setExtension(path, '.XMP'),
      '$path.XMP',
    }) {
      if (candidate == path) continue;
      try {
        final sidecar = File(candidate);
        if (!sidecar.existsSync() || sidecar.lengthSync() > 2 * 1024 * 1024) {
          continue;
        }
        mergeXmp(values, sidecar.readAsBytesSync());
        break;
      } on Object {
        // Missing and unreadable sidecars leave embedded metadata intact.
      }
    }
  }

  static void mergeXmp(Map<String, String> values, Uint8List bytes) {
    for (final entry in readXmpMetadata(bytes).entries) {
      if (descriptiveKeys.contains(entry.key)) {
        values[entry.key] = entry.value;
      } else {
        values.putIfAbsent(entry.key, () => entry.value);
      }
    }
  }

  static Future<Map<String, String>> readHeif(
    String path, {
    DecodeRequest? request,
  }) async {
    final helper = await CodecProcess.locate(
      'viewer_heif_gainmap',
      'SHENVIEW_HEIF_GAINMAP',
    );
    final bytes = await CodecProcess.run(
      helper,
      ['metadata', path],
      request: request,
      maxOutput: budget + 16384,
    );
    final values = await Isolate.run(() => _parseHeif(bytes));
    request?.throwIfCancelled();
    return values;
  }

  static Map<String, String> _parseHeif(Uint8List bytes) {
    final values = <String, String>{};
    var offset = 0;
    while (offset < bytes.length) {
      final end = bytes.indexOf(10, offset);
      if (end < 0 || end - offset > 128) {
        throw const FormatException('HEIF metadata header');
      }
      final header = ascii.decode(bytes.sublist(offset, end)).split(' ');
      if (header.length != 2) {
        throw const FormatException('HEIF metadata header');
      }
      final size = int.parse(header[1]);
      offset = end + 1;
      if (size < 0 || size > budget || size > bytes.length - offset) {
        throw const FormatException('HEIF metadata bounds');
      }
      final block = Uint8List.sublistView(bytes, offset, offset + size);
      switch (header[0]) {
        case 'EXIF':
          // HEIF prefixes Exif with a big-endian offset to its TIFF header.
          if (block.length >= 4) {
            final start = 4 + ByteData.sublistView(block).getUint32(0);
            if (start <= block.length) _exif(block.sublist(start), values);
          }
        case 'XMP':
          mergeXmp(values, block);
        case 'COLOR':
          values['colorSpace'] = utf8.decode(block);
        case 'ICC':
          values['colorSpace'] = iccProfileLabel(block);
        default:
          throw const FormatException('HEIF metadata block');
      }
      offset += size;
    }
    return values;
  }

  static void _jpeg(_MetadataFile input, Map<String, String> values) {
    var offset = 2;
    final icc = <int, Uint8List>{};
    var iccCount = 0;
    for (var count = 0; count < 4096 && offset + 4 <= input.length; count++) {
      var marker = input.read(offset++, 1)[0];
      if (marker != 255) break;
      do {
        marker = input.read(offset++, 1)[0];
      } while (marker == 255);
      if (marker == 218 || marker == 217) break;
      if (marker == 1 || marker >= 208 && marker <= 215) continue;
      final size = ByteData.sublistView(input.read(offset, 2)).getUint16(0);
      if (size < 2 || size > input.length - offset) break;
      if (marker == 225 || marker == 226) {
        final bytes = input.read(offset + 2, size - 2);
        final text = latin1.decode(bytes);
        if (text.startsWith('Exif\u0000\u0000')) {
          _exif(bytes.sublist(6), values);
        } else if (text.startsWith('http://ns.adobe.com/xap/1.0/\u0000')) {
          mergeXmp(values, bytes.sublist(29));
        } else if (text.startsWith('ICC_PROFILE\u0000') && bytes.length >= 14) {
          final index = bytes[12], total = bytes[13];
          if (index > 0 &&
              index <= total &&
              (iccCount == 0 || iccCount == total)) {
            iccCount = total;
            icc[index] = bytes.sublist(14);
          }
        }
      }
      offset += size;
    }
    if (iccCount > 0 && icc.length == iccCount) {
      final bytes = BytesBuilder(copy: false);
      for (var i = 1; i <= iccCount; i++) {
        bytes.add(icc[i]!);
      }
      values['colorSpace'] = iccProfileLabel(bytes.takeBytes());
    }
  }

  static void _chunks(
    _MetadataFile input,
    Map<String, String> values, {
    required bool png,
  }) {
    var offset = png ? 8 : 12;
    final limit = png
        ? input.length
        : (ByteData.sublistView(input.read(4, 4)).getUint32(0, Endian.little) +
                  8)
              .clamp(0, input.length);
    for (var count = 0; count < 16384 && offset + 8 <= limit; count++) {
      final header = input.read(offset, 8);
      final type = ascii.decode(png ? header.sublist(4) : header.sublist(0, 4));
      final size = ByteData.sublistView(header)
          .getUint32(png ? 0 : 4, png ? Endian.big : Endian.little);
      final end = offset + 8 + size + (png ? 4 : size % 2);
      if (end > limit) break;
      if ({
            'eXIf',
            'EXIF',
            'iTXt',
            'XMP ',
            'iCCP',
            'ICCP',
            'sRGB',
            'cICP',
          }.contains(type) &&
          size <= budget - input.used) {
        final bytes = input.read(offset + 8, size);
        try {
          switch (type) {
            case 'eXIf':
            case 'EXIF':
              _exif(bytes, values);
            case 'XMP ':
              mergeXmp(values, bytes);
            case 'iTXt':
              final zero = bytes.indexOf(0);
              if (zero >= 0 &&
                  utf8.decode(bytes.sublist(0, zero)) == 'XML:com.adobe.xmp' &&
                  zero + 3 <= bytes.length) {
                final languageEnd = bytes.indexOf(0, zero + 3);
                final nameEnd = languageEnd < 0
                    ? -1
                    : bytes.indexOf(0, languageEnd + 1);
                if (nameEnd >= 0) {
                  final text = bytes.sublist(nameEnd + 1);
                  mergeXmp(
                    values,
                    bytes[zero + 1] == 1 ? _inflate(text) : text,
                  );
                }
              }
            case 'ICCP':
              values['colorSpace'] = iccProfileLabel(bytes);
            case 'iCCP':
              final zero = bytes.indexOf(0);
              if (zero >= 0 &&
                  zero + 2 < bytes.length &&
                  bytes[zero + 1] == 0) {
                values['colorSpace'] = iccProfileLabel(
                  _inflate(bytes.sublist(zero + 2)),
                );
              }
            case 'sRGB':
              values.putIfAbsent('colorSpace', () => 'sRGB');
            case 'cICP':
              if (bytes.length == 4) {
                final gamut = switch (bytes[0]) {
                  1 => 'Rec.709',
                  9 => 'Rec.2020',
                  12 => 'Display P3',
                  _ => 'CICP ${bytes[0]}',
                };
                values['cicpColorSpace'] =
                    '$gamut / ${switch (bytes[1]) {
                      13 => "sRGB",
                      16 => "PQ",
                      18 => "HLG",
                      _ => "TRC ${bytes[1]}",
                    }}';
              }
          }
        } on Object {
          // One bad optional block does not discard the remaining metadata.
        }
      }
      offset = end;
      if (type == 'IEND') break;
    }
    if (values['cicpColorSpace'] case final String color) {
      values['colorSpace'] = color;
    }
  }

  static void _exif(Uint8List bytes, Map<String, String> values) {
    if (bytes.length >= 6 &&
        latin1.decode(bytes.sublist(0, 6)) == 'Exif\u0000\u0000') {
      bytes = bytes.sublist(6);
    }
    _Tiff(
      (offset, size) => Uint8List.sublistView(bytes, offset, offset + size),
      bytes.length,
      values,
    ).parse();
  }
}

class _MetadataFile {
  _MetadataFile(this.file) : length = file.lengthSync();
  final RandomAccessFile file;
  final int length;
  int used = 0;
  Uint8List read(int offset, int size) {
    if (size < 0 ||
        offset < 0 ||
        size > length - offset ||
        used + size > PhotoMetadataReader.budget) {
      throw const FormatException('Photo metadata budget or bounds');
    }
    used += size;
    file.setPositionSync(offset);
    final bytes = file.readSync(size);
    if (bytes.length != size) {
      throw const FormatException('Photo metadata truncated');
    }
    return bytes;
  }
}

class _Tiff {
  _Tiff(this.read, this.length, this.values);
  final Uint8List Function(int, int) read;
  final int length;
  final Map<String, String> values;
  final visited = <int>{};
  late Endian endian;
  int used = 0;
  void parse() {
    try {
      final header = ByteData.sublistView(read(0, 8));
      endian = header.getUint8(0) == 73 ? Endian.little : Endian.big;
      if (!{0x4949, 0x4d4d}.contains(header.getUint16(0)) ||
          header.getUint16(2, endian) != 42) {
        return;
      }
      _ifd(header.getUint32(4, endian), 'image');
      if (values['exifColorSpace'] == '1') {
        values.putIfAbsent('colorSpace', () => 'sRGB');
      }
      if (values['exifColorSpace'] == '2' || values['interopIndex'] == 'R03') {
        values.putIfAbsent('colorSpace', () => 'Adobe RGB (1998)');
      }
      final date = values['dateTimeOriginal'];
      if (date != null) {
        final sub = values['subSecTimeOriginal'];
        final zone = values['offsetTimeOriginal'];
        values['dateTimeOriginal'] =
            '$date${sub == null ? "" : ".$sub"}${zone == null ? "" : " $zone"}';
      }
    } on Object {
      // EXIF is optional, including for otherwise readable TIFF/RAW containers.
    }
  }

  void _ifd(int offset, String kind) {
    if (offset < 8 ||
        offset + 2 > length ||
        visited.length >= 8 ||
        !visited.add(offset)) {
      return;
    }
    final count = ByteData.sublistView(read(offset, 2)).getUint16(0, endian);
    if (count > 4096 || offset + 2 + count * 12 > length) return;
    final entries = ByteData.sublistView(read(offset + 2, count * 12));
    final children = <(int, String)>[];
    const imageTags = {
      0x010f: 'make',
      0x0110: 'model',
      0x0112: 'orientation',
      0x013b: 'creator',
      0x8298: 'copyright',
    };
    const exifTags = {
      0x9003: 'dateTimeOriginal',
      0x9011: 'offsetTimeOriginal',
      0x9291: 'subSecTimeOriginal',
      0xa434: 'lensModel',
      0x829d: 'fNumber',
      0x829a: 'exposureTime',
      0x8827: 'iso',
      0x8833: 'iso',
      0x920a: 'focalLength',
      0x9204: 'exposureBias',
      0xa403: 'whiteBalance',
      0x9209: 'flash',
      0xa001: 'exifColorSpace',
    };
    const gpsTags = {
      1: 'gpsLatitudeRef',
      2: 'gpsLatitude',
      3: 'gpsLongitudeRef',
      4: 'gpsLongitude',
    };
    for (var i = 0; i < count; i++) {
      final at = i * 12, tag = entries.getUint16(i * 12, endian);
      final type = entries.getUint16(at + 2, endian),
          count = entries.getUint32(at + 4, endian);
      if ({0x8769, 0x8825, 0xa005}.contains(tag) && type == 4 && count == 1) {
        children.add((
          entries.getUint32(at + 8, endian),
          tag == 0x8769
              ? 'exif'
              : tag == 0x8825
              ? 'gps'
              : 'interop',
        ));
        continue;
      }
      final key = kind == 'image'
          ? imageTags[tag]
          : kind == 'exif'
          ? exifTags[tag]
          : kind == 'gps'
          ? gpsTags[tag]
          : tag == 1
          ? 'interopIndex'
          : null;
      if (key == null && tag != 0x8773 && tag != 0x02bc) continue;
      const widths = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 9: 4, 10: 8};
      final size = count * (widths[type] ?? 0);
      if (size == 0 || size > PhotoMetadataReader.budget - used) continue;
      if (key != null && size > 8192) continue;
      final position = size <= 4
          ? offset + 2 + at + 8
          : entries.getUint32(at + 8, endian);
      if (position < 0 || size > length - position) continue;
      used += size;
      final bytes = read(position, size);
      if (tag == 0x8773) {
        values['colorSpace'] = iccProfileLabel(bytes);
        continue;
      }
      if (tag == 0x02bc) {
        PhotoMetadataReader.mergeXmp(values, bytes);
        continue;
      }
      if (type == 2) {
        final text = utf8
            .decode(bytes, allowMalformed: true)
            .split('\u0000')
            .first
            .trim();
        if (text.isNotEmpty) values[key!] = text;
      } else if (count <= 16) {
        final data = ByteData.sublistView(bytes);
        final parts = <String>[];
        for (var j = 0; j < count; j++) {
          final at = j * widths[type]!;
          switch (type) {
            case 1:
            case 7:
              parts.add('${data.getUint8(at)}');
            case 3:
              parts.add('${data.getUint16(at, endian)}');
            case 4:
              parts.add('${data.getUint32(at, endian)}');
            case 9:
              parts.add('${data.getInt32(at, endian)}');
            case 5:
            case 10:
              final n = type == 5
                  ? data.getUint32(at, endian)
                  : data.getInt32(at, endian);
              final d = type == 5
                  ? data.getUint32(at + 4, endian)
                  : data.getInt32(at + 4, endian);
              if (d != 0) parts.add('$n/$d');
          }
        }
        if (parts.isNotEmpty && !(key == 'iso' && parts.first == '0')) {
          values[key!] = parts.join(', ');
        }
      }
    }
    for (final child in children) {
      _ifd(child.$1, child.$2);
    }
  }
}

String iccProfileLabel(Uint8List bytes) {
  if (bytes.length < 132 || latin1.decode(bytes.sublist(36, 40)) != 'acsp') {
    return 'ICC';
  }
  final data = ByteData.sublistView(bytes);
  final count = data.getUint32(128);
  if (count > 1024 || 132 + count * 12 > bytes.length) return 'ICC';
  for (var i = 0; i < count; i++) {
    final at = 132 + i * 12;
    if (latin1.decode(bytes.sublist(at, at + 4)) != 'desc') continue;
    final start = data.getUint32(at + 4), size = data.getUint32(at + 8);
    if (size < 12 || size > bytes.length - start) continue;
    final type = latin1.decode(bytes.sublist(start, start + 4));
    String? name;
    if (type == 'desc') {
      final length = data.getUint32(start + 8);
      if (length > 0 && length <= size - 12) {
        name = latin1
            .decode(bytes.sublist(start + 12, start + 12 + length))
            .split('\u0000')
            .first;
      }
    } else if (type == 'mluc' && size >= 28) {
      final length = data.getUint32(start + 20),
          offset = data.getUint32(start + 24);
      if (length <= size - offset && length.isEven) {
        name = String.fromCharCodes([
          for (var j = 0; j < length; j += 2)
            data.getUint16(start + offset + j),
        ]);
      }
    }
    if (name != null && name.trim().isNotEmpty && name.length <= 256) {
      return '${name.trim()} (ICC)';
    }
  }
  return 'ICC';
}

Uint8List _inflate(Uint8List bytes) {
  final sink = _BoundedSink();
  final decoder = ZLibDecoder().startChunkedConversion(sink);
  decoder.add(bytes);
  decoder.close();
  return sink.bytes.takeBytes();
}

class _BoundedSink implements Sink<List<int>> {
  final bytes = BytesBuilder(copy: false);
  @override
  void add(List<int> data) {
    if (data.length > PhotoMetadataReader.budget - bytes.length) {
      throw const FormatException('Inflated metadata budget');
    }
    bytes.add(data);
  }

  @override
  void close() {}
}
