import 'components/app_backdrop_surface.dart';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

import 'components/app_icon_button.dart';
import 'components/app_slider.dart';
import 'components/app_tab_switch.dart';
import 'theme/app_styles.dart';
import 'theme/app_theme.dart';
import 'theme/demo_image_palette.dart';

enum _DemoViewMode { single, doublePage, longImage, comic }

class ThemeDemoPage extends StatefulWidget {
  const ThemeDemoPage({super.key});

  @override
  State<ThemeDemoPage> createState() => _ThemeDemoPageState();
}

class _ThemeDemoPageState extends State<ThemeDemoPage> {
  bool _floatingNavigation = false;
  _DemoViewMode _viewMode = _DemoViewMode.single;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.dark(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${AppLocalizations.of(context)!.appTitle} · Light / Dark 设计预览',
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final controls = Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('导航栏', style: AppTextStyles.label),
                AppTabSwitch<bool>(
                  options: const [
                    AppTabOption(value: false, label: '普通'),
                    AppTabOption(value: true, label: '悬浮'),
                  ],
                  value: _floatingNavigation,
                  onChanged: (value) =>
                      setState(() => _floatingNavigation = value),
                ),
                const Text('内容模式', style: AppTextStyles.label),
                AppTabSwitch<_DemoViewMode>(
                  options: const [
                    AppTabOption(value: _DemoViewMode.single, label: '单页'),
                    AppTabOption(value: _DemoViewMode.doublePage, label: '双页'),
                    AppTabOption(value: _DemoViewMode.longImage, label: '长图'),
                    AppTabOption(value: _DemoViewMode.comic, label: '漫画'),
                  ],
                  value: _viewMode,
                  onChanged: (value) => setState(() => _viewMode = value),
                ),
                const Text('视觉基准 · 仅用于评审', style: AppTextStyles.label),
              ],
            );
            final previews = [
              _ThemePreview(
                title: 'Light',
                subtitle: '浅色主题 · 适合明亮环境',
                theme: AppTheme.light(),
                isLight: true,
                floatingNavigation: _floatingNavigation,
                viewMode: _viewMode,
              ),
              _ThemePreview(
                title: 'Dark',
                subtitle: '深色主题 · 保持图片视觉重量',
                theme: AppTheme.dark(),
                isLight: false,
                floatingNavigation: _floatingNavigation,
                viewMode: _viewMode,
              ),
            ];
            final wide = constraints.maxWidth >= 1050;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  controls,
                  const SizedBox(height: 24),
                  wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: previews[0]),
                            const SizedBox(width: 24),
                            Expanded(child: previews[1]),
                          ],
                        )
                      : Column(
                          children: [
                            previews[0],
                            const SizedBox(height: 24),
                            previews[1],
                          ],
                        ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({
    required this.title,
    required this.subtitle,
    required this.theme,
    required this.isLight,
    required this.floatingNavigation,
    required this.viewMode,
  });

  final String title;
  final String subtitle;
  final ThemeData theme;
  final bool isLight;
  final bool floatingNavigation;
  final _DemoViewMode viewMode;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          final tokens = ViewerThemeTokens.of(context);
          return Container(
            height: 700,
            decoration: BoxDecoration(
              color: tokens.appBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tokens.border),
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadow.withValues(
                    alpha: isLight ? 0.12 : 0.28,
                  ),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _PreviewHeader(title: title, subtitle: subtitle),
                Expanded(
                  child: _PreviewViewer(
                    isLight: isLight,
                    floatingNavigation: floatingNavigation,
                    viewMode: viewMode,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: tokens.accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              FluentIcons.image_24_regular,
              size: 17,
              color: tokens.onAccent,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: AppTextStyles.finePrint.copyWith(
                  color: tokens.textTertiary,
                ),
              ),
            ],
          ),
          const Spacer(),
          _SmallIconButton(
            icon: FluentIcons.more_horizontal_20_regular,
            tooltip: '更多',
          ),
        ],
      ),
    );
  }
}

class _PreviewViewer extends StatelessWidget {
  const _PreviewViewer({
    required this.isLight,
    required this.floatingNavigation,
    required this.viewMode,
  });

