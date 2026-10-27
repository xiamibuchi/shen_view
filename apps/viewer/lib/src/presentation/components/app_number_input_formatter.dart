import 'package:flutter/services.dart';

/// Validates the whole edit (including paste) without silently stripping digits.
/// Empty text and a trailing decimal separator remain valid editing states;
/// callers validate the numeric range before saving the value.
class AppNumberInputFormatter extends TextInputFormatter {
  AppNumberInputFormatter({required int integerDigits, int decimalPlaces = 0})
    : assert(integerDigits > 0),
      assert(decimalPlaces >= 0),
      _decimal = decimalPlaces > 0,
      _pattern = RegExp(
        decimalPlaces == 0
            ? '^[0-9]{0,$integerDigits}\$'
            : '^[0-9]{0,$integerDigits}(?:[.][0-9]{0,$decimalPlaces})?\$',
      );

  final RegExp _pattern;
  final bool _decimal;
  TextEditingValue _lastValidValue = TextEditingValue.empty;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Never rewrite an IME's in-progress composing range. Validate on commit.
    if (_pattern.hasMatch(oldValue.text) && oldValue.composing.isCollapsed) {
      _lastValidValue = oldValue;
    }
    if (!newValue.composing.isCollapsed) return newValue;
    final text = _decimal ? newValue.text.replaceAll(',', '.') : newValue.text;
    if (!_pattern.hasMatch(text)) {
      // A rejected IME commit must not restore an invalid composing value.
      return _lastValidValue.copyWith(composing: TextRange.empty);
    }
    return _lastValidValue = newValue.copyWith(text: text);
  }
}
