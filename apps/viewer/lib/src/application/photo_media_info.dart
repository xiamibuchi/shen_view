import 'dart:convert';
import 'dart:math' as math;

import '../domain/animation_timeline.dart';
import 'codec_process.dart';
import 'decode_request.dart';
import 'media_container.dart';

class PhotoAudioTrack {
  const PhotoAudioTrack(this.index, this.codec, this.language);
  final int index;
  final String codec, language;
}

class PhotoMediaInfo {
  PhotoMediaInfo({
    required this.location,
    required this.width,
    required this.height,
    required this.videoIndex,
    required this.codec,
    required this.timestampsUs,
    required this.timeline,
    required this.audioTracks,
    required this.transfer,
    required this.primaries,
    required this.dolbyVision,
    this.alphaIndex,
    this.premultipliedAlpha = false,
    this.seekOriginUs = 0,
  });
  final PhotoMediaLocation location;
  final int width, height, videoIndex;
  final int seekOriginUs;
  final int? alphaIndex;
  final bool premultipliedAlpha, dolbyVision;
  final String codec, transfer, primaries;
  final List<int> timestampsUs;
  final AnimationTimeline timeline;
  final List<PhotoAudioTrack> audioTracks;
  bool get animated => timeline.durations.length > 1;
  bool get hdr =>
      transfer == 'smpte2084' || transfer == 'arib-std-b67' || dolbyVision;

