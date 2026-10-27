import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/domain/auto_play_settings.dart';
import 'package:shen_view/src/domain/viewer_mode.dart';
import 'package:shen_view/src/presentation/auto_play_status.dart';
import 'package:shen_view/src/presentation/components/app_button.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

void main() {
  for (final scrolling in [false, true]) {
    testWidgets(
      'numeric playback input rejects malformed edits, scrolling=$scrolling',
      (tester) async {
        final mode = scrolling ? ViewerMode.comic : ViewerMode.single;
        AutoPlaySettings? result;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            theme: AppTheme.dark(),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Builder(
              builder: (context) => Center(
                child: AppButton(
                  label: 'open',
                  onPressed: () async {
                    result = await showAutoPlayOptions(
                      context,
                      settings: const AutoPlaySettings(
                        intervals: {ViewerMode.single: 5.0123123123},
                      ),
                      mode: mode,
                      onStop: () {},
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final input = find.byKey(const ValueKey('autoPlay.parameter'));
        final editor = find.descendant(
          of: input,
          matching: find.byType(EditableText),
        );
        final original = tester.widget<EditableText>(editor).controller.text;
        if (!scrolling) expect(original, '5.0');
        for (final invalid in [
          '${original}aasdfsadf',
          '1e3',
          '-1',
          '3.4.5',
          '中文',
          'Infinity',
          ' 7 ',
          if (!scrolling) ...['5.0123123123', '7.55', '.55'],
        ]) {
          await tester.enterText(input, invalid);
          await tester.pump();
          expect(
            tester.widget<EditableText>(editor).controller.text,
            original,
            reason: invalid,
          );
        }
        if (!scrolling) {
          for (final text in ['5', '5.', '5.0']) {
            await tester.enterText(input, text);
            await tester.pump();
            expect(tester.widget<EditableText>(editor).controller.text, text);
          }
          await tester.enterText(input, '5.01');
          await tester.pump();
          expect(tester.widget<EditableText>(editor).controller.text, '5.0');
        }
        for (final invalidRange in [
          '',
          '.',
          '0',
          scrolling ? '1001' : '3601',
        ]) {
          await tester.enterText(input, invalidRange);
          await tester.pump();
          expect(
            tester
                .widget<AppButton>(find.byKey(const ValueKey('autoPlay.save')))
                .onPressed,
            isNull,
          );
          expect(
            find.text(
              scrolling ? '请输入 5 到 1000 之间的数字' : '请输入 0.5 到 3600 之间的数字',
            ),
            findsOneWidget,
          );
        }
        final accepted = scrolling ? '7.5' : '.5';
        await tester.enterText(input, accepted);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('autoPlay.statusDisplay')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('始终显示'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('autoPlay.save')));
        await tester.pumpAndSettle();
        expect(result, isNotNull);
        expect(result!.statusDisplay, AutoPlayStatusDisplay.always);
        expect(
          scrolling ? result!.speedFor(mode) : result!.intervalFor(mode),
          double.parse(accepted),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
