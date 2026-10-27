import '../domain/picked_color.dart';
import 'app_config_store.dart';

/// Color-only history shared by windows, merged under the config process lock.
class RecentColorStore {
  RecentColorStore(this.configStore);

  final AppConfigStore configStore;
  static const limit = 8;

  Future<List<PickedColor>> load() async =>
      _read((await configStore.readOrEmpty())['recentColors']);

  Future<List<PickedColor>> record(PickedColor color) async {
    var colors = <PickedColor>[];
    await configStore.update((config) {
      colors = [
        color,
        ..._read(config['recentColors'])
            .where((old) => old.hexAlpha != color.hexAlpha),
      ].take(limit).toList();
      config['recentColors'] = colors
          .map((item) => [item.red, item.green, item.blue, item.alpha])
          .toList();
      return config;
    });
    return colors;
  }

  static List<PickedColor> _read(Object? raw) {
    final colors = <PickedColor>[];
    final seen = <String>{};
    if (raw is! List) return colors;
    for (final item in raw) {
      if (item is! List ||
          item.length != 4 ||
          item.any(
            (channel) => channel is! int || channel < 0 || channel > 255,
          )) {
        continue;
      }
      final color = PickedColor(
        red: item[0] as int,
        green: item[1] as int,
        blue: item[2] as int,
        alpha: item[3] as int,
      );
      if (seen.add(color.hexAlpha)) colors.add(color);
      if (colors.length == limit) break;
    }
    return colors;
  }
}
