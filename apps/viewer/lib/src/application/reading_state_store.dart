import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as paths;

import '../domain/reading_state.dart';
import 'app_config_store.dart';

/// Shares the app config write queue and keeps loaded books available synchronously.
class ReadingStateStore {
  ReadingStateStore(this.configStore);

  final AppConfigStore configStore;
  final _states = <String, ReadingState>{};
  Future<void>? _loading;
  Future<void> _writing = Future<void>.value();

  static String folderKey(String path) => 'folder:${_canonical(path)}';
  static String archiveKey(String path, {String? innerPath}) =>
      'archive:${jsonEncode([_canonical(path), ?innerPath])}';

  static String _canonical(String path) {
    final absolute = paths.normalize(paths.absolute(path));
    return Platform.isWindows ? absolute.toLowerCase() : absolute;
  }

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final config = await configStore.readOrEmpty();
    final history = config['readingHistory'];
    if (history is! Map) return;
    for (final entry in history.entries) {
      if (entry.key is String && entry.value is Map) {
        _states[entry.key as String] = ReadingState.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
    }
  }

  ReadingState? operator [](String key) => _states[key];

  Future<void> save(String key, ReadingState state) {
    final previous = _states[key];
    if (previous != null &&
        jsonEncode(previous.toJson()) == jsonEncode(state.toJson())) {
      return _writing;
    }
    _states.remove(key);
    _states[key] = state;
    while (_states.length > 200) {
      _states.remove(_states.keys.first);
    }
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final value = {...state.toJson(), 'updatedAt': updatedAt};
    return _writing = configStore.update((config) {
      final raw = config['readingHistory'];
      final history = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      final existing = history[key];
      final existingTime = existing is Map && existing['updatedAt'] is String
          ? DateTime.tryParse(existing['updatedAt'] as String)
          : null;
      if (existingTime != null &&
          existingTime.isAfter(DateTime.parse(updatedAt))) {
        return config;
      }
      history.remove(key);
      history[key] = value;
      while (history.length > 200) {
        history.remove(history.keys.first);
      }
      config['readingHistory'] = history;
      return config;
    });
  }
}
