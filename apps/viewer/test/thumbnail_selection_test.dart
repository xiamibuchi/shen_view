import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/image_resource_service.dart';
import 'package:shen_view/src/application/viewer_controller.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';
import 'package:shen_view/src/domain/viewer_mode.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';
import 'package:shen_view/src/presentation/viewer_bottom_bar.dart';

void main() {
  testWidgets('thumbnail tap selects an item immediately', (tester) async {
    final controller = _controllerWithEntries(4);
    final resources = ImageResourceService();
    addTearDown(() {
      resources.dispose();
      controller.dispose();
    });
    var selected = -1;
    await tester.pumpWidget(
      _host(
        ViewerBottomBar(
          controller: controller,
          resources: resources,
          mode: ViewerMode.single,
          parentFolderPath: null,
          onOpenFolder: (_) {},
          onOpenArchive: (_) {},
          onSelect: (index) => selected = index,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('thumbnail-1.png'));

    expect(selected, 1);
  });

  testWidgets('thumbnail filename appears in the container on hover', (
    tester,
  ) async {
    final controller = _controllerWithEntries(4);
    final resources = ImageResourceService();
    addTearDown(() {
      resources.dispose();
      controller.dispose();
    });
    await tester.pumpWidget(
      _host(
        ViewerBottomBar(
          controller: controller,
          resources: resources,
          mode: ViewerMode.single,
          parentFolderPath: null,
          onOpenFolder: (_) {},
          onOpenArchive: (_) {},
          onSelect: (_) {},
        ),
      ),
    );
    await tester.pump();

    final item = find.bySemanticsLabel('thumbnail-1.png');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(item));
    await mouse.moveTo(tester.getCenter(item));
    await tester.pumpAndSettle();

    expect(find.text('thumbnail-1.png'), findsOneWidget);
    expect(find.byTooltip('thumbnail-1.png'), findsNothing);
    await mouse.removePointer();

    final containers = tester.widgetList<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(containers, hasLength(4));
    for (var index = 0; index < containers.length; index++) {
      final container = containers.elementAt(index);
      expect(container.constraints?.minWidth, 96);
      expect(container.constraints?.maxWidth, 96);
      expect(container.constraints?.minHeight, 72);
      expect(container.constraints?.maxHeight, 72);
      final foreground = container.foregroundDecoration! as BoxDecoration;
      expect(foreground.border!.top.width, index == 0 ? 2 : 1);
    }
  });

  testWidgets('thumbnail filenames can be hidden without hiding semantics', (
    tester,
  ) async {
    final controller = _controllerWithEntries(2);
    final resources = ImageResourceService();
    addTearDown(() {
      resources.dispose();
      controller.dispose();
    });
    await tester.pumpWidget(
      _host(
        ViewerBottomBar(
          controller: controller,
          resources: resources,
          mode: ViewerMode.single,
          parentFolderPath: null,
          onOpenFolder: (_) {},
          onOpenArchive: (_) {},
          onSelect: (_) {},
          showFileNames: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('thumbnail-0.png'), findsOneWidget);
    final labels = tester.widgetList<AnimatedOpacity>(
      find.byType(AnimatedOpacity),
    );
    expect(labels, isNotEmpty);
    expect(labels.every((label) => label.opacity == 0), isTrue);
  });

  testWidgets('thumbnail loading placeholder follows the theme', (
    tester,
  ) async {
    final controller = _controllerWithEntries(1);
    final resources = ImageResourceService();
    addTearDown(() {
      resources.dispose();
      controller.dispose();
    });

    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      await tester.pumpWidget(
        _host(
          ViewerBottomBar(
            controller: controller,
            resources: resources,
            mode: ViewerMode.single,
            parentFolderPath: null,
            onOpenFolder: (_) {},
            onOpenArchive: (_) {},
            onSelect: (_) {},
          ),
          theme: theme,
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    }
  });

  testWidgets('dragging the strip does not change the selected item', (
    tester,
  ) async {
    final controller = _controllerWithEntries(16);
    final resources = ImageResourceService();
    addTearDown(() {
      resources.dispose();
      controller.dispose();
    });
    var selectionCalls = 0;
    await tester.pumpWidget(
      _host(
        ViewerBottomBar(
          controller: controller,
          resources: resources,
          mode: ViewerMode.single,
          parentFolderPath: null,
          onOpenFolder: (_) {},
          onOpenArchive: (_) {},
          onSelect: (_) => selectionCalls++,
        ),
      ),
    );
    await tester.pump();

    await tester.dragFrom(const Offset(250, 40), const Offset(-140, 0));
    await tester.pumpAndSettle();

    expect(selectionCalls, 0);
    expect(controller.currentIndex, 0);
  });

  testWidgets('manual drag interrupts automatic selection following', (
    tester,
  ) async {
    final controller = _controllerWithEntries(32);
    final resources = ImageResourceService();
    addTearDown(() {
      resources.dispose();
      controller.dispose();
    });
    await tester.pumpWidget(
      _host(
        ViewerBottomBar(
          controller: controller,
          resources: resources,
          mode: ViewerMode.single,
          parentFolderPath: null,
          onOpenFolder: (_) {},
          onOpenArchive: (_) {},
          onSelect: (_) {},
        ),
      ),
    );
    await tester.pump();

    controller.select(20);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.dragFrom(const Offset(300, 40), const Offset(-120, 0));
    final listView = tester.widget<ListView>(find.byType(ListView));
    final offsetAfterDrag = listView.controller!.offset;
    await tester.pump(const Duration(milliseconds: 200));

    expect(offsetAfterDrag, lessThan(500));
    expect(listView.controller!.offset, closeTo(offsetAfterDrag, 1));
    await tester.pumpWidget(const SizedBox());
    resources.dispose();
  });
}

Widget _host(Widget child, {ThemeData? theme}) {
  return MaterialApp(
    theme: theme ?? AppTheme.dark(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SizedBox(width: 600, height: 88, child: child),
  );
}

ViewerController _controllerWithEntries(int count) {
  final controller = ViewerController();
  controller.entries = [
    for (var i = 0; i < count; i++)
      ImageEntry(
        file: File.fromUri(
          Directory.systemTemp.uri.resolve('thumbnail-$i.png'),
        ),
        format: ImageFormat.png,
        width: 100,
        height: 100,
        byteLength: 1,
        modifiedAt: DateTime(2026),
      ),
  ];
  controller.currentIndex = 0;
  return controller;
}
