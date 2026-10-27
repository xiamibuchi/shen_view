import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/auto_play_controller.dart';
import 'package:shen_view/src/domain/auto_play_settings.dart';
import 'package:shen_view/src/domain/viewer_mode.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';

void main() {
  late AutoPlayController c;
  setUp(() => c = AutoPlayController());
  tearDown(() => c.dispose());

  test('loading and suspension do not consume visible time; pause resumes remaining time', () {
    c.start();
    expect(c.tick(const Duration(seconds: 20), ready: false), isFalse);
    expect(c.remainingSeconds, 5);
    c.tick(const Duration(seconds: 2), ready: true);
    c.pause();
    c.tick(const Duration(seconds: 10), ready: true);
    expect(c.remainingSeconds, 3);
    c.start();
    c.tick(const Duration(seconds: 20), ready: true, suspended: true);
    expect(c.remainingSeconds, 3);
    expect(c.tick(const Duration(seconds: 3), ready: true), isTrue);
    c.resetInterval();
    expect(c.remainingSeconds, 5);
    c.stop();
    expect(c.active, isFalse);
  });

  test('short animations do not wait for another loop; long and double animations wait for every page', () {
    c.start();
    const short = (ready: true, playedOnce: true, paused: false);
    const long = (ready: true, playedOnce: false, paused: false);
    expect(
      c.tick(
        const Duration(seconds: 5),
        ready: true,
        animations: [short, long],
      ),
      isFalse,
    );
    expect(c.waitingForAnimation, isTrue);
    expect(
      c.tick(
        const Duration(seconds: 7),
        ready: true,
        animations: [short, short],
      ),
      isTrue,
    );
    c.resetInterval();
    expect(
      c.tick(const Duration(seconds: 4), ready: true, animations: [short]),
      isFalse,
    );
    expect(
      c.tick(const Duration(seconds: 1), ready: true, animations: [short]),
      isTrue,
    );
  });

  test('fixed interval ignores incomplete loops, stay policy pauses, manual animation pause pauses navigation', () {
    const unfinished = (ready: true, playedOnce: false, paused: false);
    c.configure(
      const AutoPlaySettings(
        animationPolicy: AutoPlayAnimationPolicy.fixedInterval,
      ),
      ViewerMode.single,
    );
    c.start();
    expect(
      c.tick(const Duration(seconds: 5), ready: true, animations: [unfinished]),
      isTrue,
    );
    c.configure(
      const AutoPlaySettings(animationPolicy: AutoPlayAnimationPolicy.stop),
      ViewerMode.single,
    );
    expect(
      c.tick(const Duration(seconds: 1), ready: true, animations: [unfinished]),
      isFalse,
    );
    expect(c.status, AutoPlayStatus.paused);
    c.configure(const AutoPlaySettings(), ViewerMode.single);
    c.start();
    c.tick(
      const Duration(seconds: 1),
      ready: true,
      animations: [(ready: true, playedOnce: false, paused: true)],
    );
    expect(c.status, AutoPlayStatus.paused);
  });

  test('modes have separate intervals and scroll speeds; changing interval resets countdown', () {
    const settings = AutoPlaySettings(
      intervals: {ViewerMode.single: 3, ViewerMode.doublePage: 8},
      scrollSpeeds: {ViewerMode.longImage: 40, ViewerMode.comic: 120},
    );
    c.configure(settings, ViewerMode.single);
    c.start();
    c.tick(const Duration(seconds: 1), ready: true);
    expect(c.remainingSeconds, 2);
    c.configure(settings.copyWith(loop: true), ViewerMode.single);
    expect(c.remainingSeconds, 2);
    c.configure(
      settings.copyWith(statusDisplay: AutoPlayStatusDisplay.always),
      ViewerMode.single,
    );
    expect(c.remainingSeconds, 2);
    c.configure(settings, ViewerMode.doublePage);
    expect(c.remainingSeconds, 8);
    c.configure(settings, ViewerMode.comic);
    expect(c.scrolling, isTrue);
    expect(c.settings.speedFor(c.mode), 120);
    expect(c.tick(const Duration(seconds: 99), ready: true), isFalse);
  });

  test('settings sanitize corrupt values and round trip without persisting playback state', () async {
    final malformed = AutoPlaySettings.fromJson({
      'intervals': {'single': double.nan, 'doublePage': -9},
      'scrollSpeeds': {'comic': double.infinity, 'longImage': 99999},
      'animationPolicy': 'unknown',
      'statusDisplay': 'unknown',
    });
    expect(malformed.intervalFor(ViewerMode.single), 5);
    expect(malformed.intervalFor(ViewerMode.doublePage), 0.5);
    expect(malformed.speedFor(ViewerMode.comic), 60);
    expect(malformed.speedFor(ViewerMode.longImage), 1000);
    expect(malformed.statusDisplay, AutoPlayStatusDisplay.autoHide);
    expect(
      AutoPlaySettings.fromJson({}).statusDisplay,
      AutoPlayStatusDisplay.autoHide,
    );
    final dir = await Directory.systemTemp.createTemp('auto-play-config-');
    addTearDown(() => dir.delete(recursive: true));
    final store = AppConfigStore(filePath: '${dir.path}/settings.json');
    final prefs = const AutoPlaySettings().copyWith(
      intervals: {ViewerMode.doublePage: 7.5},
      scrollSpeeds: {ViewerMode.comic: 90},
      animationPolicy: AutoPlayAnimationPolicy.fixedInterval,
      statusDisplay: AutoPlayStatusDisplay.always,
      loop: true,
    );
    final original = const ViewerSettings().copyWith(autoPlay: prefs);
    await original.save(store: store);
    final loaded = await ViewerSettings.load(store: store);
    expect(loaded, original);
    expect(loaded.hashCode, original.hashCode);
    expect(AutoPlayController().status, AutoPlayStatus.stopped);
  });

  test(
    'intervals use tenths when loading, timing and saving old preferences',
    () {
      const raw = AutoPlaySettings(
        intervals: {
          ViewerMode.single: 5.0123123123,
          ViewerMode.doublePage: 7.56,
        },
      );
      expect(raw.intervalFor(ViewerMode.single), 5);
      expect(raw.intervalFor(ViewerMode.doublePage), 7.6);
      final loaded = AutoPlaySettings.fromJson(raw.toJson());
      expect(loaded.intervals[ViewerMode.single], 5);
      expect(loaded.intervals[ViewerMode.doublePage], 7.6);
      final legacy = AutoPlaySettings.fromJson({
        'intervals': {'single': 5.0123123123, 'doublePage': 7.56},
      });
      expect(legacy, loaded);
      c.configure(legacy, ViewerMode.doublePage);
      c.start();
      expect(c.remainingSeconds, 7.6);
      expect(c.tick(const Duration(milliseconds: 7599), ready: true), isFalse);
      expect(c.tick(const Duration(milliseconds: 1), ready: true), isTrue);
    },
  );
}
