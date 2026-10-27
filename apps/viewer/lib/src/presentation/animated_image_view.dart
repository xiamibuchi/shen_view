import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../application/animation_playback_controller.dart';
import '../application/image_resource_service.dart';
import '../application/decode_request.dart';
import '../domain/image_entry.dart';
import '../domain/image_resource_key.dart';

class AnimatedImageView extends StatefulWidget {
  const AnimatedImageView({
    super.key,
    required this.file,
    required this.entry,
    required this.resources,
    required this.playing,
    required this.fit,
    this.autoPlay = true,
    this.loopMode = AnimationLoopMode.file,
    this.defaultSpeed = 1.0,
    this.targetSize,
    this.onFrameInfo,
    this.onController,
    this.initialPlayback,
    this.onError,
  });
  final File file;
  final ImageEntry entry;
  final ImageResourceService resources;
  final int? targetSize;

  /// Whether this page may run (current comic page, non-minimized window).
  final bool playing;
  final bool autoPlay;
  final AnimationLoopMode loopMode;
  final double defaultSpeed;
  final BoxFit fit;
  final void Function(int frame, int frameCount)? onFrameInfo;
  final ValueChanged<AnimationPlaybackController>? onController;
  final AnimationPlaybackSnapshot? initialPlayback;
  final ValueChanged<Object>? onError;
  @override
  State<AnimatedImageView> createState() => _AnimatedImageViewState();
}

class _AnimatedImageViewState extends State<AnimatedImageView> {
  AnimationPlaybackController? _controller;
  DecodeRequest? _request;
  ImageFileVersion? _version;
  int _generation = 0;
  bool _failed = false;
  int? _decodeSize;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AnimatedImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_version != widget.resources.version(widget.entry)) {
      _load();
    } else {
      _controller?.setSuspended(!widget.playing);
      if (oldWidget.targetSize != widget.targetSize) {
        _decodeSize = widget.targetSize;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _controller?.refreshResolution();
        });
      }
      if (oldWidget.autoPlay != widget.autoPlay ||
          oldWidget.loopMode != widget.loopMode ||
          oldWidget.defaultSpeed != widget.defaultSpeed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (oldWidget.autoPlay != widget.autoPlay) {
            _controller?.setPlaying(widget.autoPlay);
          }
          if (oldWidget.loopMode != widget.loopMode) {
            _controller?.setLoopMode(widget.loopMode);
          }
          if (oldWidget.defaultSpeed != widget.defaultSpeed) {
            _controller?.setSpeed(widget.defaultSpeed);
          }
        });
      }
      _publishController();
    }
  }

  void _publishController() {
    final controller = _controller;
    if (controller == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_controller, controller)) {
        widget.onController?.call(controller);
      }
    });
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _version = widget.resources.version(widget.entry);
    _request?.cancel();
    final request = DecodeRequest();
    _request = request;
    _controller?.removeListener(_changed);
    _controller?.dispose();
    _controller = null;
    _failed = false;
    try {
      final animation = widget.resources
          .cachedMetadata(widget.entry)
          ?.animation;
      final timeline = animation?.durationsMs != null
          ? AnimationTimeline(
              animation!.durationsMs!,
              totalPlays: animation.loopCount ?? 1,
              minimumDelayMs:
                  widget.resources.cachedMetadata(widget.entry)?.media != null
                  ? 1
                  : 16,
            )
          : await _readTimeline(widget.file.path);
      if (!mounted || generation != _generation) return;
      final effectiveTimeline = timeline ?? AnimationTimeline([100]);
      final resources = widget.resources;
      final entry = widget.entry;
      _decodeSize = widget.targetSize;
      final controller = AnimationPlaybackController(
        timeline: effectiveTimeline,
        autoPlay: widget.autoPlay,
        loopMode: widget.loopMode,
        openCodec: () => resources.animationCodec(
          entry,
          targetWidth: _decodeSize,
          targetHeight: _decodeSize,
          request: request,
        ),
      );
      _controller = controller;
      controller.setSpeed(widget.defaultSpeed);
      controller.setSuspended(!widget.playing);
      controller.addListener(_changed);
      _publishController();
      await controller.initialize(restore: widget.initialPlayback);
      if (mounted && generation == _generation) setState(() {});
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _failed = true);
        widget.onError?.call(error);
      }
    }
  }

  void _changed() {
    if (!mounted) return;
    final controller = _controller!;
    widget.onFrameInfo?.call(controller.frame, controller.frameCount);
    setState(() {});
  }

  @override
  void dispose() {
    _generation++;
    _request?.cancel();
    _controller?.removeListener(_changed);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final image = controller?.image;
    if ((_failed || controller?.error != null) && image == null) {
      return Center(
        child: Text(AppLocalizations.of(context)!.cannotDecodeAnimatedImage),
      );
    }
    if (image == null) return const Center(child: CircularProgressIndicator());
    return RawImage(
      image: image,
      fit: widget.fit,
      filterQuality: FilterQuality.medium,
    );
  }
}

// Keep the isolate closure outside the widget's scope so it cannot capture
// the render tree or resource service through Dart's shared closure context.
Future<AnimationTimeline?> _readTimeline(String path) => Isolate.run(() {
  final file = File(path);
  if (file.lengthSync() > ImageResourceService.maxEncodedBytes) {
    throw StateError('Animation read limit exceeded');
  }
  return AnimationTimeline.parse(file.readAsBytesSync());
});
