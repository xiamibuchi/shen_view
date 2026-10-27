import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as paths;

import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/app_config_store.dart';
import 'package:shen_view/src/application/archive_service.dart';
import 'package:shen_view/src/application/viewer_controller.dart';
import 'package:shen_view/src/presentation/chapter_directory_tree.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

void main() {
  testWidgets(
    'large tree builds a viewport and can scroll to the last chapter',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('large-tree-test-');
      final archive = Archive();
      for (var chapter = 1; chapter <= 1000; chapter++) {
        archive.addFile(
          ArchiveFile.bytes('第${chapter.toString().padLeft(4, '0')}章/001.png', [
            1,
          ]),
        );
      }
      final file = File('${directory.path}/large.cbz')
        ..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
      final controller = ViewerController(
        configStore: AppConfigStore(filePath: '${directory.path}/config.json'),
        archiveService: ArchiveService(
          cachePolicy: ArchiveCachePolicy(
            directory: Directory('${directory.path}/cache'),
          ),
        ),
      );
      addTearDown(() async {
        controller.dispose();
        for (var attempt = 0; attempt < 10; attempt++) {
          try {
            await directory.delete(recursive: true);
            return;
          } on FileSystemException {
            await Future<void>.delayed(const Duration(milliseconds: 30));
          }
        }
        await directory.delete(recursive: true);
      });
      await tester.runAsync(() => controller.openArchive(file));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: ChapterDirectoryTree(
                controller: controller,
                expandedPaths: <String>{},
                onOpenFolder: controller.openChapter,
                onOpenArchive: (_) async {},
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rowLabels = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            RegExp(r'^第[0-9]{4}章$').hasMatch(widget.data ?? ''),
      );
      expect(rowLabels.evaluate().length, inInclusiveRange(1, 40));
      expect(find.text('第1000章'), findsNothing);
      final list = tester.widget<ListView>(
        find.byKey(const ValueKey('directory.rows')),
      );
      list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('第1000章'), findsOneWidget);
      expect(rowLabels.evaluate().length, lessThan(40));
      await tester.enterText(find.byType(TextField), '0999');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('第0999章'), findsOneWidget);
      expect(find.text('large.cbz'), findsOneWidget);
      expect(find.text('第1000章'), findsNothing);
      expect(controller.currentEntry!.relativePath, '第0001章/001.png');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'tree restores expanded branches and keeps failed inner archives retryable',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'chapter-tree-test-',
      );
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('cover.png', [0]))
        ..addFile(ArchiveFile.bytes('卷1/上篇/第01章/001.png', [1]))
        ..addFile(ArchiveFile.bytes('卷2/broken.cbz', [2]));
      final file = File('${directory.path}/多级目录.cbz')
        ..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
      final controller = ViewerController(
        configStore: AppConfigStore(filePath: '${directory.path}/config.json'),
        archiveService: ArchiveService(
          cachePolicy: ArchiveCachePolicy(
            directory: Directory('${directory.path}/cache'),
          ),
        ),
      );
      addTearDown(() async {
        controller.dispose();
        for (var attempt = 0; attempt < 10; attempt++) {
          try {
            await directory.delete(recursive: true);
            return;
          } on FileSystemException {
            await Future<void>.delayed(const Duration(milliseconds: 30));
          }
        }
        await directory.delete(recursive: true);
      });
      await tester.runAsync(() => controller.openArchive(file));
      final root = controller.archiveContext!.extractionRoot;
      final volume = paths.join(root, '卷1');
      final part = paths.join(volume, '上篇');
      final chapter = paths.join(part, '第01章');
      final second = paths.join(root, '卷2');
      final selected = controller.currentEntry!.id;
      final expanded = <String>{};
      Widget host() => MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: AnimatedBuilder(
              animation: controller,
              builder: (_, _) => ChapterDirectoryTree(
                controller: controller,
                expandedPaths: expanded,
                onOpenFolder: controller.openChapter,
                onOpenArchive: (entry) async {
                  await controller.openArchiveEntry(entry);
                },
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('directory.expand:$root')));
      await tester.pumpAndSettle();
      // A collapsed branch is not an empty directory.
      expect(find.byKey(const ValueKey('directory.noChildren')), findsNothing);
      await tester.tap(find.byKey(ValueKey('directory.expand:$root')));
      await tester.pumpAndSettle();
      for (final path in [volume, part, second]) {
        await tester.tap(find.byKey(ValueKey('directory.expand:$path')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(ValueKey('directory.item:$chapter')), findsOneWidget);
      expect(find.byKey(ValueKey('directory.expand:$chapter')), findsNothing);
      final originalExpanded = Set<String>.of(expanded);
      await tester.enterText(find.byType(TextField), '第01');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      for (final path in [root, volume, part, chapter]) {
        expect(find.byKey(ValueKey('directory.item:$path')), findsOneWidget);
      }
      expect(find.text('第01章'), findsOneWidget);
      expect(find.byKey(ValueKey('directory.item:$second')), findsNothing);
      expect(
        tester.getTopLeft(find.text('第01章')).dx,
        greaterThan(tester.getTopLeft(find.text('上篇')).dx),
      );
      final searchBounds = tester.getRect(
        find.byKey(const ValueKey('directory.search')),
      );
      final rowBounds = tester.getRect(
        find.byKey(ValueKey('directory.item:$chapter')),
      );
      expect(rowBounds.left, searchBounds.left);
      expect(rowBounds.right, searchBounds.right);
      await tester.tap(find.byKey(ValueKey('directory.expand:$volume')));
      await tester.pumpAndSettle();
      expect(find.text('第01章'), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(expanded, originalExpanded);
      expect(find.byKey(ValueKey('directory.item:$chapter')), findsOneWidget);
      expect(find.byKey(ValueKey('directory.item:$second')), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('directory.item:$chapter')), findsOneWidget);
      expect(controller.currentEntry!.id, selected);
      final inner = (await tester.runAsync(
        () => controller.listNavigationDirectory(second),
      ))!.containers.single;
      expect(controller.openedArchiveFor(inner), isNull);
      final filesBefore = (await tester.runAsync(controller.archiveCacheStats))!
          .files;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('directory.item:$chapter')), findsOneWidget);
      expect(
        (await tester.runAsync(controller.archiveCacheStats))!.files,
        filesBefore,
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(ValueKey('directory.item:${inner.id}')));
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.pump();
          if (controller.archiveStateForEntry(inner).failure != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(controller.archiveStateForEntry(inner).failure, isNotNull);
      expect(controller.currentEntry!.id, selected);
      final item = find.byKey(ValueKey('directory.item:${inner.id}'));
      expect(
        tester
            .widget<InkWell>(
              find.descendant(of: item, matching: find.byType(InkWell)).first,
            )
            .onTap,
        isNotNull,
      );
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: item, matching: find.byType(Tooltip)).first,
      );
      expect(tooltip.message, isNotEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
