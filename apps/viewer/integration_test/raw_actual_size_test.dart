import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shen_view/main.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/raw_developer.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/raw_resource_image.dart';
import 'package:shen_view/src/presentation/resource_image.dart';
import 'package:shen_view/src/presentation/zoomable_viewport.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final tracePath = Platform.environment['RAW_TRACE_LOG'];
  testWidgets(
    'actual-size UI validates physical demand and real sensor invocations across DPI',
    (tester) async {
      final trace = File(tracePath!);
      await trace.writeAsString('');
      final output = Directory('../../artifacts/raw-actual-size')
        ..createSync(recursive: true);
      final configRoot = await Directory.systemTemp.createTemp(
        'raw-actual-size-',
      );
      addTearDown(() async {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        await configRoot.delete(recursive: true);
      });
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1264, 800));
      await windowManager.show();
      final rows = <Map<String, Object?>>[];
      final files = [
        'raw_canon_white_paper.cr2',
        'raw_sony_a7s.arw',
        'raw_nikon_d2h.nef',
      ];
      int developments(String name) => trace
          .readAsLinesSync()
          .where((line) => line.startsWith('decode\t$name\t'))
          .length;
      for (final dpi in [1.0, 1.25, 1.5, 2.0]) {
        tester.view.devicePixelRatio = dpi;
        tester.view.physicalSize = Size(1264 * dpi, 800 * dpi);
        for (final name in files) {
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
          final sourceFile = File('testdata/formats/$name').absolute;
          final preview = await RawDeveloper().preview(sourceFile.path);
          final root = GlobalKey();
          final countBefore = developments(name);
          await tester.pumpWidget(
            RepaintBoundary(
              key: root,
              child: ShenViewApp(
                initialPath: sourceFile.path,
                initialSettings: const ViewerSettings(
                  localeCode: 'zh',
                  autoHdr: false,
                  showDirectoryPanel: false,
                  watchFolderChanges: false,
                  recentOpenEnabled: false,
                  archivePrefetchMode: ArchivePrefetchMode.off,
                  thumbnailPrefetchMode: ThumbnailPrefetchMode.off,
                ),
                configStore: AppConfigStore(
                  filePath: '${configRoot.path}/$name-$dpi.json',
                ),
              ),
            ),
          );
          final mainImages = find.descendant(
            of: find.byKey(const ValueKey('single-viewport')),
            matching: find.byType(RawImage),
          );
          Future<void> waitUntil(bool Function() ready) async {
            final deadline = DateTime.now().add(const Duration(seconds: 40));
            while (DateTime.now().isBefore(deadline)) {
              await tester.pump(const Duration(milliseconds: 100));
              if (ready()) return;
            }
            fail('等待 100% RAW 显示检查超时：$name，DPI=$dpi');
          }

          await waitUntil(
            () =>
                mainImages.evaluate().isNotEmpty &&
                tester.widget<RawImage>(mainImages.first).image != null,
          );
          await tester.pumpAndSettle(const Duration(milliseconds: 100));
          Map<String, Object?> measure(String phase) {
            final raw = tester.widget<RawResourceImage>(
              find.byType(RawResourceImage),
            );
            final resource = tester.widget<ResourceImage>(
              find.descendant(
                of: find.byType(RawResourceImage),
                matching: find.byType(ResourceImage),
              ),
            );
            final render = tester.renderObject<RenderImage>(mainImages.first);
            final viewport = tester.renderObject<RenderBox>(
              find.byKey(const ValueKey('single-viewport')),
            );
            final draw = applyBoxFit(
              BoxFit.contain,
              raw.sourceSize!,
              render.size,
            ).destination;
            final matrixScale = render
                .getTransformTo(viewport)
                .getMaxScaleOnAxis();
            final expectedWidth = math
                .min(raw.sourceSize!.width, draw.width * matrixScale * dpi)
                .ceil();
            final expectedHeight = math
                .min(raw.sourceSize!.height, draw.height * matrixScale * dpi)
                .ceil();
            expect(
              resource.targetWidth,
              closeTo(expectedWidth, 1),
              reason: '$name $phase DPI=$dpi：请求必须与实际绘制区域匹配',
            );
            expect(resource.targetHeight, closeTo(expectedHeight, 1));
            return {
              'file': name,
              'dpi': dpi,
              'phase': phase,
              'preview': [preview!.width, preview.height],
              'source': [raw.sourceSize!.width, raw.sourceSize!.height],
              'logicalDraw': [draw.width, draw.height],
              'matrixScale': matrixScale,
              'physicalNeedBeforeSourceCap': [
                draw.width * matrixScale * dpi,
                draw.height * matrixScale * dpi,
              ],
              'requested': [resource.targetWidth, resource.targetHeight],
              'decoded': [render.image!.width, render.image!.height],
              'sensorInvocations': developments(name) - countBefore,
              'memoryBudgetBytes': raw.resources.memoryBudgetBytes,
            };
          }

          final fit = measure('fit');
          rows.add(fit);
          final fitImage = tester.widget<RawImage>(mainImages.first).image!;
          final fitSize = (fitImage.width, fitImage.height);
          final fitRaw = tester.widget<RawResourceImage>(
            find.byType(RawResourceImage),
          );
          final viewport = tester.widget<ZoomableViewport>(
            find.byKey(const ValueKey('single-viewport')),
          );
          // Follow the same reference-scale conversion as the zoom control,
          // independently of the original-size layout/shortcut below.
          viewport.commands!.setScale(
            fitRaw.sourceSize!.width / viewport.contentSize.width,
          );
          await waitUntil(() => find.text('100%').evaluate().isNotEmpty);
          await tester.pump(const Duration(milliseconds: 250));
          await waitUntil(() {
            final resource = tester.widget<ResourceImage>(
              find.descendant(
                of: find.byType(RawResourceImage),
                matching: find.byType(ResourceImage),
              ),
            );
            final raw = tester.widget<RawResourceImage>(
              find.byType(RawResourceImage),
            );
            final image = tester.widget<RawImage>(mainImages.first).image!;
            return resource.targetWidth == raw.sourceSize!.width &&
                resource.targetHeight == raw.sourceSize!.height &&
                (image.width, image.height) != fitSize;
          });
          await tester.pumpAndSettle(const Duration(milliseconds: 100));
          rows.add(measure('zoom100%'));
          final countAfterZoom = developments(name);
          await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
          await tester.pumpAndSettle(const Duration(milliseconds: 100));
          expect(find.text('100%'), findsWidgets);
          expect(
            developments(name),
            countAfterZoom,
            reason: '100% 缩放切换到原始尺寸复用同精度缓存',
          );
          final actual = measure('100%');
          rows.add(actual);
          final raw = tester.widget<RawResourceImage>(
            find.byType(RawResourceImage),
          );
          final actualImage = tester.widget<RawImage>(mainImages.first).image!;
          expect(
            developments(name) - countBefore,
            greaterThan((fit['sensorInvocations']! as int)),
          );
          if (name.endsWith('.cr2')) {
            expect(
              actualImage.width,
              inInclusiveRange(2049, raw.sourceSize!.width.toInt()),
              reason: '100% 主图保留预算内的传感器细节和显影曝光',
            );
            final pixels = (await actualImage.toByteData())!;
            final paper =
                (actualImage.height ~/ 2 * actualImage.width +
                    actualImage.width ~/ 8) *
                4;
            for (var c = 0; c < 3; c++) {
              expect(pixels.getUint8(paper + c), inInclusiveRange(166, 252));
            }
          } else {
            expect(actualImage.width, raw.sourceSize!.width);
            expect(actualImage.height, raw.sourceSize!.height);
          }
          final countAtActual = developments(name);
          await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
          await tester.pumpAndSettle(const Duration(milliseconds: 100));
          expect(developments(name), countAtActual, reason: '重复选择 100% 不得重复显影');
          final render =
              root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final screenshot = await render.toImage();
          final bytes = await screenshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File('${output.path}/$name-dpi$dpi-100.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          screenshot.dispose();
          await File('${output.path}/results.json')
              .writeAsString(const JsonEncoder.withIndent('  ').convert(rows));
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
      }
    },
    skip:
        !Platform.isWindows ||
        tracePath == null ||
        Platform.environment['RAW_TRACE_HELPER'] == null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
