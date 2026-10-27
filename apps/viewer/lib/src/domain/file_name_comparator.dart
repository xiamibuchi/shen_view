import 'package:path/path.dart' as paths;

import 'sort_order.dart';

/// Compares stems first, then extensions alphabetically. Callers break remaining
/// ties using the local path or archive entry index, never the scan order.
int compareFileNames(String left, String right, FileNameSortMode mode) {
  final leftExtension = paths.extension(left);
  final rightExtension = paths.extension(right);
  final stem = compareNames(
    left.substring(0, left.length - leftExtension.length),
    right.substring(0, right.length - rightExtension.length),
    mode,
  );
  return stem != 0
      ? stem
      : leftExtension.toLowerCase().compareTo(rightExtension.toLowerCase());
}

/// Directory names are compared whole, without treating dots as extensions.
int compareNames(String left, String right, FileNameSortMode mode) =>
    mode == FileNameSortMode.natural
    ? naturalCompare(left, right)
    : left.toLowerCase().compareTo(right.toLowerCase());

/// Natural comparison without integer parsing limits on long numeric names.
int naturalCompare(String left, String right) {
  final a = left.toLowerCase();
  final b = right.toLowerCase();
  var i = 0;
  var j = 0;
  bool digit(int c) => c >= 48 && c <= 57;
  while (i < a.length && j < b.length) {
    if (digit(a.codeUnitAt(i)) && digit(b.codeUnitAt(j))) {
      final startA = i;
      final startB = j;
      while (i < a.length && digit(a.codeUnitAt(i))) {
        i++;
      }
      while (j < b.length && digit(b.codeUnitAt(j))) {
        j++;
      }
      var nzA = startA;
      var nzB = startB;
      while (nzA < i - 1 && a.codeUnitAt(nzA) == 48) {
        nzA++;
      }
      while (nzB < j - 1 && b.codeUnitAt(nzB) == 48) {
        nzB++;
      }
      final length = (i - nzA).compareTo(j - nzB);
      if (length != 0) return length;
      final value = a.substring(nzA, i).compareTo(b.substring(nzB, j));
      if (value != 0) return value;
      final padding = (i - startA).compareTo(j - startB);
      if (padding != 0) return padding;
    } else {
      final value = a.codeUnitAt(i).compareTo(b.codeUnitAt(j));
      if (value != 0) return value;
      i++;
      j++;
    }
  }
  return (a.length - i).compareTo(b.length - j);
}
