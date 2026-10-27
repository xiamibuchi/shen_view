import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/hdr_display_service.dart';
import 'package:shen_view/src/application/hdr_frame.dart';
import 'package:shen_view/src/application/image_resource_service.dart';
import 'package:shen_view/src/application/native_decoder.dart';
import 'package:shen_view/src/presentation/hdr_image_view.dart';

Uint8List raw(List<double> pixels, {int width = 1, int height = 1}) {
  final bytes = ByteData(pixels.length * 4);
  for (var i = 0; i < pixels.length; i++) {
    bytes.setFloat32(i * 4, pixels[i], Endian.little);
  }
  return (BytesBuilder()
        ..add(ascii.encode('FVHDR32 $width $height\n'))
        ..add(bytes.buffer.asUint8List()))
      .takeBytes();
}

class FakeHdrService extends HdrDisplayService {
  final events = StreamController<String>.broadcast();
  @override
  Stream<String> get invalidations => events.stream;
  bool available = true;
  bool uploadSucceeds = true;
  String output = 'HDR-1';
  int decodes = 0;
  final geometryCalls = <Map<String, Object>>[];
  final removed = <int>[];

  @override
  Future<HdrDisplayCapabilities> capabilities() async =>
      HdrDisplayCapabilities(available: available, output: output);
  @override
  Future<HdrFrame> decode(String path, DecodeRequest request) async {
    decodes++;
    return HdrFrame.fromRaw(raw([8, 4, 2, 1]));
  }

  @override
  Future<bool> upload(int id, HdrFrame frame) async => uploadSucceeds;
  @override
  Future<bool> geometry(Map<String, Object> arguments) async {
    geometryCalls.add(arguments);
    return true;
  }

