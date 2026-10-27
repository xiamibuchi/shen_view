import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/decode_scheduler.dart';
import 'package:shen_view/src/application/platform_image_decoder.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real native pixels, metadata and cancelled queue recover', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    const fixtures = String.fromEnvironment('NATIVE_DECODER_FIXTURES');
    expect(
      fixtures,
      isNotEmpty,
      reason: 'Pass --dart-define=NATIVE_DECODER_FIXTURES=<absolute path>',
    );
    final decoder = PlatformImageDecoder();
    final formats = <String>[];
    for (final extension in ['png', 'jpg', 'bmp', 'tiff']) {
      final path = '$fixtures/format_static.$extension';
      final metadataRequest = DecodeRequest()
        ..updatePriority(DecodePriority.metadata);
      final metadata = await decoder.metadata(path, request: metadataRequest);
      expect(metadata?['width'], greaterThan(0));
      final pixels = await decoder.decode(
        path,
        targetWidth: 128,
        targetHeight: 128,
        request: DecodeRequest(),
      );
      expect(pixels, isNotNull, reason: extension);
      final image = await pixels!.toImage();
      try {
        expect(image.width, inInclusiveRange(1, 128));
        expect(image.height, inInclusiveRange(1, 128));
        final output = await image.toByteData();
        expect(output!.buffer.asUint8List().any((value) => value != 0), true);
      } finally {
        image.dispose();
      }
      formats.add(extension);
    }

    // Deliberately exercise the native queue directly. Production requests
    // additionally pass through the unchanged shared 2/1 task limit.
    final requests = List.generate(
      12,
      (_) => DecodeRequest()..updatePriority(DecodePriority.thumbnail),
    );
    final outcomes = <Future<bool>>[];
    for (final request in requests) {
      outcomes.add(
        decoder
            .decode(
              '$fixtures/format_static.tiff',
              targetWidth: 64,
              targetHeight: 64,
              request: request,
            )
            .then(
              (pixels) {
                expect(pixels, isNotNull);
                return true;
              },
              onError: (Object error) {
                expect(error, isA<DecodeCancelled>());
                return false;
              },
            ),
      );
    }
    for (var i = 0; i < requests.length; i++) {
      if (i % 3 == 0) {
        requests[i].cancel();
      } else if (i % 3 == 1) {
        requests[i].updatePriority(DecodePriority.foreground, distance: 0);
      }
    }
    final results = await Future.wait(outcomes);
    expect(results.where((value) => !value).length, 4);
    expect(results.where((value) => value).length, 8);
    final after = await decoder.decode(
      '$fixtures/format_static.png',
      targetWidth: 64,
      targetHeight: 64,
      request: DecodeRequest(),
    );
    expect(after, isNotNull);
    final report = <String, Object>{
      'platform': Platform.operatingSystem,
      'formats': formats,
      'cancelled': 4,
      'completed': 8,
      'recovered': true,
    };
    binding.reportData = report;
    final output = Directory.fromUri(
      Directory.current.uri.resolve('../../artifacts/main-image-priority'),
    )..createSync(recursive: true);
    File('${output.path}/native-channel.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
