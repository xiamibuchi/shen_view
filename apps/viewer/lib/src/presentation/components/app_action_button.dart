import 'package:flutter/material.dart';

/// A command with custom content, using a shared command or menu style.
class AppActionButton extends StatelessWidget {
  const AppActionButton({
    required this.child,
    required this.onPressed,
    required this.style,
    super.key,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final ButtonStyle style;

  @override
  Widget build(BuildContext context) =>
      TextButton(onPressed: onPressed, style: style, child: child);
}
