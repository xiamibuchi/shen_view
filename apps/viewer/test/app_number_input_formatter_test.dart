import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/presentation/components/app_number_input_formatter.dart';

void main() {
  TextEditingValue edit(String text) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

  test('numeric edits preserve precision and do not turn malformed paste into a different number', () {
    final formatter = AppNumberInputFormatter(
      integerDigits: 4,
      decimalPlaces: 1,
    );
    final initial = edit('12.5');
    for (final text in ['1e3', '-1', '12abc3', '10000', '1.23', ' 7 ']) {
      expect(
        formatter.formatEditUpdate(initial, edit(text)),
        initial,
        reason: text,
      );
    }
    for (final text in ['', '.', '.5', '12.', '3600.0']) {
      expect(formatter.formatEditUpdate(initial, edit(text)).text, text);
    }
    expect(formatter.formatEditUpdate(initial, edit('12,5')).text, '12.5');
  });

  test('integer fields reject decimal separators and restore the last value after IME composition', () {
    final formatter = AppNumberInputFormatter(integerDigits: 4);
    final original = edit('256');
    expect(formatter.formatEditUpdate(original, edit('12.5')), original);
    expect(formatter.formatEditUpdate(original, edit('12,5')), original);
    final composing = edit('zhong')
        .copyWith(composing: const TextRange(start: 0, end: 5));
    expect(formatter.formatEditUpdate(original, composing), composing);
    expect(formatter.formatEditUpdate(composing, edit('中')), original);
    expect(formatter.formatEditUpdate(original, edit('1024')).text, '1024');
  });
}
