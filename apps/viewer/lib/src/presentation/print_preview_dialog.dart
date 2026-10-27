import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../l10n/app_localizations.dart';
import '../domain/image_entry.dart';
import 'components/app_dialog.dart';
import 'components/app_icon_button.dart';
import 'components/app_notification.dart';
import 'components/form_components.dart';
import 'localized_error.dart';
import 'theme/app_styles.dart';
import 'theme/app_theme.dart';
import 'theme/app_tokens.dart';

class PrintPreviewDialog extends StatefulWidget {
  const PrintPreviewDialog({
    super.key,
    required this.entry,
    required this.imageBytes,
  });

  final ImageEntry entry;
  final Uint8List imageBytes;

  @override
  State<PrintPreviewDialog> createState() => _PrintPreviewDialogState();
}

enum _PrintFit { contain, fill, actual }

class _PrintPreviewDialogState extends State<PrintPreviewDialog> {
  final _notifications = AppNotificationController();
  static const _formats = <String, PdfPageFormat>{
    'Letter': PdfPageFormat.letter,
    'Tabloid': PdfPageFormat(11 * PdfPageFormat.inch, 17 * PdfPageFormat.inch),
    'Legal': PdfPageFormat.legal,
    'Statement': PdfPageFormat(
      5.5 * PdfPageFormat.inch,
      8.5 * PdfPageFormat.inch,
    ),
    'Executive': PdfPageFormat(
      7.25 * PdfPageFormat.inch,
      10.5 * PdfPageFormat.inch,
    ),
    'A3': PdfPageFormat.a3,
    'A4': PdfPageFormat.a4,
    'A5': PdfPageFormat.a5,
    'B4 (JIS)': PdfPageFormat(25.7 * PdfPageFormat.cm, 36.4 * PdfPageFormat.cm),
    'B5 (JIS)': PdfPageFormat(18.2 * PdfPageFormat.cm, 25.7 * PdfPageFormat.cm),
  };
  static const _margins = <String, double>{
    'default': 20,
    'none': 0,
    'minimum': 6,
    // The editable value is stored separately in _customMarginMm.
    'custom': 20,
  };

  List<Printer> _printers = const [];
  Printer? _printer;
  String _paper = 'A4';
  String _margin = 'default';
  double _customMarginMm = 20;
  bool _customMarginValid = true;
  late final TextEditingController _customMarginController;
  final _marginFormatter = AppNumberInputFormatter(
    integerDigits: 2,
    decimalPlaces: 1,
  );
  bool _landscape = false;
  _PrintFit _fit = _PrintFit.contain;
  bool _loadingPrinters = true;
  bool _printing = false;
  String? _printerError;

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  PdfPageFormat get _pageFormat {
    final base = _formats[_paper]!;
    final marginMm = _margin == 'custom' ? _customMarginMm : _margins[_margin]!;
    final margin = marginMm * PdfPageFormat.mm;
    final withMargin = base.copyWith(
      marginTop: margin,
      marginBottom: margin,
      marginLeft: margin,
      marginRight: margin,
    );
    return _landscape ? withMargin.landscape : withMargin.portrait;
  }

  @override
  void initState() {
    super.initState();
    _customMarginController = TextEditingController(text: '20');
    _loadPrinters();
  }

  @override
  void dispose() {
    _notifications.dispose();
    _customMarginController.dispose();
    super.dispose();
  }

  Future<void> _loadPrinters() async {
    try {
      final printers = await Printing.listPrinters();
      if (!mounted) return;
      setState(() {
        _printers = printers.where((printer) => printer.isAvailable).toList();
        _printer =
            _printers.where((printer) => printer.isDefault).firstOrNull ??
            _printers.firstOrNull;
        _loadingPrinters = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingPrinters = false;
        _printerError = localizedErrorMessage(_l10n, error);
      });
    }
  }

