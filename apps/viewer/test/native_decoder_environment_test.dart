import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/src/application/native_decoder_environment.dart';

void main() {
  const executable = r'C:\portable image\codecs\imagemagick\magick.exe';
  const directory = r'C:\portable image\codecs\imagemagick';

  test('Windows modules find bundled DLLs before inherited tools', () {
    final inherited = {
      'Path': r'C:\Windows\System32;C:\other-magick',
      'TEMP': r'C:\temp',
      'MAGICK_CODER_MODULE_PATH': r'C:\other-magick\modules',
    };
    final environment = nativeDecoderEnvironment(
      executable,
      inherited: inherited,
      isWindows: true,
    );
    expect(environment['PATH'], '$directory;${inherited['Path']}');
    expect(environment, isNot(contains('Path')));
    expect(environment['TEMP'], inherited['TEMP']);
    expect(environment['MAGICK_CONFIGURE_PATH'], directory);
    expect(
      environment['MAGICK_CODER_MODULE_PATH'],
      r'C:\portable image\codecs\imagemagick\modules\coders',
    );
    expect(
      environment['MAGICK_FILTER_MODULE_PATH'],
      r'C:\portable image\codecs\imagemagick\modules\filters',
    );
    expect(inherited['Path'], r'C:\Windows\System32;C:\other-magick');
    expect(inherited, isNot(contains('PATH')));
  });

  test('Windows keeps one PATH key regardless of inherited spelling', () {
    for (final spelling in ['PATH', 'Path', 'path']) {
      final environment = nativeDecoderEnvironment(
        executable,
        inherited: {spelling: r'C:\Windows\System32'},
        isWindows: true,
      );
      expect(environment['PATH'], '$directory;C:\\Windows\\System32');
      expect(environment.keys.where((key) => key.toUpperCase() == 'PATH'), [
        'PATH',
      ]);
    }
  });

  test(
    'Windows supplies the bundle directory when PATH is empty or absent',
    () {
      for (final inherited in [
        <String, String>{},
        {'PATH': ''},
      ]) {
        final environment = nativeDecoderEnvironment(
          executable,
          inherited: inherited,
          isWindows: true,
        );
        expect(environment['PATH'], directory);
      }
    },
  );

  test('macOS and Linux preserve their existing search environment', () {
    for (final executable in ['/opt/homebrew/bin/magick', '/usr/bin/magick']) {
      final environment = nativeDecoderEnvironment(
        executable,
        inherited: {
          'PATH': '/usr/bin:/bin',
          'MAGICK_FILTER_MODULE_PATH': 'custom',
        },
        isWindows: false,
      );
      expect(environment['PATH'], '/usr/bin:/bin');
      expect(environment['MAGICK_FILTER_MODULE_PATH'], 'custom');
      expect(environment, isNot(contains('MAGICK_CODER_MODULE_PATH')));
      expect(
        environment['MAGICK_CONFIGURE_PATH'],
        executable.replaceFirst(RegExp(r'/[^/]+$'), ''),
      );
    }
  });

  test('macOS bundled ImageMagick uses bundled modules and configuration', () {
    final environment = nativeDecoderEnvironment(
      '/Applications/ShenView.app/Contents/MacOS/codecs/imagemagick/magick',
      inherited: {'PATH': '/usr/bin:/bin'},
      isWindows: false,
    );
    expect(environment['PATH'], '/usr/bin:/bin');
    expect(
      environment['MAGICK_CONFIGURE_PATH'],
      '/Applications/ShenView.app/Contents/Resources/codecs/imagemagick',
    );
    expect(
      environment['MAGICK_CODER_MODULE_PATH'],
      '/Applications/ShenView.app/Contents/Resources/codecs/imagemagick/modules/coders',
    );
  });
}
