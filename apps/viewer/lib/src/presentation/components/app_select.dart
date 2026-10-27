import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/app_control_styles.dart';
import '../theme/app_styles.dart';
import '../theme/app_tokens.dart';
import 'field_frame.dart';

@immutable
class AppSelectOption<T> {
  const AppSelectOption({
    required this.value,
    required this.label,
    this.tooltip,
    this.icon,
    this.enabled = true,
  });

  final T value;
  final String label;
  final String? tooltip;
  final IconData? icon;
  final bool enabled;
}

class AppSelect<T> extends StatefulWidget {
  const AppSelect({
    required this.options,
    this.value,
    this.onChanged,
    this.label,
    this.hint = '',
    this.helperText,
    this.errorText,
    this.focusNode,
    this.enabled = true,
    this.menuMaxHeight = 320,
    this.borderless = false,
    this.shrinkWrap = false,
    super.key,
  });

  final List<AppSelectOption<T>> options;
  final T? value;
  final ValueChanged<T>? onChanged;
  final String? label;
  final String hint;
  final String? helperText;
  final String? errorText;
  final FocusNode? focusNode;
  final bool enabled;
  final double menuMaxHeight;
  final bool borderless;

  /// Sizes the trigger to its current label while respecting parent constraints.
  final bool shrinkWrap;

  @override
  State<AppSelect<T>> createState() => _AppSelectState<T>();
}

class _AppSelectState<T> extends State<AppSelect<T>> {
  final _menu = MenuController();
  final _internalFocus = FocusNode();
  final _itemFocus = <int, FocusNode>{};
  bool _open = false;
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;
  bool _keyboardFocus = true;

  bool get _enabled =>
      widget.enabled &&
      widget.onChanged != null &&
      widget.options.any((option) => option.enabled);
  FocusNode get _focus => widget.focusNode ?? _internalFocus;

