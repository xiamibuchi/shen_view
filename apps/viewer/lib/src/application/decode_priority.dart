// Ordering is also used by the Windows and macOS native decode queues.
enum DecodePriority {
  foreground,
  visible,
  visibleThumbnail,
  adjacent,
  near,
  metadata,
  thumbnail,
  preload,
}
