import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/system_resource_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/system_resources');
  const service = SystemResourceService(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('reads host bytes and asks for the actual cache volume', () async {
    final cachePath = Directory.systemTemp.uri
        .resolve('cache/uncreated')
        .toFilePath();
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'read');
      expect(call.arguments, {'diskPath': cachePath});
      return {
        'physicalMemoryBytes': 16 * 1024 * 1024 * 1024,
        'availableMemoryBytes': 3 * 1024 * 1024 * 1024,
        'availableDiskBytes': 100 * 1024 * 1024 * 1024,
        'diskCapacityBytes': 512 * 1024 * 1024 * 1024,
      };
    });
    final snapshot = await service.read(diskPath: cachePath);
    expect(snapshot!.physicalMemoryBytes, 16 * 1024 * 1024 * 1024);
    expect(snapshot.availableMemoryBytes, 3 * 1024 * 1024 * 1024);
    expect(snapshot.availableDiskBytes, 100 * 1024 * 1024 * 1024);
    expect(snapshot.diskCapacityBytes, 512 * 1024 * 1024 * 1024);
  });

  test('missing plugin or failed measurement stays unknown', () async {
    expect(await service.read(), isNull);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'unavailable'),
    );
    expect(await service.read(), isNull);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'physicalMemoryBytes': -1,
        'availableMemoryBytes': 'unknown',
      },
    );
    expect(await service.read(), isNull);
  });

  test('zero availability and partial data remain actionable', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'availableMemoryBytes': 0},
    );
    final snapshot = await service.read();
    expect(snapshot!.availableMemoryBytes, 0);
    expect(snapshot.physicalMemoryBytes, isNull);
    expect(snapshot.availableDiskBytes, isNull);
  });

  test(
    'bounds availability against physical memory and volume capacity',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'physicalMemoryBytes': 100,
          'availableMemoryBytes': 500,
          'diskCapacityBytes': 1000,
          'availableDiskBytes': 9000,
        },
      );
      final snapshot = await service.read();
      expect(snapshot!.availableMemoryBytes, 100);
      expect(snapshot.availableDiskBytes, 1000);
    },
  );
}
