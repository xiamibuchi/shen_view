import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'app_icon_button.dart';

class AppRepeatIconButton extends StatefulWidget {
  const AppRepeatIconButton({
    required this.tooltip,
    required this.icon,
    required this.iconSize,
    required this.onPressed,
    required this.style,
    this.activateOnPress = false,
    this.repeatEnabled = true,
    this.repeatDelay = const Duration(milliseconds: 420),
    this.repeatInterval = const Duration(milliseconds: 85),
    this.canRepeat,
    super.key,
  });
  final String tooltip;
  final IconData icon;
  final double iconSize;
  final VoidCallback? onPressed;
  final ButtonStyle style;
  final bool activateOnPress;
  final bool repeatEnabled;
  final Duration repeatDelay;
  final Duration repeatInterval;
  final bool Function()? canRepeat;
  @override
  State<AppRepeatIconButton> createState() => _AppRepeatIconButtonState();
}

class _AppRepeatIconButtonState extends State<AppRepeatIconButton> {
  Timer? _repeatTimer;
  bool _didRepeat = false;
  bool _suppressTap = false;
  @override
  void didUpdateWidget(covariant AppRepeatIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onPressed == null || !widget.repeatEnabled) {
      _repeatTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    super.dispose();
  }

  void _startRepeat(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton || widget.onPressed == null) return;
    _repeatTimer?.cancel();
    _didRepeat = false;
    _suppressTap = false;
    if (widget.activateOnPress) {
      _didRepeat = true;
      widget.onPressed!();
    }
    if (!widget.repeatEnabled) return;
    _repeatTimer = Timer(widget.repeatDelay, () {
      if (!mounted ||
          widget.onPressed == null ||
          widget.canRepeat?.call() == false) {
        return;
      }
      _didRepeat = true;
      widget.onPressed!();
      _repeatTimer = Timer.periodic(widget.repeatInterval, (_) {
        if (!mounted ||
            widget.canRepeat?.call() == false ||
            widget.onPressed == null) {
          _repeatTimer?.cancel();
          return;
        }
        if (mounted) widget.onPressed?.call();
      });
    });
  }

  void _stopRepeat(PointerEvent event) {
    final didRepeat = _didRepeat;
    _repeatTimer?.cancel();
    _repeatTimer = null;
    if (didRepeat) _suppressTap = true;
  }

  void _handleTap() {
    if (_suppressTap) {
      _suppressTap = false;
      return;
    }
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onExit: _stopRepeat,
    child: Listener(
      onPointerDown: _startRepeat,
      onPointerUp: _stopRepeat,
      onPointerCancel: _stopRepeat,
      child: AppIconButton(
        tooltip: widget.tooltip,
        onPressed: widget.onPressed == null ? null : _handleTap,
        icon: widget.icon,
        iconSize: widget.iconSize,
        style: widget.style,
      ),
    ),
  );
}
