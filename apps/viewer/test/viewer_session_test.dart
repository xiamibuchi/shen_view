import 'package:flutter_test/flutter_test.dart';

import 'package:shen_view/src/application/viewer_session.dart';
import 'package:shen_view/src/domain/view_scale_mode.dart';
import 'package:shen_view/src/domain/viewer_mode.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';

void main() {
  test('sizing is remembered per mode and independent of zoom preferences', () {
    final session = ViewerSession();
    addTearDown(session.dispose);
    session.setScaleMode(ViewScaleMode.fitHeight);
    session.setMode(ViewerMode.longImage);
    expect(session.scaleMode, ViewScaleMode.fitWidth);
    session.setScaleMode(ViewScaleMode.autoFit);
    session.applySettings(
      session.settings.copyWith(
        interaction: const ViewerInteractionSettings(
          keepZoom: true,
          keepZoomPosition: true,
          zoomCenter: ZoomCenter.viewport,
        ),
      ),
    );
    expect(session.scaleMode, ViewScaleMode.autoFit);
    session.setMode(ViewerMode.single);
    expect(session.scaleMode, ViewScaleMode.fitHeight);
    session.setScaleMode(ViewScaleMode.originalSize);
    expect(session.settings.interaction.keepZoom, isTrue);
    expect(session.settings.interaction.zoomCenter, ZoomCenter.viewport);
    session.setMode(ViewerMode.longImage);
    expect(session.scaleMode, ViewScaleMode.autoFit);
  });

  test('unchanged requests do not notify or reset reading state', () {
    final session = ViewerSession();
    addTearDown(session.dispose);
    var changes = 0;
    session.addListener(() => changes++);
    session.applySettings(const ViewerSettings());
    session.setMode(ViewerMode.single);
    session.setScaleMode(ViewScaleMode.autoFit);
    session.resetForEntry();
    expect(changes, 0);

    session.setMode(ViewerMode.comic);
    session.setZoomed(true);
    final token = session.comicJumpToken;
    changes = 0;
    session.setMode(ViewerMode.comic);
    session.applySettings(session.settings.copyWith());
    expect(changes, 0);
    expect(session.isZoomed, isTrue);
    expect(session.comicJumpToken, token);

    session.resetForEntry();
    expect(changes, 1);
    expect(session.isZoomed, isFalse);
  });

  test('keeps viewing state transitions in one session boundary', () {
    final session = ViewerSession();
    addTearDown(session.dispose);

    expect(session.mode, ViewerMode.single);
    expect(session.scaleMode, ViewScaleMode.autoFit);
    expect(session.fitMode, isTrue);
    expect(session.playing, isTrue);

    session.setMode(ViewerMode.comic);
    session.setScaleMode(ViewScaleMode.originalSize);
    session.rotateDisplay();
    session.toggleHorizontalFlip();
    session.togglePlaying();

    expect(session.mode, ViewerMode.comic);
    expect(session.scaleMode, ViewScaleMode.originalSize);
    expect(session.fitMode, isFalse);
    expect(session.rotationQuarterTurns, 1);
    expect(session.flipHorizontal, isTrue);
    expect(session.playing, isFalse);
    expect(session.comicJumpToken, 1);
    expect(session.reloadToken, 0);
  });

  test('settings only reset the scale mode when image fit changes', () {
    final session = ViewerSession();
    addTearDown(session.dispose);

    session.setScaleMode(ViewScaleMode.fitHeight);
    session.applySettings(
      const ViewerSettings(toolbarMode: ToolbarMode.normal),
    );
    expect(session.scaleMode, ViewScaleMode.fitHeight);

    session.applySettings(
      const ViewerSettings(
        defaultScaleModes: {ViewerMode.single: ViewScaleMode.originalSize},
      ),
    );
    expect(session.scaleMode, ViewScaleMode.originalSize);
  });

  test(
    'entry reset clears transient transforms and reload increments token',
    () {
      final session = ViewerSession();
      addTearDown(session.dispose);

      session.rotateDisplay();
      session.toggleHorizontalFlip();
      session.setZoomed(true);
      session.resetForEntry();
      expect(session.rotationQuarterTurns, 0);
      expect(session.flipHorizontal, isFalse);
      expect(session.isZoomed, isFalse);

      session.markReloaded();
      expect(session.reloadToken, 1);
    },
  );
}
