import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../application/auto_play_controller.dart';
import '../domain/auto_play_settings.dart';
import '../domain/viewer_mode.dart';
import 'components/app_button.dart';
import 'components/app_dialog.dart';
import 'components/app_icon_button.dart';
import 'components/app_input.dart';
import 'components/app_number_input_formatter.dart';
import 'components/app_select.dart';
import 'components/app_switch.dart';
import 'theme/app_styles.dart';
import 'theme/app_theme.dart';

/// List navigation status. The only media transport bar belongs to animation.
class AutoPlayStatusIndicator extends StatefulWidget {
  const AutoPlayStatusIndicator({
    required this.controller,
    required this.onOptions,
    required this.position,
    super.key,
  });

  final AutoPlayController controller;
  final FutureOr<void> Function() onOptions;
  final String position;

  @override
  State<AutoPlayStatusIndicator> createState() =>
      _AutoPlayStatusIndicatorState();
}

class _AutoPlayStatusIndicatorState extends State<AutoPlayStatusIndicator> {
  Timer? _hide;
  bool _visible = true;
  bool _hovered = false;
  bool _focused = false;
  bool _keyboardFocus = true;
  bool _optionsOpen = false;
  bool? _wasPlaying;
  AutoPlayStatusDisplay? _wasDisplay;

  AutoPlayController get controller => widget.controller;

  bool get _pinned =>
      controller.settings.statusDisplay == AutoPlayStatusDisplay.always ||
      !controller.playing ||
      _hovered ||
      (_focused && _keyboardFocus) ||
      _optionsOpen;

  @override
  void initState() {
    super.initState();
    controller.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(covariant AutoPlayStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.removeListener(_changed);
      controller.addListener(_changed);
      _wasPlaying = null;
      _changed();
    }
  }

  void _changed() {
    if (_wasPlaying == controller.playing &&
        _wasDisplay == controller.settings.statusDisplay) {
      return;
    }
    _wasPlaying = controller.playing;
    _wasDisplay = controller.settings.statusDisplay;
    _show();
  }

  void _scheduleHide() {
    _hide?.cancel();
    if (_pinned) return;
    _hide = Timer(const Duration(seconds: 2), () {
      if (mounted && !_pinned) setState(() => _visible = false);
    });
  }

