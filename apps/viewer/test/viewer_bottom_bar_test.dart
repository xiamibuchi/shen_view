import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/archive_service.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/image_resource_service.dart';
import 'package:shen_view/src/application/image_source.dart';
import 'package:shen_view/src/application/prefetch_planner.dart';
import 'package:shen_view/src/application/viewer_controller.dart';
import 'package:shen_view/src/domain/archive_failure.dart';
import 'package:shen_view/src/domain/archive_context.dart';
import 'package:shen_view/src/domain/folder_browse_mode.dart';
import 'package:shen_view/src/domain/folder_entry.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';
import 'package:shen_view/src/domain/viewer_mode.dart';
import 'package:shen_view/src/domain/viewer_settings.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_bottom_bar.dart';

import 'support/style_review_fonts.dart';

const _captureKey = ValueKey('bottom-bar-capture');

String _fixturePath([String relative = '']) => Directory.systemTemp.uri
    .resolve('shenview-bottom-bar/$relative')
    .toFilePath();

void main() {
  testWidgets(
    'thumbnail scrolling repeats at a controlled rate and keeps horizontal scrolling',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(440, 160);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = _controller(FolderBrowseMode.currentFolder);
      final resources = ImageResourceService();
      addTearDown(controller.dispose);
      addTearDown(resources.dispose);
      controller.entries = List.generate(
        10,
        (i) => ImageEntry.fromSource(
          source: _ThumbnailSource('scroll:$i'),
          format: ImageFormat.png,
          width: 32,
          height: 32,
          byteLength: 1024,
          modifiedAt: DateTime(2026),
        ),
      );
      controller.currentIndex = 0;
      var selections = 0;
      await tester.runAsync(
        () => tester.pumpWidget(
          _host(
            controller,
            resources,
            onSelect: (index) {
              selections++;
              controller.select(index);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      var elapsed = 0;
      Future<void> scroll(Offset delta, {int pause = 8}) {
        elapsed += pause;
        return tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(find.byType(ListView)),
            timeStamp: Duration(milliseconds: elapsed),
            scrollDelta: delta,
          ),
        );
      }

      await scroll(const Offset(0, 20));
      expect(controller.currentIndex, 1);
      expect(selections, 1);
      for (var i = 0; i < 21; i++) {
        await scroll(const Offset(0, 20));
      }
      expect(selections, 1);
      await scroll(const Offset(0, 20), pause: 12);
      expect(controller.currentIndex, 2);
      expect(selections, 2);
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      final oldPosition = position.pixels;
      await scroll(const Offset(80, 0), pause: 300);
      expect(position.pixels, greaterThan(oldPosition));
      await scroll(const Offset(0, 80));
      expect(selections, 2);
      await scroll(const Offset(0, 20), pause: 300);
      expect(controller.currentIndex, 3);
      expect(selections, 3);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await scroll(const Offset(0, 120), pause: 300);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await scroll(const Offset(0, 120));
      expect(selections, 3);
      await tester.sendEventToBinding(
        PointerScrollInertiaCancelEvent(
          position: tester.getCenter(find.byType(ListView)),
        ),
      );
      await scroll(const Offset(0, -20));
      expect(controller.currentIndex, 2);
      expect(selections, 4);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'on-demand thumbnails load only the strip viewport and follow scrolling while inactive',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(440, 160);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = _controller(FolderBrowseMode.currentFolder);
      final resources = ImageResourceService();
      addTearDown(controller.dispose);
      addTearDown(resources.dispose);
      final sources = List.generate(
        100,
        (index) => _ThumbnailSource('thumb:$index'),
      );
      controller.entries = [
        for (final source in sources)
          ImageEntry.fromSource(
            source: source,
            format: ImageFormat.png,
            width: 32,
            height: 32,
            byteLength: 1024,
            modifiedAt: DateTime(2026),
          ),
      ];
      controller.currentIndex = 0;
      resources.configurePrefetch(PrefetchLevel.onDemand);
      resources.applyWorkingSet(
        protectedIds: {'canvas'},
        retainedIds: {'canvas'},
      );
      await tester.runAsync(() async {
        await tester.pumpWidget(_host(controller, resources));
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.pump();
          if (tester
                  .widgetList<RawImage>(find.byType(RawImage))
                  .where((image) => image.image != null)
                  .length >=
              4) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      final initial = sources.fold(
        0,
        (count, source) => count + source.acquisitions,
      );
      expect(initial, inInclusiveRange(4, 6));
      resources.setActive(false);
      await tester.runAsync(() async {
        tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position
            .jumpTo(80 * 104);
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.pump();
          if (sources[80].acquisitions > 0 &&
              tester
                      .widgetList<RawImage>(find.byType(RawImage))
                      .where((image) => image.image != null)
                      .length >=
                  4) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(sources[80].acquisitions, 1);
      expect(
        sources.fold(0, (count, source) => count + source.acquisitions),
        lessThanOrEqualTo(12),
      );
      expect(
        sources.sublist(10, 70).every((source) => source.acquisitions == 0),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'nested-only archives stay navigable without sibling package actions',
    (tester) async {
      final controller = _controller(FolderBrowseMode.currentFolder);
      final resources = ImageResourceService();
      addTearDown(controller.dispose);
      addTearDown(resources.dispose);
      _seedArchive(controller);
      await tester.pumpWidget(_host(controller, resources));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('navigation.compact')), findsOneWidget);
      expect(find.text('inner.cb7'), findsNothing);
      expect(find.text('此处没有图片，可进入章节或子压缩包继续浏览。'), findsOneWidget);
      expect(find.byKey(const ValueKey('navigation.directory')), findsNothing);
      expect(find.byKey(const ValueKey('archive.previous')), findsNothing);
      expect(find.byKey(const ValueKey('archive.next')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'archive opening has a cancel action even before the first image',
    (tester) async {
      final controller = _OpeningController();
      final resources = ImageResourceService();
      addTearDown(controller.dispose);
      addTearDown(resources.dispose);
      var cancelCalls = 0;
      await tester.pumpWidget(
        _host(
          controller,
          resources,
          onCancelArchiveOpening: () => cancelCalls++,
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('archive.cancelOpening')));
      expect(cancelCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unresolved SVG thumbnail acquires its source and reports read errors',
    (tester) async {
      final controller = _controller(FolderBrowseMode.currentFolder);
      final resources = ImageResourceService();
      addTearDown(controller.dispose);
      addTearDown(resources.dispose);
      final source = _UnmaterializedSource('page.svg');
      controller.entries = [
        ImageEntry.fromSource(
          source: source,
          format: ImageFormat.svg,
          byteLength: 30,
          modifiedAt: DateTime(2024),
        ),
      ];
      controller.currentIndex = 0;
      await tester.pumpWidget(_host(controller, resources));
      await tester.pumpAndSettle();
      expect(source.acquireCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('nested archive controls fit both themes and small windows', (
    tester,
  ) async {
    final captureDir = Platform.environment['BOTTOM_BAR_CAPTURE_DIR'];
    if (captureDir != null) {
      await tester.runAsync(() async {
        for (final font in [
          ('ArchiveReview', windowsFontPath('msyh.ttc')),
          (
            'packages/fluentui_system_icons/FluentSystemIcons-Regular',
            'packages/fluentui_system_icons/fonts/FluentSystemIcons-Regular.ttf',
          ),
        ]) {
          final loader = FontLoader(font.$1)
            ..addFont(loadReviewFontData(font.$2));
          await loader.load();
        }
      });
    }
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final dark in [true, false]) {
      for (final width in [1280.0, 440.0]) {
        final controller = _controller(FolderBrowseMode.currentFolder);
        final resources = ImageResourceService();
        _seedArchive(controller);
        tester.view.physicalSize = Size(width, 124);
        final theme = dark ? AppTheme.dark() : AppTheme.light();
        await tester.pumpWidget(
          _host(
            controller,
            resources,
            theme: captureDir == null
                ? theme
                : theme.copyWith(
                    textTheme: theme.textTheme.apply(
                      fontFamily: 'ArchiveReview',
                    ),
                  ),
            onNextArchive: () {},
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('navigation.chapter')))
              .width,
          lessThanOrEqualTo(240),
        );
        if (captureDir != null) {
          await _capture(
            tester,
            '$captureDir/nested-${dark ? "dark" : "light"}-${width.toInt()}.png',
          );
        }
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        resources.dispose();
      }
    }
  });

  testWidgets('renders compact navigation in both themes', (tester) async {
    final captureDir = Platform.environment['BOTTOM_BAR_CAPTURE_DIR'];
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final dark in [true, false]) {
      for (final mode in [
        FolderBrowseMode.recursiveFolders,
        FolderBrowseMode.recursiveFlat,
      ]) {
        tester.view.physicalSize = const Size(1280, 124);
        final controller = _controller(mode);
        final resources = ImageResourceService();
        _seed(controller);
        await tester.pumpWidget(
          _host(
            controller,
            resources,
            theme: dark ? AppTheme.dark() : AppTheme.light(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (captureDir != null) {
          await _capture(
            tester,
            '$captureDir/${dark ? 'dark' : 'light'}-${mode.name}.png',
          );
        }
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        resources.dispose();
      }
    }
  });

  testWidgets('recursive folder mode shows compact chapter navigation', (
    tester,
  ) async {
    final controller = _controller(FolderBrowseMode.recursiveFolders);
    final resources = ImageResourceService();
    addTearDown(resources.dispose);
    addTearDown(controller.dispose);
    _seed(controller);

    await tester.pumpWidget(_host(controller, resources));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('navigation.compact')), findsOneWidget);
    expect(find.byKey(const ValueKey('navigation.chapter')), findsOneWidget);
    expect(find.text('book.cbz'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('flat mode hides folder and archive entry chips', (tester) async {
    final controller = _controller(FolderBrowseMode.recursiveFlat);
    final resources = ImageResourceService();
    addTearDown(resources.dispose);
    addTearDown(controller.dispose);
    _seed(controller);

    await tester.pumpWidget(_host(controller, resources));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('navigation.compact')), findsOneWidget);
    expect(find.text('chapter'), findsNothing);
    expect(find.text('book.cbz'), findsNothing);
    expect(find.text('CBZ'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('current folder mode hides the folder navigation row', (
    tester,
  ) async {
    final controller = _controller(FolderBrowseMode.currentFolder);
    final resources = ImageResourceService();
    addTearDown(resources.dispose);
    addTearDown(controller.dispose);
    _seed(controller);

    await tester.pumpWidget(_host(controller, resources));
    await tester.pumpAndSettle();

    expect(find.text('上级文件夹'), findsNothing);
    expect(find.text('chapter'), findsNothing);
    expect(find.text('book.cbz'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed archive keeps compact chapter navigation available', (
    tester,
  ) async {
    final controller = ViewerController(
      configStore: AppConfigStore(
        filePath: '${Directory.systemTemp.path}/shen_view-bottom-bar-test.json',
      ),
      archiveService: _FailingArchiveService(),
    );
    final resources = ImageResourceService();
    addTearDown(resources.dispose);
    addTearDown(controller.dispose);
    controller.configureOptions(
      sortOrder: SortOrder.fileSystem,
      browseMode: FolderBrowseMode.recursiveFolders,
      scanUnknownExtensions: false,
    );
    _seed(controller);
    await controller.openArchive(File(_fixturePath('book.cbz')));

    await tester.pumpWidget(_host(controller, resources));
    await tester.pumpAndSettle();

    expect(
      controller.archiveStateForEntry(controller.containers.single).failure,
      ArchiveFailureKind.corrupt,
    );
    expect(find.byKey(const ValueKey('navigation.compact')), findsOneWidget);
    expect(find.byKey(const ValueKey('navigation.directory')), findsNothing);
    expect(find.text('CBZ'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty folder mode shows the recursive empty message', (
    tester,
  ) async {
    final controller = _controller(FolderBrowseMode.recursiveFolders);
    final resources = ImageResourceService();
    addTearDown(resources.dispose);
    addTearDown(controller.dispose);
    controller.folderPath = _fixturePath('root');

    await tester.pumpWidget(_host(controller, resources));
    await tester.pumpAndSettle();

    expect(find.text('当前文件夹及子文件夹中没有图片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ThumbnailSource implements ImageSource {
  _ThumbnailSource(this.id);
  @override
  final String id;
  int acquisitions = 0;
  @override
  String get name => '$id.png';
  @override
  String get relativePath => name;
  @override
  bool get sensitive => false;
  @override
  Future<SourceFileLease> acquireFile({DecodeRequest? request}) async {
    acquisitions++;
    request?.throwIfCancelled();
    return SourceFileLease(File('testdata/formats/format_static.png'));
  }
}

ViewerController _controller(FolderBrowseMode mode) {
  final controller = ViewerController(
    configStore: AppConfigStore(
      filePath: '${Directory.systemTemp.path}/shen_view-bottom-bar-test.json',
    ),
  );
  controller.configureOptions(
    sortOrder: SortOrder.fileSystem,
    browseMode: mode,
    scanUnknownExtensions: false,
  );
  return controller;
}

void _seed(ViewerController controller) {
  controller.folderPath = _fixturePath('root');
  controller.childFolders = [
    FolderEntry(
      directory: Directory(_fixturePath('chapter')),
      modifiedAt: DateTime(2024),
      imageCount: 2,
    ),
  ];
  controller.containers = [
    ImageEntry(
      file: File(_fixturePath('book.cbz')),
      format: ImageFormat.archive,
      width: null,
      height: null,
      byteLength: 1024,
      modifiedAt: DateTime(2024),
    ),
  ];
}

class _FailingArchiveService extends ArchiveService {
  @override
  Future<ArchiveSession> open(
    File file, {
    DecodeRequest? request,
    String? password,
    bool sensitive = false,
    ArchiveSession? parent,
    ArchiveFileLease? parentLease,
  }) async {
    throw const ArchiveOpenException(ArchiveFailureKind.corrupt);
  }
}

void _seedArchive(ViewerController controller) {
  controller.folderPath = _fixturePath('virtual/book');
  controller.archiveContext = ArchiveContext(
    archiveFile: File(_fixturePath('book.cbz')),
    extractionRoot: _fixturePath('virtual/book'),
    originFolder: _fixturePath(),
    displayName: 'book.cbz',
  );
  controller.childFolders = [
    FolderEntry(
      directory: Directory(_fixturePath('virtual/book/nested-only')),
      modifiedAt: DateTime(2024),
      imageCount: 0,
    ),
  ];
  controller.containers = [
    ImageEntry.fromSource(
      source: _UnmaterializedSource('inner.cb7'),
      format: ImageFormat.archive,
      byteLength: 1024,
      modifiedAt: DateTime(2024),
    ),
  ];
}

class _OpeningController extends ViewerController {
  @override
  bool get isOpeningArchive => true;
}

class _UnmaterializedSource implements ImageSource {
  _UnmaterializedSource(this.name);
  @override
  final String name;
  int acquireCount = 0;
  @override
  String get id => 'archive://stable-entry/$name#2';
  @override
  String get relativePath => name;
  @override
  bool get sensitive => false;
  @override
  Future<SourceFileLease> acquireFile({DecodeRequest? request}) {
    acquireCount++;
    return Future.error(StateError('simulated unavailable source'));
  }
}

Widget _host(
  ViewerController controller,
  ImageResourceService resources, {
  ThemeData? theme,
  ValueChanged<ImageEntry>? onOpenArchive,
  VoidCallback? onPreviousArchive,
  VoidCallback? onNextArchive,
  VoidCallback? onCancelArchiveOpening,
  ValueChanged<int>? onSelect,
}) {
  return RepaintBoundary(
    key: _captureKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme ?? AppTheme.dark(),
      home: Scaffold(
        body: ViewerBottomBar(
          controller: controller,
          resources: resources,
          mode: ViewerMode.single,
          parentFolderPath: _fixturePath(),
          onOpenFolder: (_) {},
          onOpenArchive: onOpenArchive ?? (_) {},
          onPreviousArchive: onPreviousArchive,
          onNextArchive: onNextArchive,
          onCancelArchiveOpening: onCancelArchiveOpening,
          onSelect: onSelect ?? (_) {},
        ),
      ),
    ),
  );
}

Future<void> _capture(WidgetTester tester, String filePath) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