  static Future<PhotoMediaInfo?> inspect(
    String path, {
    DecodeRequest? request,
  }) async {
    final location = await MediaContainer.inspect(path, request: request);
    if (location == null) return null;
    final lease = await location.acquire(path, request: request);
    try {
      final ffprobe = await CodecProcess.locate('ffprobe', 'SHENVIEW_FFPROBE');
      Future<Map<String, dynamic>> probe(
        List<String> args, {
        int maxOutput = 2 * 1024 * 1024,
      }) async {
        final bytes = await CodecProcess.run(
          ffprobe,
          [
            '-v',
            'error',
            '-protocol_whitelist',
            'file,pipe',
            ...args,
            '-of',
            'json',
            lease.file.path,
          ],
          request: request,
          maxOutput: maxOutput,
        );
        return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      }

      final data = await probe(['-show_streams', '-show_format']);
      final streams = (data['streams'] as List).cast<Map<String, dynamic>>();
      int id(Map<String, dynamic> s) => int.tryParse(s['id'].toString()) ?? -1;
      final auxiliary = {
        for (final t in location.tracks.where(
          (t) => t.auxiliary || t.thumbnail,
        ))
          t.id,
      };
      final videos = streams
          .where(
            (s) =>
                s['codec_type'] == 'video' &&
                !auxiliary.contains(id(s)) &&
                (s['disposition'] as Map?)?['attached_pic'] != 1,
          )
          .toList();
      if (videos.isEmpty) {
        throw const FormatException('No primary timed image track');
      }
      final video = videos.first;
      final videoIndex = video['index'] as int;
      final width = (video['width'] as num?)?.toInt() ?? 0;
      final height = (video['height'] as num?)?.toInt() ?? 0;
      if (width <= 0 || height <= 0 || width > 131072 || height > 131072) {
        throw const FormatException('Video dimensions');
      }
      var rotation =
          double.tryParse(
            (video['tags'] as Map?)?['rotate'].toString() ?? '',
          ) ??
          0;
      var dolby = false;
      for (final side
          in (video['side_data_list'] as List? ?? const [])
              .cast<Map<String, dynamic>>()) {
        if (side['rotation'] is num) {
          rotation = (side['rotation'] as num).toDouble();
        }
        if (side['side_data_type'].toString().contains('DOVI')) {
          if (side['el_present_flag'] == 1) {
            throw const FormatException(
              'Dolby Vision enhancement layer required',
            );
          }
          dolby = true;
        }
      }
      final sar = video['sample_aspect_ratio'].toString().split(':');
      final sarDen = sar.length == 2 ? double.tryParse(sar[1]) ?? 0 : 0;
      final aspect = sarDen > 0
          ? (double.tryParse(sar[0]) ?? sarDen) / sarDen
          : 1.0;
      final displayWidth = (width * aspect).round().clamp(1, 131072);
      final swapped = rotation.round().abs() % 180 == 90;
      final packets = await probe([
        '-select_streams',
        '$videoIndex',
        '-show_packets',
        '-show_entries',
        'packet=pts_time,duration_time,flags',
      ], maxOutput: 16 * 1024 * 1024);
      final samples = <int, int>{};
      final startTime = double.tryParse(video['start_time'].toString()) ?? 0;
      for (final packet
          in (packets['packets'] as List? ?? const [])
              .cast<Map<String, dynamic>>()) {
        final pts = double.tryParse(packet['pts_time'].toString());
        if (pts == null ||
            !pts.isFinite ||
            pts + 0.000001 < startTime ||
            packet['flags'].toString().contains('D')) {
          continue;
        }
        samples[(pts * 1000000).round()] =
            ((double.tryParse(packet['duration_time'].toString()) ?? 0) *
                    1000000)
                .round();
      }
      if (samples.isEmpty || samples.length > 120000) {
        throw const FormatException('Video timeline bounds');
      }
      final pts = samples.keys.toList()..sort();
      final origin = pts.first;
      final times = [for (final time in pts) time - origin];
      final durations = <int>[];
      for (var i = 0; i < pts.length; i++) {
        final duration = i + 1 < pts.length
            ? pts[i + 1] - pts[i]
            : samples[pts[i]]!;
        final fallback = i > 0 ? pts[i] - pts[i - 1] : 100000;
        durations.add(
          math.max(
            1,
            ((times[i] + (duration > 0 ? duration : fallback)) / 1000).round() -
                (times[i] / 1000).round(),
          ),
        );
      }
      final alphas = location.tracks.where(
        (t) => t.alpha && (t.references['auxl']?.contains(id(video)) ?? false),
      );
      int? alphaIndex;
      if (alphas.isNotEmpty) {
        final matching = streams.where(
          (s) => id(s) == alphas.first.id && s['codec_type'] == 'video',
        );
        if (matching.isEmpty) {
          throw const FormatException('Missing HEIF alpha sequence');
        }
        alphaIndex = matching.first['index'] as int;
        final alphaPackets = await probe([
          '-select_streams',
          '$alphaIndex',
          '-show_packets',
          '-show_entries',
          'packet=pts_time,flags',
        ], maxOutput: 16 * 1024 * 1024);
        final alphaTimes = <int>{};
        for (final packet
            in (alphaPackets['packets'] as List? ?? const [])
                .cast<Map<String, dynamic>>()) {
          final time = double.tryParse(packet['pts_time'].toString());
          if (time != null &&
              time.isFinite &&
              time + 0.000001 >= startTime &&
              !packet['flags'].toString().contains('D')) {
            alphaTimes.add((time * 1000000).round());
          }
        }
        final alphaPts = alphaTimes.toList()..sort();
        if (alphaPts.length != pts.length ||
            Iterable<int>.generate(pts.length)
                .any((i) => (alphaPts[i] - pts[i]).abs() > 1)) {
          throw const FormatException('HEIF alpha and color timelines differ');
        }
      }
      final audioStreams =
          streams.where((s) => s['codec_type'] == 'audio').toList()..sort(
            (a, b) => (((b['disposition'] as Map?)?['default'] as int?) ?? 0)
                .compareTo(
                  (((a['disposition'] as Map?)?['default'] as int?) ?? 0),
                ),
          );
      return PhotoMediaInfo(
        location: location,
        width: swapped ? height : displayWidth,
        height: swapped ? displayWidth : height,
        videoIndex: videoIndex,
        codec: video['codec_name'].toString(),
        timestampsUs: List.unmodifiable(times),
        seekOriginUs: math.max(
          0,
          origin -
              ((double.tryParse(
                            (data['format'] as Map?)?['start_time']
                                    .toString() ??
                                '',
                          ) ??
                          0) *
                      1000000)
                  .round(),
        ),
        timeline: AnimationTimeline(
          durations,
          totalPlays: 1,
          minimumDelayMs: 1,
        ),
        audioTracks: [
          for (final s in audioStreams)
            PhotoAudioTrack(
              s['index'] as int,
              s['codec_name'].toString(),
              ((s['tags'] as Map?)?['language'] ?? 'und').toString(),
            ),
        ],
        transfer: video['color_transfer'].toString(),
        primaries: video['color_primaries'].toString(),
        dolbyVision: dolby,
        alphaIndex: alphaIndex,
        premultipliedAlpha: location.tracks.any(
          (t) =>
              alphaIndex != null &&
              t.id == id(video) &&
              (t.references['prem']?.contains(alphas.first.id) ?? false),
        ),
      );
    } finally {
      await lease.release();
    }
  }
}
