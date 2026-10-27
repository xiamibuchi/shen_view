import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'codec_process.dart';
import 'decode_request.dart';

enum HdrEncoding { sdr, sceneLinear, pq, hlg, gainMap, dolbyVision }

class HdrInputMetadata {
  const HdrInputMetadata({
    this.encoding = HdrEncoding.sdr,
    this.primaries = 1,
    this.dolbyProfile,
    this.dolbyCompatibility = 0,
    this.maxCll,
    this.maxFall,
    this.width,
    this.height,
    this.dolbyNeedsEnhancementLayer = false,
  });
  final HdrEncoding encoding;
  final int primaries;
  final int? dolbyProfile;
  final int dolbyCompatibility;
  final double? maxCll, maxFall;
  final int? width, height;
  final bool dolbyNeedsEnhancementLayer;
  bool get isHdr => encoding != HdrEncoding.sdr;
  static const _budget = 4 * 1024 * 1024;

  static bool candidate(String path) => RegExp(
    r'\.(hdr|exr|avif|heic|heif|png|jpe?g|hevc|h265|dng|cr2|cr3|nef|nrw|arw|sr2|orf|rw2|raf|pef|srw)$',
    caseSensitive: false,
  ).hasMatch(path);

  static Future<HdrInputMetadata> read(
    String path, {
    DecodeRequest? request,
  }) async {
    request?.throwIfCancelled();
    final lower = path.toLowerCase();
    if (lower.endsWith('.hevc') || lower.endsWith('.h265')) {
      return readVideo(path, request: request);
    }
    if (lower.endsWith('.hdr') || lower.endsWith('.exr')) {
      return const HdrInputMetadata(encoding: HdrEncoding.sceneLinear);
    }
    if (RegExp(
      r'\.(dng|cr2|cr3|nef|nrw|arw|sr2|orf|rw2|raf|pef|srw)$',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return const HdrInputMetadata(encoding: HdrEncoding.sceneLinear);
    }
    if (!candidate(path)) return const HdrInputMetadata();
    final file = await File(path).open();
    try {
      final prefix = await file.read(32);
      if (prefix.length >= 8 && latin1.decode(prefix.sublist(4, 8)) == 'ftyp') {
        final length = await file.length();
        var offset = 0;
        for (var count = 0; offset + 8 <= length && count < 256; count++) {
          request?.throwIfCancelled();
          await file.setPosition(offset);
          final head = await file.read(16);
          if (head.length < 8) break;
          final data = ByteData.sublistView(head);
          final smallSize = data.getUint32(0);
          final size = smallSize == 1 && head.length >= 16
              ? data.getUint64(8)
              : smallSize == 0
              ? length - offset
              : smallSize;
          final header = smallSize == 1 ? 16 : 8;
          if (size < header || offset + size > length) {
            throw const FormatException('ISO box bounds');
          }
          if (latin1.decode(head.sublist(4, 8)) == 'meta') {
            if (size > _budget) {
              throw const FormatException('HDR metadata budget');
            }
            await file.setPosition(offset + header);
            final metaBytes = await file.read(size - header);
            final parsed = fromIsoMeta(metaBytes);
            if (_hasTmapItem(metaBytes) &&
                (lower.endsWith('.avif') ||
                    lower.endsWith('.heic') ||
                    lower.endsWith('.heif'))) {
              return const HdrInputMetadata(encoding: HdrEncoding.gainMap);
            }
            return parsed;
          }
          offset += size;
        }
        return const HdrInputMetadata();
      }
      await file.setPosition(0);
      final bytes = await _readPrefix(file, request);
      request?.throwIfCancelled();
      return fromBytes(bytes);
    } finally {
      await file.close();
    }
  }

  static Future<HdrInputMetadata> readVideo(
    String path, {
    DecodeRequest? request,
  }) async {
    final ffprobe = await CodecProcess.locate('ffprobe', 'SHENVIEW_FFPROBE');
    final bytes = await CodecProcess.run(
      ffprobe,
      [
        '-v',
        'error',
        '-select_streams',
        'v:0',
        '-show_frames',
        '-read_intervals',
        '%+#1',
        '-of',
        'json',
        path,
      ],
      request: request,
      timeout: const Duration(seconds: 15),
      maxOutput: 1024 * 1024,
    );
    return fromFfprobe(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
  }

  static HdrInputMetadata fromFfprobe(Map<String, dynamic> document) {
    final frames = document['frames'];
    if (frames is! List || frames.isEmpty || frames.first is! Map) {
      throw const FormatException('HDR frame probe');
    }
    final frame = frames.first as Map;
    final width = frame['width'] as int?;
    final height = frame['height'] as int?;
    if (width == null ||
        height == null ||
        width < 1 ||
        height < 1 ||
        width * height > 64 * 1024 * 1024) {
      throw const FormatException('HDR frame pixel budget');
    }
    final side = (frame['side_data_list'] as List? ?? [])
        .whereType<Map<String, Object?>>();
    final dovi = side
        .where((value) => value['side_data_type'] == 'Dolby Vision Metadata')
        .firstOrNull;
    final encoding = dovi != null
        ? HdrEncoding.dolbyVision
        : switch (frame['color_transfer']) {
            'smpte2084' => HdrEncoding.pq,
            'arib-std-b67' => HdrEncoding.hlg,
            _ => HdrEncoding.sdr,
          };
    return HdrInputMetadata(
      encoding: encoding,
      primaries: switch (frame['color_primaries']) {
        _ when dovi != null => 9,
        'bt2020' => 9,
        'bt709' => 1,
        'smpte432' => 12,
        _ when encoding == HdrEncoding.sdr => 1,
        _ => throw const FormatException('Unspecified HDR video primaries'),
      },
      width: width,
      height: height,
      dolbyNeedsEnhancementLayer:
          dovi != null && dovi['disable_residual_flag'] != 1,
    );
  }

  static HdrInputMetadata fromBytes(Uint8List bytes) {
    if (_isPng(bytes)) {
      final data = ByteData.sublistView(bytes);
      int? transfer, primaries;
      double? cll, fall;
      var offset = 8;
      while (offset + 12 <= bytes.length) {
        final size = data.getUint32(offset);
        final type = latin1.decode(bytes.sublist(offset + 4, offset + 8));
        if (type == 'IDAT') break;
        if (offset + size + 12 > bytes.length) {
          throw const FormatException('PNG metadata bounds');
        }
        if ((type == 'cICP' || type == 'cLLi') &&
            _crc32(bytes.sublist(offset + 4, offset + 8 + size)) !=
                data.getUint32(offset + 8 + size)) {
          throw const FormatException('PNG HDR metadata CRC');
        }
        if (type == 'cICP' && size == 4) {
          primaries = bytes[offset + 8];
          transfer = bytes[offset + 9];
          if (bytes[offset + 10] != 0 || bytes[offset + 11] != 1) {
            throw const FormatException('PNG HDR requires full range RGB');
          }
        }
        if (type == 'cLLi' && size == 8) {
          cll = data.getUint32(offset + 8) / 10000;
          fall = data.getUint32(offset + 12) / 10000;
        }
        offset += size + 12;
      }
      return HdrInputMetadata(
        encoding: _transfer(transfer),
        primaries: primaries ?? 1,
        maxCll: cll,
        maxFall: fall,
      );
    }
    if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xd8) {
      var offset = 2;
      while (offset + 4 <= bytes.length) {
        if (bytes[offset++] != 0xff) break;
        while (offset < bytes.length && bytes[offset] == 0xff) {
          offset++;
        }
        if (offset >= bytes.length) break;
        final marker = bytes[offset++];
        if (marker == 0xda || marker == 0xd9) break;
        if (marker >= 0xd0 && marker <= 0xd7 || marker == 1) continue;
        if (offset + 2 > bytes.length) break;
        final size = ByteData.sublistView(bytes).getUint16(offset);
        if (size < 2 || offset + size > bytes.length) {
          throw const FormatException('JPEG metadata bounds');
        }
        if (marker == 0xe1 || marker == 0xe2) {
          final text = latin1.decode(bytes.sublist(offset + 2, offset + size));
          if (text.contains('http://ns.adobe.com/hdr-gain-map/1.0/') ||
              text.contains('urn:iso:std:iso:ts:21496:-1') ||
              text.contains('http://ns.google.com/photos/1.0/gainmap/')) {
            return const HdrInputMetadata(encoding: HdrEncoding.gainMap);
          }
        }
        offset += size;
      }
    }
    return const HdrInputMetadata();
  }

  /// Read only properties associated with pitm; thumbnail/auxiliary colr boxes
  /// must not override the primary image. Indices and sizes are bounded.
  static HdrInputMetadata fromIsoMeta(Uint8List bytes) {
    if (bytes.length < 4) throw const FormatException('ISO meta');
    final children = _boxes(bytes, 4, bytes.length);
    final pitm = children.where((b) => b.type == 'pitm').firstOrNull;
    final iprp = children.where((b) => b.type == 'iprp').firstOrNull;
    if (pitm == null || iprp == null) return const HdrInputMetadata();
    final data = ByteData.sublistView(bytes);
    if (pitm.end - pitm.start < 6) {
      throw const FormatException('ISO primary item');
    }
    final primary = bytes[pitm.start] == 0
        ? data.getUint16(pitm.start + 4)
        : pitm.end - pitm.start >= 8
        ? data.getUint32(pitm.start + 4)
        : throw const FormatException('ISO primary item');
    final properties = _boxes(bytes, iprp.start, iprp.end);
    final ipco = properties.where((b) => b.type == 'ipco').firstOrNull;
    if (ipco == null) return const HdrInputMetadata();
    final table = _boxes(bytes, ipco.start, ipco.end);
    final associations = <int>[];
    for (final ipma in properties.where((b) => b.type == 'ipma')) {
      if (ipma.end - ipma.start < 8) {
        throw const FormatException('ISO associations');
      }
      final version = bytes[ipma.start],
          wide = (bytes[ipma.start + 3] & 1) != 0;
      final count = data.getUint32(ipma.start + 4);
      if (count > 65536) throw const FormatException('ISO association budget');
      var p = ipma.start + 8;
      for (var i = 0; i < count; i++) {
        final idSize = version < 1 ? 2 : 4;
        if (p + idSize + 1 > ipma.end) {
          throw const FormatException('ISO association bounds');
        }
        final id = idSize == 2 ? data.getUint16(p) : data.getUint32(p);
        p += idSize;
        final n = bytes[p++];
        for (var j = 0; j < n; j++) {
          if (p + (wide ? 2 : 1) > ipma.end) {
            throw const FormatException('ISO property bounds');
          }
          final index = wide ? data.getUint16(p) & 0x7fff : bytes[p] & 0x7f;
          p += wide ? 2 : 1;
          if (index > table.length) {
            throw const FormatException('ISO property index');
          }
          if (id == primary && index != 0) associations.add(index - 1);
        }
      }
    }
    int primaries = 1;
    int? transfer, dolby;
    var compatibility = 0;
    for (final index in associations) {
      final box = table[index];
      if (box.type == 'colr' &&
          box.end - box.start >= 11 &&
          latin1.decode(bytes.sublist(box.start, box.start + 4)) == 'nclx') {
        primaries = data.getUint16(box.start + 4);
        transfer = data.getUint16(box.start + 6);
      }
      if ((box.type == 'dvcC' || box.type == 'dvvC') &&
          box.end - box.start >= 5) {
        dolby = bytes[box.start + 2] >> 1;
        compatibility = bytes[box.start + 4] >> 4;
      }
    }
    return HdrInputMetadata(
      encoding: dolby == null ? _transfer(transfer) : HdrEncoding.dolbyVision,
      primaries: primaries,
      dolbyProfile: dolby,
      dolbyCompatibility: compatibility,
    );
  }

  static HdrEncoding _transfer(int? transfer) => switch (transfer) {
    16 => HdrEncoding.pq,
    18 => HdrEncoding.hlg,
    _ => HdrEncoding.sdr,
  };
}

bool _isPng(Uint8List bytes) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 8) return false;
  for (var i = 0; i < 8; i++) {
    if (bytes[i] != signature[i]) return false;
  }
  return true;
}