  Future<Uint8List> _buildDocument(PdfPageFormat format) async {
    final document = pw.Document();
    final image = pw.MemoryImage(widget.imageBytes);
    document.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Padding(
          padding: pw.EdgeInsets.only(
            left: format.marginLeft,
            top: format.marginTop,
            right: format.marginRight,
            bottom: format.marginBottom,
          ),
          child: pw.Center(
            child: pw.Image(
              image,
              fit: switch (_fit) {
                _PrintFit.contain => pw.BoxFit.contain,
                _PrintFit.fill => pw.BoxFit.cover,
                _PrintFit.actual => pw.BoxFit.none,
              },
            ),
          ),
        ),
      ),
    );
    return document.save();
  }

  Future<void> _print() async {
    if (_printing || (_margin == 'custom' && !_customMarginValid)) return;
    setState(() => _printing = true);
    try {
      final selected = _printer;
      final printed = selected == null
          ? await Printing.layoutPdf(
              name: widget.entry.name,
              format: _pageFormat,
              dynamicLayout: false,
              onLayout: _buildDocument,
            )
          : await Printing.directPrintPdf(
              printer: selected,
              name: widget.entry.name,
              format: _pageFormat,
              dynamicLayout: false,
              onLayout: _buildDocument,
            );
      if (printed && mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      _notifications.show(
        _l10n.printFailed(localizedErrorMessage(_l10n, error)),
        type: AppNotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ViewerThemeTokens.of(context);
    final viewport = MediaQuery.sizeOf(context);
    return AppNotificationHost(
      controller: _notifications,
      child: Dialog(
        child: SizedBox(
          width: math
              .min(1100.0, math.max(0.0, viewport.width - 48.0))
              .toDouble(),
          height: math
              .min(760.0, math.max(420.0, viewport.height - 48.0))
              .toDouble(),
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 720) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildPreview(tokens)),
                          VerticalDivider(width: 1, color: tokens.border),
                          SizedBox(
                            width: 320,
                            child: _buildSettingsPanel(tokens),
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        SizedBox(
                          height: math.min(240.0, constraints.maxHeight * 0.4),
                          child: _buildPreview(tokens),
                        ),
                        Divider(height: 1, color: tokens.border),
                        Expanded(child: _buildSettingsPanel(tokens)),
                      ],
                    );
                  },
                ),
              ),
              _buildActions(tokens),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final tokens = ViewerThemeTokens.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space4,
        vertical: AppTokens.space2,
      ),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      FluentIcons.print_20_regular,
                      size: 18,
                      color: tokens.accentStrong,
                    ),
                    const SizedBox(width: AppTokens.space2),
                    Expanded(
                      child: Text(
                        _l10n.printPreview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.compactTitle.copyWith(
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.space1),
                Padding(
                  padding: const EdgeInsets.only(left: 18 + AppTokens.space2),
                  child: Tooltip(
                    message: widget.entry.name,
                    child: Text(
                      widget.entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: tokens.textTertiary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.space2),
          AppIconButton(
            icon: FluentIcons.dismiss_20_regular,
            tooltip: _l10n.close,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(ViewerThemeTokens tokens) {
    return ColoredBox(
      color: tokens.canvasBackground,
      child: PdfPreview.builder(
        key: ValueKey(
          '${_paper}_${_margin}_${_customMarginMm}_${_landscape}_${_fit.name}',
        ),
        build: _buildDocument,
        initialPageFormat: _pageFormat,
        pageFormats: _formats,
        canChangePageFormat: false,
        canChangeOrientation: false,
        allowPrinting: false,
        allowSharing: false,
        useActions: false,
        canDebug: false,
        pdfFileName: widget.entry.name,
        scrollViewDecoration: BoxDecoration(color: tokens.canvasBackground),
        pdfPreviewPageDecoration: AppDecorations.printPaper,
        loadingWidget: CircularProgressIndicator(color: tokens.accent),
        pagesBuilder: _buildPreviewPages,
      ),
    );
  }

  Widget _buildPreviewPages(
    BuildContext context,
    List<PdfPreviewPageData> pages,
  ) {
    final page = pages.first;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = math.max(
          0.0,
          constraints.maxWidth - AppTokens.space6,
        );
        final availableHeight = math.max(
          0.0,
          constraints.maxHeight - AppTokens.space6,
        );
        final aspectRatio = page.aspectRatio.isFinite && page.aspectRatio > 0
            ? page.aspectRatio
            : 1.0;
        final pageWidth = math
            .min(availableWidth, availableHeight * aspectRatio)
            .toDouble();
        final pageHeight = pageWidth / aspectRatio;
        return Center(
          child: Container(
            width: pageWidth,
            height: pageHeight,
            decoration: AppDecorations.printPaper,
            clipBehavior: Clip.antiAlias,
            child: Image(image: page.image, fit: BoxFit.fill),
          ),
        );
      },
    );
  }

  Widget _buildSettingsPanel(ViewerThemeTokens tokens) {
    return ColoredBox(
      color: tokens.surfaceElevated,
      child: SingleChildScrollView(
        key: const ValueKey('print.settingsScroll'),
        padding: const EdgeInsets.all(AppTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSelect<Printer>(
              key: const ValueKey('print.printer'),
              label: _l10n.printer,
              value: _printer,
              options: [
                for (final printer in _printers)
                  AppSelectOption(value: printer, label: printer.name),
              ],
              enabled: !_loadingPrinters,
              onChanged: (value) {
                if (value != _printer) setState(() => _printer = value);
              },
              hint: _loadingPrinters
                  ? _l10n.readingPrinters
                  : (_printerError == null
                        ? _l10n.defaultPrinter
                        : _l10n.printerListUnavailable),
            ),
            const SizedBox(height: AppTokens.space4),
            AppSelect<bool>(
              key: const ValueKey('print.orientation'),
              label: _l10n.orientation,
              value: _landscape,
              options: [
                AppSelectOption(value: false, label: _l10n.portrait),
                AppSelectOption(value: true, label: _l10n.landscape),
              ],
              onChanged: (value) {
                if (value != _landscape) setState(() => _landscape = value);
              },
            ),
            const SizedBox(height: AppTokens.space4),
            AppSelect<String>(
              key: const ValueKey('print.paper'),
              label: _l10n.paperSize,
              value: _paper,
              options: [
                for (final name in _formats.keys)
                  AppSelectOption(value: name, label: name),
              ],
              onChanged: (value) {
                if (value != _paper) setState(() => _paper = value);
              },
            ),
            const SizedBox(height: AppTokens.space4),
            AppSelect<String>(
              key: const ValueKey('print.margins'),
              label: _l10n.margins,
              value: _margin,
              options: [
                for (final name in _margins.keys)
                  AppSelectOption(
                    value: name,
                    label: switch (name) {
                      'default' => _l10n.defaultOption,
                      'none' => _l10n.noMargin,
                      'minimum' => _l10n.narrowMargin,
                      'custom' => _l10n.normalMargin,
                      _ => name,
                    },
                  ),
              ],
              onChanged: (value) {
                if (value != _margin) setState(() => _margin = value);
              },
            ),
            if (_margin == 'custom') ...[
              const SizedBox(height: AppTokens.space4),
              AppInput(
                key: const ValueKey('print.customMargin'),
                controller: _customMarginController,
                label: _l10n.customMarginLabel,
                suffixText: 'mm',
                helperText: _l10n.customMarginHint,
                errorText: _customMarginValid
                    ? null
                    : _l10n.customMarginInvalid,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [_marginFormatter],
                onChanged: (value) => setState(() {
                  final parsed = double.tryParse(value);
                  _customMarginValid =
                      parsed != null &&
                      parsed.isFinite &&
                      parsed >= 0 &&
                      parsed <= 50;
                  if (_customMarginValid) _customMarginMm = parsed!;
                }),
              ),
            ],
            const SizedBox(height: AppTokens.space4),
            AppSelect<_PrintFit>(
              key: const ValueKey('print.fit'),
              label: _l10n.fitMode,
              value: _fit,
              helperText: _fitDescription,
              options: [
                AppSelectOption(value: _PrintFit.contain, label: _l10n.fitPage),
                AppSelectOption(value: _PrintFit.fill, label: _l10n.fillPage),
                AppSelectOption(
                  value: _PrintFit.actual,
                  label: _l10n.actualSize,
                ),
              ],
              onChanged: (value) {
                if (value != _fit) setState(() => _fit = value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(ViewerThemeTokens tokens) => Container(
    key: const ValueKey('print.actions'),
    padding: const EdgeInsets.all(AppTokens.space4),
    decoration: BoxDecoration(
      color: tokens.surfaceElevated,
      border: Border(top: BorderSide(color: tokens.border)),
    ),
    child: AppDialogActions(
      children: [
        AppButton(
          key: const ValueKey('print.cancel'),
          label: _l10n.cancel,
          variant: AppButtonVariant.neutral,
          size: AppButtonSize.prominent,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          size: AppButtonSize.prominent,
          key: const ValueKey('print.submit'),
          label: _l10n.printAction,
          leadingIcon: FluentIcons.print_20_regular,
          busy: _printing,
          onPressed: _margin == 'custom' && !_customMarginValid ? null : _print,
        ),
      ],
    ),
  );

  String get _fitDescription => switch (_fit) {
    _PrintFit.contain => _l10n.fitPageDescription,
    _PrintFit.fill => _l10n.fillPageDescription,
    _PrintFit.actual => _l10n.actualSizeDescription,
  };
}
