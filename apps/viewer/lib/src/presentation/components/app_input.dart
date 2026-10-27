import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/app_styles.dart';
import '../theme/app_tokens.dart';
import 'field_frame.dart';
import 'app_icon_button.dart';

/// A single-line desktop input, with an optional unit outside the editable text.
class AppInput extends StatefulWidget {
  const AppInput({
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.leadingIcon,
    this.suffixText,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.clearTooltip,
    this.clearable = false,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.maxLength,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? hint;
  final String? helperText;
  final String? errorText;
  final IconData? leadingIcon;
  final String? suffixText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  final VoidCallback? onClear;
  final String? clearTooltip;
  final bool clearable;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;

  @override
  State<AppInput> createState() => _AppInputState();
}

class _AppInputState extends State<AppInput> {
  late TextEditingController _controller;
  final _internalFocus = FocusNode();
  FocusNode get _focusNode => widget.focusNode ?? _internalFocus;
  bool _focused = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant AppInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      final value = _controller.value;
      _controller.removeListener(_handleTextChanged);
      if (oldWidget.controller == null) _controller.dispose();
      _controller = widget.controller ?? TextEditingController.fromValue(value);
      _controller.addListener(_handleTextChanged);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    if (widget.controller == null) _controller.dispose();
    _internalFocus.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    if (mounted) setState(() {});
  }

  void _setFocused(bool value) {
    if (mounted && _focused != value) setState(() => _focused = value);
  }

  void _setHovered(bool value) {
    if (mounted && _hovered != value) setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    final textStyle = Theme.of(context).textTheme.bodyLarge!
        .merge(AppTextStyles.control)
        .copyWith(
          leadingDistribution: TextLeadingDistribution.even,
          color: widget.enabled ? tokens.textPrimary : tokens.textDisabled,
        );
    // The hint and editor must use the same strut. Font fallback (especially
    // CJK) otherwise gives InputDecorator two different baseline metrics.
    final strutStyle = StrutStyle.fromTextStyle(
      textStyle,
      forceStrutHeight: true,
    );
    return FieldFrame(
      label: widget.label,
      helperText: widget.helperText,
      errorText: widget.errorText,
      enabled: widget.enabled,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.text
            : SystemMouseCursors.basic,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: _setFocused,
          child: TextFieldTapRegion(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.enabled ? _focusNode.requestFocus : null,
              child: FieldSurface(
                focused: _focused,
                hovered: _hovered,
                pressed: false,
                enabled: widget.enabled,
                hasError: widget.errorText != null,
                child: Row(
                  children: [
                    if (widget.leadingIcon != null) ...[
                      Icon(
                        widget.leadingIcon,
                        size: 18,
                        color: widget.enabled
                            ? tokens.textTertiary
                            : tokens.textDisabled,
                      ),
                      const SizedBox(width: AppTokens.space2),
                    ],
                    Expanded(
                      child: Semantics(
                        label: widget.label,
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          enabled: widget.enabled,
                          readOnly: widget.readOnly,
                          autofocus: widget.autofocus,
                          obscureText: widget.obscureText,
                          keyboardType: widget.keyboardType,
                          textInputAction: widget.textInputAction,
                          inputFormatters: widget.inputFormatters,
                          maxLength: widget.maxLength,
                          onChanged: widget.onChanged,
                          onSubmitted: widget.onSubmitted,
                          textAlignVertical: TextAlignVertical.center,
                          style: textStyle,
                          strutStyle: strutStyle,
                          cursorColor: tokens.accentStrong,
                          decoration: InputDecoration(
                            // FieldSurface owns the control geometry. Material's
                            // desktop compact density shifts a collapsed input by 4px.
                            visualDensity: VisualDensity.standard,
                            counterText: '',
                            hint: widget.hint == null
                                ? null
                                : Text(
                                    widget.hint!,
                                    style: textStyle.copyWith(
                                      color: widget.enabled
                                          ? tokens.textTertiary
                                          : tokens.textDisabled,
                                    ),
                                    strutStyle: strutStyle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            isDense: true,
                            isCollapsed: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            filled: false,
                          ),
                        ),
                      ),
                    ),
                    if (widget.suffixText != null) ...[
                      const SizedBox(width: AppTokens.space2),
                      Text(
                        widget.suffixText!,
                        style: AppTextStyles.control.copyWith(
                          color: widget.enabled
                              ? tokens.textSecondary
                              : tokens.textDisabled,
                        ),
                      ),
                    ],
                    if ((widget.clearable || widget.onClear != null) &&
                        widget.enabled &&
                        !widget.readOnly) ...[
                      const SizedBox(width: AppTokens.space1),
                      TextFieldTapRegion(
                        child: SizedBox.square(
                          dimension: AppTokens.iconButtonSize,
                          child: _controller.text.isEmpty
                              ? null
                              : AppIconButton(
                                  key: const ValueKey('appInput.clearButton'),
                                  icon: FluentIcons.dismiss_16_regular,
                                  iconSize: 16,
                                  tooltip:
                                      widget.clearTooltip ??
                                      MaterialLocalizations.of(context)
                                          .deleteButtonTooltip,
                                  onPressed: () {
                                    _controller.clear();
                                    widget.onChanged?.call('');
                                    widget.onClear?.call();
                                    _focusNode.requestFocus();
                                  },
                                ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
