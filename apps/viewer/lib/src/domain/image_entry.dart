import 'dart:io';

import '../application/decode_request.dart';
import '../application/image_source.dart';

import 'image_format.dart';

class ImageEntry {
  const ImageEntry({
    required File file,
    required ImageFormat format,
    required int? width,
    required int? height,
    required int byteLength,
    required DateTime modifiedAt,
    String? relativeFolder,
  }) : this._(
         file,
         null,
         format,
         byteLength,
         modifiedAt,
         width,
         height,
         relativeFolder,
       );

  const ImageEntry.fromSource({
    required ImageSource source,
    required ImageFormat format,
    required int byteLength,
    required DateTime modifiedAt,
    int? width,
    int? height,
    String? relativeFolder,
  }) : this._(
         null,
         source,
         format,
         byteLength,
         modifiedAt,
         width,
         height,
         relativeFolder,
       );

  const ImageEntry._(
    this._file,
    this.source,
    this.format,
    this.byteLength,
    this.modifiedAt,
    this.width,
    this.height,
    this.relativeFolder,
  );
  final File? _file;
  final ImageSource? source;

  /// Only local or leased entries expose a real file. Archive lists never
  /// manufacture a nonexistent temporary path. Use [id] for identity.
  File get file => _file ?? (throw StateError('Image source is not acquired'));
  bool get isMaterialized => _file != null;
  String get id => source?.id ?? file.path;

  Future<SourceFileLease> acquireFile({DecodeRequest? request}) {
    request?.throwIfCancelled();
    return source?.acquireFile(request: request) ??
        Future.value(SourceFileLease(file));
  }

  ImageEntry withFile(File file) => ImageEntry._(
    file,
    source,
    format,
    byteLength,
    modifiedAt,
    width,
    height,
    relativeFolder,
  );
  final ImageFormat format;
  final int? width;
  final int? height;
  final int byteLength;
  final DateTime modifiedAt;

  /// Folder path relative to the opened folder, or null for direct images.
  /// Used by the flat recursive mode to label and group images.
  final String? relativeFolder;

  String get name => source?.name ?? file.uri.pathSegments.last;

  String get relativePath {
    if (source != null) return source!.relativePath;
    final folder = relativeFolder;
    if (folder == null || folder.isEmpty) return name;
    return '$folder/$name';
  }

  bool get isAnimated =>
      format == ImageFormat.gif ||
      format == ImageFormat.webp ||
      format == ImageFormat.apng;
}
