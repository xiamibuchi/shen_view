import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:image/src/util/rational.dart';

img.Image metadataPhoto({bool southWest = true}) {
  final image = img.Image(width: 16, height: 8);
  img.fill(image, color: img.ColorRgb8(128, 64, 32));
  image.exif.imageIfd.make = 'ShenView';
  image.exif.imageIfd.model = 'Test camera';
  image.exif.imageIfd.orientation = 6;
  final exif = image.exif.exifIfd;
  exif[0x9003] = img.IfdValueAscii('2026:10:26 12:34:56');
  exif[0x9011] = img.IfdValueAscii('+08:00');
  exif[0x9291] = img.IfdValueAscii('123');
  exif[0xa434] = img.IfdValueAscii('Test lens');
  exif[0x829d] = img.IfdValueRational(28, 10);
  exif[0x829a] = img.IfdValueRational(1, 125);
  exif[0x8827] = img.IfdValueShort(100);
  exif[0xa001] = img.IfdValueShort(2);
  exif[0x920a] = img.IfdValueRational(50, 1);
  exif[0x9204] = img.IfdValueSRational(1, 3);
  exif[0xa403] = img.IfdValueShort(0);
  exif[0x9209] = img.IfdValueShort(89);
  final gps = image.exif.gpsIfd;
  gps[1] = img.IfdValueAscii(southWest ? 'S' : 'N');
  gps[2] = img.IfdValueRational.list([
    Rational(33, 1),
    Rational(30, 1),
    Rational(0, 1),
  ]);
  gps[3] = img.IfdValueAscii(southWest ? 'W' : 'E');
  gps[4] = img.IfdValueRational.list([
    Rational(70, 1),
    Rational(40, 1),
    Rational(0, 1),
  ]);
  return image;
}

Uint8List photoExif(img.Image image) {
  final jpeg = img.encodeJpg(image);
  for (var offset = 2; offset + 4 <= jpeg.length;) {
    final size = (jpeg[offset + 2] << 8) | jpeg[offset + 3];
    if (jpeg[offset + 1] == 225 &&
        latin1.decode(jpeg.sublist(offset + 4, offset + 8)) == 'Exif') {
      return Uint8List.fromList(jpeg.sublist(offset + 10, offset + 2 + size));
    }
    offset += size + 2;
  }
  throw StateError('Fixture EXIF not encoded');
}

Uint8List pngChunk(String type, List<int> payload) {
  final body = [...ascii.encode(type), ...payload];
  return Uint8List.fromList([
    ...(ByteData(4)..setUint32(0, payload.length)).buffer.asUint8List(),
    ...body,
    ...(ByteData(4)..setUint32(0, getCrc32(body))).buffer.asUint8List(),
  ]);
}

Uint8List pngWithMetadata(
  img.Image image, {
  bool afterPixels = false,
  bool padded = false,
}) {
  final png = img.encodePng(image);
  final at = afterPixels ? png.length - 12 : 33;
  return Uint8List.fromList([
    ...png.take(at),
    if (padded) ...pngChunk('teSt', Uint8List(3 * 1024 * 1024)),
    ...pngChunk('eXIf', photoExif(image)),
    ...pngChunk('iTXt', [
      ...ascii.encode('XML:com.adobe.xmp'),
      0,
      0,
      0,
      0,
      0,
      ...utf8.encode(photoXmp()),
    ]),
    ...png.skip(at),
  ]);
}

Uint8List jpegWithXmp(List<int> jpeg, String xml) {
  final payload = [
    ...ascii.encode('http://ns.adobe.com/xap/1.0/'),
    0,
    ...utf8.encode(xml),
  ];
  final size = payload.length + 2;
  return Uint8List.fromList([
    255,
    216,
    255,
    225,
    size >> 8,
    size & 255,
    ...payload,
    ...jpeg.skip(2),
  ]);
}

Uint8List jpegWithIcc(List<int> jpeg, List<int> profile) {
  final payload = [...ascii.encode('ICC_PROFILE'), 0, 1, 1, ...profile];
  final size = payload.length + 2;
  return Uint8List.fromList([
    255,
    216,
    255,
    226,
    size >> 8,
    size & 255,
    ...payload,
    ...jpeg.skip(2),
  ]);
}

Uint8List riffChunk(String type, List<int> payload) => Uint8List.fromList([
  ...ascii.encode(type),
  ...(ByteData(
    4,
  )..setUint32(0, payload.length, Endian.little)).buffer.asUint8List(),
  ...payload,
  if (payload.length.isOdd) 0,
]);

Uint8List webpWithMetadata(img.Image image) {
  final webp = File('testdata/formats/format_static.webp').readAsBytesSync();
  final out = Uint8List.fromList([
    ...webp,
    ...riffChunk('JUNK', Uint8List(3 * 1024 * 1024)),
    ...riffChunk('EXIF', photoExif(image)),
    ...riffChunk('XMP ', utf8.encode(photoXmp())),
  ]);
  ByteData.sublistView(out).setUint32(4, out.length - 8, Endian.little);
  return out;
}

String photoXmp({String title = '中文标题 café 📷', int rating = 4}) =>
    '''
<?xpacket begin="﻿"?>
<q:xmpmeta xmlns:q="adobe:ns:meta/">
<r:RDF xmlns:r="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
<r:Description xmlns:d="http://purl.org/dc/elements/1.1/"
 xmlns:a="http://ns.adobe.com/xap/1.0/" xmlns:e="http://ns.adobe.com/exif/1.0/"
 xmlns:t="http://ns.adobe.com/tiff/1.0/" a:Rating="$rating" t:Model="XMP fallback"
 e:DateTimeOriginal="2000-01-01T00:00:00Z" e:FNumber="9/1">
 <d:title><r:Alt><r:li xml:lang="en-US">English title</r:li><r:li xml:lang="x-default">$title</r:li></r:Alt></d:title>
 <d:description><r:Alt><r:li xml:lang="x-default">海边 &amp; 山间</r:li></r:Alt></d:description>
 <d:creator><r:Seq><r:li>测试作者</r:li><r:li>Second author</r:li></r:Seq></d:creator>
 <d:rights><r:Alt><r:li xml:lang="x-default">CC0</r:li></r:Alt></d:rights>
 <d:subject><r:Bag><r:li>旅行</r:li><r:li>照片</r:li><r:li>旅行</r:li></r:Bag></d:subject>
</r:Description></r:RDF></q:xmpmeta><?xpacket end="w"?>
''';
