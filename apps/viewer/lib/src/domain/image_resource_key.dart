class ImageFileVersion {
  const ImageFileVersion({
    required this.path,
    required this.modifiedMicroseconds,
    required this.byteLength,
    this.revision = 0,
  });

  final String path;
  final int modifiedMicroseconds;
  final int byteLength;
  final int revision;

  @override
  bool operator ==(Object other) =>
      other is ImageFileVersion &&
      other.path == path &&
      other.modifiedMicroseconds == modifiedMicroseconds &&
      other.byteLength == byteLength &&
      other.revision == revision;

  @override
  int get hashCode =>
      Object.hash(path, modifiedMicroseconds, byteLength, revision);
}

class ImageRegion {
  const ImageRegion({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int left;
  final int top;
  final int width;
  final int height;

  Map<String, int> toMap() => {
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };

  String get crop => '${width}x$height+$left+$top';

  @override
  bool operator ==(Object other) =>
      other is ImageRegion &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}

class ImageResourceKey {
  const ImageResourceKey({
    required this.version,
    this.targetWidth,
    this.targetHeight,
    this.region,
    this.allowSmallRawPreview = false,
    this.icoIndex,
  });

  final ImageFileVersion version;
  final int? targetWidth;
  final int? targetHeight;
  final ImageRegion? region;
  final int? icoIndex;

  /// Small camera previews are valid for thumbnails, never for main detail.
  final bool allowSmallRawPreview;

  @override
  bool operator ==(Object other) =>
      other is ImageResourceKey &&
      other.version == version &&
      other.targetWidth == targetWidth &&
      other.targetHeight == targetHeight &&
      other.allowSmallRawPreview == allowSmallRawPreview &&
      other.icoIndex == icoIndex &&
      other.region == region;

  @override
  int get hashCode => Object.hash(
    version,
    targetWidth,
    targetHeight,
    region,
    allowSmallRawPreview,
    icoIndex,
  );
}