  @override
  Future<void> remove(int id) async {
    removed.add(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native HDR upload uses the shared source callback', (
    tester,
  ) async {
    final service = FakeHdrService();
    var sharedDecodes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: HdrImageView(
          path: 'shared.avif',
          revision: 1,
          sourceSize: const Size(1, 1),
          fit: BoxFit.contain,
          service: service,
          decodeFrame: (_) async {
            sharedDecodes++;
            return HdrFrame.fromRaw(raw([8, 4, 2, 1]));
          },
          child: const Text('cached SDR'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sharedDecodes, 1);
    expect(service.decodes, 0);
    expect(find.text('cached SDR'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await service.events.close();
  });

  testWidgets(
    'HDR admission keeps SDR on temporary pressure and retries after recovery',
    (tester) async {
      final service = FakeHdrService();
      var permitted = false;
      var admissions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 100,
            height: 100,
            child: HdrImageView(
              path: 'chart.hdr',
              revision: 1,
              sourceSize: const Size(1, 1),
              fit: BoxFit.contain,
              service: service,
              runDecode: (request, operation) async {
                admissions++;
                if (!permitted) throw ImageResourceUnavailable();
                return operation();
              },
              child: const Text('SDR fallback'),
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(service.decodes, 0);
      expect(find.text('SDR fallback'), findsOneWidget);
      permitted = true;
      await tester.pump(const Duration(seconds: 2));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(admissions, 2);
      expect(service.decodes, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await service.events.close();
    },
  );

  test(
    'float bridge preserves highlights, rows and alpha without quantization',
    () {
      final frame = HdrFrame.fromRaw(
        raw([8, 4, 2, 1, 4, 2, 1, 0.5], height: 2),
      );
      final pixels = ByteData.sublistView(frame.pixels);
      expect(pixels.getFloat32(0, Endian.little), 8);
      expect(pixels.getFloat32(16, Endian.little), 2);
      expect(pixels.getFloat32(28, Endian.little), 0.5);
      expect(frame.hasTransparency, isTrue);
    },
  );

  test(
    'bad HDR samples and hostile/truncated buffers cannot reach the GPU',
    () {
      final frame = HdrFrame.fromRaw(raw([double.nan, double.infinity, -2, 1]));
      final pixels = ByteData.sublistView(frame.pixels);
      expect(pixels.getFloat32(0, Endian.little), 0);
      expect(pixels.getFloat32(4, Endian.little), 0);
      expect(pixels.getFloat32(8, Endian.little), -2);
      for (final data in [
        Uint8List(0),
        Uint8List.fromList(ascii.encode('FVHDR32 999999 999999\n')),
        raw([1, 1, 1, 1], width: 2),
      ]) {
        expect(() => HdrFrame.fromRaw(data), throwsFormatException);
      }
    },
  );

  test(
    'missing native plugin is an SDR capability, not an application error',
    () async {
      final capabilities = await HdrDisplayService().capabilities();
      expect(capabilities.available, isFalse);
      expect(
        await HdrDisplayService().upload(
          1,
          HdrFrame.fromRaw(raw([8, 4, 2, 1])),
        ),
        isFalse,
      );
      await HdrDisplayService().remove(1);
    },
  );

  test(
    'real RGBE/EXR float decoding retains the >1 highlight ladder',
    () async {
      final bundled = File(
        'build/windows/x64/runner/Release/codecs/magick.exe',
      );
      final configured = Platform.environment['SHENVIEW_MAGICK'];
      final executable =
          configured ?? (bundled.existsSync() ? bundled.absolute.path : null);
      if (executable == null) {
        markTestSkipped('需要 ImageMagick HDRI，设置 SHENVIEW_MAGICK 后运行');
        return;
      }
      final service = HdrDisplayService(
        decoder: NativeDecoder(executableOverride: executable),
      );
      for (final name in [
        'hdr_highlights.hdr',
        'hdr_highlights.exr',
        'hdr_rec2020.exr',
      ]) {
        final frame = await service.decode(
          File('testdata/formats/$name').absolute.path,
          DecodeRequest(),
        );
        expect(frame.width, 384);
        expect(frame.height, 192);
        final values = ByteData.sublistView(frame.pixels);
        final highlights = [
          for (var i = 0; i < 6; i++)
            values.getFloat32((i * 64 + 63) * 16, Endian.little),
        ];
        for (var i = 1; i < 6; i++) {
          expect(highlights[i], greaterThan(highlights[i - 1]));
        }
        expect(highlights.last, closeTo(16, 0.2));
        if (name == 'hdr_rec2020.exr') {
          final red = values.getFloat32(
            (100 * frame.width + 383) * 16,
            Endian.little,
          );
          expect(red, closeTo(24.159, 0.02));
        }
        // The first row is neutral, the last row blue: no vertical mirroring.
        final bottom = (frame.height - 1) * frame.width * 16;
        expect(
          values.getFloat32(bottom + 8, Endian.little),
          greaterThan(values.getFloat32(bottom, Endian.little)),
        );
      }
      final transparent = await service.decode(
        File('testdata/formats/hdr_transparent.exr').absolute.path,
        DecodeRequest(),
      );
      expect(transparent.hasTransparency, isTrue);
      final bytes = await NativeDecoder(executableOverride: executable)
          .decode(File('testdata/formats/hdr_highlights.hdr').absolute.path);
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      final sdr = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final steps = [
        for (var i = 0; i < 6; i++) sdr!.getUint8((i * 64 + 63) * 4),
      ];
      for (var i = 1; i < 6; i++) {
        expect(steps[i], greaterThan(steps[i - 1]));
      }
      expect(steps[1], closeTo(188, 2));
      expect(steps.last, closeTo(248, 2));
      image.dispose();
      codec.dispose();
    },
  );

  Widget host(
    FakeHdrService service, {
    bool suspended = false,
    double scale = 1,
    double topInset = 0,
  }) => MaterialApp(
    home: HdrOverlayScope(
      suspended: suspended,
      child: Center(
        child: SizedBox(
          width: 200,
          height: 160,
          child: RepaintBoundary(
            key: const ValueKey('hdr.capture'),
            child: HdrViewportBoundary(
              insets: EdgeInsets.only(top: topInset),
              child: ClipRect(
                child: Transform.scale(
                  scale: scale,
                  child: HdrImageView(
                    path: 'chart.hdr',
                    revision: 1,
                    sourceSize: const Size(200, 160),
                    fit: BoxFit.contain,
                    service: service,
                    child: const ColoredBox(color: Colors.red),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  testWidgets(
    'HDR geometry follows zoom, clips to canvas and resumes after overlays',
    (tester) async {
      final service = FakeHdrService();
      await tester.pumpWidget(host(service));
      await settle(tester);
      expect(service.geometryCalls.last['visible'], true);
      Future<int> fallbackAlpha({int y = 80}) async =>
          (await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('hdr.capture')),
            );
            final image = await boundary.toImage();
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final alpha = bytes.getUint8((y * image.width + 100) * 4 + 3);
            image.dispose();
            return alpha;
          }))!;

      expect(
        await fallbackAlpha(),
        0,
        reason: 'transparent native pixels need a clean canvas',
      );
      final initial = service.geometryCalls.last['geometry'] as Float64List;
      await tester.pumpWidget(host(service, scale: 2));
      await settle(tester);
      final zoom = service.geometryCalls.last['geometry'] as Float64List;
      expect(zoom[2] - zoom[0], closeTo(2 * (initial[2] - initial[0]), 0.01));
      expect(zoom.sublist(6), initial.sublist(6));
      await tester.pumpWidget(host(service, suspended: true));
      await settle(tester);
      expect(service.geometryCalls.last['visible'], false);
      expect(await fallbackAlpha(), 255);
      await tester.pumpWidget(host(service));
      await settle(tester);
      expect(service.geometryCalls.last['visible'], true);
      expect(service.decodes, 1);
      await tester.pumpWidget(host(service, topInset: 44, scale: 2));
      await settle(tester);
      expect(service.geometryCalls.last['visible'], true);
      expect(
        await fallbackAlpha(y: 20),
        255,
        reason: 'SDR proxy fills the floating toolbar strip',
      );
      expect(
        await fallbackAlpha(),
        0,
        reason: 'native HDR canvas never receives a second image copy',
      );
      service.available = false;
      service.events.add('display-changed');
      await settle(tester);
      expect(
        await fallbackAlpha(),
        255,
        reason: 'native invalidation restores SDR immediately',
      );
      await tester.pumpWidget(const SizedBox());
      await service.events.close();
      expect(service.removed, isNotEmpty);
    },
  );

  testWidgets(
    'display changes reupload, SDR never decodes HDR, failure does not loop',
    (tester) async {
      final service = FakeHdrService()..available = false;
      await tester.pumpWidget(host(service));
      await settle(tester);
      expect(service.decodes, 0);
      service.available = true;
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(service.decodes, 1);
      service.output = 'HDR-2';
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(service.decodes, 2);
      service.output = 'HDR-3';
      service.uploadSucceeds = false;
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(service.decodes, 3);
      await tester.pump(const Duration(seconds: 10));
      await settle(tester);
      expect(service.decodes, 3);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
