import '../domain/image_format.dart';
import 'format_detector.dart';

class FileAssociationFormats {
  static final images = Set<String>.unmodifiable(
    FormatDetector.extensionMap.entries
        .where(
          (entry) =>
              entry.value != ImageFormat.archive &&
              entry.value != ImageFormat.hdrVideo,
        )
        .map((entry) => entry.key),
  );
  static const archives = FormatDetector.archiveExtensions;
  static final all = Set<String>.unmodifiable({...images, ...archives});
}