  final bool isLight;
  final bool floatingNavigation;
  final _DemoViewMode viewMode;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: _PreviewBody(isLight: isLight, viewMode: viewMode),
              ),
              _PreviewThumbnails(),
            ],
          ),
        ),
        const _PreviewInfoPanel(),
      ],
    );

    return Column(
      children: [
        if (!floatingNavigation) const _PreviewNavigation(),
        Expanded(
          child: Stack(
            children: [
              content,
              if (floatingNavigation)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _PreviewNavigation(floating: true),
                ),
            ],
          ),
        ),
        _PreviewStatusBar(),
      ],
    );
  }
}

class _PreviewNavigation extends StatelessWidget {
  const _PreviewNavigation({this.floating = false});

  final bool floating;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),

      child: Row(
        children: [
          _SmallIconButton(
            icon: FluentIcons.arrow_rotate_clockwise_20_regular,
            tooltip: '顺时针旋转',
          ),
          _SmallIconButton(icon: FluentIcons.copy_20_regular, tooltip: '水平翻转'),
          _SmallIconButton(icon: FluentIcons.crop_20_regular, tooltip: '打印'),
          _SmallIconButton(
            icon: FluentIcons.more_horizontal_20_regular,
            tooltip: '设置',
          ),
          const Spacer(),
          _ToolbarLabel(label: 'sample.heic'),
          const Spacer(),
          const _PreviewSortControl(),
          _SmallIconButton(
            icon: FluentIcons.panel_right_20_regular,
            tooltip: '窗口置顶',
          ),
          _SmallIconButton(
            icon: FluentIcons.chevron_left_20_regular,
            tooltip: '最小化',
          ),
          _SmallIconButton(
            icon: FluentIcons.full_screen_maximize_16_regular,
            tooltip: '最大化',
          ),
          _SmallIconButton(icon: FluentIcons.dismiss_16_regular, tooltip: '关闭'),
        ],
      ),
    );
    return AppBackdropSurface(active: floating, child: content);
  }
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({required this.isLight, required this.viewMode});

  final bool isLight;
  final _DemoViewMode viewMode;

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    Widget image() => DecoratedBox(
      decoration: BoxDecoration(color: tokens.canvasBackground),
      child: CustomPaint(painter: _DemoImagePainter(isLight: isLight)),
    );

    final content = switch (viewMode) {
      _DemoViewMode.single => FractionallySizedBox(
        widthFactor: .86,
        heightFactor: .72,
        child: AspectRatio(aspectRatio: 1.45, child: image()),
      ),
      _DemoViewMode.doublePage => FractionallySizedBox(
        widthFactor: .86,
        heightFactor: .72,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: image()),
            const SizedBox(width: 2),
            Expanded(child: image()),
          ],
        ),
      ),
      _DemoViewMode.longImage => FractionallySizedBox(
        widthFactor: .58,
        heightFactor: .94,
        child: image(),
      ),
      _DemoViewMode.comic => FractionallySizedBox(
        widthFactor: .92,
        heightFactor: .60,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: image()),
            const SizedBox(width: 2),
            Expanded(child: image()),
            const SizedBox(width: 2),
            Expanded(child: image()),
          ],
        ),
      ),
    };

    return Container(
      color: tokens.shellSurface,
      child: Center(child: content),
    );
  }
}

