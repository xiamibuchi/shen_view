import 'folder_entry.dart';
import 'image_entry.dart';

enum ScanTruncationReason { imageLimit, directoryLimit, depthLimit }

/// Progress reported while an index scan is running.
class FolderScanProgress {
  const FolderScanProgress({
    required this.scannedDirectories,
    required this.foundImages,
  });

  final int scannedDirectories;
  final int foundImages;
}

class FolderIndexResult {
  const FolderIndexResult({
    required this.images,
    required this.containers,
    required this.childFolders,
    required this.truncated,
    required this.scannedDirectoryCount,
    this.truncationReason,
    this.skippedFolders = const [],
    this.headerProbeCount = 0,
  });

  final List<ImageEntry> images;
  final List<ImageEntry> containers;
  final List<FolderEntry> childFolders;
  final bool truncated;
  final int scannedDirectoryCount;
  final ScanTruncationReason? truncationReason;

  /// Directories that could not be read. They do not make the scan truncated;
  /// remaining sibling folders are still indexed.
  final List<String> skippedFolders;

  /// Number of files whose header was read. Used by tests and the scan probe
  /// to verify that extension-first scanning avoids unnecessary IO.
  final int headerProbeCount;

  FolderIndexResult copyWith({
    List<ImageEntry>? images,
    List<ImageEntry>? containers,
    List<FolderEntry>? childFolders,
  }) {
    return FolderIndexResult(
      images: images ?? this.images,
      containers: containers ?? this.containers,
      childFolders: childFolders ?? this.childFolders,
      truncated: truncated,
      scannedDirectoryCount: scannedDirectoryCount,
      truncationReason: truncationReason,
      skippedFolders: skippedFolders,
      headerProbeCount: headerProbeCount,
    );
  }
}
