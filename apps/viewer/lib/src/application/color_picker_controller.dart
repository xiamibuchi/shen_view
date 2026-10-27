import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'color_picker_service.dart';
import 'recent_color_store.dart';

enum ColorSampleKind { srgb, sdrMapped, sdrBase, svg }

typedef ColorPixelNudge = void Function(int dx, int dy);

class ColorPick {
  const ColorPick({
    required this.patch,
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.kind,
    required this.previewOnly,
  });
  final ColorSamplePatch patch;
  final String id, name;
  final int x, y;
  final ColorSampleKind kind;
  final bool previewOnly;
  PickedColor get color => patch.color;
}

class ColorPickerRequest {
  const ColorPickerRequest({
    required this.image,
    required this.pixel,
    required this.sourcePixel,
    required this.id,
    required this.name,
    required this.kind,
    required this.previewOnly,
    required this.nudge,
    this.refresh,
  });
  final ui.Image image;
  final ui.Offset pixel, sourcePixel;
  final String id, name;
  final ColorSampleKind kind;
  final bool previewOnly;
  final ColorPixelNudge nudge;
  final VoidCallback? refresh;
}

class _Capture {
  _Capture(this.request, this.epoch, this.serial)
    : image = request.image.clone();
  final ColorPickerRequest request;
  final ui.Image image;
  final int epoch, serial;
  void dispose() => image.dispose();
}

class ColorPickerController extends ChangeNotifier {
  ColorPickerController({ColorPickerService? service, this.history})
    : _service = service ?? ColorPickerService();
  final ColorPickerService _service;
  final RecentColorStore? history;
  bool active = false;
  ColorPick? hover, selected;
  final List<PickedColor> recent = [];
  PickedColor? _retainedColor;
  PickedColor? get color => selected?.color ?? _retainedColor;
  final List<PickedColor> _unsavedColors = [];
  Future<void> _historyTail = Future<void>.value();
  bool historyFailed = false;
  ui.Offset? pointer;
  ColorCopyFormat format = ColorCopyFormat.hex;
  String? copiedValue;
  bool copyFailed = false, sampleFailed = false;
  bool _disposed = false, _reading = false;
  int _epoch = 0, _serial = 0, _lockSerial = 0;
  _Capture? _pending;
  ColorPixelNudge? _hoverNudge, _selectedNudge;
  Object? _lastPixel;
  Timer? _copyTimer;
  String? _targetId;
  VoidCallback? _refresh;

  void setActive(bool value) {
    if (active == value) return;
    active = value;
    resetImage();
    if (value) unawaited(refreshHistory());
  }

  void resetImage() {
    _epoch++;
    _pending?.dispose();
    _pending = null;
    _retainedColor = color;
    hover = selected = null;
    pointer = null;
    _hoverNudge = _selectedNudge = null;
    _lastPixel = null;
    _targetId = null;
    _refresh = null;
    copiedValue = null;
    copyFailed = sampleFailed = false;
    if (!_disposed) notifyListeners();
  }

  void clearHover() {
    _serial++;
    _pending?.dispose();
    _pending = null;
    hover = null;
    _hoverNudge = null;
    pointer = null;
    _lastPixel = null;
    _refresh = null;
    if (!_disposed) notifyListeners();
  }

  void preview(ColorPickerRequest request, ui.Offset position) {
    if (!active || _disposed) return;
    _targetId = request.id;
    _refresh = request.refresh;
    pointer = position;
    final pixel = (
      request.image,
      request.pixel,
      request.id,
      request.kind,
      request.previewOnly,
    );
    if (_lastPixel != pixel) {
      _lastPixel = pixel;
      _pending?.dispose();
      _pending = _Capture(request, _epoch, ++_serial);
      unawaited(_drain());
    }
    notifyListeners();
  }

  /// A manually selected animation frame invalidates coordinates on the old
  /// frame. Keep history, then refresh the candidate after the new frame paints.
  void refreshFrame(String id) {
    if (!active || _disposed || _targetId != id) return;
    final refresh = _refresh;
    resetImage();
    refresh?.call();
  }

