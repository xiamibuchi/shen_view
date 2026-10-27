import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/hdr_video_worker.dart';

void main() {
  final samplePath = Directory.systemTemp.uri
      .resolve('图片/杜比.hevc')
      .toFilePath();
  Future<Uint8List> decode(HdrVideoWorker worker, [DecodeRequest? request]) =>
      worker.decode(
        samplePath,
        width: 2,
        height: 1,
        sourceWidth: 2,
        sourceHeight: 1,
        request: request ?? DecodeRequest(),
      );

  test('fragmented frames and Unicode paths reuse one serial worker', () async {
    final process = _Process();
    var starts = 0;
    final worker = HdrVideoWorker(
      startProcess: () async {
        starts++;
        return process;
      },
    );
    addTearDown(worker.close);
    expect(await decode(worker), Uint8List(16));
    expect(await decode(worker), Uint8List(16));
    expect(starts, 1);
    expect(process.paths, [samplePath, samplePath]);
    expect(process.decodeIds.toSet().length, 2);
  });

  test(
    'cancel waits for acknowledgement and preserves the GPU owner',
    () async {
      final began = Completer<ByteData>(), cancelled = Completer<ByteData>();
      final process = _Process()
        ..onDecode = (p, h) {
          began.complete(h);
        }
        ..onCancel = (p, h) {
          cancelled.complete(h);
        };
      var starts = 0, settled = false;
      final worker = HdrVideoWorker(
        startProcess: () async {
          starts++;
          return process;
        },
      );
      addTearDown(worker.close);
      final request = DecodeRequest();
      final pending = decode(worker, request);
      unawaited(
        pending.then(
          (_) {
            settled = true;
          },
          onError: (Object _) {
            settled = true;
          },
        ),
      );
      final checked = expectLater(pending, throwsA(isA<DecodeCancelled>()));
      final first = await began.future;
      request.cancel();
      await cancelled.future;
      await Future<void>.delayed(Duration.zero);
      expect(settled, false);
      process.reply(first, status: 2);
      await checked;
      process.onDecode = null;
      expect(await decode(worker), Uint8List(16));
      expect(starts, 1);
    },
  );

  test('queued cancellation never submits another decode', () async {
    final began = Completer<ByteData>();
    final process = _Process()..onDecode = (p, h) => began.complete(h);
    final worker = HdrVideoWorker(startProcess: () async => process);
    addTearDown(worker.close);
    final first = decode(worker);
    final header = await began.future;
    final request = DecodeRequest();
    final second = decode(worker, request);
    final checked = expectLater(second, throwsA(isA<DecodeCancelled>()));
    request.cancel();
    process.reply(header);
    await first;
    await checked;
    expect(process.decodeIds, hasLength(1));
  });

  for (final fault in ['identity', 'length', 'format', 'truncated']) {
    test('rejects $fault before accepting another worker response', () async {
      final bad = _Process()
        ..onDecode = (p, h) {
          if (fault == 'truncated') {
            p.output.add([1, 2]);
            p.finish();
            return;
          }
          p.reply(
            h,
            id: fault == 'identity' ? 500 : null,
            length: fault == 'length' ? 0xffffffff : null,
            format: fault == 'format' ? 7 : 1,
          );
        };
      final good = _Process();
      var starts = 0;
      final worker = HdrVideoWorker(
        startProcess: () async => starts++ == 0 ? bad : good,
      );
      addTearDown(worker.close);
      await expectLater(decode(worker), throwsFormatException);
      expect(await decode(worker), Uint8List(16));
      expect(starts, 2);
    });
  }

  test(
    'timeout drains the killed process and the next request restarts',
    () async {
      final held = _Process()..onDecode = (p, h) {};
      final good = _Process();
      var starts = 0;
      final worker = HdrVideoWorker(
        timeout: const Duration(milliseconds: 30),
        startProcess: () async => starts++ == 0 ? held : good,
      );
      addTearDown(worker.close);
      await expectLater(decode(worker), throwsA(isA<DecodeTimedOut>()));
      expect(held.killed, true);
      expect(await decode(worker), Uint8List(16));
    },
  );

  test(
    'memory pressure trims GPU state; idle timeout retires the process',
    () async {
      final processes = <_Process>[];
      final worker = HdrVideoWorker(
        idleDuration: const Duration(milliseconds: 20),
        startProcess: () async {
          final p = _Process();
          processes.add(p);
          return p;
        },
      );
      addTearDown(worker.close);
      await decode(worker);
      worker.releaseGpu();
      await decode(worker);
      expect(processes, hasLength(1));
      expect(processes.first.trims, 1);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(await processes.first.exitCode, 0);
      await decode(worker);
      expect(processes, hasLength(2));
    },
  );
  test('GPU release tolerates an already closed worker pipe', () async {
    final process = _Process();
    final worker = HdrVideoWorker(startProcess: () async => process);
    addTearDown(worker.close);
    await decode(worker);
    await process.stdin.close();
    expect(worker.releaseGpu, returnsNormally);
  });
}

