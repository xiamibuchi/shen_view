import 'package:flutter/foundation.dart';

import '../domain/view_scale_mode.dart';
import '../domain/viewer_mode.dart';
import '../domain/viewer_settings.dart';
import '../domain/reading_state.dart';
import '../domain/comic_layout_direction.dart';

class ViewerSession extends ChangeNotifier {
  ViewerSettings _settings = const ViewerSettings();
  ViewerMode _mode = ViewerMode.single;
  ViewScaleMode _scaleMode = ViewScaleMode.autoFit;
  final _modeScales = <ViewerMode, ViewScaleMode>{};
  bool _hasReadingContext = false;
  ReadingDirection? _readingDirection;
  ComicLayoutDirection? _layoutDirection;
  ReadingDirection get readingDirection =>
      _readingDirection ?? _settings.readingDirection;
  ComicLayoutDirection get layoutDirection =>
      _layoutDirection ?? _settings.comicLayoutDirection;
  bool _isZoomed = false;
  bool _playing = true;
  int _rotationQuarterTurns = 0;
  bool _flipHorizontal = false;
  int _reloadToken = 0;
  int _comicJumpToken = 0;

  ViewerSettings get settings => _settings;
  ViewerMode get mode => _mode;
  ViewScaleMode get scaleMode => _scaleMode;
  bool get fitMode => _scaleMode != ViewScaleMode.originalSize;

  ViewScaleMode scaleModeFor(ViewerMode mode) =>
      _modeScales[mode] ?? defaultScaleModeFor(mode);

  ViewScaleMode defaultScaleModeFor(ViewerMode mode) {
    return _settings.defaultScaleModeFor(mode, direction: layoutDirection);
  }

  void restoreReadingState(ReadingState? state) {
    _hasReadingContext = true;
    _mode = state?.mode ?? _settings.defaultViewerMode;
    _modeScales
      ..clear()
      ..addAll(state?.scales ?? {});
    _readingDirection = state?.readingDirection ?? _settings.readingDirection;
    _layoutDirection = state?.layoutDirection ?? _settings.comicLayoutDirection;
    _scaleMode = scaleModeFor(_mode);
    _isZoomed = false;
    _rotationQuarterTurns = 0;
    _flipHorizontal = false;
    _comicJumpToken++;
    notifyListeners();
  }

  ReadingState readingState({
    String? entryPath,
    double? pageFraction,
    double? crossFraction,
  }) => ReadingState(
    mode: _mode,
    scales: {..._modeScales, _mode: _scaleMode},
    readingDirection: readingDirection,
    layoutDirection: layoutDirection,
    entryPath: entryPath,
    pageFraction: pageFraction,
    crossFraction: crossFraction,
  );

  void setReadingDirection(ReadingDirection direction) {
    _readingDirection = direction;
    notifyListeners();
  }

  void setLayoutDirection(ComicLayoutDirection direction) {
    _layoutDirection = direction;
    if (!_modeScales.containsKey(ViewerMode.comic) &&
        _mode == ViewerMode.comic) {
      _scaleMode = defaultScaleModeFor(_mode);
    }
    notifyListeners();
  }

  bool get isZoomed => _isZoomed;
  bool get playing => _playing;
  int get rotationQuarterTurns => _rotationQuarterTurns;
  bool get flipHorizontal => _flipHorizontal;
  int get reloadToken => _reloadToken;
  int get comicJumpToken => _comicJumpToken;

  void applySettings(ViewerSettings settings) {
    if (_settings == settings) return;
    final fitChanged = !mapEquals(
      _settings.defaultScaleModes,
      settings.defaultScaleModes,
    );
    _settings = settings;
    if (fitChanged && !_hasReadingContext) {
      _modeScales.clear();
      _scaleMode = defaultScaleModeFor(_mode);
      _isZoomed = false;
    }
    notifyListeners();
  }

  void setMode(ViewerMode mode) {
    if (_mode == mode) return;
    _modeScales[_mode] = _scaleMode;
    _mode = mode;
    _scaleMode = scaleModeFor(mode);
    _isZoomed = false;
    if (mode == ViewerMode.comic) _comicJumpToken++;
    notifyListeners();
  }

  void setScaleMode(ViewScaleMode mode) {
    if (_scaleMode == mode && !_isZoomed) return;
    _scaleMode = mode;
    _modeScales[_mode] = mode;
    _isZoomed = false;
    notifyListeners();
  }

  void rotateDisplay() {
    _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4;
    notifyListeners();
  }

  void toggleHorizontalFlip() {
    _flipHorizontal = !_flipHorizontal;
    notifyListeners();
  }

  void togglePlaying() {
    _playing = !_playing;
    notifyListeners();
  }

  void setZoomed(bool value) {
    if (_isZoomed == value) return;
    _isZoomed = value;
    notifyListeners();
  }

  void resetForEntry() {
    if (!_isZoomed && _rotationQuarterTurns == 0 && !_flipHorizontal) return;
    _isZoomed = false;
    _rotationQuarterTurns = 0;
    _flipHorizontal = false;
    notifyListeners();
  }

  void markReloaded() {
    _reloadToken++;
    notifyListeners();
  }

  void moveComicSelection() {
    _comicJumpToken++;
    notifyListeners();
  }
}
