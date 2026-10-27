// AOT microbenchmark: isolate lifecycle, byte transport and real histogram work.
// This does not measure Flutter frames, native codecs or end-to-end navigation.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:shen_view/src/application/image_histogram.dart';

enum _Mode { shortLived, persistentCopy, persistentTransfer }

Object _execute(String operation, Uint8List bytes) {
  if (operation == 'histogram') return ImageHistogram.fromRgba(bytes);
  if (operation == 'toneMapProxy') {
    // Same arithmetic as PlatformDecodedImage's float compatibility fallback;
    // a proxy, deliberately not claimed to exercise the real rendering path.
    final floats = Float32List.view(bytes.buffer, bytes.offsetInBytes);
    final output = Uint8List(floats.length);
    for (var i = 0; i < floats.length; i += 4) {
      for (var c = 0; c < 3; c++) {
        var value = floats[i + c].toDouble();
        if (!value.isFinite || value < 0) value = 0;
        value = value / (1 + value);
        output[i + c] = (math.pow(value, 1 / 2.2) * 255).round();
      }
      output[i + 3] = 255;
    }
    return output;
  }
  return bytes;
}

void _worker(SendPort ready) {
  final inbox = ReceivePort();
  ready.send(inbox.sendPort);
  inbox.listen((Object? message) {
    final (operation, payload, transfer, reply) =
        message as (String, Object, bool, SendPort);
    try {
      final bytes = payload is TransferableTypedData
          ? payload.materialize().asUint8List()
          : payload as Uint8List;
      final result = _execute(operation, bytes);
      reply.send((
        true,
        transfer && result is Uint8List
            ? TransferableTypedData.fromList([result])
            : result,
      ));
    } on Object catch (error) {
      reply.send((false, error.toString()));
    }
  });
}

class _PersistentWorker {
  _PersistentWorker(this.isolate, this.port);
  final Isolate isolate;
  final SendPort port;

  static Future<_PersistentWorker> start() async {
    final ready = ReceivePort();
    try {
      final isolate = await Isolate.spawn(_worker, ready.sendPort);
      return _PersistentWorker(isolate, await ready.first as SendPort);
    } finally {
      ready.close();
    }
  }

  Future<Object> run(String operation, Uint8List bytes, bool transfer) async {
    final reply = ReceivePort();
    try {
      port.send((
        operation,
        transfer ? TransferableTypedData.fromList([bytes]) : bytes,
        transfer,
        reply.sendPort,
      ));
      final (success, result) = await reply.first as (bool, Object);
      if (!success) throw StateError(result.toString());
      return result is TransferableTypedData
          ? result.materialize().asUint8List()
          : result;
    } finally {
      reply.close();
    }
  }
}

int _checksum(Object result) {
  if (result is ImageHistogram) {
    return result.samples + result.luminance.fold(0, (a, b) => a + b);
  }
  final bytes = result as Uint8List;
  var sum = bytes.length;
  for (var i = 0; i < bytes.length; i += 4093) {
    sum += bytes[i];
  }
  return sum;
}

double _percentile(List<double> values, double percentile) {
  final sorted = values.toList()..sort();
  return sorted[(sorted.length * percentile).ceil() - 1];
}

Future<void> main(List<String> arguments) async {
  final rounds = arguments.isEmpty ? 40 : int.parse(arguments.first);
  if (rounds < 20) throw ArgumentError('Use at least 20 samples per mode.');
  final startup = Stopwatch()..start();
  final worker = await _PersistentWorker.start();
  final startupMs = startup.elapsedMicroseconds / 1000;
  final cases = <(String, String, int)>[
    ('emptyTransport', 'transport', 0),
    ('histogram96x72', 'histogram', 96 * 72 * 4),
    ('histogram512x512', 'histogram', 512 * 512 * 4),
    ('transport16MiB', 'transport', 16 * 1024 * 1024),
    ('transport64MiB', 'transport', 64 * 1024 * 1024),
    ('toneMapProxy1024x1024', 'toneMapProxy', 1024 * 1024 * 16),
  ];
  final reports = <Map<String, Object>>[];
  try {
    for (final (name, operation, length) in cases) {
      final bytes = Uint8List(length);
      if (operation == 'toneMapProxy') {
        final floats = Float32List.view(bytes.buffer);
        for (var i = 0; i < floats.length; i++) {
          floats[i] = (i % 97) / 32;
        }
      } else {
        for (var i = 0; i < length; i++) {
          bytes[i] = (i * 31 + i ~/ 7) & 255;
        }
      }
      final expected = _checksum(_execute(operation, bytes));
      final samples = {for (final mode in _Mode.values) mode: <double>[]};
      // Interleave modes to reduce ordering/temperature bias; include input
      // packaging and output materialization, exclude output verification.
      for (var round = -6; round < rounds; round++) {
        for (var offset = 0; offset < _Mode.values.length; offset++) {
          final mode = _Mode.values[(round + 6 + offset) % _Mode.values.length];
          final clock = Stopwatch()..start();
          final result = mode == _Mode.shortLived
              ? await Isolate.run(() => _execute(operation, bytes))
              : await worker.run(
                  operation,
                  bytes,
                  mode == _Mode.persistentTransfer,
                );
          clock.stop();
          if (_checksum(result) != expected) {
            throw StateError('Mismatched output: $name / ${mode.name}');
          }
          if (round >= 0) {
            samples[mode]!.add(clock.elapsedMicroseconds / 1000);
          }
        }
      }
      final report = <String, Object>{
        'case': name,
        'inputBytes': length,
        'samplesPerMode': rounds,
        'results': {
          for (final mode in _Mode.values)
            mode.name: {
              'p50Ms': _percentile(samples[mode]!, .5),
              'p95Ms': _percentile(samples[mode]!, .95),
            },
        },
      };
      reports.add(report);
      stderr.writeln(jsonEncode(report));
    }
  } finally {
    worker.isolate.kill(priority: Isolate.immediate);
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'sdk': Platform.version,
      'processors': Platform.numberOfProcessors,
      'persistentStartupMs': startupMs,
      'cases': reports,
    }),
  );
}
