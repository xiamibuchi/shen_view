import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Tracks native accessibility, transparency and power preferences.
class AppMaterialEffects extends StatefulWidget {
  const AppMaterialEffects({required this.child, super.key});

  static const channel = MethodChannel('shenview/material_effects');
  final Widget child;

  static bool enabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MaterialPolicy>()?.enabled ??
      true;

  @override
  State<AppMaterialEffects> createState() => _AppMaterialEffectsState();
}

class _AppMaterialEffectsState extends State<AppMaterialEffects>
    with WidgetsBindingObserver {
  bool _enabled = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppMaterialEffects.channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') await _refresh();
    });
    _refresh();
  }

  Future<void> _refresh() async {
    final revision = ++_revision;
    bool enabled;
    try {
      enabled =
          await AppMaterialEffects.channel.invokeMethod<bool>('enabled') ??
          defaultTargetPlatform != TargetPlatform.linux;
    } on MissingPluginException {
      // Linux has no native preference/compositor probe yet.
      enabled = defaultTargetPlatform != TargetPlatform.linux;
    } on PlatformException {
      enabled = false;
    }
    if (mounted && revision == _revision && enabled != _enabled) {
      setState(() => _enabled = enabled);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppMaterialEffects.channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _MaterialPolicy(enabled: _enabled, child: widget.child);
}

class _MaterialPolicy extends InheritedWidget {
  const _MaterialPolicy({required this.enabled, required super.child});
  final bool enabled;

  @override
  bool updateShouldNotify(_MaterialPolicy oldWidget) =>
      enabled != oldWidget.enabled;
}

enum AppBackdropKind { toolbar, directory }

/// In-app frosted material. Only its background is translucent; controls retain
/// their normal foreground, focus and hit-testing behavior.
class AppBackdropSurface extends StatelessWidget {
  const AppBackdropSurface({
    required this.child,
    this.kind = AppBackdropKind.toolbar,
    this.active = true,
    super.key,
  });

  final Widget child;
  final AppBackdropKind kind;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    final enabled =
        active &&
        AppMaterialEffects.enabledOf(context) &&
        !MediaQuery.highContrastOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opacity = switch (kind) {
      AppBackdropKind.toolbar => dark ? 0.76 : 0.82,
      AppBackdropKind.directory => dark ? 0.84 : 0.88,
    };
    final surface = ColoredBox(
      color: active
          ? tokens.navigationOverlay.withValues(alpha: enabled ? opacity : 1)
          : tokens.navigationSurface,
      child: child,
    );
    if (!enabled) return surface;
    // Separate clips prevent a full-screen blur and double filtering where the
    // toolbar and directory meet. Their regions do not overlap.
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: kind == AppBackdropKind.toolbar ? 14 : 16,
          sigmaY: kind == AppBackdropKind.toolbar ? 14 : 16,
        ),
        child: surface,
      ),
    );
  }
}
