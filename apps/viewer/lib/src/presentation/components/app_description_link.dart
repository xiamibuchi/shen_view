import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_styles.dart';
import '../theme/app_theme.dart';
import 'app_search_text.dart';

/// A description with one inline navigation link and no pointer state effects.
class AppDescriptionLink extends StatefulWidget {
  const AppDescriptionLink({
    required this.text,
    required this.linkText,
    required this.linkLabel,
    required this.onPressed,
    this.linkKey,
    super.key,
  });

  final String text;
  final String linkText;
  final String linkLabel;
  final VoidCallback onPressed;
  final Key? linkKey;

  @override
  State<AppDescriptionLink> createState() => _AppDescriptionLinkState();
}

class _AppDescriptionLinkState extends State<AppDescriptionLink> {
  bool _showFocus = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    final style = AppTextStyles.label.copyWith(
      color: tokens.textTertiary,
      height: 1.5,
    );
    final start = widget.text.indexOf(widget.linkText);
    if (widget.linkText.isEmpty || start < 0) {
      return AppSearchText(widget.text, style: style);
    }
    return Text.rich(
      TextSpan(
        children: [
          AppSearchText.spanFor(context, widget.text.substring(0, start)),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Semantics(
              link: true,
              label: widget.linkLabel,
              onTap: widget.onPressed,
              excludeSemantics: true,
              child: FocusableActionDetector(
                mouseCursor: SystemMouseCursors.click,
                onShowFocusHighlight: (value) =>
                    setState(() => _showFocus = value),
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                },
                actions: {
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) => widget.onPressed(),
                  ),
                },
                child: GestureDetector(
                  key: widget.linkKey,
                  onTap: widget.onPressed,
                  child: AppSearchText(
                    widget.linkText,
                    style: style.copyWith(
                      color: tokens.accentStrong,
                      decoration: _showFocus ? TextDecoration.underline : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
          AppSearchText.spanFor(
            context,
            widget.text.substring(start + widget.linkText.length),
          ),
        ],
      ),
      style: style,
    );
  }
}
