import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../application/animation_playback_controller.dart';
import 'components/app_button.dart';
import 'components/app_icon_button.dart';
import 'components/app_slider.dart';
import 'theme/app_control_styles.dart';
import 'theme/app_styles.dart';
import 'theme/app_theme.dart';
import 'viewer_shortcuts.dart';

String animationLoopLabel(AppLocalizations l10n, AnimationLoopMode mode) =>
    switch (mode) {
      AnimationLoopMode.file => l10n.animationLoopFile,
      AnimationLoopMode.infinite => l10n.animationLoopInfinite,
      AnimationLoopMode.once => l10n.animationLoopOnce,
    };

class AnimationPlaybackBar extends StatefulWidget {
  const AnimationPlaybackBar({
    required this.controller,
    this.autoHide = true,
    this.shortcuts = ViewerShortcutBindings.defaults,
    super.key,
  });
  final AnimationPlaybackController controller;
  final bool autoHide;
  final ViewerShortcutBindings shortcuts;

  @override
  State<AnimationPlaybackBar> createState() => _AnimationPlaybackBarState();
}

class _AnimationPlaybackBarState extends State<AnimationPlaybackBar> {
  Timer? _hideTimer;
  bool _visible = true;
  bool _hovered = false;
  bool _focused = false;
  bool _keyboardFocus = true;
  bool _menuOpen = false;
  bool? _wasPlaying;
  bool? _wasReady;
  double? _dragPosition;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(covariant AnimationPlaybackBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _wasPlaying = null;
      _dragPosition = null;
      _visible = true;
      _changed();
    }
    if (oldWidget.autoHide != widget.autoHide) {
      _visible = true;
      _scheduleHide();
    }
  }

  bool get _pinned =>
      !widget.autoHide ||
      _hovered ||
      (_focused && _keyboardFocus) ||
      _menuOpen ||
      !widget.controller.playing ||
      widget.controller.seeking ||
      !widget.controller.ready;

  void _changed() {
    if (_wasPlaying != widget.controller.playing ||
        _wasReady != widget.controller.ready) {
      _wasPlaying = widget.controller.playing;
      _wasReady = widget.controller.ready;
      _visible = true;
      _scheduleHide();
    }
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_pinned) return;
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_pinned) setState(() => _visible = false);
    });
  }

  void _show() {
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  String _time(int ms) {
    final minutes = ms ~/ 60000;
    final seconds = (ms ~/ 1000 % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds.${ms ~/ 100 % 10}';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final l10n = AppLocalizations.of(context)!;
    final tokens = ViewerThemeTokens.of(context);
    final frameLabel = l10n.animationFramePosition(c.frame + 1, c.frameCount);
    return MouseRegion(
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
        onPointerDown: (_) {
          _keyboardFocus = false;
          _scheduleHide();
        },
        child: Focus(
          onKeyEvent: (_, event) {
            _keyboardFocus = true;
            _show();
            return KeyEventResult.ignored;
          },
          onFocusChange: (value) {
            _focused = value;
            if (HardwareKeyboard.instance.logicalKeysPressed.contains(
              LogicalKeyboardKey.tab,
            )) {
              _keyboardFocus = true;
            }
            _show();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: AnimatedOpacity(
              opacity: _visible || _pinned ? 1 : 0,
              duration: const Duration(milliseconds: 140),
              child: IgnorePointer(
                ignoring: !_visible && !_pinned,
                child: Semantics(
                  label: l10n.animationControls,
                  container: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    height: 44,
                    decoration: BoxDecoration(
                      color: tokens.surfaceElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: tokens.border),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final showProgress = constraints.maxWidth >= 160;
                        final showSteps = constraints.maxWidth >= 400;
                        final showTime = constraints.maxWidth >= 600;
                        final showSpeed = constraints.maxWidth >= 300;
                        return Row(
                          children: [
                            if (showProgress)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(
                                  l10n.animationLabel,
                                  style: AppTextStyles.label.copyWith(
                                    color: tokens.textSecondary,
                                  ),
                                ),
                              )
                            else
                              Expanded(
                                child: Tooltip(
                                  message: l10n.animationControls,
                                  child: Text(
                                    l10n.animationLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.label.copyWith(
                                      color: tokens.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            AppIconButton(
                              key: const ValueKey('animation.play'),
                              size: 32,
                              tooltip:
                                  '${c.playing ? l10n.pause : l10n.play} (${widget.shortcuts.label(ViewerCommand.toggleAnimation, platform: Theme.of(context).platform)})',
                              icon: c.playing
                                  ? FluentIcons.pause_20_regular
                                  : FluentIcons.play_20_regular,
                              onPressed: c.ready ? c.toggle : null,
                            ),
                            if (showSteps) ...[
                              _stepButton(-1, frameLabel),
                              _stepButton(1, frameLabel),
                            ],
                            if (showProgress && c.audioTrackCount > 0)
                              AppIconButton(
                                key: const ValueKey('animation.audio'),
                                size: 32,
                                tooltip: c.audioError != null
                                    ? l10n.photoAudioRetry
                                    : c.muted
                                    ? l10n.photoUnmute
                                    : l10n.photoMute,
                                icon: c.muted || c.audioError != null
                                    ? FluentIcons.speaker_off_20_regular
                                    : FluentIcons.speaker_2_20_regular,
                                onPressed: c.audioError != null
                                    ? c.retryAudio
                                    : () => c.setMuted(!c.muted),
                              ),
                            if (showProgress)
                              Expanded(
                                child: Tooltip(
                                  message: frameLabel,
                                  child: Semantics(
                                    label: l10n.animationProgress,
                                    child: AppSlider(
                                      key: const ValueKey('animation.progress'),
                                      variant: AppSliderVariant.zoom,
                                      value:
                                          (_dragPosition ??
                                                  c.positionMs.toDouble())
                                              .clamp(
                                                0,
                                                c.timeline.durationMs
                                                    .toDouble(),
                                              ),
                                      max: c.timeline.durationMs.toDouble(),
                                      semanticFormatterCallback: (v) =>
                                          _time(v.round()),
                                      onChangeStart: c.ready
                                          ? (v) {
                                              _dragPosition = v;
                                              c.beginSeek();
                                            }
                                          : null,
                                      onChanged: c.ready
                                          ? (v) {
                                              setState(() => _dragPosition = v);
                                              c.seekTime(v.round());
                                            }
                                          : null,
                                      onChangeEnd: c.ready
                                          ? (v) {
                                              _dragPosition = null;
                                              c.seekTime(v.round());
                                              c.endSeek();
                                            }
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            if (showTime)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                child: Text(
                                  '${_time((_dragPosition ?? c.positionMs).round())} / ${_time(c.timeline.durationMs)}',
                                  style: AppTextStyles.label.copyWith(
                                    color: tokens.textSecondary,
                                  ),
                                ),
                              ),
                            if (showSpeed)
                              _menu(
                                label: l10n.animationSpeed,
                                height: 208,
                                items: _speedItems(l10n),
                                text:
                                    '${c.speed.toString().replaceAll(RegExp(r'\.0$'), '')}×',
                              ),
                            _menu(
                              label: l10n.moreActions,
                              height: showSpeed ? 208 : 408,
                              items: [
                                MenuItemButton(
                                  style: AppControlStyles.menuItem(context),
                                  onPressed: c.ready ? c.restart : null,
                                  child: Text(l10n.animationRestart),
                                ),
                                for (final mode in AnimationLoopMode.values)
                                  MenuItemButton(
                                    style: AppControlStyles.menuItem(
                                      context,
                                      selected: mode == c.loopMode,
                                    ),
                                    onPressed: () => c.setLoopMode(mode),
                                    trailingIcon: mode == c.loopMode
                                        ? const Icon(
                                            FluentIcons.checkmark_20_regular,
                                            size: 16,
                                          )
                                        : null,
                                    child: Text(animationLoopLabel(l10n, mode)),
                                  ),
                                if (!showSteps) ...[
                                  MenuItemButton(
                                    style: AppControlStyles.menuItem(context),
                                    onPressed: c.ready
                                        ? () => c.step(-1)
                                        : null,
                                    trailingIcon: Text(
                                      widget.shortcuts.label(
                                        ViewerCommand.previousFrame,
                                        platform: Theme.of(context).platform,
                                      ),
                                    ),
                                    child: Text(l10n.previousFrame),
                                  ),
                                  MenuItemButton(
                                    style: AppControlStyles.menuItem(context),
                                    onPressed: c.ready ? () => c.step(1) : null,
                                    trailingIcon: Text(
                                      widget.shortcuts.label(
                                        ViewerCommand.nextFrame,
                                        platform: Theme.of(context).platform,
                                      ),
                                    ),
                                    child: Text(l10n.nextFrame),
                                  ),
                                ],
                                if (!showSpeed) ..._speedItems(l10n),
                                if (!showProgress && c.audioTrackCount > 0)
                                  MenuItemButton(
                                    style: AppControlStyles.menuItem(context),
                                    onPressed: () => c.setMuted(!c.muted),
                                    child: Text(
                                      c.muted
                                          ? l10n.photoUnmute
                                          : l10n.photoMute,
                                    ),
                                  ),
                                if (c.audioTrackCount > 1)
                                  for (
                                    var track = 0;
                                    track < c.audioTrackCount;
                                    track++
                                  )
                                    MenuItemButton(
                                      style: AppControlStyles.menuItem(
                                        context,
                                        selected: c.audioTrack == track,
                                      ),
                                      onPressed: () => c.setAudioTrack(track),
                                      child: Text(
                                        l10n.photoAudioTrack(track + 1),
                                      ),
                                    ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepButton(int delta, String frameLabel) {
    final l10n = AppLocalizations.of(context)!;
    final c = widget.controller;
    return AppIconButton(
      key: ValueKey('animation.step.$delta'),
      size: 32,
      tooltip:
          '${delta < 0 ? l10n.previousFrame : l10n.nextFrame} · ${widget.shortcuts.label(delta < 0 ? ViewerCommand.previousFrame : ViewerCommand.nextFrame, platform: Theme.of(context).platform)} · $frameLabel',
      icon: delta < 0
          ? FluentIcons.previous_20_regular
          : FluentIcons.next_20_regular,
      onPressed:
          c.ready && (delta < 0 ? c.frame > 0 : c.frame < c.frameCount - 1)
          ? () => c.step(delta)
          : null,
    );
  }

  List<Widget> _speedItems(AppLocalizations l10n) => [
    for (final speed in animationPlaybackSpeeds)
      MenuItemButton(
        style: AppControlStyles.menuItem(
          context,
          selected: widget.controller.speed == speed,
        ),
        onPressed: () => widget.controller.setSpeed(speed),
        child: Text('${speed.toString().replaceAll(RegExp(r'\.0$'), '')}×'),
      ),
  ];

  Widget _menu({
    required String label,
    required List<Widget> items,
    required double height,
    String? text,
  }) => MenuAnchor(
    style: AppControlStyles.menu(ViewerThemeTokens.of(context)),
    alignmentOffset: Offset(0, -height - 40),
    onOpen: () {
      _menuOpen = true;
      _show();
    },
    onClose: () {
      _menuOpen = false;
      _scheduleHide();
    },
    menuChildren: items,
    builder: (context, menu, child) => text == null
        ? AppIconButton(
            key: const ValueKey('animation.more'),
            size: 32,
            tooltip: label,
            icon: FluentIcons.more_horizontal_20_regular,
            onPressed: () => menu.isOpen ? menu.close() : menu.open(),
          )
        : SizedBox(
            width: 60,
            child: AppButton(
              label: text,
              tooltip: label,
              variant: AppButtonVariant.subtle,
              onPressed: () => menu.isOpen ? menu.close() : menu.open(),
            ),
          ),
  );
}