class _PreviewInfoPanel extends StatelessWidget {
  const _PreviewInfoPanel();

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    return Container(
      width: 178,
      margin: const EdgeInsets.fromLTRB(8, 8, 10, 8),
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 12),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.border.withValues(alpha: 0.65)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '信息',
                style: AppTextStyles.subtitle.copyWith(
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
              const Spacer(),
              Icon(
                FluentIcons.dismiss_16_regular,
                size: 16,
                color: tokens.textTertiary,
              ),
            ],
          ),
          Divider(color: tokens.border),
          _InfoField(label: '文件名', value: 'sample.heic'),
          _InfoField(label: '格式', value: 'HEIC'),
          _InfoField(label: '尺寸', value: '700 × 476'),
          _InfoField(label: '方向', value: 'Normal (orientation 1)'),
          _InfoField(label: '大小', value: '40.6 KB (41,574 bytes)'),
          _InfoField(label: '修改时间', value: '2026-10-15 04:02'),
          const SizedBox(height: 4),
          Text(
            '路径',
            style: AppTextStyles.finePrint.copyWith(color: tokens.textTertiary),
          ),
          const SizedBox(height: 2),
          Text(
            'Pictures/sample.heic',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.finePrint.copyWith(color: tokens.accentStrong),
          ),
          const Divider(height: 24),
          Text(
            '其他元数据',
            style: AppTextStyles.finePrint.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '无附加元数据',
            style: AppTextStyles.finePrint.copyWith(color: tokens.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _InfoField extends StatelessWidget {
  const _InfoField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.finePrint.copyWith(color: tokens.textTertiary),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.label.copyWith(color: tokens.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _PreviewStatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tokens.shellSurface,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          _SmallIconButton(
            icon: FluentIcons.panel_right_20_regular,
            tooltip: '显示/隐藏缩略图',
          ),
          const SizedBox(width: 2),
          Icon(
            FluentIcons.image_16_regular,
            size: 14,
            color: tokens.textTertiary,
          ),
          const SizedBox(width: 5),
          Text(
            'HEIC',
            style: AppTextStyles.finePrint.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            '700 × 476',
            style: AppTextStyles.finePrint.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          const Spacer(),
          _SmallIconButton(
            icon: FluentIcons.image_16_regular,
            tooltip: '显示/隐藏信息',
          ),
          const Spacer(),
          _SmallIconButton(icon: FluentIcons.crop_20_regular, tooltip: '适应窗口'),
          Text(
            '1×',
            style: AppTextStyles.finePrint.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          _SmallIconButton(
            icon: FluentIcons.chevron_left_20_regular,
            tooltip: '缩小',
          ),
          SizedBox(
            width: 74,
            child: AppSlider(
              variant: AppSliderVariant.demo,
              value: .55,
              onChanged: (_) {},
            ),
          ),
          _SmallIconButton(
            icon: FluentIcons.chevron_right_20_regular,
            tooltip: '放大',
          ),
          _SmallIconButton(
            icon: FluentIcons.full_screen_maximize_20_regular,
            tooltip: '全屏',
          ),
        ],
      ),
    );
  }
}

class _PreviewThumbnails extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    return Container(
      height: 88,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: tokens.shellSurface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < 5; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  width: 90,
                  height: 70,
                  decoration: BoxDecoration(
                    color: tokens.canvasBackground,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: i == 0 ? tokens.accent : tokens.border,
                      width: i == 0 ? 2 : 1,
                    ),
                  ),
                  child: CustomPaint(
                    painter: _DemoImagePainter(isLight: i.isEven),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({required this.icon, required this.tooltip});

  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) => AppIconButton(
    icon: icon,
    iconSize: 18,
    tooltip: tooltip,
    onPressed: () {},
  );
}

class _ToolbarLabel extends StatelessWidget {
  const _ToolbarLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    return Text(
      label,
      style: AppTextStyles.label.copyWith(color: tokens.textTertiary),
    );
  }
}

class _PreviewSortControl extends StatelessWidget {
  const _PreviewSortControl();

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: tokens.surfaceSubtle,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '按文件名',
            style: AppTextStyles.thumbnailText.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(width: 3),
          Icon(
            FluentIcons.chevron_down_16_regular,
            size: 13,
            color: tokens.textTertiary,
          ),
        ],
      ),
    );
  }
}

class _DemoImagePainter extends CustomPainter {
  const _DemoImagePainter({required this.isLight});

  final bool isLight;

  @override
  void paint(Canvas canvas, Size size) {
    final palette = isLight ? DemoImagePalette.light : DemoImagePalette.dark;
    final sky = Paint()
      ..shader = LinearGradient(
        colors: palette.sky,
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);
    final sun = Paint()..color = palette.sun;
    canvas.drawCircle(
      Offset(size.width * .76, size.height * .22),
      size.shortestSide * .09,
      sun,
    );
    final back = Paint()..color = palette.backMountain;
    final backPath = Path()
      ..moveTo(0, size.height * .68)
      ..lineTo(size.width * .25, size.height * .37)
      ..lineTo(size.width * .45, size.height * .65)
      ..lineTo(size.width * .68, size.height * .30)
      ..lineTo(size.width, size.height * .67)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(backPath, back);
    final front = Paint()..color = palette.frontMountain;
    final frontPath = Path()
      ..moveTo(0, size.height * .78)
      ..lineTo(size.width * .28, size.height * .54)
      ..lineTo(size.width * .50, size.height * .75)
      ..lineTo(size.width * .78, size.height * .50)
      ..lineTo(size.width, size.height * .76)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(frontPath, front);
    final ground = Paint()..color = palette.ground;
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * .82, size.width, size.height * .18),
      ground,
    );
  }

  @override
  bool shouldRepaint(covariant _DemoImagePainter oldDelegate) =>
      oldDelegate.isLight != isLight;
}
