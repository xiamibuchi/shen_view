import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/presentation/components/app_info_field.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

void main() {
  testWidgets('metadata aligns values and keeps long content fully visible', (
    tester,
  ) async {
    const longValue =
        'A long camera lens description with additional metadata that must '
        'remain readable across more than three lines in a narrow information '
        'panel, including its final detail.';
    for (final (width, scale) in [(310.0, 1.0), (210.0, 1.5)]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: const SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppInfoField(label: 'Format', value: 'PNG'),
                        AppInfoField(label: 'Lens', value: longValue),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final short = tester.getRect(find.text('PNG'));
      final long = tester.getRect(find.text(longValue));
      final label = tester.getRect(find.text('Lens'));
      expect(long.left, short.left);
      expect(long.right, lessThanOrEqualTo(width));
      final field = tester.getRect(find.byType(AppInfoField).last);
      expect(long.bottom, lessThanOrEqualTo(field.bottom));
      expect(
        tester
            .widget<SelectableText>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is SelectableText && widget.data == longValue,
              ),
            )
            .maxLines,
        isNull,
      );
      if (scale == 1) {
        expect(long.top, label.top);
        expect(long.left - label.right, greaterThanOrEqualTo(12));
      } else {
        expect(long.top, greaterThanOrEqualTo(label.bottom + 4));
      }
      expect(tester.takeException(), isNull);
    }
  });
}
