import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/presentation/components/app_input.dart';
import 'package:shen_view/src/presentation/components/field_frame.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

import 'support/style_review_fonts.dart';

void main() {
  testWidgets(
    'search hint and typed text stay centered with desktop density and font fallback',
    (tester) async {
      final captureDir = Platform.environment['INPUT_CAPTURE_DIR'];
      if (captureDir != null) {
        await tester.runAsync(() async {
          for (final font in [
            ('Segoe UI', windowsFontPath('segoeui.ttf')),
            ('Microsoft YaHei UI', windowsFontPath('msyh.ttc')),
            (
              'packages/fluentui_system_icons/FluentSystemIcons-Regular',
              'packages/fluentui_system_icons/fonts/FluentSystemIcons-Regular.ttf',
            ),
          ]) {
            final loader = FontLoader(font.$1)
              ..addFont(loadReviewFontData(font.$2));
            await loader.load();
          }
        });
      }
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 240);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      const captureKey = ValueKey('input-alignment-capture');
      for (final dark in [true, false]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          var theme = dark ? AppTheme.dark() : AppTheme.light();
          theme = theme.copyWith(
            platform: TargetPlatform.windows,
            visualDensity: VisualDensity.compact,
          );
          if (captureDir != null) {
            theme = theme.copyWith(
              textTheme: theme.textTheme.apply(
                fontFamily: 'Microsoft YaHei UI',
                fontFamilyFallback: ['Segoe UI'],
              ),
            );
          }
          controller.clear();
          await tester.pumpWidget(
            RepaintBoundary(
              key: captureKey,
              child: MaterialApp(
                theme: theme,
                debugShowCheckedModeBanner: false,
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          AppInput(
                            controller: controller,
                            hint: '搜索目录与章节',
                            leadingIcon: FluentIcons.search_20_regular,
                            onClear: () {},
                          ),
                          const SizedBox(height: 16),
                          const AppInput(
                            hint: '搜索设置',
                            leadingIcon: FluentIcons.search_20_regular,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final input = find.byType(AppInput).first;
          final icon = find
              .descendant(of: input, matching: find.byType(Icon))
              .first;
          final center = tester.getCenter(icon).dy;
          final hintRect = tester.getRect(find.text('搜索目录与章节'));
          final hint = tester.renderObject<RenderParagraph>(
            find.text('搜索目录与章节'),
          );
          final hintBox = hint
              .getBoxesForSelection(
                const TextSelection(baseOffset: 0, extentOffset: 7),
                boxHeightStyle: EditableText.defaultSelectionHeightStyle,
              )
              .first
              .toRect();
          final hintGlyphCenter = hint.localToGlobal(hintBox.center);
          expect(hintRect.center.dy, closeTo(center, 0.5));
          for (final text in ['搜索目录与章节', 'Search settings']) {
            await tester.enterText(
              find.descendant(of: input, matching: find.byType(TextField)),
              text,
            );
            await tester.pumpAndSettle();
            final editable = tester
                .state<EditableTextState>(
                  find.descendant(
                    of: input,
                    matching: find.byType(EditableText),
                  ),
                )
                .renderEditable;
            final boxes = editable.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: text.length),
            );
            final textCenter = editable.localToGlobal(
              boxes.first.toRect().center,
            );
            final lineCenter = editable.localToGlobal(
              Offset(0, editable.size.height / 2),
            );
            expect(lineCenter.dy, closeTo(center, 0.5));
            if (text == '搜索目录与章节') {
              expect(textCenter.dy, closeTo(hintGlyphCenter.dy, 0.5));
            }
            final surfaceHeight = tester
                .getSize(find.byType(FieldSurface).first)
                .height;
            expect(surfaceHeight, scale == 1 ? 36 : greaterThan(36));
            expect(
              surfaceHeight - editable.size.height,
              greaterThanOrEqualTo(12),
              reason: 'Enlarged text retains vertical breathing room',
            );
          }
          await tester.tap(find.byKey(const ValueKey('appInput.clearButton')));
          await tester.pumpAndSettle();
          expect(tester.getRect(find.text('搜索目录与章节')), hintRect);
          if (captureDir != null) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(captureKey),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '$captureDir/${dark ? 'dark' : 'light'}-$scale.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}
