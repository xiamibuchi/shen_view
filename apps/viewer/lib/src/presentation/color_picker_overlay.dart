import 'dart:async';
import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../application/color_picker_controller.dart';
import '../application/color_picker_service.dart';
import 'components/app_button.dart';
import 'components/app_icon_button.dart';
import 'components/app_select.dart';
import 'theme/app_styles.dart';
import 'theme/app_theme.dart';
import 'theme/app_tokens.dart';

String colorPickerCopy(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

String colorSampleLabel(BuildContext context, ColorPick pick) {
  final base = switch (pick.kind) {
    ColorSampleKind.srgb => 'sRGB',
    ColorSampleKind.sdrMapped => colorPickerCopy(
      context,
      'sRGB · SDR 映射',
      'sRGB · SDR mapped',
    ),
    ColorSampleKind.sdrBase => colorPickerCopy(
      context,
      'sRGB · SDR 基础图',
      'sRGB · SDR base',
    ),
    ColorSampleKind.svg => colorPickerCopy(
      context,
      'sRGB · SVG 栅格',
      'sRGB · SVG raster',
    ),
  };
  return '$base · ${pick.previewOnly ? colorPickerCopy(context, '预览采样', 'Preview sample') : '1×1'}';
}

class ColorPickerOverlay extends StatefulWidget {
  const ColorPickerOverlay({
    required this.controller,
    required this.onClose,
    required this.onFormatChanged,
    this.bottomInset = 0,
    super.key,
  });
  final ColorPickerController controller;
  final VoidCallback onClose;
  final ValueChanged<ColorCopyFormat> onFormatChanged;
  final double bottomInset;
  @override
  State<ColorPickerOverlay> createState() => _ColorPickerOverlayState();
}

class _ColorPickerOverlayState extends State<ColorPickerOverlay> {
  final _helpKey = GlobalKey<TooltipState>();
  final _scrollController = ScrollController();
  ColorPickerController get c => widget.controller;
  String _t(String zh, String en) => colorPickerCopy(context, zh, en);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        if (!c.active ||
            constraints.maxWidth < 32 ||
            constraints.maxHeight < 32) {
          return const SizedBox.shrink();
        }
        final width = math.min(300.0, constraints.maxWidth - 24);
        final bottom = math.min(
          widget.bottomInset + 12,
          math.max(12.0, constraints.maxHeight - 96),
        );
        final box = context.findRenderObject() as RenderBox?;
        final compact = constraints.maxHeight - bottom - 12 < 300;
        final pointer = c.pointer == null || box == null || !box.hasSize
            ? null
            : box.globalToLocal(c.pointer!);
        final hover = c.hover;
        return Stack(
          children: [
            if (hover != null &&
                pointer != null &&
                constraints.maxWidth > 200 &&
                constraints.maxHeight > 220)
              _magnifier(hover, pointer, constraints.biggest, width, bottom),
            Positioned(
              key: const ValueKey('colorPicker.panel'),
              right: 12,
              bottom: bottom,
              width: width,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.max(1, constraints.maxHeight - bottom - 12),
                ),
                child: _surface(
                  Padding(
                    padding: EdgeInsets.all(compact ? 8 : 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _header(),
                        Flexible(
                          child: SingleChildScrollView(
                            key: const ValueKey('colorPicker.scroll'),
                            controller: _scrollController,
                            child: _card(compact: compact),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _surface(Widget child) {
    final tokens = ViewerThemeTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AppTokens.containerRadius),
        border: Border.all(color: tokens.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withValues(alpha: 0.16),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  String _helpText(ColorPick? pick) => [
    _t(
      '单击锁定颜色；方向键微调；Ctrl/Cmd+C 复制；Esc 退出。',
      'Click to lock; arrows to adjust; Ctrl/Cmd+C to copy; Esc to exit.',
    ),
    _t(
      'sRGB 表示颜色空间；1×1 表示读取单个像素，不是区域平均。X/Y 从 0 开始。',
      'sRGB is the color space; 1×1 samples one pixel, not an area average. X/Y start at 0.',
    ),
    if (pick != null) colorSampleLabel(context, pick),
    _t(
      '全透明像素的隐藏 RGB 可能已被解码器丢弃。最近拾取的颜色在不同图片和窗口间共享，重启后仍会保留。',
      'Decoders may discard hidden RGB in fully transparent pixels. Recent colors are shared across images and windows, and kept after restarting.',
    ),
    if (c.format == ColorCopyFormat.yuv)
      _t(
        'YUV 使用 BT.601 亮度系数。Y 的范围为 0 到 1，U/V 为以 0 为中心的色差值，均不是视频编码值。',
        'YUV uses BT.601 luma coefficients. Y ranges from 0 to 1; U/V are color differences centered at zero. These are not video code values.',
      ),
  ].join('\n');

  Widget _header() => Row(
    children: [
      Icon(
        FluentIcons.eyedropper_20_regular,
        size: 18,
        color: ViewerThemeTokens.of(context).accent,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Row(
          children: [
            Flexible(
              child: Text(
                _t('颜色拾取', 'Color picker'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.compactTitle,
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              key: _helpKey,
              message: _helpText(c.selected),
              child: AppIconButton(
                key: const ValueKey('colorPicker.help'),
                icon: FluentIcons.info_20_regular,
                tooltip: '',
                onPressed: () => _helpKey.currentState?.ensureTooltipVisible(),
              ),
            ),
          ],
        ),
      ),
      AppIconButton(
        key: const ValueKey('colorPicker.close'),
        icon: FluentIcons.dismiss_20_regular,
        tooltip: _t('退出取色（Esc）', 'Exit color picker (Esc)'),
        onPressed: widget.onClose,
      ),
    ],
  );

  Widget _card({required bool compact}) {
    final tokens = ViewerThemeTokens.of(context);
    final gap = compact ? 8.0 : 12.0;
    final pick = c.selected;
    final color = c.color;
    return Column(
      key: const ValueKey('colorPicker.card'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (c.sampleFailed) ...[
          SizedBox(height: gap),
          Text(
            _t(
              '无法读取当前像素，请移到图片上重试。',
              'Unable to read this pixel. Move over the image to retry.',
            ),
            style: AppTextStyles.caption.copyWith(color: tokens.danger),
          ),
        ],
        SizedBox(height: gap),
        if (color == null)
          Text(
            _t(
              '将指针移到图片上预览，单击保留颜色。',
              'Move over the image to preview, then click to keep a color.',
            ),
            style: AppTextStyles.bodySmall.copyWith(
              color: tokens.textSecondary,
            ),
          )
        else ...[
          Row(
            children: [
              ColorSwatchPreview(color: color, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pick == null
                          ? _t('已选颜色', 'Selected color')
                          : 'X ${pick.x}   Y ${pick.y}',
                      key: const ValueKey('colorPicker.position'),
                      style: AppTextStyles.code,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_t('不透明度 ', 'Opacity ')}${color.opacity}',
                      key: const ValueKey('colorPicker.opacity'),
                      style: AppTextStyles.caption.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (pick != null &&
              (pick.previewOnly || pick.kind != ColorSampleKind.srgb)) ...[
            SizedBox(height: gap),
            Text(
              colorSampleLabel(context, pick),
              key: const ValueKey('colorPicker.source'),
              style: AppTextStyles.finePrint.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          ],
          SizedBox(height: gap),
          Row(
            children: [
              SizedBox(
                width: 100,
                child: AppSelect<ColorCopyFormat>(
                  key: const ValueKey('colorPicker.format'),
                  value: c.format,
                  options: [
                    for (final format in ColorCopyFormat.values)
                      AppSelectOption(
                        value: format,
                        label: format.name.toUpperCase(),
                      ),
                  ],
                  onChanged: (format) {
                    c.setFormat(format);
                    widget.onFormatChanged(format);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  key: const ValueKey('colorPicker.copy'),
                  label: c.copiedValue == color.format(c.format)
                      ? _t('已复制', 'Copied')
                      : _t('复制', 'Copy'),
                  leadingIcon: c.copiedValue == color.format(c.format)
                      ? FluentIcons.checkmark_20_regular
                      : FluentIcons.copy_20_regular,
                  onPressed: () => unawaited(c.copy()),
                ),
              ),
            ],
          ),
          SizedBox(height: gap),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: SelectableText(
              color.format(c.format),
              key: const ValueKey('colorPicker.value'),
              style: AppTextStyles.code,
            ),
          ),
          Divider(height: gap, color: tokens.border),
          for (final format in const [
            ColorCopyFormat.hex,
            ColorCopyFormat.rgba,
            ColorCopyFormat.hsl,
          ])
            _quickCopyRow(color, format),
          if (c.copyFailed)
            Text(
              _t('复制失败，请重试。', 'Copy failed. Please retry.'),
              style: AppTextStyles.caption.copyWith(color: tokens.danger),
            ),
        ],
        if (c.recent.isNotEmpty) ...[
          SizedBox(height: gap),
          Text(
            _t('最近拾取', 'Recent colors'),
            style: AppTextStyles.finePrint.copyWith(color: tokens.textTertiary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final recent in c.recent)
                AppIconButton(
                  key: ValueKey('colorPicker.recent.${recent.hexAlpha}'),
                  size: 28,
                  tooltip: recent.hexAlpha,
                  iconWidget: ColorSwatchPreview(color: recent, size: 24),
                  onPressed: () => c.chooseRecent(recent),
                ),
            ],
          ),
        ],
        if (c.historyFailed) ...[
          SizedBox(height: gap),
          Text(
            _t(
              '最近颜色同步失败，重新进入取色可重试。',
              'Recent colors could not sync. Reopen the picker to retry.',
            ),
            style: AppTextStyles.caption.copyWith(color: tokens.danger),
          ),
        ],
      ],
    );
  }

  Widget _quickCopyRow(PickedColor color, ColorCopyFormat format) {
    final tokens = ViewerThemeTokens.of(context);
    final value = color.format(format);
    final label = format.name.toUpperCase();
    return ConstrainedBox(
      key: ValueKey('colorPicker.quick.${format.name}'),
      constraints: const BoxConstraints(minHeight: 40),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SelectableText(
              value,
              style: AppTextStyles.code.copyWith(color: tokens.textSecondary),
            ),
          ),
          const SizedBox(width: 4),
          AppIconButton(
            key: ValueKey('colorPicker.quickCopy.${format.name}'),
            icon: c.copiedValue == value
                ? FluentIcons.checkmark_20_regular
                : FluentIcons.copy_20_regular,
            size: 28,
            iconSize: 16,
            tooltip: _t('复制 $label', 'Copy $label'),
            onPressed: () => unawaited(c.copy(format)),
          ),
        ],
      ),
    );
  }

  Widget _magnifier(
    ColorPick pick,
    Offset pointer,
    Size canvas,
    double cardWidth,
    double bottom,
  ) {
    const width = 164.0, height = 198.0;
    var left = pointer.dx + 24, top = pointer.dy + 24;
    if (left + width > canvas.width - 12) left = pointer.dx - width - 24;
    if (top + height > canvas.height - 12) top = pointer.dy - height - 24;
    left = left.clamp(12.0, math.max(12.0, canvas.width - width - 12));
    top = top.clamp(12.0, math.max(12.0, canvas.height - height - 12));
    final cardRect = Rect.fromLTWH(
      canvas.width - cardWidth - 12,
      math.max(0, canvas.height - bottom - 390),
      cardWidth,
      390,
    );
    if (cardRect.overlaps(Rect.fromLTWH(left, top, width, height)) &&
        pointer.dx - width - 24 >= 12) {
      left = pointer.dx - width - 24;
    }
    return Positioned(
      left: left,
      top: top,
      width: width,
      child: IgnorePointer(
        child: _surface(
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: CustomPaint(
                    key: const ValueKey('colorPicker.magnifier'),
                    painter: _PixelPatchPainter(
                      pick.patch,
                      ViewerThemeTokens.of(context),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(pick.color.hex, style: AppTextStyles.code),
                Text(
                  '${pick.x}, ${pick.y}${pick.previewOnly ? ' · ${_t('预览', 'Preview')}' : ''}',
                  style: AppTextStyles.finePrint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ColorSwatchPreview extends StatelessWidget {
  const ColorSwatchPreview({required this.color, this.size = 32, super.key});
  final PickedColor color;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _PixelPatchPainter(
        ColorSamplePatch(
          List.filled(ColorSamplePatch.side * ColorSamplePatch.side, color),
        ),
        ViewerThemeTokens.of(context),
        swatch: true,
      ),
    ),
  );
}

class _PixelPatchPainter extends CustomPainter {
  const _PixelPatchPainter(this.patch, this.tokens, {this.swatch = false});
  final ColorSamplePatch patch;
  final ViewerThemeTokens tokens;
  final bool swatch;
  @override
  void paint(Canvas canvas, Size size) {
    final tile = swatch ? size.width / 4 : size.width / ColorSamplePatch.side;
    for (var y = 0; y < (size.height / tile).ceil(); y++) {
      for (var x = 0; x < (size.width / tile).ceil(); x++) {
        canvas.drawRect(
          Rect.fromLTWH(x * tile, y * tile, tile, tile),
          Paint()
            ..color = (x + y).isEven
                ? tokens.surfaceSubtle
                : tokens.borderStrong,
        );
      }
    }
    if (swatch) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = AppImageColors.sampled(patch.color),
      );
    } else {
      final step = size.width / ColorSamplePatch.side;
      for (var i = 0; i < patch.pixels.length; i++) {
        final color = patch.pixels[i];
        if (color == null) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            (i % ColorSamplePatch.side) * step,
            (i ~/ ColorSamplePatch.side) * step,
            step,
            step,
          ),
          Paint()
            ..isAntiAlias = false
            ..color = AppImageColors.sampled(color),
        );
      }
      final grid = Paint()
        ..color = tokens.borderStrong.withValues(alpha: 0.45)
        ..strokeWidth = 0.5;
      for (var i = 1; i < ColorSamplePatch.side; i++) {
        canvas.drawLine(
          Offset(i * step, 0),
          Offset(i * step, size.height),
          grid,
        );
        canvas.drawLine(
          Offset(0, i * step),
          Offset(size.width, i * step),
          grid,
        );
      }
      final center = Rect.fromLTWH(
        ColorSamplePatch.radius * step,
        ColorSamplePatch.radius * step,
        step,
        step,
      );
      canvas.drawRect(
        center.inflate(1),
        Paint()
          ..color = tokens.surfaceElevated
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      canvas.drawRect(
        center,
        Paint()
          ..color = tokens.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    canvas.drawRect(
      (Offset.zero & size).deflate(0.5),
      Paint()
        ..color = tokens.borderStrong
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_PixelPatchPainter oldDelegate) =>
      patch != oldDelegate.patch ||
      tokens != oldDelegate.tokens ||
      swatch != oldDelegate.swatch;
}
