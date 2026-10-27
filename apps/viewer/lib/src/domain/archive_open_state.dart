import 'archive_failure.dart';

enum ArchiveOpenPhase { idle, opening, ready, empty, failed }

/// Session state of one archive entry shown in the folder navigation row.
class ArchiveOpenState {
  const ArchiveOpenState({
    this.phase = ArchiveOpenPhase.idle,
    this.failure,
    this.imageCount = 0,
    this.extracted = 0,
    this.total = 0,
  });

  final ArchiveOpenPhase phase;
  final ArchiveFailureKind? failure;
  final int imageCount;
  final int extracted;
  final int total;

  bool get isOpening => phase == ArchiveOpenPhase.opening;
  bool get isEmpty => phase == ArchiveOpenPhase.empty;
  bool get hasFailed => phase == ArchiveOpenPhase.failed;

  ArchiveOpenState copyWith({
    ArchiveOpenPhase? phase,
    ArchiveFailureKind? failure,
    bool clearFailure = false,
    int? imageCount,
    int? extracted,
    int? total,
  }) {
    return ArchiveOpenState(
      phase: phase ?? this.phase,
      failure: clearFailure ? null : (failure ?? this.failure),
      imageCount: imageCount ?? this.imageCount,
      extracted: extracted ?? this.extracted,
      total: total ?? this.total,
    );
  }
}
