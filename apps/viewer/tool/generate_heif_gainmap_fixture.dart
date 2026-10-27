// Build deterministic HEVC + ISO 21496-1 tmap fixtures from format_alpha.heif.
// Reuses the sample's alpha item as a synthetic gain map. This exercises item
// linkage and SDR-base preservation, not photographic HDR brightness accuracy.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

List<int> be(int value, int bytes) =>
    List<int>.generate(bytes, (i) => value >> ((bytes - i - 1) * 8) & 0xff);
int u32(Uint8List b, int p) =>
    b[p] * 0x1000000 + b[p + 1] * 0x10000 + b[p + 2] * 0x100 + b[p + 3];
List<int> box(String type, List<int> payload) => [
  ...be(payload.length + 8, 4),
  ...ascii.encode(type),
  ...payload,
];
({int start, int end, int header}) findBox(
  Uint8List b,
  int start,
  int end,
  String type,
) {
  for (var p = start; p + 8 <= end;) {
    final small = u32(b, p), header = small == 1 ? 16 : 8;
    final size = small == 1 ? ByteData.sublistView(b).getUint64(p + 8) : small;
    if (size < header || p + size > end) break;
    if (type.isEmpty || ascii.decode(b.sublist(p + 4, p + 8)) == type) {
      return (start: p, end: p + size, header: header);
    }
    p += size;
  }
  throw StateError('missing $type box');
}

List<int> gainMetadata() {
  final bytes = <int>[0, 0, 0, 0, 0, 0x40];
  void fraction(int n, int d) => bytes.addAll([...be(n, 4), ...be(d, 4)]);
  fraction(0, 1);
  fraction(3, 1);
  fraction(0, 1);
  fraction(3, 1);
  fraction(1, 1);
  fraction(0, 1);
  fraction(0, 1);
  if (bytes.length != 62) throw StateError('unexpected tmap metadata size');
  return bytes;
}

List<int> addInfe(List<int> input) {
  final bytes = [...input];
  final entry = box('infe', [
    2,
    0,
    0,
    0,
    0,
    4,
    0,
    0,
    ...ascii.encode('tmap'),
    0,
  ]);
  bytes.addAll(entry);
  bytes.setRange(0, 4, be(u32(Uint8List.fromList(input), 0) + entry.length, 4));
  bytes[12] = 0;
  bytes[13] = 4;
  return bytes;
}

List<int> addDimg(List<int> input) {
  final bytes = [...input];
  final entry = box('dimg', [
    ...be(4, 2),
    ...be(2, 2),
    ...be(1, 2),
    ...be(2, 2),
  ]);
  bytes.addAll(entry);
  bytes.setRange(0, 4, be(u32(Uint8List.fromList(input), 0) + entry.length, 4));
  return bytes;
}

List<int> addIloc(List<int> input, int offset, int length, int delta) {
  final bytes = [...input], oldSize = u32(Uint8List.fromList(input), 0);
  if (bytes[12] != 0x44 || ((bytes[14] << 8) | bytes[15]) != 3) {
    throw StateError('format_alpha.heif has an unexpected iloc layout');
  }
  for (var p = 16; p < 16 + 3 * 14; p += 14) {
    final old =
        (bytes[p + 6] << 24) |
        (bytes[p + 7] << 16) |
        (bytes[p + 8] << 8) |
        bytes[p + 9];
    bytes.setRange(p + 6, p + 10, be(old + delta, 4));
  }
  bytes.setRange(14, 16, [0, 4]);
  bytes.addAll([0, 4, 0, 0, 0, 1, ...be(offset, 4), ...be(length, 4)]);
  bytes.setRange(0, 4, be(oldSize + 14, 4));
  return bytes;
}

Future<void> main() async {
  final input = Uint8List.fromList(
    File('testdata/formats/format_alpha.heif').readAsBytesSync(),
  );
  final ftyp = findBox(input, 0, input.length, 'ftyp');
  final meta = findBox(input, ftyp.end, input.length, 'meta');
  final metaPayload = input.sublist(meta.start + meta.header + 4, meta.end);
  findBox(input, meta.end, input.length, 'mdat');
  final payload = gainMetadata();
  const delta = 21 + 16 + 14;
  final newMdatOffset = input.length + delta + 8;
  final children = <int>[];
  var p = 0;
  while (p < metaPayload.length) {
    final child = findBox(metaPayload, p, metaPayload.length, '');
    final type = ascii.decode(
      metaPayload.sublist(child.start + 4, child.start + 8),
    );
    final original = metaPayload.sublist(child.start, child.end);
    if (type == 'iinf') {
      children.addAll(addInfe(original));
    } else if (type == 'iref') {
      children.addAll(addDimg(original));
    } else if (type == 'iloc') {
      children.addAll(addIloc(original, newMdatOffset, payload.length, delta));
    } else {
      children.addAll(original);
    }
    p = child.end;
  }
  final output = <int>[
    ...input.sublist(0, meta.start),
    ...box('meta', [0, 0, 0, 0, ...children]),
    ...input.sublist(meta.end),
    ...box('mdat', payload),
  ];
  for (final name in ['hdr_gain_map.heic', 'hdr_gain_map.heif']) {
    final outputPath = 'testdata/formats/$name';
    final file = File(outputPath);
    // Existing test images may be memory-mapped by a running viewer/Photos.
    // Reproducibility checks should not rewrite byte-identical fixtures.
    final previous = file.existsSync() ? file.readAsBytesSync() : null;
    if (previous != null && _sameBytes(previous, output)) {
      stdout.writeln('unchanged $outputPath (${output.length} bytes)');
      continue;
    }
    file.writeAsBytesSync(output);
    stdout.writeln('wrote $outputPath (${output.length} bytes)');
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
