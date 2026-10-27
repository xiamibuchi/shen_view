import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/presentation/licenses_page.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

void main() {
  testWidgets(
    'groups repeated packages and safely renders centered paragraphs',
    (tester) async {
      await tester.pumpWidget(
        _host(
          LicensesPage(
            source: Stream.fromIterable([
              const _CenteredLicense(),
              const LicenseEntryWithLineBreaks([
                'abseil-cpp',
              ], 'Additional license'),
              const _CenteredLicense(),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('abseil-cpp'), findsOneWidget);
      expect(find.text('2 份许可文本'), findsOneWidget);
      await tester.tap(find.text('abseil-cpp'));
      await tester.pumpAndSettle();
      final centered = tester.widget<SelectableText>(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText && widget.data == 'Centered heading',
        ),
      );
      expect(centered.textAlign, TextAlign.center);
      expect(find.text('Body terms'), findsOneWidget);
      expect(find.text('Additional license'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('lists licenses, opens the text and closes the dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        LicensesPage(
          source: Stream.fromIterable([
            const LicenseEntryWithLineBreaks([
              'alpha',
            ], 'Alpha License\n\nPermission is granted to use alpha.'),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('1 份许可文本'), findsOneWidget);
    await tester.tap(find.text('alpha'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Permission is granted'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Permission is granted'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search filters package names', (tester) async {
    await tester.pumpWidget(
      _host(
        LicensesPage(
          source: Stream.fromIterable([
            const LicenseEntryWithLineBreaks(['alpha'], 'Alpha License'),
            const LicenseEntryWithLineBreaks(['gamma'], 'Gamma License'),
            const LicenseEntryWithLineBreaks([
              'archive',
              'printing',
            ], 'Multi License'),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('gamma'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'gam');
    await tester.pumpAndSettle();
    expect(find.text('gamma'), findsOneWidget);
    expect(find.text('alpha'), findsNothing);
    expect(find.text('匹配 1 条'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('appInput.clearButton')));
    await tester.pumpAndSettle();
    expect(find.text('alpha'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'printing');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text('printing'),
      ),
      findsOneWidget,
    );
    expect(find.text('archive'), findsNothing);
    expect(find.text('1 份许可文本'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows empty and error states', (tester) async {
    await tester.pumpWidget(
      _host(const LicensesPage(source: Stream<LicenseEntry>.empty())),
    );
    await tester.pumpAndSettle();
    expect(find.text('没有可显示的许可证'), findsOneWidget);

    await tester.pumpWidget(
      _host(
        LicensesPage(
          source: Stream<LicenseEntry>.error(StateError('notices missing')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('无法读取许可证信息'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _host(Widget home) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.dark(),
  locale: const Locale('zh'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: home,
);

class _CenteredLicense extends LicenseEntry {
  const _CenteredLicense();

  @override
  Iterable<String> get packages => ['abseil-cpp'];

  @override
  Iterable<LicenseParagraph> get paragraphs => const [
    LicenseParagraph('Centered heading', LicenseParagraph.centeredIndent),
    LicenseParagraph('Body terms', 1),
  ];
}
