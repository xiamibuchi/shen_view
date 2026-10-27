import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/external_open_service.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/image_source.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const service = ExternalOpenService();
  const editor = ExternalApplication(id: 'editor-id', name: 'Editor');
  final calls = <MethodCall>[];
  late Directory directory;
  late File image;
  late ImageEntry local;
  var failOpen = false;

  setUp(() {
    calls.clear();
    failOpen = false;
    directory = Directory.systemTemp.createTempSync('shenview-external-open-');
    image = File('${directory.path}/图片 空格 & literal.png')
      ..writeAsBytesSync([1, 2, 3, 4]);
    local = ImageEntry(
      file: image,
      format: ImageFormat.png,
      width: 1,
      height: 1,
      byteLength: 4,
      modifiedAt: DateTime(2026),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ExternalOpenService.channel, (call) async {
          calls.add(call);
          if (call.method == 'applications') {
            return [
              {'id': 'editor-id', 'name': 'Editor'},
              {'id': 'editor-id', 'name': 'Duplicate'},
              {'id': '', 'name': 'Missing ID'},
              {'id': 'invalid', 'name': null},
            ];
          }
          if (failOpen) throw PlatformException(code: 'open_failed');
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ExternalOpenService.channel, null);
    directory.deleteSync(recursive: true);
  });

  test('lists applications for the original extension and removes invalid duplicates', () async {
    final apps = await service.applications(local);
    expect(apps.map((app) => app.name), ['Editor']);
    expect(calls.single.arguments, {
      'extension': '.png',
      'path': image.absolute.path,
    });
  });

  test('local images use the captured original path without saving or shell quoting', () async {
    expect(
      await service.open(
        local,
        application: editor,
        saveCopy: (_) async {
          fail('Local images must not ask to save a copy');
        },
      ),
      isTrue,
    );
    expect(calls.single.method, 'open');
    expect(calls.single.arguments, {
      'path': image.absolute.path,
      'application': editor.id,
    });
  });

  test(
    'choosing another application passes only the file to the native picker',
    () async {
      await service.open(local, saveCopy: (_) async => null);
      expect(calls.single.method, 'choose');
      expect(calls.single.arguments, {'path': image.absolute.path});
    },
  );

  test(
    'archive applications use the logical extension without extracting',
    () async {
      final source = _Source(image);
      await service.applications(_archive(source));
      expect(calls.single.arguments, {'extension': '.png'});
      expect(source.acquired, 0);
    },
  );

  test('archive opens a persistent byte-identical copy and releases the cache lease first', () async {
    final source = _Source(image);
    final copy = File('${directory.path}/saved.png');
    await service.open(
      _archive(source),
      application: editor,
      saveCopy: (file) async {
        expect(source.released, 0);
        return file.copy(copy.path);
      },
    );
    expect(source.released, 1);
    expect(calls.single.arguments, {
      'path': copy.absolute.path,
      'application': editor.id,
    });
    await image.delete();
    expect(await copy.readAsBytes(), [1, 2, 3, 4]);
  });

  test(
    'canceling archive save releases the lease and never starts an application',
    () async {
      final source = _Source(image);
      expect(
        await service.open(_archive(source), saveCopy: (_) async => null),
        isFalse,
      );
      expect(source.released, 1);
      expect(calls, isEmpty);
    },
  );

  test(
    'save failures release the archive lease and never start an application',
    () async {
      final source = _Source(image);
      await expectLater(
        service.open(
          _archive(source),
          saveCopy: (_) async => throw const FileSystemException('disk full'),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(source.released, 1);
      expect(calls, isEmpty);
    },
  );

  test('missing files do not reach the operating system', () async {
    await image.delete();
    await expectLater(
      service.open(local, saveCopy: (_) async => null),
      throwsA(isA<FileSystemException>()),
    );
    expect(calls, isEmpty);
  });

  test('launch failures retain the user-owned archive copy', () async {
    failOpen = true;
    final source = _Source(image);
    final copy = File('${directory.path}/saved.png');
    await expectLater(
      service.open(
        _archive(source),
        application: editor,
        saveCopy: (file) => file.copy(copy.path),
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(source.released, 1);
    expect(await copy.readAsBytes(), [1, 2, 3, 4]);
  });
}

ImageEntry _archive(_Source source) => ImageEntry.fromSource(
  source: source,
  format: ImageFormat.png,
  byteLength: 4,
  modifiedAt: DateTime(2026),
);

class _Source implements ImageSource {
  _Source(this.file);
  final File file;
  int acquired = 0;
  int released = 0;
  @override
  String get id => 'archive://book/0';
  @override
  String get name => '原图.PNG';
  @override
  String get relativePath => name;
  @override
  bool get sensitive => true;
  @override
  Future<SourceFileLease> acquireFile({DecodeRequest? request}) async {
    acquired++;
    return SourceFileLease(
      file,
      onRelease: () async {
        released++;
      },
    );
  }
}