  @override
  void didUpdateWidget(covariant AppSelect<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled && _menu.isOpen) _menu.close();
  }

  @override
  void dispose() {
    _internalFocus.dispose();
    for (final node in _itemFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _openFromKeyboard({bool last = false}) {
    if (!_enabled) return;
    _keyboardFocus = true;
    _menu.open();
    final indices = [
      for (var i = 0; i < widget.options.length; i++)
        if (widget.options[i].enabled) i,
    ];
    final current = indices.where(
      (index) => widget.options[index].value == widget.value,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_menu.isOpen || indices.isEmpty) return;
      final index = current.isNotEmpty
          ? current.first
          : last
          ? indices.last
          : indices.first;
      _itemFocus[index]?.requestFocus();
    });
  }

  void _onClose() {
    if (!mounted) return;
    setState(() => _open = false);
    // MenuAnchor restores its trigger's focus after activating an item. Wait
    // for that restoration, then return pointer users to the enclosing view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _menu.isOpen || _keyboardFocus || !_focus.hasFocus) {
        return;
      }
      final enclosingFocus = Focus.maybeOf(context);
      if (enclosingFocus != null && enclosingFocus.canRequestFocus) {
        enclosingFocus.requestFocus();
      } else {
        _focus.unfocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    AppSelectOption<T>? selected;
    for (final option in widget.options) {
      if (option.value == widget.value) selected = option;
    }
    final selectedLabel = selected?.label ?? widget.hint;
    final field = FieldFrame(
      label: widget.label,
      helperText: widget.helperText,
      errorText: widget.errorText,
      enabled: _enabled,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : 240.0;
          // Cap menu growth so long labels cannot fill the screen width.
          final screenWidth = MediaQuery.maybeSizeOf(context)?.width;
          final maxMenuWidth = math.max(
            width,
            math.min(
              AppTokens.menuMaxWidth,
              (screenWidth ?? double.infinity) - AppTokens.space5 * 2,
            ),
          );
          return SizedBox(
            width: width,
            child: MenuAnchor(
              controller: _menu,
              childFocusNode: _focus,
              alignmentOffset: const Offset(0, 6),
              crossAxisUnconstrained: false,
              consumeOutsideTap: true,
              onOpen: () => setState(() => _open = true),
              onClose: _onClose,
              style: AppControlStyles.menu(tokens).copyWith(
                alignment: AlignmentDirectional.bottomStart,
                minimumSize: WidgetStatePropertyAll(Size(width, 0)),
                maximumSize: WidgetStatePropertyAll(
                  Size(maxMenuWidth, widget.menuMaxHeight),
                ),
              ),
              menuChildren: [
                for (var i = 0; i < widget.options.length; i++)
                  _menuItem(i, tokens),
              ],
              builder: (context, controller, _) => CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      _openFromKeyboard(),
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                      _openFromKeyboard(last: true),
                },
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onFocusChange: (focused) {
                    if (mounted) {
                      setState(() {
                        _focused = focused;
                        if (focused &&
                            HardwareKeyboard.instance.logicalKeysPressed
                                .contains(LogicalKeyboardKey.tab)) {
                          _keyboardFocus = true;
                        }
                      });
                    }
                  },
                  onKeyEvent: (_, event) {
                    if (event is KeyDownEvent && !_keyboardFocus) {
                      setState(() => _keyboardFocus = true);
                    }
                    return KeyEventResult.ignored;
                  },
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _hovered = true),
                    onExit: (_) => setState(() => _hovered = false),
                    child: Listener(
                      onPointerDown: (_) => setState(() {
                        _pressed = true;
                        _keyboardFocus = false;
                      }),
                      onPointerUp: (_) => setState(() => _pressed = false),
                      onPointerCancel: (_) => setState(() => _pressed = false),
                      child: Semantics(
                        label: widget.label,
                        expanded: _open,
                        child: TextButton(
                          focusNode: _focus,
                          onPressed: _enabled
                              ? () {
                                  if (_menu.isOpen) {
                                    _menu.close();
                                  } else {
                                    _menu.open();
                                  }
                                }
                              : null,
                          style: ButtonStyle(
                            visualDensity: VisualDensity.standard,
                            textStyle: WidgetStatePropertyAll(
                              Theme.of(context).textTheme.bodyMedium!
                                  .merge(AppTextStyles.control)
                                  .copyWith(fontWeight: FontWeight.w400),
                            ),
                            padding: const WidgetStatePropertyAll(
                              EdgeInsets.zero,
                            ),
                            minimumSize: const WidgetStatePropertyAll(
                              Size(0, AppTokens.controlHeight),
                            ),
                            overlayColor: const WidgetStatePropertyAll(
                              Colors.transparent,
                            ),
                            mouseCursor: WidgetStatePropertyAll(
                              _enabled
                                  ? SystemMouseCursors.click
                                  : SystemMouseCursors.basic,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            animationDuration: Duration.zero,
                          ),
                          child: FieldSurface(
                            borderless: widget.borderless,
                            enabled: _enabled,
                            focused: _open || (_focused && _keyboardFocus),
                            hovered: _hovered,
                            pressed: _pressed,
                            hasError: widget.errorText != null,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Tooltip(
                                    message: selected?.tooltip ?? selectedLabel,
                                    child: Text(
                                      selectedLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.control.copyWith(
                                        fontWeight: FontWeight.w400,
                                        color: !_enabled
                                            ? tokens.textDisabled
                                            : selected == null
                                            ? tokens.textTertiary
                                            : tokens.textPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppTokens.space2),
                                Icon(
                                  _open
                                      ? FluentIcons.chevron_up_16_regular
                                      : FluentIcons.chevron_down_16_regular,
                                  size: 14,
                                  color: _enabled
                                      ? tokens.textSecondary
                                      : tokens.textDisabled,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    if (!widget.shrinkWrap) return field;
    final painter = TextPainter(
      text: TextSpan(
        text: selectedLabel,
        style: DefaultTextStyle.of(context).style
            .merge(AppTextStyles.control.copyWith(fontWeight: FontWeight.w400)),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = math.max(
      96.0,
      (painter.width + AppTokens.space3 * 2 + AppTokens.space2 + 14)
          .ceilToDouble(),
    );
    painter.dispose();
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: field,
    );
  }

  Widget _menuItem(int index, ViewerThemeTokens tokens) {
    final option = widget.options[index];
    final selected = option.value == widget.value;
    final enabled = _enabled && option.enabled;
    final item = Listener(
      onPointerDown: (_) => setState(() => _keyboardFocus = false),
      child: MenuItemButton(
        focusNode: _itemFocus.putIfAbsent(index, FocusNode.new),
        onPressed: enabled ? () => widget.onChanged?.call(option.value) : null,
        leadingIcon: option.icon == null ? null : Icon(option.icon, size: 18),
        trailingIcon: selected
            ? Icon(
                FluentIcons.checkmark_16_regular,
                size: 18,
                color: enabled ? tokens.accentStrong : tokens.textDisabled,
              )
            : const SizedBox(width: 18),
        style: AppControlStyles.menuItem(context, selected: selected).copyWith(
          minimumSize: WidgetStatePropertyAll(
            Size(
              0,
              AppControlStyles.controlHeight(
                context,
                minimum: AppTokens.menuItemHeight,
              ),
            ),
          ),
          mouseCursor: WidgetStatePropertyAll(
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(option.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
    final tooltip = option.tooltip?.trim();
    if (tooltip == null || tooltip.isEmpty || tooltip == option.label.trim()) {
      return item;
    }
    return Tooltip(message: tooltip, child: item);
  }
}
