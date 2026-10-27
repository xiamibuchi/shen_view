import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'src/rules.dart';

PluginBase createPlugin() => _ShenViewDesignLintPlugin();

class _ShenViewDesignLintPlugin extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => [
    const NoRawColorLint(),
    const NoRawMaterialControlLint(),
    const NoLegacyIconLint(),
    const NoInlineStyleLint(),
  ];
}
