import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shen_view/src/application/hdr_display_service.dart';
import 'package:shen_view/src/application/hdr_frame.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native HDR capability, FP16 readback and safe SDR fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('HDR pipeline probe'))),
      ),
    );
    await tester.pumpAndSettle();
    final service = HdrDisplayService();
    final caps = await service.capabilities();
    final report = <String, Object>{
      'platform': Platform.operatingSystem,
      'available': caps.available,
      'output': caps.output,
      'headroom': caps.headroom,
      'reason': caps.reason,
      'colorManagement': caps.colorManagement,
      if (caps.displayProfile != null) 'displayProfile': caps.displayProfile!,
    };
    if (Platform.isWindows) {
      final red = await HdrDisplayService.channel.invokeMethod<double>(
        'verifyFloatPipeline',
      );
      // 8 * reference white 203 / scRGB white 80 = 20.3, never clamped to 1.
      expect(red, closeTo(20.3, 0.03));
      report['fp16ReadbackRed'] = red!;
      final mapped = await HdrDisplayService.channel.invokeMethod<double>(
        'verifyDisplayMapping',
      );
      // A 5x scRGB headroom display tone-maps an 8x highlight while keeping
      // the reference white unchanged.
      expect(mapped, closeTo(4.70, 0.08));
      report['displayAwareMappingRed'] = mapped!;
      final transparent = await HdrDisplayService.channel
          .invokeMapMethod<String, dynamic>('verifyPremultipliedPipeline');
      expect(transparent?['red'], closeTo(10.15, 0.03));
      expect(transparent?['alpha'], closeTo(0.5, 0.001));
      report['premultipliedReadback'] = transparent!;
      final composition = await HdrDisplayService.channel.invokeMethod<bool>(
        'verifyComposition',
      );
      expect(composition, true);
      report['scRGBCompositionProbe'] = composition!;
    }
    final data = Float32List.fromList([8, 4, 2, 1]);
    const id = 9000001;
    addTearDown(() => service.remove(id));
    final uploaded = await service.upload(
      id,
      HdrFrame(1, 1, data.buffer.asUint8List()),
    );
    report['uploaded'] = uploaded;
    expect(uploaded, caps.available);
    if (uploaded) {
      final okay = await service.geometry({
        'id': id,
        'visible': true,
        'geometry': Float64List.fromList([
          100,
          100,
          200,
          100,
          100,
          200,
          80,
          80,
          240,
          240,
        ]),
      });
      expect(okay, true);
      await tester.pump(const Duration(milliseconds: 500));
      final diagnostics = await HdrDisplayService.channel
          .invokeMapMethod<String, dynamic>('diagnostics');
      expect(diagnostics?['activeFrames'], 1);
      expect(diagnostics?['visibleFrames'], 1);
      report['diagnostics'] = diagnostics!;
      expect(await service.geometry({'id': id, 'visible': false}), true);
      final hidden = await HdrDisplayService.channel
          .invokeMapMethod<String, dynamic>('diagnostics');
      expect(hidden?['visibleFrames'], 0);
    } else {
      // A genuine SDR machine must not accidentally expose an HDR surface.
      expect(await service.geometry({'id': id, 'visible': true}), false);
    }
    expect(
      await service.upload(id + 1, HdrFrame(4096, 4096, Uint8List(0))),
      false,
    );
    await service.remove(id);
    binding.reportData = report;
    Directory('../../artifacts/hdr').createSync(recursive: true);
    File('../../artifacts/hdr/native-probe.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
