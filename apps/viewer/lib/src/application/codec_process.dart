import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as paths;

import 'decode_request.dart';
import 'development_codec_paths.dart';

/// Optional codecs are isolated processes with bounded I/O and cancellation.
class CodecProcess {
  static int _running = 0;
  static final _waiting = <Completer<void>>[];

  static Future<void> _acquire(DecodeRequest? request) async {
    request?.throwIfCancelled();
    while (_running >= 2) {
      final ready = Completer<void>();
      void cancel() {
        _waiting.remove(ready);
        if (!ready.isCompleted) ready.complete();
      }

      _waiting.add(ready);
      request?.addCancelListener(cancel);
      try {
        await ready.future;
      } finally {
        request?.removeCancelListener(cancel);
      }
      request?.throwIfCancelled();
    }
    _running++;
  }

  static void _release() {
    _running--;
    if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
  }

  static Future<String> locate(String name, String environment) async {
    final override = Platform.environment[environment];
    if (override != null && await File(override).exists()) return override;
    final executable = Platform.isWindows ? '$name.exe' : name;
    final candidates = [
      if (Platform.isWindows && name == 'viewer_heif_gainmap')
        paths.join(
          paths.dirname(Platform.resolvedExecutable),
          'codecs',
          'imagemagick',
          executable,
        ),
      if (name == 'ffmpeg' ||
          name == 'ffprobe' ||
          name == 'viewer_hdr_video') ...[
        paths.join(
          paths.dirname(Platform.resolvedExecutable),
          'codecs',
          'ffmpeg',
          executable,
        ),
        if (Platform.isMacOS)
          paths.join(
            paths.dirname(Platform.resolvedExecutable),
            '../Helpers',
            executable,
          ),
        ...developmentCodecCandidates(
          'ffmpeg/${Platform.isWindows ? 'windows-x64' : 'macos'}/runtime/$executable',
        ),
      ],
      paths.join(
        paths.dirname(Platform.resolvedExecutable),
        'codecs',
        executable,
      ),
      if (Platform.isMacOS)
        paths.join(
          paths.dirname(Platform.resolvedExecutable),
          '../Resources/codecs',
          executable,
        ),
      ...developmentCodecCandidates('avif-codecs/bin/$executable'),
      ...developmentCodecCandidates('hdr-codecs/bin/$executable'),
      ...developmentCodecCandidates('svg-codecs/bin/$executable'),
      if (Platform.isMacOS) '/opt/homebrew/bin/$name',
    ];
    for (final path in candidates) {
      if (await File(path).exists()) return File(path).absolute.path;
    }
    final lookup = await Process.run(
      Platform.isWindows ? 'where.exe' : 'which',
      [executable],
    );
    if (lookup.exitCode == 0) {
      final first = lookup.stdout
          .toString()
          .trim()
          .split(RegExp(r'[\r\n]+'))
          .first;
      if (await File(first).exists()) return first;
    }
    throw StateError('缺少 $name 解码组件，请安装完整发行包或设置 $environment。');
  }

  static Future<Uint8List> run(
    String executable,
    List<String> arguments, {
    DecodeRequest? request,
    Uint8List? input,
    Duration timeout = const Duration(seconds: 40),
    int maxOutput = 72 * 1024 * 1024,
  }) async {
    await _acquire(request);
    try {
      return await _run(
        executable,
        arguments,
        request: request,
        input: input,
        timeout: timeout,
        maxOutput: maxOutput,
      );
    } finally {
      _release();
    }
  }

  static Future<T> runTask<T>(
    Future<T> Function() operation, {
    DecodeRequest? request,
  }) async {
    await _acquire(request);
    try {
      request?.throwIfCancelled();
      return await operation();
    } finally {
      _release();
    }
  }

  static Future<Uint8List> _run(
    String executable,
    List<String> arguments, {
    DecodeRequest? request,
    Uint8List? input,
    required Duration timeout,
    required int maxOutput,
  }) async {
    request?.throwIfCancelled();
    final process = await Process.start(executable, arguments);
    void cancel() {
      process.kill();
    }

    request?.addCancelListener(cancel);
    var timedOut = false, overflow = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      process.kill();
    });
    final output = BytesBuilder(copy: false),
        errors = BytesBuilder(copy: false);
    final stderrDone = process.stderr.forEach((bytes) {
      if (errors.length < 16384) {
        errors.add(bytes.take(16384 - errors.length).toList());
      }
    });
    final stdoutDone = process.stdout.forEach((bytes) {
      if (output.length + bytes.length > maxOutput) {
        overflow = true;
        process.kill();
      } else {
        output.add(bytes);
      }
    });
    try {
      if (input != null) process.stdin.add(input);
      try {
        await process.stdin.close();
      } catch (_) {
        /* Report process failure below. */
      }
      final code = await process.exitCode;
      await Future.wait([stdoutDone, stderrDone]);
      request?.throwIfCancelled();
      if (timedOut) throw DecodeTimedOut('解码处理超时，请重试或选择较小的文件。');
      if (overflow) throw DecodeBudgetExceeded('解码结果超过内存预算。');
      if (code != 0) {
        throw StateError(
          '解码组件处理失败：${utf8.decode(errors.takeBytes(), allowMalformed: true)}',
        );
      }
      return output.takeBytes();
    } finally {
      timer.cancel();
      request?.removeCancelListener(cancel);
      process.kill();
    }
  }
}
