import 'archive_service.dart';
import 'decode_request.dart';
import 'image_source.dart';

class ArchiveImageSource implements ImageSource {
  const ArchiveImageSource(this.session, this.entry);
  final ArchiveSession session;
  final ArchiveEntry entry;

  @override
  String get id => 'archive:${session.identity}:${entry.index}';
  @override
  String get name => entry.name.split('/').last;
  @override
  String get relativePath => entry.name;
  @override
  bool get sensitive => session.encrypted;

  @override
  Future<SourceFileLease> acquireFile({DecodeRequest? request}) async {
    final lease = await session.acquireFile(entry, request: request);
    return SourceFileLease(lease.file, onRelease: lease.release);
  }
}