// Stop before compressed pixels: ordinary JPEG/PNG thumbnails do not require
// reading a 4 MiB prefix just to decide whether an HDR path is needed.
Future<Uint8List> _readPrefix(
  RandomAccessFile file,
  DecodeRequest? request,
) async {
  final first = await file.read(8);
  final output = BytesBuilder(copy: false)..add(first);
  if (_isPng(first)) {
    while (output.length < HdrInputMetadata._budget) {
      request?.throwIfCancelled();
      final head = await file.read(8);
      if (head.length != 8) break;
      final size = ByteData.sublistView(head).getUint32(0);
      final type = latin1.decode(head.sublist(4));
      output.add(head);
      if (type == 'IDAT' || type == 'IEND') break;
      if (output.length + size + 4 > HdrInputMetadata._budget) {
        throw const FormatException('PNG metadata budget');
      }
      final payload = await file.read(size + 4);
      output.add(payload);
      if (payload.length != size + 4) break;
    }
    return output.takeBytes();
  }
  if (first.length >= 2 && first[0] == 255 && first[1] == 216) {
    await file.setPosition(2);
    final jpeg = BytesBuilder(copy: false)..add([255, 216]);
    while (jpeg.length < HdrInputMetadata._budget) {
      request?.throwIfCancelled();
      final markerPrefix = await file.read(1);
      if (markerPrefix.isEmpty || markerPrefix[0] != 255) break;
      var marker = await file.read(1);
      while (marker.isNotEmpty && marker[0] == 255) {
        marker = await file.read(1);
      }
      if (marker.isEmpty) break;
      jpeg.add([255, marker[0]]);
      if (marker[0] == 218 || marker[0] == 217) break;
      if (marker[0] == 1 || marker[0] >= 208 && marker[0] <= 215) continue;
      final sizeBytes = await file.read(2);
      if (sizeBytes.length != 2) break;
      final size = ByteData.sublistView(sizeBytes).getUint16(0);
      if (size < 2 || jpeg.length + size > HdrInputMetadata._budget) {
        throw const FormatException('JPEG metadata budget');
      }
      jpeg.add(sizeBytes);
      final payload = await file.read(size - 2);
      jpeg.add(payload);
      if (payload.length != size - 2) break;
    }
    return jpeg.takeBytes();
  }
  return first;
}

