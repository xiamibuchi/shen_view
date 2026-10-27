import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Opt-in search highlighting. Outside this scope text renders normally.
class AppSearchScope extends InheritedWidget {
  const AppSearchScope({required this.query, required super.child, super.key});

  final String query;

  static String queryOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppSearchScope>()?.query ?? '';

  static List<String> terms(String query) => query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toSet()
      .toList();

  @override
  bool updateShouldNotify(AppSearchScope oldWidget) => query != oldWidget.query;
}

/// Preserves typography and semantics while marking literal search matches.
class AppSearchText extends StatelessWidget {
  const AppSearchText(
    this.data, {
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    super.key,
  });

  final String data;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  static TextSpan spanFor(BuildContext context, String data) {
    final terms = AppSearchScope.terms(AppSearchScope.queryOf(context));
    final ranges = <(int, int)>[];
    // Case-insensitive regex keeps offsets in the original string, including
    // Unicode characters whose lowercase form has a different UTF-16 length.
    for (final term in terms) {
      for (final match in RegExp(
        RegExp.escape(term),
        caseSensitive: false,
        unicode: true,
      ).allMatches(data)) {
        ranges.add((match.start, match.end));
      }
    }
    if (ranges.isEmpty) {
      return TextSpan(text: data);
    }
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final range in ranges) {
      if (merged.isNotEmpty && range.$1 <= merged.last.$2) {
        final previous = merged.removeLast();
        merged.add((
          previous.$1,
          range.$2 > previous.$2 ? range.$2 : previous.$2,
        ));
      } else {
        merged.add(range);
      }
    }
    final tokens = ViewerThemeTokens.of(context);
    final highlight = TextStyle(
      color: tokens.textPrimary,
      backgroundColor: tokens.accent.withValues(alpha: 0.22),
    );
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final (start, end) in merged) {
      if (start > offset) {
        spans.add(TextSpan(text: data.substring(offset, start)));
      }
      spans.add(TextSpan(text: data.substring(start, end), style: highlight));
      offset = end;
    }
    if (offset < data.length) spans.add(TextSpan(text: data.substring(offset)));
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final span = spanFor(context, data);
    if (span.children == null) {
      return Text(
        data,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );
    }
    return Text.rich(
      span,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}
