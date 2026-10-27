import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as imaging;
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/svg_resources.dart';
import 'package:shen_view/src/application/svg_webview_session.dart';

String svg(String body) =>
    '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100">$body</svg>';
SvgVersion version(String id, [int revision = 1]) =>
    (id: id, modified: revision, bytes: 100);
Uint8List png(int red, int blue) => Uint8List.fromList(
  imaging.encodePng(
    imaging.Image(width: 4, height: 2, numChannels: 4)
      ..clear(imaging.ColorRgba8(red, 0, blue, 255)),
  ),
);

void main() {
  for (final entry in {
    'embedded_font.svg': SvgFeature.fontFace,
    'smil.svg': SvgFeature.smil,
    'css_animation.svg': SvgFeature.cssAnimation,
    'css_variables.svg': SvgFeature.cssVariables,
    'foreign_object.svg': SvgFeature.foreignObject,
  }.entries) {
    test('complex fixture routes raw SVG to browser: ${entry.key}', () {
      final document = SvgDocument.parse(
        File('testdata/svg/${entry.key}').readAsStringSync(),
      );
      expect(document.needsWebView, isTrue);
      expect(document.features, contains(entry.value));
      if (entry.value == SvgFeature.fontFace) {
        expect(document.source, contains('data:font/woff2;base64,'));
      }
    });
  }
  for (final name in ['static_filter.svg', 'static_clip.svg', 'comments.svg']) {
    test('static fixture does not start browser: $name', () {
      final document = SvgDocument.parse(
        File('testdata/svg/$name').readAsStringSync(),
      );
      expect(document.needsWebView, isFalse);
    });
  }
  test(
    'inline variables, prefixed animation and namespaced SMIL are detected',
    () {
      expect(
        SvgDocument.parse(svg('<rect style="--ink:red;fill:var(--ink)"/>'))
            .features,
        contains(SvgFeature.cssVariables),
      );
      expect(
        SvgDocument.parse(svg('<rect style="-webkit-animation: pulse 2s"/>'))
            .features,
        contains(SvgFeature.cssAnimation),
      );
      expect(
        SvgDocument.parse(
          '<s:svg xmlns:s="http://www.w3.org/2000/svg"><s:set attributeName="fill" to="red"/></s:svg>',
        ).features,
        contains(SvgFeature.smil),
      );
    },
  );
  test('nested CSS rules are visited; text and comments are not CSS', () {
    expect(
      SvgDocument.parse(
        svg('<style>@media screen { rect { animation-name: pulse; } }</style>'),
      ).features,
      contains(SvgFeature.cssAnimation),
    );
    expect(
      SvgDocument.parse(
        svg(
          '<text>@font-face var(--ink) animation: pulse</text><!-- <animate/> -->',
        ),
      ).needsWebView,
      isFalse,
    );
  });
  test(
    'external files, script and event handlers cannot reach either renderer',
    () {
      final document = SvgDocument.parse(
        svg(
          '<script>alert(1)</script><image href="file:///private.png"/><rect onclick="alert(2)"/><foreignObject><iframe src="https://example.com"/></foreignObject>',
        ),
      );
      expect(document.source, isNot(contains('<script')));
      expect(document.source, isNot(contains('onclick')));
      expect(document.source, isNot(contains('file:///')));
      expect(document.source, isNot(contains('<iframe')));
    },
  );
  test('DTD, malformed input and excessive nodes fail before rendering', () {
    expect(
      () => SvgDocument.parse('<!DOCTYPE svg [<!ENTITY a "x">]><svg/>'),
      throwsFormatException,
    );
    expect(() => SvgDocument.parse('<svg><g></svg>'), throwsFormatException);
    expect(
      () => SvgDocument.parse(
        svg(List.filled(20, '<rect/>').join()),
        nodeLimit: 10,
      ),
      throwsA(isA<DecodeBudgetExceeded>()),
    );
  });
  test(
    'gzip source has the same routing and an enforced expanded byte limit',
    () async {
      final dir = Directory.systemTemp.createTempSync('svgz-routing-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final raw = File('testdata/svg/css_variables.svg').readAsBytesSync();
      final file = File('${dir.path}/image.svgz')
        ..writeAsBytesSync(gzip.encode(raw));
      final bytes = await readSvgBytes(file);
      expect(bytes, raw);
      expect(
        SvgDocument.parse(utf8.decode(bytes)).features,
        contains(SvgFeature.cssVariables),
      );
      await expectLater(
        readSvgBytes(file, maxExpandedBytes: 32),
        throwsA(isA<DecodeBudgetExceeded>()),
      );
    },
  );
  test('source version is stable across extracted archive files', () async {
    final dir = Directory.systemTemp.createTempSync('svg-version-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = SvgResources();
    addTearDown(store.dispose);
    final one = File('${dir.path}/one.svg')..writeAsStringSync(svg('<rect/>'));
    final two = File('${dir.path}/two.svg')..writeAsStringSync(svg('<rect/>'));
    final first = await store.read(one, version: version('archive://page.svg'));
    final second = await store.read(
      two,
      version: version('archive://page.svg'),
    );
    expect(identical(first, second), isTrue);
  });
  test('browser snapshot wins a race with an older static thumbnail', () async {
    final pending = Completer<Uint8List>();
    var renders = 0;
    final store = SvgResources(
      rasterize: (_, edge, request) {
        renders++;
        return pending.future;
      },
    );
    addTearDown(store.dispose);
    final resource = SvgResource(
      version('race'),
      SvgDocument.parse(svg('<rect/>')),
    );
    final loading = store.raster(resource, 128, thumbnail: true);
    await Future<void>.delayed(Duration.zero);
    await store.publishSnapshot(resource.version, png(255, 0));
    pending.complete(png(0, 255));
    final result = imaging.decodePng(await loading)!;
    expect(result.getPixel(0, 0).r, 255);
    expect(
      imaging
          .decodePng(await store.raster(resource, 128, thumbnail: true))!
          .getPixel(0, 0)
          .r,
      255,
    );
    expect(renders, 1);
  });
  test(
    'late screenshot is rejected and file versions never share snapshots',
    () async {
      final store = SvgResources();
      addTearDown(store.dispose);
      final old = version('same', 1), current = version('same', 2);
      await store.publishSnapshot(old, png(255, 0), isCurrent: () => false);
      expect(store.snapshot(old), isNull);
      await store.publishSnapshot(current, png(0, 255));
      expect(store.snapshot(old), isNull);
      expect(store.snapshot(current), isNotNull);
    },
  );
  test(
    'raster cache is bounded and evicted entries can render again',
    () async {
      var renders = 0;
      final bytes = png(255, 0);
      final store = SvgResources(
        maxRasterBytes: bytes.length * 2,
        rasterize: (_, edge, request) async {
          renders++;
          return bytes;
        },
      );
      addTearDown(store.dispose);
      final doc = SvgDocument.parse(svg('<rect/>'));
      for (var i = 0; i < 3; i++) {
        await store.raster(SvgResource(version('$i'), doc), 128);
      }
      expect(store.rasterBytes, lessThanOrEqualTo(bytes.length * 2));
      await store.raster(SvgResource(version('0'), doc), 128);
      expect(renders, 4);
    },
  );
  test(
    'window session is exclusive, serializes work and releases idle state',
    () async {
      final session = SvgWebViewSession(
        idleDelay: const Duration(milliseconds: 5),
      );
      addTearDown(session.dispose);
      final a = Object(), b = Object();
      expect(session.acquire(a), isTrue);
      final previous = session.keepAlive;
      expect(session.acquire(b), isFalse);
      final order = <int>[];
      await Future.wait([
        session.run(a, () async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          order.add(1);
        }),
        session.run(a, () async {
          order.add(2);
        }),
      ]);
      expect(order, [1, 2]);
      session.release(a);
      await expectLater(
        session.run(a, () async {}),
        throwsA(isA<DecodeCancelled>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(session.acquire(b), isTrue);
      expect(identical(previous, session.keepAlive), isFalse);
      session.release(b);
    },
  );
  test('real resvg preserves filter and clipping pixels', () async {
    for (final name in ['static_filter.svg', 'static_clip.svg']) {
      final document = SvgDocument.parse(
        File('testdata/svg/$name').readAsStringSync(),
      );
      final image = imaging.decodePng(
        await rasterizeSvg(document, 200, DecodeRequest()),
      )!;
      expect((image.width, image.height), (200, 100));
      expect(image.getPixel(100, 50).r, greaterThan(245));
      if (name == 'static_filter.svg') {
        expect(image.getPixel(56, 50).a, inExclusiveRange(5, 240));
      } else {
        expect(image.getPixel(52, 12).a, 0);
      }
    }
  });
}
