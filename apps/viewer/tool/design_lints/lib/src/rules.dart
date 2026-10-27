// custom_lint 0.8.1 exposes ErrorReporter while analyzer 8 marks the legacy
// type as deprecated; the plugin API still requires it.
// ignore_for_file: deprecated_member_use

import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

const _presentationPrefix = 'lib/src/presentation/';
const _foundationPrefixes = <String>[
  'lib/src/presentation/components/',
  'lib/src/presentation/theme/',
];

String _normalizedPath(String path) => path.replaceAll('\\', '/');

bool _isDesignCheckedFile(String path) {
  final normalized = _normalizedPath(path);
  if (!normalized.contains('/lib/src/presentation/') &&
      !normalized.startsWith(_presentationPrefix)) {
    return false;
  }
  if (_foundationPrefixes.any(normalized.contains)) return false;
  return true;
}

abstract class _PresentationLint extends DartLintRule {
  const _PresentationLint({required super.code});

  bool shouldCheck(CustomLintResolver resolver) =>
      _isDesignCheckedFile(resolver.path);
}

class NoRawColorLint extends _PresentationLint {
  const NoRawColorLint() : super(code: _code);

  static const _code = LintCode(
    name: 'design_no_raw_color',
    problemMessage:
        'Use a semantic ViewerThemeTokens color instead of a raw color.',
    correctionMessage:
        'Read the color from ViewerThemeTokens.of(context) or AppTokens.',
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    if (!shouldCheck(resolver)) return;
    context.registry.addSimpleIdentifier((node) {
      if (node.name == 'Colors') reporter.atNode(node, code);
    });
    context.registry.addInstanceCreationExpression((node) {
      final source = node.toSource();
      if (RegExp(r'^(const )?Color(?:\.|\()').hasMatch(source)) {
        reporter.atNode(node, code);
      }
    });
  }
}

class NoRawMaterialControlLint extends _PresentationLint {
  const NoRawMaterialControlLint() : super(code: _code);

  static const _code = LintCode(
    name: 'design_no_raw_material_control',
    problemMessage:
        'Use a ShenView form component instead of a raw Material control.',
    correctionMessage:
        'Prefer AppButton, AppInput, AppSelect, AppSwitch, or AppTabSwitch.',
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    if (!shouldCheck(resolver)) return;
    context.registry.addInstanceCreationExpression((node) {
      final type = node.constructorName.type.toSource().split('<').first;
      if (_rawMaterialControls.contains(type)) reporter.atNode(node, code);
    });
  }
}

const _rawMaterialControls = <String>{
  'DropdownButton',
  'DropdownButtonFormField',
  'ElevatedButton',
  'FilledButton',
  'OutlinedButton',
  'TextButton',
  'Switch',
  'TabBar',
  'TextField',
  'IconButton',
  'Slider',
  'SegmentedButton',
};

class NoInlineStyleLint extends _PresentationLint {
  const NoInlineStyleLint() : super(code: _code);

  static const _code = LintCode(
    name: 'design_no_inline_style',
    problemMessage: 'Use shared typography, control, or slider styles.',
    correctionMessage:
        'Use AppTextStyles, AppControlStyles, or a shared component.',
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    if (!shouldCheck(resolver)) return;
    context.registry.addInstanceCreationExpression((node) {
      final type = node.constructorName.type.toSource().split('<').first;
      if (const {
        'TextStyle',
        'ButtonStyle',
        'MenuStyle',
        'SliderTheme',
        'SliderThemeData',
      }.contains(type)) {
        reporter.atNode(node, code);
      }
    });
  }
}

class NoLegacyIconLint extends _PresentationLint {
  const NoLegacyIconLint() : super(code: _code);

  static const _code = LintCode(
    name: 'design_no_legacy_icon',
    problemMessage: 'Use a Fluent UI System Icon for new presentation code.',
    correctionMessage:
        'Import fluentui_system_icons and use a FluentIcons glyph.',
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    if (!shouldCheck(resolver)) return;
    context.registry.addSimpleIdentifier((node) {
      if (node.name == 'Icons') reporter.atNode(node, code);
    });
  }
}
