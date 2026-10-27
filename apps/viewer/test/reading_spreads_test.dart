import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/reading_spreads.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';

void main() {
  test(
    'wide-image preferences share the same render and navigation groups',
    () {
      final pages = _pages(6);
      pages[2] = _page(2, width: 1600, height: 1000);
      expect(readingSpreads(pages, wideAlone: false), [
        [0],
        [1, 2],
        [3, 4],
        [5],
      ]);
      // Splitting takes priority over pairing, including failure fallback.
      expect(readingSpreads(pages, wideAlone: false, splitWide: true), [
        [0],
        [1],
        [2],
        [3, 4],
        [5],
      ]);
      expect(readingSpreads(pages, firstAlone: false, wideAlone: false), [
        [0, 1],
        [2, 3],
        [4, 5],
      ]);
      expect(readingSpreads(_pages(6), pairingAnchor: 2), [
        [0],
        [1],
        [2, 3],
        [4, 5],
      ]);
    },
  );

  test(
    'covers, full spreads and the final unpaired page form navigation groups',
    () {
      expect(readingSpreads([]), isEmpty);
      expect(readingSpreads(_pages(1)), [
        [0],
      ]);
      expect(readingSpreads(_pages(6)), [
        [0],
        [1, 2],
        [3, 4],
        [5],
      ]);
      expect(readingSpreads(_pages(5), firstAlone: false), [
        [0, 1],
        [2, 3],
        [4],
      ]);
    },
  );

  test('landscape pages never pair with a preceding or following portrait', () {
    final pages = _pages(7);
    pages[2] = _page(2, width: 1600, height: 900);
    pages[5] = _page(5, width: 1200, height: 800);
    expect(readingSpreads(pages, firstAlone: false), [
      [0, 1],
      [2],
      [3, 4],
      [5],
      [6],
    ]);
    pages[1] = _page(1, width: 1400, height: 900);
    expect(readingSpreads(pages, firstAlone: false), [
      [0],
      [1],
      [2],
      [3, 4],
      [5],
      [6],
    ]);
  });

  test('late landscape metadata regroups around stable image identities', () {
    final pages = _pages(5, unknown: true);
    final before = readingSpreads(pages);
    final after = readingSpreads(pages, landscapeIds: {pages[2].id});
    expect(before, [
      [0],
      [1, 2],
      [3, 4],
    ]);
    expect(after, [
      [0],
      [1],
      [2],
      [3, 4],
    ]);
    expect(
      after.expand((group) => group).map((index) => pages[index].id),
      pages.map((entry) => entry.id),
    );
    expect(after.singleWhere((group) => group.contains(2)), [2]);
  });

  test('square and unknown-size pages retain portrait grouping until dimensions arrive', () {
    final pages = [
      _page(0, width: 1000, height: 1000),
      _page(1),
      _page(2, width: 900, height: null),
    ];
    expect(readingSpreads(pages, firstAlone: false), [
      [0, 1],
      [2],
    ]);
  });
}

List<ImageEntry> _pages(int count, {bool unknown = false}) => List.generate(
  count,
  (index) => unknown ? _page(index) : _page(index, width: 800, height: 1200),
);

ImageEntry _page(int index, {int? width, int? height}) => ImageEntry(
  file: File.fromUri(Directory.systemTemp.uri.resolve('page-$index.png')),
  format: ImageFormat.png,
  width: width,
  height: height,
  byteLength: 10,
  modifiedAt: DateTime(2024),
);
