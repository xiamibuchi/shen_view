import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../domain/viewer_settings.dart';
import 'components/app_backdrop_surface.dart';
import 'theme/app_theme.dart';
import 'theme/app_tokens.dart';
import 'viewer_shortcuts.dart';

/// Shares one preferred width between docked and overlay directory panels.
/// Window constraints only affect the display, never the stored preference.
class DirectoryPanelRegion extends StatefulWidget {
  const DirectoryPanelRegion({
    required this.availableWidth,
    required this.minimumContentWidth,
    required this.preferredWidth,
    required this.docked,
    required this.visible,
    required this.panel,
    required this.child,
    required this.onClose,
    required this.onWidthChanged,
    this.maintainState = false,
    this.overlayTopInset = 0,
    super.key,
  });

  final double availableWidth;
  final double minimumContentWidth;
  final double preferredWidth;
  final bool docked;
  final bool visible;
  final Widget panel;
  final Widget child;
  final VoidCallback onClose;
  final ValueChanged<double> onWidthChanged;
  final bool maintainState;

  /// Leaves floating window commands above the overlay, without stacking blur.
  final double overlayTopInset;

  @override
  State<DirectoryPanelRegion> createState() => _DirectoryPanelRegionState();
}

class _DirectoryPanelRegionState extends State<DirectoryPanelRegion> {
  final _resizeFocus = FocusNode();
  final _panelKey = GlobalKey();
  double? _dragWidth;
  double _dragStartWidth = 0;
  double _lastDragX = 0;
  double? _undoWidth;
  Timer? _hoverTimer;
  bool _near = false;
  bool _hovered = false;
  bool _pressed = false;
  bool _keyboardFocus = false;
  bool _touch = false;
  bool _dragCancelled = false;
  int? _activePointer;
  bool _panelCreated = false;

  double get _maximum => math.min(
    ViewerSettings.maxDirectoryPanelWidth,
    math.max(0, widget.availableWidth - widget.minimumContentWidth),
  );

  double get _minimum =>
      math.min(ViewerSettings.minDirectoryPanelWidth, _maximum);

  double _constrain(double value) => value.clamp(_minimum, _maximum);

  double get _width => _constrain(
    _dragWidth ??
        ViewerSettings.normalizeDirectoryPanelWidth(widget.preferredWidth),
  );

  bool get _dragging => _dragWidth != null;
  bool get _atMinimum => _width <= _minimum;
  bool get _atMaximum => _width >= _maximum;

  MouseCursor get _cursor => _maximum <= _minimum
      ? SystemMouseCursors.basic
      : _atMinimum
      ? SystemMouseCursors.resizeRight
      : _atMaximum
      ? SystemMouseCursors.resizeLeft
      : SystemMouseCursors.resizeLeftRight;

