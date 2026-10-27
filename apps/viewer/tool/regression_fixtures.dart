import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as imaging;
import 'package:path/path.dart' as paths;

Future<Directory> createRegressionFixtures(String outputPath) async {
  final root = await Directory(outputPath).create(recursive: true);
  final normal = await Directory(paths.join(root.path, 'normal')).create();
  final chapters = await Directory(paths.join(root.path, 'chapters')).create();
  final chapter = await Directory(paths.join(chapters.path, 'chapter-01'))
      .create();
  final long = await Directory(paths.join(root.path, 'long')).create();
  final invalid = await Directory(paths.join(root.path, 'invalid')).create();
  final archiveDirectory = await Directory(paths.join(root.path, 'archives'))
      .create();
  final red = _solid(1600, 1200, 220, 40, 40);
  final green = _solid(1600, 1200, 40, 180, 70);
  await File(paths.join(normal.path, '001-red.png')).writeAsBytes(red);
  await File(paths.join(normal.path, '002-green.png')).writeAsBytes(green);
  await File(paths.join(chapters.path, '001-cover.png')).writeAsBytes(red);
  await File(paths.join(chapter.path, '001-page.png')).writeAsBytes(green);
  final tall = imaging.Image(width: 400, height: 16000);
  for (var row = 0; row < tall.height; row++) {
    final section = row ~/ 2000;
    for (var column = 0; column < tall.width; column++) {
      tall.setPixelRgb(column, row, 30 + section * 25, 80, 220 - section * 20);
    }
  }
  await File(paths.join(long.path, '001-long.png'))
      .writeAsBytes(imaging.encodePng(tall));
  await File(paths.join(long.path, '002-next.png')).writeAsBytes(green);
  await File(paths.join(invalid.path, 'broken.png'))
      .writeAsBytes([137, 80, 78, 71]);
  final archive = Archive()
    ..addFile(ArchiveFile.bytes('001-red.png', red))
    ..addFile(ArchiveFile.bytes('002-green.png', green));
  await File(paths.join(archiveDirectory.path, 'book.cbz'))
      .writeAsBytes(ZipEncoder().encodeBytes(archive));
  await File(paths.join(root.path, 'manifest.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'normal': ['001-red.png', '002-green.png'],
      'imageSize': [1600, 1200],
      'colors': {
        'red': [220, 40, 40],
        'green': [40, 180, 70],
      },
      'longImageSize': [400, 16000],
    }),
  );
  return root;
}

List<int> _solid(int width, int height, int red, int green, int blue) {
  final image = imaging.Image(width: width, height: height);
  imaging.fill(image, color: imaging.ColorRgb8(red, green, blue));
  return imaging.encodePng(image);
}

Future<void> main(List<String> arguments) async {
  final root = await createRegressionFixtures(
    arguments.isEmpty ? '.dart_tool/regression-fixtures' : arguments.single,
  );
  stdout.writeln(root.absolute.path);
}
