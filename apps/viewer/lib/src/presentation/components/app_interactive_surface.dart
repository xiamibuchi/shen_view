import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_control_styles.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// A clickable row or card. Its focus ring never changes the content inset.
class AppInteractiveSurface extends StatefulWidget {
  const AppInteractiveSurface({
    required this.child,
    required this.onTap,
    this.selected = false,
    this.radius = AppTokens.controlRadius,
    this.canRequestFocus = true,
    this.excludeFromSemantics = false,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final double radius;
  final bool canRequestFocus;
  final bool excludeFromSemantics;

  @override
  State<AppInteractiveSurface> createState() => _AppInteractiveSurfaceState();
}

class _AppInteractiveSurfaceState extends State<AppInteractiveSurface> {
  final _states = WidgetStatesController();
  bool _updateScheduled = false;

  @override
  void initState() {
    super.initState();
    _states.addListener(_onStatesChanged);
  }

  void _onStatesChanged() {
    // InkWell also updates disabled/hover states from didUpdateWidget.
    // Those notifications must not rebuild an ancestor during layout/build.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_updateScheduled) return;
      _updateScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateScheduled = false;
        if (mounted) setState(() {});
      });
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _states.removeListener(_onStatesChanged);
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    final enabled = widget.onTap != null;
    final radius = BorderRadius.circular(widget.radius);
    final states = _states.value;
    final background = widget.selected
        ? AppControlStyles.selectionFill(
            tokens,
            enabled: enabled,
            hovered: states.contains(WidgetState.hovered),
            pressed: states.contains(WidgetState.pressed),
          )
        : !enabled
        ? Colors.transparent
        : states.contains(WidgetState.pressed)
        ? tokens.surfacePressed
        : states.contains(WidgetState.hovered)
        ? tokens.surfaceHover
        : Colors.transparent;
    return Semantics(
      selected: widget.selected ? true : null,
      child: Material(
        color: background,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          statesController: _states,
          onTap: widget.onTap,
          canRequestFocus: widget.canRequestFocus,
          excludeFromSemantics: widget.excludeFromSemantics,
          borderRadius: radius,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          mouseCursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: Container(
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                width: 1,
                color: enabled && states.contains(WidgetState.focused)
                    ? tokens.focusRing
                    : Colors.transparent,
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
