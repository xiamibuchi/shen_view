import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../application/decode_request.dart';
import '../application/image_source.dart';
import '../domain/image_entry.dart';
import 'components/app_button.dart';
import 'theme/app_tokens.dart';

/// Keeps the archive file leased for the entire lifetime of native, animated
/// and SVG consumers, including decoders that continue reading after startup.
class SourceImageView extends StatefulWidget {
  const SourceImageView({
    required this.entry,
    required this.builder,
    required this.errorBuilder,
    this.showRetryButton = true,
    super.key,
  });
  final ImageEntry entry;
  final Widget Function(ImageEntry entry) builder;
  final Widget Function(Object error) errorBuilder;
  final bool showRetryButton;

  @override
  State<SourceImageView> createState() => _SourceImageViewState();
}

class _SourceImageViewState extends State<SourceImageView> {
  DecodeRequest? _request;
  SourceFileLease? _lease;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant SourceImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id) {
      _release();
      _error = null;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final request = _request = DecodeRequest();
    try {
      final lease = await widget.entry.acquireFile(request: request);
      if (!mounted || request.cancelled || !identical(request, _request)) {
        await lease.release();
        return;
      }
      setState(() => _lease = lease);
    } on DecodeCancelled {
      // Removed/replaced viewport. Never publish its obsolete result.
    } catch (error) {
      if (mounted && identical(request, _request)) {
        setState(() => _error = error);
      }
    }
  }

  void _release() {
    _request?.cancel();
    _request = null;
    final lease = _lease;
    _lease = null;
    if (lease != null) unawaited(lease.release());
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      if (!widget.showRetryButton) return widget.errorBuilder(_error!);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.errorBuilder(_error!),
            const SizedBox(height: AppTokens.space3),
            AppButton(
              label: AppLocalizations.of(context)!.archiveRetryPage,
              variant: AppButtonVariant.neutral,
              onPressed: () {
                _release();
                setState(() => _error = null);
                unawaited(_load());
              },
            ),
          ],
        ),
      );
    }
    final lease = _lease;
    if (lease != null) return widget.builder(widget.entry.withFile(lease.file));
    return Center(
      child: Text(AppLocalizations.of(context)!.archivePreparingPage),
    );
  }
}
