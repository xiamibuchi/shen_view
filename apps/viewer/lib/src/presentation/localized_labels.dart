import '../../l10n/app_localizations.dart';
import '../domain/comic_layout_direction.dart';
import '../domain/image_format.dart';
import '../domain/viewer_settings.dart';
import '../domain/view_scale_mode.dart';
import '../domain/viewer_mode.dart';
import '../application/decoder_registry.dart';

String localizedViewerModeLabel(AppLocalizations l10n, ViewerMode mode) =>
    switch (mode) {
      ViewerMode.single => l10n.singlePage,
      ViewerMode.doublePage => l10n.doublePage,
      ViewerMode.longImage => l10n.longImage,
      ViewerMode.comic => l10n.comic,
    };

String localizedSortOrderLabel(AppLocalizations l10n, SortOrder order) {
  switch (order) {
    case SortOrder.fileSystem:
      return l10n.fileSystemOrder;
    case SortOrder.nameAscending:
      return l10n.fileNameAscending;
    case SortOrder.nameDescending:
      return l10n.fileNameDescending;
    case SortOrder.sizeAscending:
      return l10n.fileSizeAscending;
    case SortOrder.sizeDescending:
      return l10n.fileSizeDescending;
    case SortOrder.modifiedNewest:
      return l10n.modifiedNewest;
    case SortOrder.modifiedOldest:
      return l10n.modifiedOldest;
  }
}

String localizedScaleModeLabel(AppLocalizations l10n, ViewScaleMode mode) {
  switch (mode) {
    case ViewScaleMode.autoFit:
      return l10n.autoZoom;
    case ViewScaleMode.fitWidth:
      return l10n.widthPriority;
    case ViewScaleMode.fitHeight:
      return l10n.heightPriority;
    case ViewScaleMode.originalSize:
      return l10n.originalSize;
  }
}

String localizedComicLayoutLabel(
  AppLocalizations l10n,
  ComicLayoutDirection direction,
) {
  switch (direction) {
    case ComicLayoutDirection.vertical:
      return l10n.verticalContinuous;
    case ComicLayoutDirection.horizontalLeftToRight:
      return l10n.horizontalLeftToRight;
    case ComicLayoutDirection.horizontalRightToLeft:
      return l10n.horizontalRightToLeft;
  }
}

String localizedFormatLabel(AppLocalizations l10n, ImageFormat format) {
  return switch (format) {
    ImageFormat.archive => l10n.archiveFormat,
    ImageFormat.unknown => l10n.unknownFormat,
    _ => format.label,
  };
}

String localizedDecoderSource(AppLocalizations l10n, DecoderSource source) {
  switch (source) {
    case DecoderSource.flutterCodec:
      return l10n.decoderFlutterCodec;
    case DecoderSource.dartImageSvg:
      return l10n.decoderDartImageSvg;
    case DecoderSource.archive:
      return l10n.decoderArchive;
    case DecoderSource.imageMagickJxl:
      return l10n.decoderImageMagickJxl;
    case DecoderSource.windowsWic:
      return l10n.decoderWindowsWic;
    case DecoderSource.macImageIo:
      return l10n.decoderMacImageIo;
    case DecoderSource.imageMagickFallback:
      return l10n.decoderImageMagickFallback;
    case DecoderSource.hdrVideo:
      return 'FFmpeg / libplacebo';
    case DecoderSource.unavailable:
      return l10n.decoderUnavailable;
  }
}