  void _show() {
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  Future<void> _openOptions() async {
    setState(() => _optionsOpen = true);
    _show();
    try {
      await widget.onOptions();
    } finally {
      if (mounted) {
        setState(() => _optionsOpen = false);
        _show();
      }
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    opaque: false,
    onEnter: (_) {
      _hovered = true;
      _show();
    },
    onHover: (_) => _show(),
    onExit: (_) {
      _hovered = false;
      _scheduleHide();
    },
    child: Listener(
      onPointerDown: (_) => _keyboardFocus = false,
      child: Focus(
        onKeyEvent: (_, _) {
          _keyboardFocus = true;
          _show();
          return KeyEventResult.ignored;
        },
        onFocusChange: (focused) {
          _focused = focused;
          if (HardwareKeyboard.instance.logicalKeysPressed.contains(
            LogicalKeyboardKey.tab,
          )) {
            _keyboardFocus = true;
          }
          _show();
        },
        child: AnimatedOpacity(
          key: const ValueKey('autoPlay.statusVisibility'),
          opacity: _visible || _pinned ? 1 : 0,
          duration: const Duration(milliseconds: 140),
          child: IgnorePointer(
            ignoring: !_visible && !_pinned,
            child: _buildStatus(context),
          ),
        ),
      ),
    ),
  );

  Widget _buildStatus(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = ViewerThemeTokens.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final title = controller.scrolling
            ? l10n.autoPlayScrolling
            : l10n.autoPlayAdvancing;
        final status = !controller.playing
            ? l10n.autoPlayPaused
            : controller.waitingForAnimation
            ? l10n.autoPlayWaiting
            : controller.scrolling
            ? l10n.autoPlayScrollRate(
                controller.settings
                    .speedFor(controller.mode)
                    .toStringAsFixed(0),
              )
            : l10n.autoPlayCountdown(
                controller.remainingSeconds.toStringAsFixed(1),
              );
        final description = '$title · ${widget.position} · $status';
        return Semantics(
          container: true,
          label: description,
          child: Tooltip(
            message: description,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
              decoration: BoxDecoration(
                color: tokens.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: tokens.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: LayoutBuilder(
                      builder: (context, constraints) => Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            constraints.maxWidth >= 140
                                ? '$title · ${widget.position}'
                                : title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.label.copyWith(
                              color: tokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: tokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AppIconButton(
                    key: const ValueKey('autoPlay.options'),
                    tooltip: l10n.autoPlayOptions,
                    icon: FluentIcons.settings_20_regular,
                    size: 32,
                    onPressed: _openOptions,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<AutoPlaySettings?> showAutoPlayOptions(
  BuildContext context, {
  required AutoPlaySettings settings,
  required ViewerMode mode,
  required VoidCallback onStop,
}) async {
  final scrolling = mode == ViewerMode.comic || mode == ViewerMode.longImage;
  final initial = scrolling
      ? settings.speedFor(mode)
      : settings.intervalFor(mode);
  final input = TextEditingController(text: initial.toString());
  final numberFormatter = AppNumberInputFormatter(
    integerDigits: 4,
    decimalPlaces: scrolling ? 2 : 1,
  );
  var value = settings;
  var valid = true;
  try {
    final route = DialogRoute<AutoPlaySettings>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return StatefulBuilder(
          builder: (context, setState) => AppDialog(
            title: l10n.autoPlayOptions,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppInput(
                  key: const ValueKey('autoPlay.parameter'),
                  controller: input,
                  label: scrolling ? l10n.autoPlaySpeed : l10n.autoPlayInterval,
                  suffixText: scrolling ? 'px/s' : 's',
                  helperText: scrolling
                      ? '5–1000 px/s'
                      : l10n.autoPlayIntervalHint,
                  errorText: valid
                      ? null
                      : scrolling
                      ? l10n.autoPlayInvalidSpeed
                      : l10n.autoPlayInvalidInterval,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [numberFormatter],
                  onChanged: (text) => setState(() {
                    final n = double.tryParse(text);
                    valid =
                        n != null &&
                        n.isFinite &&
                        n >= (scrolling ? 5 : 0.5) &&
                        n <= (scrolling ? 1000 : 3600);
                    if (valid) {
                      value = scrolling
                          ? value.copyWith(
                              scrollSpeeds: {...value.scrollSpeeds, mode: n!},
                            )
                          : value.copyWith(
                              intervals: {...value.intervals, mode: n!},
                            );
                    }
                  }),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Text(l10n.autoPlayLoop)),
                    AppSwitch(
                      value: value.loop,
                      onChanged: (loop) =>
                          setState(() => value = value.copyWith(loop: loop)),
                    ),
                  ],
                ),
                if (!scrolling) ...[
                  const SizedBox(height: 16),
                  AppSelect<AutoPlayAnimationPolicy>(
                    label: l10n.autoPlayAnimation,
                    value: value.animationPolicy,
                    options: [
                      AppSelectOption(
                        value: AutoPlayAnimationPolicy.completeOnce,
                        label: l10n.autoPlayCompleteOnce,
                      ),
                      AppSelectOption(
                        value: AutoPlayAnimationPolicy.fixedInterval,
                        label: l10n.autoPlayFixedInterval,
                      ),
                      AppSelectOption(
                        value: AutoPlayAnimationPolicy.stop,
                        label: l10n.autoPlayStay,
                      ),
                    ],
                    onChanged: (policy) => setState(
                      () => value = value.copyWith(animationPolicy: policy),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                AppSelect<AutoPlayStatusDisplay>(
                  key: const ValueKey('autoPlay.statusDisplay'),
                  label: l10n.autoPlayStatusDisplay,
                  value: value.statusDisplay,
                  options: [
                    AppSelectOption(
                      value: AutoPlayStatusDisplay.autoHide,
                      label: l10n.animationControlsAutoHide,
                    ),
                    AppSelectOption(
                      value: AutoPlayStatusDisplay.always,
                      label: l10n.animationControlsAlways,
                    ),
                  ],
                  onChanged: (display) => setState(
                    () => value = value.copyWith(statusDisplay: display),
                  ),
                ),
                const SizedBox(height: 8),
                Text(l10n.autoPlayStatusDisplayDescription),
                const SizedBox(height: 16),
                Text(l10n.autoPlayScope),
              ],
            ),
            actions: [
              AppButton(
                key: const ValueKey('autoPlay.stop'),
                label: l10n.autoPlayStop,
                variant: AppButtonVariant.neutral,
                onPressed: () {
                  onStop();
                  Navigator.pop(context);
                },
              ),
              AppButton(
                label: l10n.cancel,
                variant: AppButtonVariant.neutral,
                onPressed: () => Navigator.pop(context),
              ),
              AppButton(
                key: const ValueKey('autoPlay.save'),
                label: l10n.autoPlaySave,
                onPressed: valid ? () => Navigator.pop(context, value) : null,
              ),
            ],
          ),
        );
      },
    );
    final result = await Navigator.of(context).push(route);
    await route.completed;
    return result;
  } finally {
    input.dispose();
  }
}
