import 'dart:io';
import 'dart:typed_data';

import '../domain/image_format.dart';
import 'ico_file.dart';

class FormatDetector {
  static const archiveExtensions = {
    'zip',
    'cbz',
    'cbr',
    'rar',
    '7z',
    'cb7',
    'tar',
    'cbt',
  };

  static const extensionMap = <String, ImageFormat>{
    'jpg': ImageFormat.jpeg,
    'jpeg': ImageFormat.jpeg,
    'jpe': ImageFormat.jpeg,
    'jfif': ImageFormat.jpeg,
    'png': ImageFormat.png,
    'gif': ImageFormat.gif,
    'webp': ImageFormat.webp,
    'bmp': ImageFormat.bmp,
    'ico': ImageFormat.ico,
    'tif': ImageFormat.tiff,
    'tiff': ImageFormat.tiff,
    'apng': ImageFormat.apng,
    'heic': ImageFormat.heic,
    'heif': ImageFormat.heif,
    'heics': ImageFormat.heic,
    'heifs': ImageFormat.heif,
    'hif': ImageFormat.heif,
    'avif': ImageFormat.avif,
    'avis': ImageFormat.avif,
    'jxl': ImageFormat.jxl,
    'psd': ImageFormat.psd,
    'svg': ImageFormat.svg,
    'cr2': ImageFormat.raw,
    'exr': ImageFormat.exr,
    'hdr': ImageFormat.hdr,
    'hevc': ImageFormat.hdrVideo,
    'h265': ImageFormat.hdrVideo,
    'dds': ImageFormat.dds,
    'zip': ImageFormat.archive,
    'cbz': ImageFormat.archive,
    'cbr': ImageFormat.archive,
    'rar': ImageFormat.archive,
    '7z': ImageFormat.archive,
    'cb7': ImageFormat.archive,
    'tar': ImageFormat.archive,
    'cbt': ImageFormat.archive,
    'nef': ImageFormat.raw,
    'arw': ImageFormat.raw,
    'dng': ImageFormat.raw,
  };

  Future<ImageFormat> detect(File file) async {
    final bytes = await file
        // Include the APNG acTL chunk following PNG's 33-byte IHDR. Folder
        // scans already use this same bounded header size.
        .openRead(0, 128)
        .fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    return fromFileHeader(Uint8List.fromList(bytes), file.path);
  }

  static String extensionOf(String path) {
    final name = path.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static ImageFormat? formatForPath(String path) {
    final extension = extensionOf(path);
    if (extension.isEmpty) return null;
    return extensionMap[extension];
  }

  static bool isArchivePath(String path) =>
      archiveExtensions.contains(extensionOf(path));

  static bool isKnownPath(String path) =>
      extensionMap.containsKey(extensionOf(path));

  /// Folder scans reuse their buffered header while retaining format-specific
  /// routes for camera RAW files inside TIFF containers.
  ImageFormat fromFileHeader(Uint8List bytes, String path) {
    final detected = fromSignature(bytes);
    final extension = extensionOf(path);
    final byExtension = extensionMap[extension];
    // Camera RAW containers such as CR2, NEF, ARW and DNG use a TIFF
    // signature. Keep the format-specific route instead of treating them as
    // ordinary TIFF files.
    if (detected == ImageFormat.tiff && byExtension == ImageFormat.raw) {
      return ImageFormat.raw;
    }
    if (detected == ImageFormat.heic && byExtension == ImageFormat.heif) {
      return ImageFormat.heif;
    }
    if (detected != ImageFormat.unknown) return detected;
    return byExtension ?? ImageFormat.unknown;
  }

  ImageFormat fromSignature(Uint8List bytes) {
    if (IcoFile.matches(bytes)) return ImageFormat.ico;
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return ImageFormat.jpeg;
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      if (_contains(bytes, const [0x61, 0x63, 0x54, 0x4C])) {
        return ImageFormat.apng;
      }
      return ImageFormat.png;
    }
    if (bytes.length >= 6 &&
        (String.fromCharCodes(bytes.sublist(0, 6)) == 'GIF89a' ||
            String.fromCharCodes(bytes.sublist(0, 6)) == 'GIF87a')) {
      return ImageFormat.gif;
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return ImageFormat.webp;
    }
    if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return ImageFormat.bmp;
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04) {
      return ImageFormat.archive;
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x38 &&
        bytes[1] == 0x42 &&
        bytes[2] == 0x50 &&
        bytes[3] == 0x53) {
      return ImageFormat.psd;
    }
    if (bytes.length >= 4 &&
        ((bytes[0] == 0x49 &&
                bytes[1] == 0x49 &&
                bytes[2] == 0x2A &&
                bytes[3] == 0x00) ||
            (bytes[0] == 0x4D &&
                bytes[1] == 0x4D &&
                bytes[2] == 0x00 &&
                bytes[3] == 0x2A))) {
      return ImageFormat.tiff;
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
      final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
      final boxSize = ByteData.sublistView(bytes).getUint32(0);
      if (brand == 'avif' || brand == 'avis') return ImageFormat.avif;
      for (var at = 16; at + 4 <= bytes.length && at + 4 <= boxSize; at += 4) {
        final compatible = String.fromCharCodes(bytes.sublist(at, at + 4));
        if (compatible == 'avif' || compatible == 'avis') {
          return ImageFormat.avif;
        }
      }
      if (brand == 'heic') return ImageFormat.heic;
      if (brand == 'heif') return ImageFormat.heif;
    }
    return ImageFormat.unknown;
  }

  bool _contains(Uint8List bytes, List<int> needle) {
    for (var index = 0; index <= bytes.length - needle.length; index++) {
      var match = true;
      for (var offset = 0; offset < needle.length; offset++) {
        if (bytes[index + offset] != needle[offset]) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
    return false;
  }
}
