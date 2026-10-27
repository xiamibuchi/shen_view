import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

/// Only bounded, well-known XMP properties are exposed. XML namespace URIs,
/// rather than producer-specific prefixes, identify each property.
Map<String, String> readXmpMetadata(Uint8List bytes) {
  if (bytes.length > 2 * 1024 * 1024) return const {};
  try {
    final text = utf8.decode(bytes).replaceAll('\u0000', '');
    if (text.contains('<!DOCTYPE') || text.contains('<!ENTITY')) {
      return const {};
    }
    final document = XmlDocument.parse(text);
    const dc = 'http://purl.org/dc/elements/1.1/';
    const xmp = 'http://ns.adobe.com/xap/1.0/';
    const tiff = 'http://ns.adobe.com/tiff/1.0/';
    const exif = 'http://ns.adobe.com/exif/1.0/';
    const aux = 'http://ns.adobe.com/exif/1.0/aux/';
    const exifEx = 'http://cipa.jp/exif/1.0/';
    const rdf = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';
    const fields = {
      dc: {
        'title': 'title',
        'description': 'description',
        'creator': 'creator',
        'rights': 'copyright',
        'subject': 'keywords',
      },
      xmp: {'Rating': 'rating', 'CreateDate': '_createDate'},
      tiff: {'Make': 'make', 'Model': 'model', 'Orientation': 'orientation'},
      exif: {
        'DateTimeOriginal': 'dateTimeOriginal',
        'ExposureTime': 'exposureTime',
        'FNumber': 'fNumber',
        'FocalLength': 'focalLength',
        'ISOSpeedRatings': 'iso',
        'ExposureBiasValue': 'exposureBias',
        'WhiteBalance': 'whiteBalance',
        'Flash': 'flash',
        'GPSLatitude': 'gpsLatitude',
        'GPSLongitude': 'gpsLongitude',
        'ColorSpace': 'exifColorSpace',
      },
      aux: {'Lens': 'lensModel', 'LensModel': 'lensModel'},
      exifEx: {'LensModel': 'lensModel', 'PhotographicSensitivity': 'iso'},
    };
    final values = <String, String>{};
    void add(String? key, String value) {
      value = value.trim();
      if (key == null || value.isEmpty || value.length > 8192) return;
      if (key == 'rating') {
        final rating = int.tryParse(value);
        if (rating == null || rating < -1 || rating > 5) return;
      }
      values[key] = value;
    }

    for (final element in document.descendants.whereType<XmlElement>()) {
      for (final attribute in element.attributes) {
        add(
          fields[attribute.namespaceUri]?[attribute.name.local],
          attribute.value,
        );
      }
      final key = fields[element.namespaceUri]?[element.name.local];
      if (key == null) continue;
      if (key == 'flash' && element.childElements.isNotEmpty) {
        String? flashField(String name) => element.descendants
            .whereType<XmlElement>()
            .where((e) => e.namespaceUri == exif && e.name.local == name)
            .map((e) => e.innerText.trim())
            .firstOrNull;
        final fired = flashField('Fired')?.toLowerCase();
        if (fired == 'true' || fired == 'false') {
          final mode = int.tryParse(flashField('Mode') ?? '') ?? 0;
          final returned = int.tryParse(flashField('Return') ?? '') ?? 0;
          add(
            key,
            '${(fired == "true" ? 1 : 0) | ((returned & 3) << 1) | ((mode & 3) << 3) | (flashField("Function")?.toLowerCase() == "false" ? 32 : 0) | (flashField("RedEyeMode")?.toLowerCase() == "true" ? 64 : 0)}',
          );
        }
        continue;
      }
      final items = element.descendants
          .whereType<XmlElement>()
          .where((e) => e.namespaceUri == rdf && e.name.local == 'li')
          .toList();
      if (items.isEmpty) {
        if (element.childElements.isEmpty) {
          add(key, element.innerText);
        }
      } else if ({'title', 'description', 'copyright'}.contains(key)) {
        final preferred = items
            .where(
              (e) =>
                  e.getAttribute(
                    'lang',
                    namespaceUri: 'http://www.w3.org/XML/1998/namespace',
                  ) ==
                  'x-default',
            )
            .firstOrNull;
        add(key, (preferred ?? items.first).innerText);
      } else {
        add(
          key,
          items
              .map((e) => e.innerText.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .join(', '),
        );
      }
    }
    final created = values.remove('_createDate');
    if (created != null) values.putIfAbsent('dateTimeOriginal', () => created);
    return values;
  } on Object {
    return const {};
  }
}
