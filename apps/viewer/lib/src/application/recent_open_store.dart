import 'dart:io';

import 'package:path/path.dart' as paths;

import 'app_config_store.dart';

enum RecentOpenKind { image, folder, archive }

class RecentOpenEntry {
  const RecentOpenEntry({
    required this.path,
    required this.kind,
    required this.openedAt,
  });

  final String path;
  final RecentOpenKind kind;
  final DateTime openedAt;

  String get name => paths.basename(path);

  Map<String, dynamic> toJson() => {
    'path': path,
    'kind': kind.name,
    'openedAt': openedAt.toUtc().toIso8601String(),
  };

  static RecentOpenEntry? fromJson(Object? value) {
    if (value is! Map || value['path'] is! String) return null;
    final path = paths.normalize(value['path'] as String);
    if (path.isEmpty || !paths.isAbsolute(path)) return null;
    final kind = RecentOpenKind.values
        .where((item) => item.name == value['kind'])
        .firstOrNull;
    final rawDate = value['openedAt'];
    final openedAt = rawDate is String
        ? DateTime.tryParse(rawDate)?.toUtc()
        : null;
    if (kind == null || openedAt == null) return null;
    return RecentOpenEntry(path: path, kind: kind, openedAt: openedAt);
  }
}

class RecentOpenStore {
  RecentOpenStore(this.configStore);

  final AppConfigStore configStore;

  Future<List<RecentOpenEntry>> load({int limit = 20}) async {
    final config = await configStore.readOrEmpty();
    final raw = config['recentOpen'];
    if (raw is! List) return const [];
    final entries = raw
        .map(RecentOpenEntry.fromJson)
        .whereType<RecentOpenEntry>()
        .toList();
    entries.sort((a, b) => b.openedAt.compareTo(a.openedAt));
    return entries.take(limit.clamp(1, 100)).toList(growable: false);
  }

  Future<void> record(
    String path,
    RecentOpenKind kind, {
    int limit = 20,
  }) async {
    final normalized = paths.normalize(paths.absolute(path));
    await configStore.update((config) {
      final settings = config['settings'];
      if (settings is Map && settings['recentOpenEnabled'] == false) {
        return config;
      }
      final savedLimit = settings is Map ? settings['recentOpenLimit'] : null;
      final effectiveLimit = savedLimit is int ? savedLimit : limit;
      final raw = config['recentOpen'];
      final entries = raw is List
          ? raw
                .map(RecentOpenEntry.fromJson)
                .whereType<RecentOpenEntry>()
                .toList()
          : <RecentOpenEntry>[];
      entries.removeWhere((entry) => _samePath(entry.path, normalized));
      entries.insert(
        0,
        RecentOpenEntry(
          path: normalized,
          kind: kind,
          openedAt: DateTime.now().toUtc(),
        ),
      );
      config['recentOpen'] = entries
          .take(effectiveLimit.clamp(1, 100))
          .map((entry) => entry.toJson())
          .toList();
      return config;
    });
  }

  Future<void> remove(String path) => configStore.update((config) {
    final raw = config['recentOpen'];
    if (raw is List) {
      raw.removeWhere((value) {
        final entry = RecentOpenEntry.fromJson(value);
        return entry != null && _samePath(entry.path, path);
      });
      config['recentOpen'] = raw;
    }
    return config;
  });

  Future<void> clear() => configStore.update((config) {
    config['recentOpen'] = <Object>[];
    final session = config['session'];
    if (session is Map) {
      session.remove('recentFolder');
      session.remove('recentFile');
      session.remove('recentReadingPath');
    }
    return config;
  });

  Future<void> trim(int limit) => configStore.update((config) {
    final raw = config['recentOpen'];
    if (raw is List) {
      config['recentOpen'] = raw.take(limit.clamp(1, 100)).toList();
    }
    return config;
  });

  static bool _samePath(String a, String b) {
    final left = paths.normalize(paths.absolute(a));
    final right = paths.normalize(paths.absolute(b));
    return Platform.isWindows
        ? left.toLowerCase() == right.toLowerCase()
        : left == right;
  }
}