  Future<ColorPick?> _read(_Capture capture) async {
    try {
      final r = capture.request;
      final patch = await _service.capture(
        capture.image,
        r.pixel.dx.toInt(),
        r.pixel.dy.toInt(),
      );
      if (patch == null || _disposed || !active || capture.epoch != _epoch) {
        return null;
      }
      return ColorPick(
        patch: patch,
        id: r.id,
        name: r.name,
        x: r.sourcePixel.dx.floor(),
        y: r.sourcePixel.dy.floor(),
        kind: r.kind,
        previewOnly: r.previewOnly,
      );
    } catch (_) {
      if (!_disposed && capture.epoch == _epoch) {
        sampleFailed = true;
        notifyListeners();
      }
      return null;
    } finally {
      capture.dispose();
    }
  }

  Future<void> _drain() async {
    if (_reading) return;
    _reading = true;
    try {
      while (_pending != null) {
        final capture = _pending!;
        _pending = null;
        final pick = await _read(capture);
        if (pick != null && capture.serial == _serial) {
          hover = pick;
          sampleFailed = false;
          _hoverNudge = capture.request.nudge;
          notifyListeners();
        }
      }
    } finally {
      _reading = false;
    }
  }

  Future<void> lock(ColorPickerRequest request) async {
    if (!active || _disposed) return;
    final serial = ++_lockSerial;
    final pick = await _read(_Capture(request, _epoch, serial));
    if (pick == null || serial != _lockSerial) return;
    selected = pick;
    _selectedNudge = request.nudge;
    _remember(pick.color);
    copiedValue = null;
    copyFailed = sampleFailed = false;
    notifyListeners();
  }

  void nudge(int dx, int dy) =>
      (selected != null ? _selectedNudge : _hoverNudge)?.call(dx, dy);

  void chooseRecent(PickedColor color) {
    selected = null;
    _retainedColor = color;
    _selectedNudge = null;
    _remember(color);
    copiedValue = null;
    copyFailed = false;
    notifyListeners();
  }

  void _remember(PickedColor color) {
    recent.removeWhere((old) => old.hexAlpha == color.hexAlpha);
    recent.insert(0, color);
    if (recent.length > RecentColorStore.limit) recent.removeLast();
    if (history == null) return;
    _unsavedColors.add(color);
    unawaited(refreshHistory());
  }

  /// Refresh on entry/window focus; queued transactions never replace another
  /// window's history with a stale in-memory list.
  Future<void> refreshHistory() {
    if (history == null || _disposed) return Future<void>.value();
    return _historyTail = _historyTail.then((_) async {
      try {
        while (_unsavedColors.isNotEmpty) {
          await history!.record(_unsavedColors.first);
          _unsavedColors.removeAt(0);
        }
        final colors = await history!.load();
        // Keep picks arriving during load in front until their transaction.
        for (final pending in _unsavedColors) {
          colors.removeWhere((old) => old.hexAlpha == pending.hexAlpha);
          colors.insert(0, pending);
        }
        recent
          ..clear()
          ..addAll(colors.take(RecentColorStore.limit));
        historyFailed = false;
      } catch (error) {
        historyFailed = true;
        debugPrint('Unable to sync recent colors: $error');
      }
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> flushHistory() => _historyTail;

  void setFormat(ColorCopyFormat value) {
    format = value;
    copiedValue = null;
    notifyListeners();
  }

  Future<void> copy([ColorCopyFormat? selectedFormat]) async {
    final picked = color;
    if (picked == null) return;
    final value = picked.format(selectedFormat ?? format);
    final epoch = _epoch;
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (_disposed || epoch != _epoch || color != picked) return;
      copiedValue = value;
      copyFailed = false;
    } catch (_) {
      if (_disposed || epoch != _epoch || color != picked) return;
      copyFailed = true;
      copiedValue = null;
    }
    notifyListeners();
    _copyTimer?.cancel();
    _copyTimer = Timer(const Duration(seconds: 2), () {
      if (_disposed) return;
      copiedValue = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _pending?.dispose();
    _pending = null;
    _copyTimer?.cancel();
    super.dispose();
  }
}
