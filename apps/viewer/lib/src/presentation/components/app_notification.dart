import 'dart:async';
import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../theme/app_styles.dart';
import '../theme/app_control_styles.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'app_text_action.dart';
import 'app_icon_button.dart';

enum AppNotificationType { success, info, warning, error }

/// A notification can be closed independently when its operation completes.
class AppNotificationHandle {
  AppNotificationHandle._(
    this._owner,
    this.message,
    this.type,
    this.actionLabel,
    this.onAction,
  );

  final AppNotificationController _owner;
  final String message;
  final AppNotificationType type;
  final String? actionLabel;
  final VoidCallback? onAction;
  Timer? _timer;

  void close() => _owner._close(this);
}

/// Owned by the page so pending timers cannot outlive the window or dialog.
class AppNotificationController extends ChangeNotifier {
  final _items = <AppNotificationHandle>[];
  bool _disposed = false;

  bool get isNotEmpty => _items.isNotEmpty;

  AppNotificationHandle show(
    String message, {
    AppNotificationType type = AppNotificationType.info,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    assert(!_disposed);
    final item = AppNotificationHandle._(
      this,
      message,
      type,
      actionLabel,
      onAction,
    );
    _items.add(item);
    if (type != AppNotificationType.error) {
      item._timer = Timer(
        Duration(seconds: type == AppNotificationType.warning ? 6 : 4),
        item.close,
      );
    }
    notifyListeners();
    return item;
  }

  void _close(AppNotificationHandle item) {
    item._timer?.cancel();
    if (_disposed || !_items.remove(item)) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final item in _items) {
      item._timer?.cancel();
    }
    _items.clear();
    super.dispose();
  }
}

/// Non-modal notifications float below the title bar, above page content.
class AppNotificationHost extends StatelessWidget {
  const AppNotificationHost({
    required this.controller,
    required this.child,
    super.key,
  });

  final AppNotificationController controller;
  final Widget child;

  static AppNotificationController of(BuildContext context) =>
      context.findAncestorWidgetOfExactType<AppNotificationHost>()!.controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    child: child,
    builder: (context, child) => Stack(
      fit: StackFit.expand,
      children: [
        child!,
        if (controller.isNotEmpty)
          Positioned.fill(
            child: SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 60, 16, 16),
              child: LayoutBuilder(
                builder: (context, constraints) => Align(
                  alignment: Alignment.topRight,
                  child: SizedBox(
                    width: math.min(420, constraints.maxWidth),
                    child: ListView(
                      primary: false,
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: [
                        for (final item in controller._items)
                          Padding(
                            key: ObjectKey(item),
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AppNotificationCard(notification: item),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class AppNotificationCard extends StatelessWidget {
  const AppNotificationCard({required this.notification, super.key});

  final AppNotificationHandle notification;

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    final (color, icon) = switch (notification.type) {
      AppNotificationType.success => (
        tokens.success,
        FluentIcons.checkmark_circle_20_regular,
      ),
      AppNotificationType.info => (
        tokens.accentStrong,
        FluentIcons.info_20_regular,
      ),
      AppNotificationType.warning => (
        tokens.warning,
        FluentIcons.warning_20_regular,
      ),
      AppNotificationType.error => (
        tokens.danger,
        FluentIcons.error_circle_20_regular,
      ),
    };
    return Semantics(
      container: true,
      liveRegion: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppTokens.panelAnimation,
        curve: Curves.easeOutCubic,
        builder: (context, value, child) =>
            Opacity(opacity: value, child: child),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(AppTokens.containerRadius),
            border: Border.all(color: tokens.border.withValues(alpha: 0.65)),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.18
                      : 0.08,
                ),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(AppTokens.containerRadius),
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.space3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      top:
                          6 +
                          (MediaQuery.textScalerOf(context).scale(20) - 20) / 2,
                    ),
                    child: Icon(icon, size: 20, color: color),
                  ),
                  const SizedBox(width: AppTokens.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 160),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                notification.message,
                                style: AppTextStyles.control.copyWith(
                                  color: tokens.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (notification.actionLabel != null &&
                            notification.onAction != null) ...[
                          const SizedBox(height: AppTokens.space1),
                          AppTextAction(
                            label: notification.actionLabel!,
                            onPressed: notification.onAction,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppTokens.space2),
                  AppIconButton(
                    style: AppControlStyles.notificationClose(tokens),
                    icon: FluentIcons.dismiss_20_regular,
                    iconSize: 16,
                    tooltip: MaterialLocalizations.of(context)
                        .closeButtonTooltip,
                    onPressed: notification.close,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
