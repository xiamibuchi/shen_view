import '../../l10n/app_localizations.dart';
import '../domain/archive_failure.dart';

String localizedArchiveFailure(AppLocalizations l10n, ArchiveFailureKind kind) {
  return switch (kind) {
    ArchiveFailureKind.missingTool => l10n.sevenZipMissing,
    ArchiveFailureKind.encrypted => l10n.archiveEncrypted,
    ArchiveFailureKind.corrupt => l10n.archiveCorrupt,
    ArchiveFailureKind.unsupported => l10n.archiveUnsupported,
    ArchiveFailureKind.limit => l10n.archiveLimitExceeded,
    ArchiveFailureKind.timeout => l10n.archiveTimeout,
    ArchiveFailureKind.unsafePath => l10n.unsafeArchivePath,
    ArchiveFailureKind.io => l10n.archiveIoError,
    ArchiveFailureKind.empty => l10n.archiveEmpty,
    ArchiveFailureKind.wrongPassword => l10n.archivePasswordWrong,
    ArchiveFailureKind.passwordUnverifiable => l10n.archivePasswordUnverified,
    ArchiveFailureKind.volumeMissing => l10n.archiveVolumeMissing,
    ArchiveFailureKind.sourceChanged => l10n.archiveSourceChanged,
    ArchiveFailureKind.resource => l10n.archiveResourceInsufficient,
  };
}

String localizedErrorMessage(AppLocalizations l10n, Object error) {
  var message = error.toString();
  while (message.startsWith('Bad state: ')) {
    message = message.substring('Bad state: '.length);
  }
  if (message.startsWith('Unsupported operation: ')) {
    message = message.substring('Unsupported operation: '.length);
  }

  switch (message) {
    case '不是有效的 PNG/APNG':
      return l10n.invalidPngApng;
    case '当前平台没有实现文件复制到系统剪贴板':
      return l10n.clipboardUnavailable;
    case '当前平台没有实现回收站接口':
      return l10n.recycleBinUnavailable;
    case '无法解析图片像素':
      return l10n.pixelReadFailed;
    case '动图超过文件读取预算。':
      return l10n.animatedReadLimit;
    case '图片文件超过读取预算，请使用长图模式或较小的图片。':
      return l10n.imageReadLimit;
    case '扩展解码器不可用，请重新安装完整发行包，或设置 SHENVIEW_MAGICK。':
      return l10n.decoderUnavailableError;
  }
  if (message.startsWith('图片解析超时')) return l10n.decodeTimeout;
  if (message.startsWith('图片超过解码内存预算')) {
    return l10n.decodeMemoryLimit;
  }
  if (message.startsWith('解析失败：')) {
    return l10n.decodeFailed(message.substring('解析失败：'.length));
  }
  return message;
}
