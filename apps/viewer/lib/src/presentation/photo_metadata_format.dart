import '../../l10n/app_localizations.dart';

List<(String, String)> cameraMetadataRows(
  Map<String, String> values,
  AppLocalizations l10n,
) {
  String? get(String key) => values.entries
      .where((e) => e.key.toLowerCase() == key.toLowerCase())
      .map((e) => e.value.trim())
      .where((v) => v.isNotEmpty)
      .firstOrNull;
  final rows = <(String, String)>[];
  final make = get('make'), model = get('model');
  final device =
      model != null &&
          make != null &&
          model.toLowerCase().startsWith(make.toLowerCase())
      ? model
      : [make, model].whereType<String>().join(' ');
  if (device.isNotEmpty) rows.add((l10n.device, device));
  for (final (label, key) in [
    (l10n.captureTime, 'dateTimeOriginal'),
    (l10n.lens, 'lensModel'),
    (l10n.aperture, 'fNumber'),
    (l10n.shutterSpeed, 'exposureTime'),
    (l10n.iso, 'iso'),
    (l10n.focalLength, 'focalLength'),
    (l10n.exposureCompensation, 'exposureBias'),
    (l10n.whiteBalance, 'whiteBalance'),
    (l10n.flash, 'flash'),
  ]) {
    final raw = get(key);
    if (raw == null) continue;
    final number = photoNumber(raw);
    final String value;
    switch (key) {
      case 'dateTimeOriginal':
        value = raw
            .replaceFirstMapped(
              RegExp(r'^(\d{4}):(\d{2}):(\d{2})'),
              (m) => '${m[1]}-${m[2]}-${m[3]}',
            )
            .replaceFirst('T', ' ');
      case 'fNumber':
        if (number != null && number <= 0) continue;
        value = number == null ? raw : 'f/${_decimal(number)}';
      case 'exposureTime':
        if (number != null && number <= 0) continue;
        value = number == null
            ? raw
            : number < 1
            ? '1/${_decimal(1 / number)} s'
            : '${_decimal(number)} s';
      case 'focalLength':
        if (number != null && number <= 0) continue;
        value = number == null ? raw : '${_decimal(number)} mm';
      case 'exposureBias':
        value = number == null
            ? raw
            : '${number > 0 ? '+' : ''}${_decimal(number)} EV';
      case 'iso':
        if (number != null && number <= 0) continue;
        value = number == null ? raw : _decimal(number);
      case 'whiteBalance':
        value = switch (number) {
          0 => l10n.photoAuto,
          1 => l10n.photoManual,
          _ => raw,
        };
      case 'flash':
        final bits = int.tryParse(raw);
        if (bits == null || bits < 0 || bits > 127) {
          value = raw;
          break;
        }
        if (bits & 32 != 0) {
          value = l10n.flashUnavailable;
          break;
        }
        value = [
          bits & 1 != 0 ? l10n.flashFired : l10n.flashNotFired,
          if ((bits >> 3) & 3 == 3) l10n.photoAuto,
          if (bits & 64 != 0) l10n.flashRedEye,
        ].join(' · ');
      default:
        value = raw;
    }
    rows.add((label, value));
  }
  final lat = photoCoordinate(
    get('gpsLatitude'),
    get('gpsLatitudeRef'),
    latitude: true,
  );
  final lon = photoCoordinate(
    get('gpsLongitude'),
    get('gpsLongitudeRef'),
    latitude: false,
  );
  if (lat != null && lon != null) rows.add((l10n.location, '$lat, $lon'));
  return rows;
}

List<(String, String)> descriptiveMetadataRows(
  Map<String, String> values,
  AppLocalizations l10n,
) => [
  for (final (key, label) in [
    ('title', l10n.photoTitle),
    ('description', l10n.photoDescription),
    ('creator', l10n.photoCreator),
    ('copyright', l10n.photoCopyright),
    ('rating', l10n.photoRating),
    ('keywords', l10n.photoKeywords),
  ])
    if (values[key]?.trim() case final String text when text.isNotEmpty)
      (label, key == 'rating' && text == '-1' ? l10n.photoRejected : text),
];

double? photoNumber(String text) {
  final parts = text.trim().split('/');
  final numerator = double.tryParse(parts.first);
  final denominator = parts.length == 2 ? double.tryParse(parts[1]) : 1.0;
  if (parts.length > 2 ||
      numerator == null ||
      denominator == null ||
      denominator == 0) {
    return null;
  }
  final value = numerator / denominator;
  return value.isFinite ? value : null;
}

String _decimal(double n) =>
    n.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

String? photoCoordinate(
  String? text,
  String? reference, {
  required bool latitude,
}) {
  if (text == null) return null;
  var raw = text.trim().replaceAll(RegExp(r'[\[\]]'), '');
  final suffix = RegExp(r'[NSEW]$', caseSensitive: false).firstMatch(raw);
  final direction = (reference?.trim().isNotEmpty ?? false)
      ? reference!.trim().toUpperCase()
      : suffix?.group(0)?.toUpperCase();
  if (suffix != null) raw = raw.substring(0, suffix.start).trim();
  if (direction != null &&
      !(latitude ? {'N', 'S'} : {'E', 'W'}).contains(direction)) {
    return null;
  }
  final parts = raw
      .split(RegExp(r'[\s,]+'))
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.isEmpty || parts.length > 3) return null;
  final numbers = parts.map(photoNumber).toList();
  if (numbers.any((n) => n == null)) return null;
  final degrees = numbers[0]!;
  final minutes = numbers.elementAtOrNull(1) ?? 0,
      seconds = numbers.elementAtOrNull(2) ?? 0;
  if (minutes < 0 || minutes >= 60 || seconds < 0 || seconds >= 60) return null;
  var value = degrees.abs() + minutes / 60 + seconds / 3600;
  if (value > (latitude ? 90 : 180)) return null;
  if (direction == 'S' ||
      direction == 'W' ||
      direction == null && degrees < 0) {
    value = -value;
  }
  return direction == null
      ? '${value.toStringAsFixed(6)}°'
      : '${value.abs().toStringAsFixed(6)}° $direction';
}
