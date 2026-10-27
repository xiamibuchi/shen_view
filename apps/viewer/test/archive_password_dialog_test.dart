import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/presentation/archive_password_dialog.dart';
import 'package:shen_view/src/presentation/components/app_button.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

import 'support/style_review_fonts.dart';

void main() {
  testWidgets('password dialog fits narrow windows and both themes', (
    tester,
  ) async {
    final capture = Platform.environment['SETTINGS_CAPTURE_DIR'];
    if (capture != null) {
      await tester.runAsync(() async {
        final loader = FontLoader('PasswordReview')
          ..addFont(
            File(windowsFontPath('msyh.ttc'))
                .readAsBytes()
                .then(ByteData.sublistView),
          );
        await loader.load();
        final icons =
            FontLoader(
              'packages/fluentui_system_icons/FluentSystemIcons-Regular',
            )..addFont(
              rootBundle.load(
                'packages/fluentui_system_icons/fonts/FluentSystemIcons-Regular.ttf',
              ),
            );
        await icons.load();
      });
    }
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final dark in [true, false]) {
      for (final width in [800.0, 440.0]) {
        tester.view.physicalSize = Size(width, 560);
        final theme = dark ? AppTheme.dark() : AppTheme.light();
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('password-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: capture == null
                  ? theme
                  : theme.copyWith(
                      textTheme: theme.textTheme.apply(
                        fontFamily: 'PasswordReview',
                      ),
                    ),
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(
                body: ArchivePasswordDialog(
                  archiveName: '漫画合集 第 12 章.cbz',
                  error: ArchivePasswordError.wrongPassword,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (capture != null) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('password-capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '$capture/password-${dark ? "dark" : "light"}-${width.toInt()}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
      }
    }
  });

  testWidgets(
    'password is hidden, toggles visibly and returns exact in-memory input',
    (tester) async {
      String? result;
      await tester.pumpWidget(
        _host((context) async {
          result = await showArchivePasswordDialog(
            context,
            archiveName: '漫画.cbz',
          );
        }),
      );
      await tester.tap(find.text('launch'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey('archive.passwordSubmit')),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), ' secret 密码 ');
      await tester.tap(
        find.byKey(const ValueKey('archive.passwordVisibility')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('archive.passwordSubmit')));
      await tester.pumpAndSettle();
      expect(result, ' secret 密码 ');
      expect(find.byType(ArchivePasswordDialog), findsNothing);
    },
  );

  testWidgets(
    'cancel clears dialog without submitting and errors are localized',
    (tester) async {
      String? result = 'not completed';
      await tester.pumpWidget(
        _host((context) async {
          result = await showArchivePasswordDialog(
            context,
            archiveName: '长文件名漫画.cbz',
            error: ArchivePasswordError.cannotVerify,
          );
        }),
      );
      await tester.tap(find.text('launch'));
      await tester.pumpAndSettle();
      expect(find.text('无法验证密码或数据，请检查密码，或重新获取一份压缩包。'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'private');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    },
  );
}

Widget _host(Future<void> Function(BuildContext) onLaunch) => MaterialApp(
  theme: AppTheme.dark(),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => onLaunch(context),
        child: const Text('launch'),
      ),
    ),
  ),
);
