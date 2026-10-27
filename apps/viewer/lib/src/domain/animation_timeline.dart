import 'dart:typed_data';

enum AnimationLoopMode { file, infinite, once }

const animationPlaybackSpeeds = [0.25, 0.5, 1.0, 1.5, 2.0];

/// Header-only timing information. No pixels are decoded to build the timeline.
class AnimationTimeline {
  AnimationTimeline(
    List<int> durations, {
    this.totalPlays = 0,
    int minimumDelayMs = 16,
  }) : durations = List.unmodifiable(
         durations.map(
           (ms) => ms <= 0 ? 100 : ms.clamp(minimumDelayMs, 0x7fffffff),
         ),
       ) {
    var time = 0;
    starts = List.unmodifiable(
      this.durations.map((delay) {
        final start = time;
        time += delay;
        return start;
      }),
    );
    durationMs = time;
  }

  final List<int> durations;
  final int totalPlays; // 0 means infinite; otherwise includes the first play.
  late final List<int> starts;
  late final int durationMs;

  static int normalizeDelay(int ms) => ms <= 0 ? 100 : ms.clamp(16, 0x7fffffff);

  int frameAt(int ms) {
    var lo = 0;
    var hi = starts.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (starts[mid] <= ms) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return (lo - 1).clamp(0, starts.length - 1);
  }

  static AnimationTimeline? parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final delays = <int>[];
    var plays = 1;
    bool tag(int p, String s) =>
        p + s.length <= bytes.length &&
        List.generate(
          s.length,
          (i) => bytes[p + i] == s.codeUnitAt(i),
        ).every((v) => v);
    try {
      if (tag(0, 'GIF')) {
        var p = 13;
        if (bytes[10] & 0x80 != 0) p += 3 * (1 << ((bytes[10] & 7) + 1));
        var delay = 100;
        int skipBlocks(int at) {
          while (bytes[at] != 0) {
            at += bytes[at] + 1;
          }
          return at + 1;
        }

        while (p < bytes.length && bytes[p] != 0x3b) {
          if (bytes[p] == 0x21) {
            final kind = bytes[p + 1];
            p += 2;
            if (kind == 0xf9 && bytes[p] == 4) {
              delay = data.getUint16(p + 2, Endian.little) * 10;
            }
            if (kind == 0xff &&
                bytes[p] == 11 &&
                (tag(p + 1, 'NETSCAPE2.0') || tag(p + 1, 'ANIMEXTS1.0')) &&
                bytes[p + 12] == 3 &&
                bytes[p + 13] == 1) {
              final repeats = data.getUint16(p + 14, Endian.little);
              plays = repeats == 0 ? 0 : repeats + 1;
            }
            p = skipBlocks(p);
          } else if (bytes[p] == 0x2c) {
            final flags = bytes[p + 9];
            p += 10;
            if (flags & 0x80 != 0) p += 3 * (1 << ((flags & 7) + 1));
            p = skipBlocks(p + 1);
            delays.add(delay);
            delay = 100;
          } else {
            return null;
          }
        }
      } else if (tag(0, 'RIFF') && tag(8, 'WEBP')) {
        for (var p = 12; p + 8 <= bytes.length;) {
          final size = data.getUint32(p + 4, Endian.little);
          if (p + 8 + size > bytes.length) return null;
          if (tag(p, 'ANIM') && size >= 6) {
            plays = data.getUint16(p + 12, Endian.little);
          }
          if (tag(p, 'ANMF') && size >= 16) {
            delays.add(
              bytes[p + 20] | bytes[p + 21] << 8 | bytes[p + 22] << 16,
            );
          }
          p += 8 + size + (size & 1);
        }
      } else if (bytes.length >= 8 && bytes[0] == 137 && tag(1, 'PNG')) {
        for (var p = 8; p + 12 <= bytes.length;) {
          final size = data.getUint32(p);
          if (p + 12 + size > bytes.length) return null;
          if (tag(p + 4, 'acTL') && size == 8) plays = data.getUint32(p + 12);
          if (tag(p + 4, 'fcTL') && size == 26) {
            final denominator = data.getUint16(p + 30);
            delays.add(
              (1000 *
                      data.getUint16(p + 28) /
                      (denominator == 0 ? 100 : denominator))
                  .round(),
            );
          }
          p += size + 12;
        }
      }
    } on RangeError {
      return null;
    }
    return delays.isEmpty ? null : AnimationTimeline(delays, totalPlays: plays);
  }
}
