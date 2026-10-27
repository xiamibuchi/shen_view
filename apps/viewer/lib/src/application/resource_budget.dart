import 'dart:math' as math;

/// Includes both resident resources and in-flight peak allocations.
/// A reservation is charged until its owner actually releases the allocation.
class ResourceBudget {
  ResourceBudget({required int limitBytes})
    : _limitBytes = math.max(0, limitBytes);

  int _limitBytes;
  int _usedBytes = 0;
  void Function()? onChanged;

  int get limitBytes => _limitBytes;
  set limitBytes(int value) {
    final next = math.max(0, value);
    if (next == _limitBytes) return;
    _limitBytes = next;
    _notifyChanged();
  }

  void _notifyChanged() {
    onChanged?.call();
  }

  int get usedBytes => _usedBytes;
  int get availableBytes => math.max(0, _limitBytes - _usedBytes);
  bool get oversubscribed => _usedBytes > _limitBytes;

  ResourceReservation? reserve(int bytes, {int headroomBytes = 0}) {
    if (bytes < 0 || headroomBytes < 0) {
      throw ArgumentError('Resource costs must be nonnegative.');
    }
    if (bytes + headroomBytes > availableBytes) return null;
    _usedBytes += bytes;
    return ResourceReservation._(this, bytes);
  }
}

class ResourceReservation {
  ResourceReservation._(this._budget, this.bytes);

  ResourceBudget? _budget;
  final int bytes;
  bool get released => _budget == null;

  void release() {
    final budget = _budget;
    if (budget == null) return;
    _budget = null;
    budget._usedBytes -= bytes;
    budget._notifyChanged();
  }
}
