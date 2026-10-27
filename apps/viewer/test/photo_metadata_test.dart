import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shen_view/l10n/app_localizations_en.dart';
import 'package:shen_view/l10n/app_localizations_zh.dart';
import 'package:shen_view/src/application/codec_process.dart';
import 'package:shen_view/src/application/metadata_service.dart';
import 'package:shen_view/src/application/native_decoder.dart';
import 'package:shen_view/src/application/photo_metadata_reader.dart';
import 'package:shen_view/src/application/xmp_metadata.dart';
import 'package:shen_view/src/presentation/photo_metadata_format.dart';

import 'support/photo_metadata_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('photo-metadata');
  });
  tearDown(() => dir.deleteSync(recursive: true));
  File save(String name, List<int> bytes) =>
      File('${dir.path}/$name')..writeAsBytesSync(bytes);

  test(
    'common EXIF is read consistently from JPEG, PNG, WebP and TIFF',
    () async {
      final image = metadataPhoto();
      final fixtures = {
        'photo.jpg': img.encodeJpg(image),
        'photo.png': pngWithMetadata(image, afterPixels: true, padded: true),
        'photo.webp': webpWithMetadata(image),
        'photo.tiff': img.encodeTiff(image),
      };
      for (final fixture in fixtures.entries) {
        final file = save(fixture.key, fixture.value);
        final values = (await MetadataService().read(file.path)).values;
        expect(values['make'], 'ShenView', reason: fixture.key);
        expect(values['model'], 'Test camera', reason: fixture.key);
        expect(
          values['dateTimeOriginal'],
          '2026:10:26 12:34:56.123 +08:00',
          reason: fixture.key,
        );
        expect(values['lensModel'], 'Test lens');
        expect(photoNumber(values['fNumber']!), 2.8);
        expect(photoNumber(values['exposureTime']!), .008);
        expect(values['iso'], '100');
        expect(values['gpsLatitudeRef'], 'S');
        expect(values['gpsLongitudeRef'], 'W');
        final rows = Map.fromEntries(
          cameraMetadataRows(
            values,
            AppLocalizationsEn(),
          ).map((row) => MapEntry(row.$1, row.$2)),
        );
        expect(rows['Date taken'], '2026-10-26 12:34:56.123 +08:00');
        expect(rows['Aperture'], 'f/2.8');
        expect(rows['Shutter speed'], '1/125 s');
        expect(rows['Focal length'], '50 mm');
        expect(rows['White balance'], 'Auto');
        expect(rows['Flash'], 'Fired · Auto · Red-eye reduction');
        expect(rows['Location'], '33.500000° S, 70.666667° W');
      }
    },
  );

  test('XMP respects namespaces, UTF-8, localized alternatives, arrays and EXIF priority', () async {
    final parsed = readXmpMetadata(Uint8List.fromList(utf8.encode(photoXmp())));
    expect(parsed['title'], '中文标题 café 📷');
    expect(parsed['description'], '海边 & 山间');
    expect(parsed['creator'], '测试作者, Second author');
    expect(parsed['keywords'], '旅行, 照片');
    expect(parsed['rating'], '4');
    final file = save(
      'embedded.jpg',
      jpegWithXmp(img.encodeJpg(metadataPhoto()), photoXmp()),
    );
    final metadata = await MetadataService().read(file.path);
    expect(metadata.values['model'], 'Test camera');
    expect(photoNumber(metadata.values['fNumber']!), 2.8);
    expect(metadata.values['title'], '中文标题 café 📷');
    final rows = descriptiveMetadataRows(metadata.values, AppLocalizationsZh());
    expect(rows, contains(('标题', '中文标题 café 📷')));
    expect(rows, contains(('关键词', '旅行, 照片')));
  });

  test(
    'sidecar descriptions override embedded XMP without replacing capture data',
    () async {
      final file = save(
        'sidecar.jpg',
        jpegWithXmp(img.encodeJpg(metadataPhoto()), photoXmp()),
      );
      save('sidecar.xmp', utf8.encode(photoXmp(title: '旁车标题', rating: -1)));
      final values = (await MetadataService().read(file.path)).values;
      expect(values['title'], '旁车标题');
      expect(values['model'], 'Test camera');
      expect(values['rating'], '-1');
      expect(
        descriptiveMetadataRows(values, AppLocalizationsZh()),
        contains(('评分', '已拒绝')),
      );
      File('${dir.path}/sidecar.xmp').deleteSync();
      save('sidecar.jpg.XMP', utf8.encode(photoXmp(title: '扩展名旁车')));
      expect(PhotoMetadataReader.read(file.path)['title'], '扩展名旁车');
    },
  );

  test('missing, malformed and over-budget optional metadata leave valid images readable', () async {
    for (final xml in [
      '<bad>',
      '<!DOCTYPE x [<!ENTITY test "bad">]><x/>',
      photoXmp(rating: 9),
    ]) {
      final values = readXmpMetadata(Uint8List.fromList(utf8.encode(xml)));
      expect(values.containsKey('rating'), false);
    }
    expect(readXmpMetadata(Uint8List(2 * 1024 * 1024 + 1)), isEmpty);
    final plain = img.Image(width: 16, height: 8);
    final png = img.encodePng(plain);
    final file = save('bad.png', [
      ...png.take(33),
      ...pngChunk('eXIf', [73, 73, 42, 0, 255, 255, 255, 127]),
      ...pngChunk('iTXt', [
        ...ascii.encode('XML:com.adobe.xmp'),
        0,
        1,
        0,
        0,
        0,
        ...zlib.encode(Uint8List(5 * 1024 * 1024)),
      ]),
      ...png.skip(33),
    ]);
    final metadata = await MetadataService().read(file.path);
    expect((metadata.width, metadata.height), (16, 8));
    expect(metadata.values, isEmpty);
    expect(metadata.readable, isTrue);
    expect(metadata.colorSpace, isNull);
    save('bad.xmp', utf8.encode('<malformed>'));
    expect(PhotoMetadataReader.read(file.path), isEmpty);
  });

  test('GPS accepts DMS and XMP coordinates and rejects invalid ranges', () {
    expect(
      photoCoordinate('33/1, 30/1, 0/1', 'S', latitude: true),
      '33.500000° S',
    );
    expect(photoCoordinate('70,40W', null, latitude: false), '70.666667° W');
    expect(photoCoordinate('-33.5', null, latitude: true), '-33.500000°');
    expect(photoCoordinate('0,0N', null, latitude: true), '0.000000° N');
    for (final text in [
      '91,0N',
      '60/1, 60/1, 60/1',
      '1/0, 0, 0',
      'NaN',
      '1,2E',
    ]) {
      expect(photoCoordinate(text, null, latitude: true), isNull, reason: text);
    }
    expect(
      cameraMetadataRows({
        'iso': '0',
        'fNumber': '0',
        'focalLength': '0',
        'exposureTime': '0',
      }, AppLocalizationsZh()),
      isEmpty,
    );
  });

  test('embedded ICC names override EXIF color hints; absent profiles stay unknown', () async {
    final image = metadataPhoto();
    image.iccProfile = img.IccProfile(
      'Display P3',
      img.IccProfileCompression.none,
      File('testdata/photo_metadata/display_p3.icc').readAsBytesSync(),
    );
    final jpeg = save(
      'profile.jpg',
      jpegWithIcc(
        img.encodeJpg(image),
        File('testdata/photo_metadata/display_p3.icc').readAsBytesSync(),
      ),
    );
    expect(
      (await MetadataService().read(jpeg.path)).colorSpace,
      'Display P3 (ICC)',
    );
    final png = save('profile.png', img.encodePng(image));
    expect(
      (await MetadataService().read(png.path)).colorSpace,
      'Display P3 (ICC)',
    );
    final untagged = save(
      'untagged.jpg',
      img.encodeJpg(img.Image(width: 4, height: 2)),
    );
    expect((await MetadataService().read(untagged.path)).colorSpace, isNull);
    expect(iccProfileLabel(Uint8List(2)), 'ICC');
  });

  test('device fixtures retain the upstream bytes', () {
    const hashes = {
      'iphone_13_pro_max.heic':
          'e760c80eed310e4f27c092d5487693ca8e104e7cc01d25ba4828deb28f679676',
      'nokia_8_3.heif':
          'c2820b3e4e0368c6f031b28b62945658a97446895cb446dfc37acdcf7109e0f5',
      'nokia_8_3.jpg':
          '9be023624ccd5846beeb5b02d9b571251ef5bd8ed820389a430d114029f58eda',
    };
    for (final entry in hashes.entries) {
      expect(
        sha256
            .convert(
              File('testdata/photo_metadata/${entry.key}').readAsBytesSync(),
            )
            .toString(),
        entry.value,
      );
    }
  });

  test(
    'Android JPEG retains exposure, clock offset and all three GPS components',
    () async {
      final metadata = await MetadataService().read(
        'testdata/photo_metadata/nokia_8_3.jpg',
      );
      expect((metadata.width, metadata.height), (4608, 1976));
      expect(metadata.values['make'], 'HMD Global');
      expect(metadata.values['model'], 'Nokia 8.3 5G');
      expect(metadata.values['iso'], '100');
      expect(metadata.values['dateTimeOriginal'], '2022:08:14 14:12:31 +03:00');
      expect(photoNumber(metadata.values['fNumber']!), 2.2);
      expect(photoNumber(metadata.values['exposureTime']!), .000541);
      expect(
        cameraMetadataRows(metadata.values, AppLocalizationsEn()),
        contains(('Location', '60.146706° N, 24.906772° E')),
      );
    },
  );

  test(
    'iPhone HEIC exposes common EXIF and P3 even with minimal Windows metadata',
    () async {
      if (!await _hasHeifHelper()) return;
      const channel = MethodChannel('shenview/native_decoder');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'metadata'
            ? {'width': 4032, 'height': 3024, 'orientation': 6}
            : null,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final metadata = await MetadataService().read(
        'testdata/photo_metadata/iphone_13_pro_max.heic',
      );
      expect((metadata.width, metadata.height), (3024, 4032));
      expect(metadata.values['make'], 'Apple');
      expect(metadata.values['model'], 'iPhone 13 Pro Max');
      expect(
        metadata.values['dateTimeOriginal'],
        '2022:02:16 12:55:41.762 +01:00',
      );
      expect(metadata.values['iso'], '250');
      expect(metadata.values['lensModel'], contains('back triple camera'));
      expect(metadata.colorSpace, 'Display P3 (ICC)');
      final fallback = await NativeDecoder().metadata(
        'testdata/photo_metadata/iphone_13_pro_max.heic',
      );
      expect(
        (fallback['width'], fallback['height'], fallback['orientation']),
        (3024, 4032, 1),
      );
    },
  );

  test(
    'Android HEIF reads trailing EXIF without requiring a camera model',
    () async {
      if (!await _hasHeifHelper()) return;
      final values = await PhotoMetadataReader.readHeif(
        'testdata/photo_metadata/nokia_8_3.heif',
      );
      expect(photoNumber(values['fNumber']!), 1.89);
      expect(photoNumber(values['exposureTime']!), .0002);
      expect(
        photoCoordinate(
          values['gpsLatitude'],
          values['gpsLatitudeRef'],
          latitude: true,
        ),
        '40.788685° N',
      );
      expect(
        photoCoordinate(
          values['gpsLongitude'],
          values['gpsLongitudeRef'],
          latitude: false,
        ),
        '4.005141° W',
      );
    },
  );

  test('real Nikon and Sony RAW preserve their capture information', () async {
    try {
      await CodecProcess.locate('viewer_raw', 'SHENVIEW_RAW');
    } catch (_) {
      markTestSkipped('需要 LibRaw 组件');
      return;
    }
    for (final (name, model, iso, date) in [
      ('raw_nikon_d2h.nef', 'D2H', '200', '2005:09:24 13:23:28'),
      ('raw_sony_a7s.arw', 'ILCE-7S', '400', '2017:07:13 16:58:28'),
    ]) {
      final metadata = await MetadataService().read('testdata/formats/$name');
      expect(metadata.values['model'], model);
      expect(metadata.values['iso'], iso);
      expect(
        metadata.values['dateTimeOriginal'],
        startsWith(date),
        reason: name,
      );
    }
  });
}

Future<bool> _hasHeifHelper() async {
  try {
    await CodecProcess.locate('viewer_heif_gainmap', 'SHENVIEW_HEIF_GAINMAP');
    return true;
  } catch (_) {
    markTestSkipped('需要 HEIF 组件');
    return false;
  }
}
