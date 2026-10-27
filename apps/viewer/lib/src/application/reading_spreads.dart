import '../domain/image_entry.dart';

/// Logical spreads shared by rendering, navigation and prefetch.
List<List<int>> readingSpreads(
  List<ImageEntry> pages, {
  bool firstAlone = true,
  bool wideAlone = true,
  bool splitWide = false,
  int? pairingAnchor,
  Set<String> landscapeIds = const {},
}) {
  final groups = <List<int>>[];
  var index = 0;
  bool landscape(int i) =>
      (wideAlone || splitWide) &&
      (landscapeIds.contains(pages[i].id) ||
          (pages[i].width != null &&
              pages[i].height != null &&
              pages[i].width! > pages[i].height!));
  while (index < pages.length) {
    if ((index == 0 && firstAlone) ||
        index + 1 == pairingAnchor ||
        landscape(index) ||
        index + 1 >= pages.length ||
        landscape(index + 1)) {
      groups.add([index++]);
    } else {
      groups.add([index, index + 1]);
      index += 2;
    }
  }
  return groups;
}
