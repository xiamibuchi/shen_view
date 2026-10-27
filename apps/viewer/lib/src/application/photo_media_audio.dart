import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'photo_media_info.dart';

/// PCM is backpressured by a small native playback queue, not stored as a WAV.
class PhotoMediaAudio {
  PhotoMediaAudio(
    this.executable,
    this.path,
    this.tracks, {
    this.startOffsetUs = 0,
  });
  static const _channel = MethodChannel('shenview/media_audio');
  static int _serial = 0;
  final String executable, path;
  final int startOffsetUs;
  final List<PhotoAudioTrack> tracks;
  Process? _process;
  int _epoch = 0;
  int? _owner;
  Future<void> _pending = Future.value();
  bool _disposed = false;
  Object? error;

  void synchronize({
    required int positionMs,
    required double speed,
    required bool playing,
    required bool muted,
    required int track,
  }) {
    final clock = Stopwatch()..start();
    final epoch = ++_epoch;
    _process?.kill();
    final oldOwner = _owner;
    if (oldOwner != null) {
      unawaited(
        _channel.invokeMethod<void>('stop', oldOwner).catchError((Object _) {}),
      );
    }
    _pending = _pending.then((_) async {
      await _stop();
      if (_disposed || epoch != _epoch || !playing || muted || tracks.isEmpty) {
        return;
      }
      final owner = ++_serial;
      error = null;
      _owner = owner;
      try {
        await _channel.invokeMethod<void>('open', owner);
        if (_disposed || epoch != _epoch) return;
        final tempo = <String>[];
        var rate = speed;
        while (rate < 0.5) {
          tempo.add('atempo=0.5');
          rate /= 0.5;
        }
        while (rate > 2) {
          tempo.add('atempo=2');
          rate /= 2;
        }
        tempo.add('atempo=$rate');
        tempo.insert(0, 'aresample=async=1:first_pts=0');
        final process = await Process.start(executable, [
          '-nostdin',
          '-v',
          'error',
          '-threads',
          '2',
          '-filter_threads',
          '1',
          '-protocol_whitelist',
          'file,pipe',
          '-ss',
          ((positionMs * 1000 + startOffsetUs) / 1000000).toStringAsFixed(6),
          '-i',
          path,
          '-map',
          '0:${tracks[track.clamp(0, tracks.length - 1)].index}',
          '-vn',
          '-sn',
          '-dn',
          '-af',
          tempo.join(','),
          '-ar',
          '48000',
          '-ac',
          '2',
          '-c:a',
          'pcm_s16le',
          '-f',
          's16le',
          'pipe:1',
        ]);
        _process = process;
        unawaited(process.stderr.drain<void>());
        if (_disposed || epoch != _epoch) {
          process.kill();
          return;
        }
        unawaited(_feed(process, owner, epoch, clock));
      } on Object catch (failure) {
        error = failure;
        await _stop();
      }
    });
  }

  Future<void> _feed(
    Process process,
    int owner,
    int epoch,
    Stopwatch clock,
  ) async {
    var remainder = <int>[];
    var producedFrames = 0;
    try {
      await for (final chunk in process.stdout) {
        final aligned = <int>[...remainder, ...chunk];
        final length = aligned.length - aligned.length % 4;
        remainder = aligned.sublist(length);
        for (var offset = 0; offset < length; offset += 8192) {
          if (_disposed || epoch != _epoch) return;
          var bytes = Uint8List.fromList(
            aligned.sublist(offset, (offset + 8192).clamp(0, length)),
          );
          // Match the video wall clock after process/device startup or a slow
          // decode. Buffering stale PCM would leave sound behind every seek.
          final due = clock.elapsedMicroseconds * 48000 ~/ 1000000;
          final skip = (due - producedFrames).clamp(0, bytes.length ~/ 4);
          producedFrames += bytes.length ~/ 4;
          if (skip > 0) bytes = Uint8List.sublistView(bytes, skip * 4);
          if (bytes.isEmpty) continue;
          while (true) {
            if (_disposed || epoch != _epoch) return;
            final accepted = await _channel.invokeMethod<bool>('write', {
              'owner': owner,
              'bytes': bytes,
            });
            if (accepted == true) break;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        }
      }
      final code = await process.exitCode;
      if (code != 0 && epoch == _epoch) {
        error = StateError('动态照片音频解码失败 ($code)');
      }
    } on Object catch (failure) {
      if (epoch == _epoch) error = failure;
    } finally {
      process.kill();
    }
  }

  Future<void> _stop() async {
    final process = _process;
    _process = null;
    process?.kill();
    if (process != null) await process.exitCode;
    final owner = _owner;
    _owner = null;
    if (owner != null) {
      try {
        await _channel.invokeMethod<void>('stop', owner);
      } on Object {
        /* No audio device leaves video available. */
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _epoch++;
    _process?.kill();
    await _pending;
    await _stop();
  }
}