int _crc32(Uint8List bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0);
    }
  }
  return crc ^ 0xffffffff;
}

class _Box {
  const _Box(this.type, this.start, this.end);
  final String type;
  final int start, end;
}

bool _hasTmapItem(Uint8List bytes) {
  if (bytes.length < 4) return false;
  final iinf = _boxes(
    bytes,
    4,
    bytes.length,
  ).where((b) => b.type == 'iinf').firstOrNull;
  if (iinf == null || iinf.end - iinf.start < 6) return false;
  final skip = bytes[iinf.start] == 0 ? 6 : 8;
  if (iinf.start + skip > iinf.end) {
    throw const FormatException('ISO item info');
  }
  for (final item in _boxes(
    bytes,
    iinf.start + skip,
    iinf.end,
  ).where((b) => b.type == 'infe')) {
    if (item.start >= item.end) throw const FormatException('ISO item entry');
    final version = bytes[item.start];
    final typeOffset = item.start + (version == 2 ? 8 : 10);
    if ((version == 2 || version == 3) &&
        typeOffset + 4 <= item.end &&
        latin1.decode(bytes.sublist(typeOffset, typeOffset + 4)) == 'tmap') {
      return true;
    }
  }
  return false;
}

List<_Box> _boxes(Uint8List bytes, int start, int end) {
  final data = ByteData.sublistView(bytes);
  final result = <_Box>[];
  while (start + 8 <= end) {
    if (result.length > 65536) throw const FormatException('ISO box budget');
    final size32 = data.getUint32(start);
    final header = size32 == 1 ? 16 : 8;
    if (start + header > end) throw const FormatException('ISO box header');
    final size = size32 == 1
        ? data.getUint64(start + 8)
        : size32 == 0
        ? end - start
        : size32;
    if (size < header || start + size > end) {
      throw const FormatException('ISO box bounds');
    }
    result.add(
      _Box(
        latin1.decode(bytes.sublist(start + 4, start + 8)),
        start + header,
        start + size,
      ),
    );
    start += size;
  }
  if (start != end) throw const FormatException('ISO box tail');
  return result;
}
