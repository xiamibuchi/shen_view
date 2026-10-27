import 'dart:convert';
import 'dart:io';

import 'package:shen_view/src/application/file_association_formats.dart';

void main() {
  stdout.writeln(
    jsonEncode({
      'images': FileAssociationFormats.images.toList()..sort(),
      'archives': FileAssociationFormats.archives.toList()..sort(),
    }),
  );
}