  void _setNear(bool value) {
    _hoverTimer?.cancel();
    setState(() {
      _near = value;
      if (!value) _hovered = false;
    });
    if (value) {
      _hoverTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _hovered = true);
      });
    }
  }

  @override
  void didUpdateWidget(covariant DirectoryPanelRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.visible ||
        oldWidget.docked != widget.docked ||
        oldWidget.availableWidth != widget.availableWidth ||
        oldWidget.minimumContentWidth != widget.minimumContentWidth ||
        oldWidget.preferredWidth != widget.preferredWidth) {
      _dragWidth = null;
      _pressed = false;
      _dragCancelled = true;
      if (!widget.visible) {
        _activePointer = null;
        _hoverTimer?.cancel();
        _near = false;
        _hovered = false;
      }
    }
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _resizeFocus.dispose();
    super.dispose();
  }

  void _saveWidth(double width) {
    if (width == widget.preferredWidth) return;
    _undoWidth = widget.preferredWidth;
    widget.onWidthChanged(width);
  }

  void _commitDrag() {
    final width = _dragWidth;
    setState(() {
      _dragWidth = null;
      _pressed = false;
      if (!_dragCancelled && width != null && width != _dragStartWidth) {
        _saveWidth(width);
      }
    });
  }

  void _cancelDrag() {
    setState(() {
      _dragWidth = null;
      _pressed = false;
      _dragCancelled = true;
    });
  }

  void _undo() {
    final width = _undoWidth;
    if (width == null) return;
    setState(() {
      _undoWidth = null;
      widget.onWidthChanged(width);
    });
  }

  void _reset() {
    setState(() {
      _saveWidth(ViewerSettings.defaultDirectoryPanelWidth);
    });
  }

  void _stepWidth(double delta) {
    final width = _constrain(_width + delta);
    setState(() {
      if (width != _width) _saveWidth(width);
      _keyboardFocus = true;
    });
  }

  KeyEventResult _onResizeKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        (_pressed || _dragging)) {
      _cancelDrag();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyZ &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        _undoWidth != null &&
        !_dragging) {
      _undo();
      return KeyEventResult.handled;
    }
    if (_dragging) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.home) {
      _reset();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _stepWidth(-10);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _stepWidth(10);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildPanel(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    return SizedBox(
      key: const ValueKey('directory.sizedPanel'),
      width: _width,
      child: AppBackdropSurface(
        kind: AppBackdropKind.directory,
        active: !widget.docked,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Keep the resize target separate from the tree's scrollbar.
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: KeyedSubtree(key: _panelKey, child: widget.panel),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 1,
              child: ColoredBox(color: tokens.navigationBorder),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dragTarget({
    required Widget child,
    required Key key,
    bool mouseOnly = false,
  }) => MouseRegion(
    cursor: _cursor,
    child: Listener(
      onPointerDown: (event) {
        if (event.buttons != kPrimaryMouseButton ||
            (mouseOnly && event.kind == PointerDeviceKind.touch)) {
          return;
        }
        if (_activePointer != null) {
          _cancelDrag();
          return;
        }
        _activePointer = event.pointer;
        _resizeFocus.requestFocus();
        setState(() {
          _keyboardFocus = false;
          _pressed = true;
          _dragCancelled = false;
          _touch = event.kind == PointerDeviceKind.touch;
          _lastDragX = event.position.dx;
          _dragStartWidth = _width;
        });
      },
      onPointerUp: (event) {
        if (_activePointer != event.pointer) return;
        _activePointer = null;
        if (!_dragging) setState(() => _pressed = false);
      },
      onPointerCancel: (event) {
        if (_activePointer != event.pointer) return;
        _activePointer = null;
        _cancelDrag();
      },
      child: GestureDetector(
        key: key,
        supportedDevices: mouseOnly
            ? {
                PointerDeviceKind.mouse,
                PointerDeviceKind.stylus,
                PointerDeviceKind.invertedStylus,
              }
            : null,
        dragStartBehavior: DragStartBehavior.down,
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _reset,
        onHorizontalDragStart: (_) {
          if (_dragCancelled) return;
          setState(() => _dragWidth = _width);
          if (_touch) unawaited(HapticFeedback.selectionClick());
        },
        onHorizontalDragUpdate: (details) {
          if (_dragCancelled || !_dragging) return;
          final wasBounded = _atMinimum || _atMaximum;
          setState(() {
            _dragWidth = _constrain(
              _width + details.globalPosition.dx - _lastDragX,
            );
            _lastDragX = details.globalPosition.dx;
          });
          if (_touch && !wasBounded && (_atMinimum || _atMaximum)) {
            unawaited(HapticFeedback.selectionClick());
          }
        },
        onHorizontalDragEnd: (_) => _commitDrag(),
        onHorizontalDragCancel: () {
          if (_dragging) {
            _cancelDrag();
          } else {
            setState(() => _pressed = false);
          }
        },
        child: child,
      ),
    ),
  );

  Widget _buildResizeHandle(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    final undoShortcut = const ViewerShortcutBinding(
      key: LogicalKeyboardKey.keyZ,
      control: true,
    ).displayLabel(platform: Theme.of(context).platform);
    final label = AppLocalizations.of(context)!
        .resizeDirectoryPanel(undoShortcut);
    final active = _pressed || _dragging || _hovered;
    return Focus(
      focusNode: _resizeFocus,
      onFocusChange: (focused) =>
          setState(() => _keyboardFocus = focused && !_pressed),
      onKeyEvent: _onResizeKey,
      child: Semantics(
        label: label,
        value: '${_width.round()} px',
        increasedValue: '${_constrain(_width + 10).round()} px',
        decreasedValue: '${_constrain(_width - 10).round()} px',
        onIncrease: () => _stepWidth(10),
        onDecrease: () => _stepWidth(-10),
        child: Stack(
          children: [
            Positioned(
              left: 18,
              width: 8,
              top: 0,
              bottom: 0,
              child: _dragTarget(
                key: const ValueKey('directory.resizeStrip'),
                mouseOnly: true,
                child: Center(
                  child: _resizeSurface(
                    context,
                    key: const ValueKey('directory.resizeLine'),
                    width: active
                        ? 4
                        : _near
                        ? 2
                        : 1,
                    decoration: BoxDecoration(
                      color: active
                          ? tokens.accent
                          : _near
                          ? tokens.borderStrong
                          : tokens.navigationBorder,
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: SizedBox(
                width: 44,
                height: 48,
                child: _dragTarget(
                  key: const ValueKey('directory.resize'),
                  child: Center(
                    child: _resizeSurface(
                      context,
                      key: const ValueKey('directory.resizeGrip'),
                      width: _pressed
                          ? 16
                          : active || _near || _keyboardFocus
                          ? 14
                          : 6,
                      height: _pressed
                          ? 32
                          : active || _near || _keyboardFocus
                          ? 36
                          : 24,
                      decoration: BoxDecoration(
                        color: _pressed
                            ? tokens.accentStrong
                            : active
                            ? tokens.accent
                            : tokens.surfaceElevated,
                        borderRadius: BorderRadius.circular(
                          AppTokens.controlRadius,
                        ),
                        border: Border.all(
                          color: _keyboardFocus
                              ? tokens.focusRing
                              : tokens.borderStrong,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 2,
                          height: 12,
                          color: active ? tokens.onAccent : tokens.textTertiary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resizeSurface(
    BuildContext context, {
    Key? key,
    required double width,
    double? height,
    required BoxDecoration decoration,
    Widget? child,
  }) {
    // Immediate paint for direct manipulation; no tween can lag behind a press.
    if (_pressed || _dragging || MediaQuery.disableAnimationsOf(context)) {
      return Container(
        key: key,
        width: width,
        height: height,
        decoration: decoration,
        child: child,
      );
    }
    return AnimatedContainer(
      key: key,
      duration: AppTokens.selectionAnimation,
      width: width,
      height: height,
      decoration: decoration,
      child: child,
    );
  }

  Widget _rememberPanel(BuildContext context) {
    _panelCreated = true;
    return _buildPanel(context);
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Padding(
        padding: EdgeInsets.only(
          left: widget.visible && widget.docked ? _width : 0,
        ),
        child: widget.child,
      ),
      if (widget.visible && !widget.docked) ...[
        Positioned.fill(
          child: ModalBarrier(
            key: const ValueKey('directory.barrier'),
            dismissible: true,
            onDismiss: widget.onClose,
            // Light-dismiss navigation keeps the underlying picture visible.
            // Smoke is reserved for modal dialogs.
            color: null,
          ),
        ),
      ],
      if (widget.visible || (widget.maintainState && _panelCreated))
        Positioned(
          left: 0,
          top: widget.docked ? 0 : widget.overlayTopInset,
          bottom: 0,
          width: _width,
          child: Offstage(
            offstage: !widget.visible,
            child: SizedBox(
              key: widget.docked ? const ValueKey('directory.docked') : null,
              child: _rememberPanel(context),
            ),
          ),
        ),
      if (widget.visible) ...[
        if (_dragging)
          Positioned.fill(
            child: MouseRegion(
              cursor: _cursor,
              child: Listener(
                onPointerDown: (event) {
                  if (event.kind == PointerDeviceKind.touch) _cancelDrag();
                },
                onPointerSignal: (event) => GestureBinding
                    .instance
                    .pointerSignalResolver
                    .register(event, (_) {}),
                child: const AbsorbPointer(
                  key: ValueKey('directory.resizeShield'),
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),
        Positioned(
          key: const ValueKey('directory.resizeRegion'),
          left: _width - 22,
          width: 44,
          top: widget.docked ? 0 : widget.overlayTopInset,
          bottom: 0,
          child: _buildResizeHandle(context),
        ),
        Positioned(
          left: _width - 14,
          width: 28,
          top: widget.docked ? 0 : widget.overlayTopInset,
          bottom: 0,
          child: MouseRegion(
            key: const ValueKey('directory.resizeProximity'),
            opaque: false,
            hitTestBehavior: HitTestBehavior.translucent,
            onEnter: (_) => _setNear(true),
            onExit: (_) => _setNear(false),
          ),
        ),
      ],
    ],
  );
}
