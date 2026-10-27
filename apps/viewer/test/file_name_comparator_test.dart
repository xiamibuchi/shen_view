import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/domain/file_name_comparator.dart';
import 'package:shen_view/src/domain/sort_order.dart';

void main() {
  test('natural numbers, padding and string ordering are explicit', () {
    final names = ['10.jpg', '0001.jpg', '2.jpg', '01.jpg', '001.jpg', '1.jpg'];
    expect(
      [...names]
        ..sort((a, b) => compareFileNames(a, b, FileNameSortMode.natural)),
      ['1.jpg', '01.jpg', '001.jpg', '0001.jpg', '2.jpg', '10.jpg'],
    );
    expect(
      [
        ...names,
      ]..sort((a, b) => compareFileNames(a, b, FileNameSortMode.lexicographic)),
      ['0001.jpg', '001.jpg', '01.jpg', '1.jpg', '10.jpg', '2.jpg'],
    );
    expect(naturalCompare('p${'9' * 80}', 'p1${'0' * 80}'), lessThan(0));
    expect(naturalCompare('p0', 'p00'), lessThan(0));
    expect(naturalCompare('v2-p10', 'v10-p2'), lessThan(0));
  });

  test(
    'stems precede extensions and extensions always compare alphabetically',
    () {
      for (final mode in FileNameSortMode.values) {
        final names = ['01.png', '01.jpg', '01.avif', '01-2.jpg', '01.jxl'];
        names.sort((a, b) => compareFileNames(a, b, mode));
        expect(names, ['01.avif', '01.jpg', '01.jxl', '01.png', '01-2.jpg']);
        expect(compareFileNames('01.JPG', '01.jpg', mode), 0);
        expect(compareFileNames('page.a10', 'page.a2', mode), lessThan(0));
      }
    },
  );
}
