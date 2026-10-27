import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shen_view/main.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/locale_controller.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/animation_playback_bar.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const supplied = String.fromEnvironment('PHOTO_MEDIA_FIXTURES');
  final fixtures = Directory(
    supplied.isEmpty ? 'testdata/photo_media' : supplied,
  ).absolute.path;
  const audio = MethodChannel('shenview/media_audio');
  setUpAll(() async {
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1264, 800));
    await windowManager.show();
  });

  testWidgets(
    'photo videos share controls, audio output and cleanup in a real app',
    (tester) async {
      for (final name in [
        'motion-h264.jpg',
        'motion-hevc.jpg',
        'motion-av1.jpg',
        'motion-multiple-audio.jpg',
        'motion-offset.jpg',
        'sequence.heic',
        'sequence-alpha-depth.heic',
        'motion-heic.heic',
        'motion-hevc-main10-pq-aac.jpg',
        'motion-hevc-main10-hlg-aac.jpg',
      ]) {
        await _open(tester, '$fixtures/$name');
        await _until(
          tester,
          () => find.byType(AnimationPlaybackBar).evaluate().isNotEmpty,
        );
        final c = tester
            .widget<AnimationPlaybackBar>(find.byType(AnimationPlaybackBar))
            .controller;
        await _until(tester, () => c.ready || c.error != null);
        expect(c.error, isNull, reason: name);
        expect(c.frame, 0);
        await tester.tap(find.byKey(const ValueKey('animation.step.1')));
        await _until(tester, () => c.frame == 1);
        c.seekFrame(c.frameCount - 1);
        await _until(tester, () => c.frame == c.frameCount - 1);
        c.seekFrame(0);
        await _until(tester, () => c.frame == 0);
        if (c.audioTrackCount > 0) {
          if (c.audioTrackCount > 1) c.setAudioTrack(1);
          await tester.tap(find.byKey(const ValueKey('animation.audio')));
          expect(c.muted, isFalse);
        }
        c.setPlaying(true);
        await _until(tester, () => c.frame > 2);
        if (c.audioTrackCount > 0) {
          Map<String, Object?>? position;
          final deadline = DateTime.now().add(const Duration(seconds: 2));
          do {
            position = await audio.invokeMapMethod<String, Object?>('position');
            if ((position!['samples']! as num) > 0 || c.audioError != null) {
              break;
            }
            await tester.pump(const Duration(milliseconds: 20));
          } while (DateTime.now().isBefore(deadline));
          expect(c.audioError, isNull, reason: name);
          expect(position['samples'], greaterThan(0), reason: name);
          expect(position['queuedBytes'], inInclusiveRange(0, 48000));
        }
        c.setSuspended(true);
        final paused = c.positionMs;
        await tester.pump(const Duration(milliseconds: 200));
        expect(c.positionMs, paused);
        final stopped = await audio.invokeMapMethod<String, Object?>(
          'position',
        );
        expect(stopped!['queuedBytes'], 0);
        c.setSpeed(2);
        c.setSuspended(false);
        await _until(tester, () => c.positionMs > paused + 100);
        c.setPlaying(false);
        c.step(-1);
        await tester.pump(const Duration(milliseconds: 100));
        expect(c.error, isNull, reason: name);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 150));
        final closed = await audio.invokeMapMethod<String, Object?>('position');
        expect(closed!['queuedBytes'], 0);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'static JPEG and single-frame HEIF do not show playback controls',
    (tester) async {
      for (final name in ['cover.jpg', 'single.heic']) {
        await _open(tester, '$fixtures/$name');
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(AnimationPlaybackBar), findsNothing, reason: name);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}

Future<void> _open(WidgetTester tester, String path) async {
  final root = await Directory.systemTemp.createTemp('photo-playback-');
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await root.delete(recursive: true);
  });
  await tester.pumpWidget(
    ShenViewApp(
      key: UniqueKey(),
      initialPath: path,
      initialSettings: const ViewerSettings(
        localeCode: 'zh',
        showDirectoryPanel: false,
        watchFolderChanges: false,
        animationAutoPlay: false,
        animationControlsMode: AnimationControlsMode.always,
      ),
      configStore: AppConfigStore(filePath: '${root.path}/config.json'),
      localeController: AppLocaleController()..setPreference('zh'),
    ),
  );
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(condition(), isTrue);
}
