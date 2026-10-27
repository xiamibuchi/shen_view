import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:shen_view/src/presentation/components/form_components.dart';
import 'package:shen_view/src/presentation/components/app_interactive_surface.dart';
import 'package:shen_view/src/presentation/components/app_notification.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:window_manager/window_manager.dart';

/// Run with flutter run -d windows -t tool/form_components_demo.dart.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: 'Form components',
      size: Size(1120, 900),
      minimumSize: Size(800, 600),
      titleBarStyle: TitleBarStyle.normal,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  runApp(const FormComponentsDemo());
}

class FormComponentsDemo extends StatefulWidget {
  const FormComponentsDemo({
    this.dark = true,
    this.platform,
    this.textScale = 1,
    super.key,
  });

  final bool dark;
  final TargetPlatform? platform;
  final double textScale;

  @override
  State<FormComponentsDemo> createState() => _FormComponentsDemoState();
}

class _FormComponentsDemoState extends State<FormComponentsDemo> {
  late bool dark = widget.dark;
  bool filenames = true;
  bool recursive = false;
  String fit = 'contain';
  String mode = 'single';
  String status = '所有控件都可交互';
  final margin = TextEditingController(text: '20');
  final search = TextEditingController(text: '风景 Landscape');
  final notifications = AppNotificationController();
  final numberFormatter = AppNumberInputFormatter(
    integerDigits: 2,
    decimalPlaces: 1,
  );
  String? marginError;

  @override
  void dispose() {
    margin.dispose();
    search.dispose();
    notifications.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(platform: widget.platform),
    darkTheme: AppTheme.dark(platform: widget.platform),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(widget.textScale)),
      child: child!,
    ),
    home: Builder(
      builder: (context) {
        final tokens = ViewerThemeTokens.of(context);
        return AppNotificationHost(
          controller: notifications,
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '表单组件',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w600,
                                    color: tokens.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '统一尺寸、主题颜色与桌面交互',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: tokens.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AppButton(
                            label: dark ? '切换浅色' : '切换深色',
                            variant: AppButtonVariant.neutral,
                            onPressed: () => setState(() => dark = !dark),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      _section(context, 'Search · 搜索与清空', [
                        AppInput(
                          key: const ValueKey('demo.search'),
                          controller: search,
                          hint: '搜索名称或路径',
                          leadingIcon: FluentIcons.search_20_regular,
                          clearable: true,
                          clearTooltip: '清空搜索',
                        ),
                      ]),
                      _section(context, 'Button · 操作按钮', [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            AppButton(
                              label: '保存设置',
                              leadingIcon: FluentIcons.save_20_regular,
                              onPressed: () => setState(() => status = '设置已保存'),
                            ),
                            AppButton(
                              label: '取消',
                              variant: AppButtonVariant.neutral,
                              onPressed: () => setState(() => status = '已取消'),
                            ),
                            AppButton(
                              label: '了解更多',
                              variant: AppButtonVariant.subtle,
                              onPressed: () {},
                            ),
                            AppButton(
                              label: '删除',
                              variant: AppButtonVariant.danger,
                              onPressed: () =>
                                  setState(() => status = '危险按钮示例'),
                            ),
                            const AppButton(label: '不可用'),
                            const AppButton(label: '处理中', busy: true),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          status,
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.textTertiary,
                          ),
                        ),
                      ]),
                      _section(context, 'Select / Input · 相同高度与文字基线', [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: AppSelect<String>(
                                key: const ValueKey('demo-select'),
                                label: '适应方式',
                                value: fit,
                                options: const [
                                  AppSelectOption(
                                    value: 'contain',
                                    label: '适应页面',
                                  ),
                                  AppSelectOption(
                                    value: 'cover',
                                    label: '填充页面',
                                  ),
                                  AppSelectOption(
                                    value: 'original',
                                    label: '实际大小',
                                  ),
                                  AppSelectOption(
                                    value: 'disabled',
                                    label: '不可用选项',
                                    enabled: false,
                                  ),
                                ],
                                onChanged: (value) =>
                                    setState(() => fit = value),
                                helperText: '保留完整图片，按可打印区域缩放。',
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: AppInput(
                                label: '自定义页边距',
                                controller: margin,
                                suffixText: 'mm',
                                helperText: '0–50 mm，最多 1 位小数',
                                errorText: marginError,
                                inputFormatters: [numberFormatter],
                                onChanged: (text) => setState(() {
                                  final value = double.tryParse(text);
                                  marginError =
                                      value == null || value < 0 || value > 50
                                      ? '请输入 0–50 之间的数字。'
                                      : null;
                                }),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Expanded(
                              child: AppInput(
                                label: '错误提示',
                                hint: '请输入数值',
                                errorText: '请输入 0–50 之间的数值。',
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: AppSelect<String>(
                                label: '禁用选择',
                                value: 'a4',
                                enabled: false,
                                options: const [
                                  AppSelectOption(value: 'a4', label: 'A4'),
                                ],
                                onChanged: (_) {},
                              ),
                            ),
                          ],
                        ),
                      ]),
                      _section(context, 'Switch · 独立开关', [
                        AppSwitch(
                          label: '显示文件名',
                          description: '在缩略图下方显示图片文件名。',
                          value: filenames,
                          onChanged: (value) =>
                              setState(() => filenames = value),
                        ),
                        const SizedBox(height: 12),
                        AppSwitch(
                          label: '包含子文件夹',
                          value: recursive,
                          onChanged: (value) =>
                              setState(() => recursive = value),
                        ),
                        const SizedBox(height: 12),
                        const AppSwitch(
                          label: '不可用设置',
                          value: true,
                          onChanged: null,
                        ),
                      ]),
                      _section(context, 'Tab switch · 单选分段切换', [
                        AppTabSwitch<String>(
                          showSelectedIcon: false,
                          value: mode,
                          options: const [
                            AppTabOption(
                              value: 'single',
                              label: '单页',
                              icon: FluentIcons.document_one_page_20_regular,
                            ),
                            AppTabOption(
                              value: 'double',
                              label: '双页',
                              icon: FluentIcons.copy_20_regular,
                            ),
                            AppTabOption(
                              value: 'comic',
                              label: '漫画',
                              icon: FluentIcons.book_open_20_regular,
                            ),
                          ],
                          onChanged: (value) => setState(() => mode = value),
                        ),
                      ]),
                      _section(context, 'Card · 可点击卡片', [
                        AppInteractiveSurface(
                          key: const ValueKey('demo.card'),
                          onTap: () => setState(() => status = '已打开文件信息'),
                          child: const Padding(
                            padding: EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(FluentIcons.info_20_regular, size: 20),
                                SizedBox(width: 12),
                                Expanded(child: Text('文件信息 · 悬停、按下与键盘聚焦')),
                              ],
                            ),
                          ),
                        ),
                      ]),
                      _section(context, 'Notification · 通知', [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final (type, label, message) in [
                              (AppNotificationType.success, '成功', '图片已保存'),
                              (AppNotificationType.info, '信息', '正在准备压缩包中的下一页'),
                              (
                                AppNotificationType.warning,
                                '警告',
                                '压缩包中的图片为只读，无法重命名',
                              ),
                              (AppNotificationType.error, '错误', '压缩包内没有可浏览的图片'),
                            ])
                              AppButton(
                                label: label,
                                variant: AppButtonVariant.neutral,
                                onPressed: () =>
                                    notifications.show(message, type: type),
                              ),
                          ],
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _section(BuildContext context, String title, List<Widget> children) {
    final tokens = ViewerThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaceElevated,
          border: Border.all(color: tokens.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