class _Process implements Process {
  _Process() {
    stdin = IOSink(_input.sink);
    _input.stream.listen(_consume, onDone: finish);
  }
  final _input = StreamController<List<int>>();
  final output = StreamController<List<int>>();
  final errors = StreamController<List<int>>();
  final _exit = Completer<int>();
  final _pending = <int>[];
  final paths = <String>[];
  final decodeIds = <int>[];
  int trims = 0;
  bool killed = false;
  void Function(_Process, ByteData)? onDecode, onCancel;
  @override
  late final IOSink stdin;
  @override
  Stream<List<int>> get stdout => output.stream;
  @override
  Stream<List<int>> get stderr => errors.stream;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 42;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    finish();
    return true;
  }

  void finish() {
    if (_exit.isCompleted) return;
    _exit.complete(0);
    unawaited(output.close());
    unawaited(errors.close());
  }

  void _consume(List<int> chunk) {
    _pending.addAll(chunk);
    while (_pending.length >= 32) {
      final h = ByteData.sublistView(
        Uint8List.fromList(_pending.take(32).toList()),
      );
      final op = h.getUint32(4, Endian.little);
      final pathLength = op == 1 ? h.getUint32(20, Endian.little) : 0;
      if (_pending.length < 32 + pathLength) return;
      if (op == 1) {
        paths.add(utf8.decode(_pending.sublist(32, 32 + pathLength)));
        decodeIds.add(h.getUint32(8, Endian.little));
      }
      _pending.removeRange(0, 32 + pathLength);
      if (op == 1) {
        if (onDecode case final callback?) {
          callback(this, h);
        } else {
          reply(h);
        }
      } else if (op == 2) {
        onCancel?.call(this, h);
      } else if (op == 3) {
        trims++;
      }
    }
  }

  void reply(
    ByteData request, {
    int status = 0,
    int? id,
    int? length,
    int format = 1,
  }) {
    final w = status == 0 ? request.getUint32(12, Endian.little) : 0;
    final h = status == 0 ? request.getUint32(16, Endian.little) : 0;
    final words = [
      0x31564853,
      status,
      id ?? request.getUint32(8, Endian.little),
      w,
      h,
      length ?? w * h * 8,
      status == 0 ? format : 0,
      status == 0 ? 9 << 16 | 16 : 0,
    ];
    final header = ByteData(32);
    for (var i = 0; i < words.length; i++) {
      header.setUint32(i * 4, words[i], Endian.little);
    }
    final bytes = [...header.buffer.asUint8List(), ...Uint8List(w * h * 8)];
    for (var i = 0; i < bytes.length; i += 3) {
      output.add(bytes.sublist(i, (i + 3).clamp(0, bytes.length)));
    }
  }
}
