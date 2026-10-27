import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'codec_process.dart';
import 'decode_request.dart';
import 'hdr_frame.dart';

class HdrWorkerUnavailable implements Exception {}

/// One serial GPU owner shared by source decodes, never by UI surfaces.
class HdrVideoWorker {
  HdrVideoWorker({
    Future<Process> Function()? startProcess,
    this.timeout = const Duration(seconds: 40),
    this.idleDuration = const Duration(seconds: 30),
  }) : _startProcess = startProcess ?? _start;

  static final shared = HdrVideoWorker();
  static const _magic = 0x31564853;
  final Future<Process> Function() _startProcess;
  final Duration timeout;
  final Duration idleDuration;
  Future<void> _tail = Future.value();
  Future<void>? _closing;
  Process? _process;
  _PixelReader? _reader;
  StreamSubscription<List<int>>? _stderr;
  Timer? _idle;
  int _nextId = 0;

  static Future<Process> _start() async {
    late final String path;
    try {
      path = await CodecProcess.locate(
        'viewer_hdr_video',
        'SHENVIEW_HDR_VIDEO',
      );
    } on StateError {
      throw HdrWorkerUnavailable();
    }
    return Process.start(path, const []);
  }

  Future<Uint8List> decode(
    String path, {
    required int width,
    required int height,
    required int sourceWidth,
    required int sourceHeight,
    required DecodeRequest request,
  }) {
    final result = Completer<Uint8List>();
    _tail = _tail.then((_) async {
      try {
        request.throwIfCancelled();
        result.complete(
          await CodecProcess.runTask(
            () => _decode(
              path,
              width,
              height,
              sourceWidth,
              sourceHeight,
              request,
            ),
            request: request,
          ),
        );
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<Uint8List> _decode(
    String path,
    int width,
    int height,
    int sourceWidth,
    int sourceHeight,
    DecodeRequest request,
  ) async {
    final encodedPath = utf8.encode(path);
    if (width < 1 ||
        height < 1 ||
        width > 2048 ||
        height > 2048 ||
        width * height > HdrFrame.maxPixels ||
        sourceWidth < 1 ||
        sourceHeight < 1 ||
        sourceWidth * sourceHeight > 128 * 1024 * 1024 ||
        encodedPath.isEmpty ||
        encodedPath.length > 32768 ||
        encodedPath.contains(0)) {
      throw const FormatException('HDR worker request bounds');
    }
    _idle?.cancel();
    await _closing;
    request.throwIfCancelled();
    if (_process == null) {
      final started = _process = await _startProcess();
      _reader = _PixelReader(started.stdout);
      _stderr = started.stderr.listen((_) {});
      unawaited(
        started.stdin.done.catchError((_) {
          started.kill();
        }),
      );
    }
    final process = _process!;
    final id = _nextId = _nextId >= 0x7fffffff ? 1 : _nextId + 1;
    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      process.kill();
    });
    void cancel() {
      // The response acknowledges real decoder/GPU cleanup. Do not release
      // the caller's byte reservation while a cancelled worker still runs.
      _control(process, [2, id, 0, 0, 0, 0, 0]);
    }

    try {
      _send(process, [
        1,
        id,
        width,
        height,
        encodedPath.length,
        sourceWidth,
        sourceHeight,
      ], encodedPath);
      request.addCancelListener(cancel);
      final reader = _reader!;
      final header = ByteData.sublistView(await reader.read(32));
      int word(int at) => header.getUint32(at * 4, Endian.little);
      final status = word(1), length = word(5);
      if (word(0) != _magic || word(2) != id) {
        throw const FormatException('HDR worker response identity');
      }
      if (status != 0) {
        if (status > 2 ||
            word(3) != 0 ||
            word(4) != 0 ||
            word(6) != 0 ||
            word(7) != 0 ||
            length > 4096 ||
            (status == 2 && length != 0)) {
          throw const FormatException('HDR worker error bounds');
        }
        final message = utf8.decode(
          await reader.read(length),
          allowMalformed: true,
        );
        if (status == 2) throw DecodeCancelled();
        throw StateError(message);
      }
      if (word(3) != width ||
          word(4) != height ||
          length != width * height * 8 ||
          word(6) != 1 ||
          word(7) != (9 << 16 | 16)) {
        throw const FormatException('HDR worker pixel bounds');
      }
      final pixels = await reader.read(length);
      request.throwIfCancelled();
      return pixels;
    } on DecodeCancelled {
      rethrow;
    } catch (_) {
      await _stop();
      if (timedOut) throw DecodeTimedOut('HDR 解码处理超时，请重试。');
      request.throwIfCancelled();
      rethrow;
    } finally {
      request.removeCancelListener(cancel);
      timer.cancel();
      if (identical(_process, process)) {
        _idle = Timer(idleDuration, () => unawaited(_stop()));
      }
    }
  }

  void _send(Process process, List<int> words, [List<int> body = const []]) {
    final header = ByteData(32)..setUint32(0, _magic, Endian.little);
    for (var i = 0; i < words.length; i++) {
      header.setUint32(4 + i * 4, words[i], Endian.little);
    }
    process.stdin.add(header.buffer.asUint8List());
    if (body.isNotEmpty) process.stdin.add(body);
  }

  /// GPU memory can be discarded without interrupting an active source lease.
  void releaseGpu() {
    final process = _process;
    if (process != null) _control(process, [3, 1, 0, 0, 0, 0, 0]);
  }

  void _control(Process process, List<int> words) {
    try {
      _send(process, words);
    } on StateError {
      process.kill();
    } on IOException {
      process.kill();
    }
  }

  Future<void> close() async {
    await _tail;
    await _stop();
  }

  Future<void> _stop() {
    _idle?.cancel();
    return _closing ??= _closeProcess().whenComplete(() => _closing = null);
  }

  Future<void> _closeProcess() async {
    final process = _process;
    final reader = _reader;
    final stderr = _stderr;
    _process = null;
    _reader = null;
    _stderr = null;
    if (process == null) return;
    try {
      unawaited(process.stdin.close().catchError((_) {}));
      await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process.kill();
          return process.exitCode;
        },
      );
    } finally {
      await reader?.close();
      await stderr?.cancel();
    }
  }
}

class _PixelReader {
  _PixelReader(Stream<List<int>> stream) : _chunks = StreamIterator(stream);
  final StreamIterator<List<int>> _chunks;
  List<int> _chunk = const [];
  int _offset = 0;

  Future<Uint8List> read(int length) async {
    final output = Uint8List(length);
    var at = 0;
    while (at < length) {
      if (_offset == _chunk.length) {
        if (!await _chunks.moveNext()) {
          throw const FormatException('Truncated HDR worker response');
        }
        _chunk = _chunks.current;
        _offset = 0;
      }
      final count = (length - at).clamp(0, _chunk.length - _offset);
      output.setRange(at, at + count, _chunk, _offset);
      at += count;
      _offset += count;
    }
    return output;
  }

  Future<void> close() => _chunks.cancel();
}
