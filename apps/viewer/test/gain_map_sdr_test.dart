import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/decode_scheduler.dart';
import 'package:shen_view/src/application/hdr_decoder.dart';
import 'package:shen_view/src/application/hdr_frame.dart';
import 'package:shen_view/src/application/hdr_input_metadata.dart';
import 'package:shen_view/src/application/image_resource_service.dart';
import 'package:shen_view/src/application/native_decoder.dart';
import 'package:shen_view/src/application/platform_image_decoder.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';

// Deliberately make the alternate rendition much brighter than the SDR base.
// This catches accidentally reconstructing HDR before generating the fallback.
class _BrightHdrDecoder extends HdrDecoder {
  int calls = 0;

  @override
  Future<HdrFrame> decode(
    String path,
    DecodeRequest request, {
    HdrInputMetadata? metadata,
  }) async {
    calls++;
    return HdrFrame(
      1,
      1,
      Float32List.fromList([8, 8, 8, 1]).buffer.asUint8List(),
    );
  }
}

class _BaseDecoder extends NativeDecoder {
  @override
  Future<PlatformDecodedImage?> decodePlatform(
    String path, {
    int? targetWidth,
    int? targetHeight,
    Map<String, int>? region,
    bool preserveHdr = false,
    DecodeRequest? request,
  }) async => PlatformDecodedImage(
    width: 1,
    height: 1,
    pixels: Uint8List.fromList([60, 90, 120, 255]),
  );
}

Future<ui.Image> _load(ImageProvider<Object> provider) async {
  final done = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      done.complete(info.image.clone());
      stream.removeListener(listener);
    },
    onError: (Object error, StackTrace? stack) {
      done.completeError(error, stack);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return done.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final extension in ['heic', 'heif', 'avif', 'jpg']) {
    for (final priority in [
      DecodePriority.foreground,
      DecodePriority.thumbnail,
    ]) {
      test(
        'Gain Map $extension $priority preserves the authored SDR base',
        () async {
          final hdr = _BrightHdrDecoder();
          final resources = ImageResourceService(
            decoder: _BaseDecoder(),
            hdrDecoder: hdr,
          );
          addTearDown(resources.dispose);
          addTearDown(PaintingBinding.instance.imageCache.clear);
          final file = File('testdata/formats/hdr_gain_map.$extension');
          final stat = file.statSync();
          final metadata = await HdrInputMetadata.read(file.path);
          expect(metadata.encoding, HdrEncoding.gainMap);
          final entry = ImageEntry(
            file: file,
            format: switch (extension) {
              'heic' || 'heif' => ImageFormat.heic,
              'avif' => ImageFormat.avif,
              _ => ImageFormat.jpeg,
            },
            width: null,
            height: null,
            byteLength: stat.size,
            modifiedAt: stat.modified,
          );
          final image = await _load(
            resources.provider(
              entry,
              targetWidth: 1,
              targetHeight: 1,
              priority: priority,
            ),
          );
          addTearDown(image.dispose);
          expect(
            hdr.calls,
            0,
            reason: 'SDR must not apply the HDR enhancement',
          );
          if (extension != 'jpg') {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            expect(bytes!.buffer.asUint8List(), [60, 90, 120, 255]);
          }
        },
      );
    }
  }
}
