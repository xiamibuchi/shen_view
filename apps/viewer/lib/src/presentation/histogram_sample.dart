import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../application/svg_resources.dart';

import '../application/decode_request.dart';
import '../application/decode_scheduler.dart';
import '../application/image_histogram.dart';
import '../application/image_resource_service.dart';
import '../domain/image_entry.dart';
import '../domain/image_format.dart';

/// Use the viewer's SDR decoding and archive leases, with at most 512² pixels.
/// This is deliberately independent of zoom, crop, and animation playback.
Future<ImageHistogram> readImageHistogram(
  ImageResourceService resources,
  ImageEntry entry,
  DecodeRequest request,
) async {
  request.throwIfCancelled();
  final image = entry.format == ImageFormat.svg
      ? await _svgSample(entry, request)
      : resources.isAnimated(entry)
      ? await _animationSample(resources, entry, request)
      : await _rasterSample(resources, entry, request);
  try {
    request.throwIfCancelled();
    final bytes = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    request.throwIfCancelled();
    if (bytes == null) throw StateError('Histogram pixels unavailable');
    final result = await compute(
      ImageHistogram.fromRgba,
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    request.throwIfCancelled();
    return result;
  } finally {
    image.dispose();
  }
}

Future<ui.Image> _rasterSample(
  ImageResourceService resources,
  ImageEntry entry,
  DecodeRequest request,
) async {
  final stream = resources
      .provider(
        entry,
        targetWidth: 512,
        targetHeight: 512,
        priority: DecodePriority.visible,
      )
      .resolve(ImageConfiguration.empty);
  final ready = Completer<ImageInfo>();
  final listener = ImageStreamListener(
    (info, _) {
      if (ready.isCompleted) {
        info.dispose();
      } else {
        ready.complete(info);
      }
    },
    onError: (Object error, StackTrace? stack) {
      if (!ready.isCompleted) ready.completeError(error, stack);
    },
  );
  void cancel() {
    if (!ready.isCompleted) ready.completeError(DecodeCancelled());
  }

  stream.addListener(listener);
  request.addCancelListener(cancel);
  try {
    final info = await ready.future;
    try {
      request.throwIfCancelled();
      return info.image.clone();
    } finally {
      info.dispose();
    }
  } finally {
    request.removeCancelListener(cancel);
    stream.removeListener(listener);
  }
}

Future<ui.Image> _animationSample(
  ImageResourceService resources,
  ImageEntry entry,
  DecodeRequest request,
) async {
  final codec = await resources.animationCodec(
    entry,
    targetWidth: 512,
    targetHeight: 512,
    request: request,
  );
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Future<ui.Image> _svgSample(ImageEntry entry, DecodeRequest request) async {
  final lease = await entry.acquireFile(request: request);
  try {
    request.throwIfCancelled();
    final resource = await SvgResources.shared.read(
      lease.file,
      version: svgVersion(entry),
    );
    final edge = math.max(
      1,
      math.min(
        512,
        math.max(resource.document.width, resource.document.height).ceil(),
      ),
    );
    final bytes = await SvgResources.shared.raster(
      resource,
      edge,
      request: request,
      thumbnail: true,
    );
    request.throwIfCancelled();
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final image = (await codec.getNextFrame()).image;
      if (request.cancelled) {
        image.dispose();
        request.throwIfCancelled();
      }
      return image;
    } finally {
      codec.dispose();
    }
  } finally {
    await lease.release();
  }
}
