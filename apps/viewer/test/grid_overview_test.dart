import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shen_view/l10n/app_localizations.dart';
import 'package:shen_view/src/application/decode_request.dart';
import 'package:shen_view/src/application/image_resource_service.dart';
import 'package:shen_view/src/application/image_source.dart';
import 'package:shen_view/src/domain/image_entry.dart';
import 'package:shen_view/src/domain/image_format.dart';
import 'package:shen_view/src/presentation/grid_overview.dart';
import 'package:shen_view/src/presentation/resource_image.dart';
import 'package:shen_view/src/presentation/theme/app_theme.dart';

void main() {
  testWidgets(
    'grid clicks select in the next frame and double clicks still open',
    (tester) async {
      final resources = ImageResourceService();
      addTearDown(resources.dispose);
      final entries = List.generate(
        2,
        (id) => ImageEntry.fromSource(
          source: _GridSource(id.toString()),
          format: ImageFormat.png,
          width: 2,
          height: 3,
          byteLength: 0,
          modifiedAt: DateTime(2026),
        ),
      );
      var selectedId = '0';
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => GridOverview(
                entries: entries,
                resources: resources,
                selectedId: selectedId,
                readingId: '0',
                scopeLabel: 'Images',
                onSelect: (entry) => setState(() => selectedId = entry.id),
                onOpen: (entry) => opened.add(entry.id),
                onClose: () {},
                onSizeChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      final second = find.byKey(const ValueKey('grid.item.1'));
      final first = find.byKey(const ValueKey('grid.item.0'));
      Future<void> tapCard(Finder card) =>
          tester.tapAt(tester.getTopLeft(card) + const Offset(12, 12));
      await tapCard(second);
      await tester.pump();
      expect(selectedId, '1');
      expect(
        tester.widget<GridOverview>(find.byType(GridOverview)).selectedId,
        '1',
      );
      expect(opened, isEmpty);
      await tester.pump(const Duration(milliseconds: 100));
      await tapCard(second);
      expect(opened, ['1']);
      opened.clear();

      // Two quick clicks on different cards must only update selection.
      await tapCard(first);
      await tester.pump(const Duration(milliseconds: 100));
      await tapCard(second);
      await tester.pump();
      expect(selectedId, '1');
      expect(opened, isEmpty);
      // An expired double-click window must never turn a later click into open.
      await tester.pump(const Duration(milliseconds: 400));
      await tapCard(second);
      expect(opened, isEmpty);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.dragFrom(
        tester.getTopLeft(first) + const Offset(12, 12),
        const Offset(0, 80),
      );
      await tester.pump();
      expect(selectedId, '1');
      expect(opened, isEmpty);
      await tapCard(first);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(tester.getBottomRight(first) - const Offset(12, 12));
      expect(selectedId, '0');
      expect(opened, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'grid virtualizes images and keeps the visible anchor on refresh and sort',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final resources = ImageResourceService();
      addTearDown(resources.dispose);
      ImageEntry entry(int id) => ImageEntry.fromSource(
        source: _GridSource(id.toString()),
        format: ImageFormat.png,
        width: 2,
        height: 3,
        byteLength: 0,
        modifiedAt: DateTime(2026),
      );
      var entries = List.generate(200, entry);
      late StateSetter update;
      final key = GlobalKey<GridOverviewState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return GridOverview(
                  key: key,
                  entries: entries,
                  resources: resources,
                  selectedId: '0',
                  readingId: '0',
                  scopeLabel: 'Images',
                  onSelect: (_) => fail('Refreshing must not change selection'),
                  onOpen: (_) {},
                  onClose: () {},
                  onSizeChanged: (_) {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ResourceImage).evaluate().length, lessThan(30));
      final scrollbar = tester.widget<Scrollbar>(
        find
            .descendant(of: find.byKey(key), matching: find.byType(Scrollbar))
            .first,
      );
      scrollbar.controller!.jumpTo(1200);
      await tester.pump();
      final gridRect = tester.getRect(
        find.byKey(const ValueKey('grid.images')),
      );
      for (final next in [
        [entry(1000), ...entries],
        entries.reversed.toList(),
      ]) {
        String? anchor;
        double? anchorTop;
        for (final candidate in entries) {
          final item = find.byKey(ValueKey('grid.item.${candidate.id}'));
          if (item.evaluate().isEmpty) continue;
          final rect = tester.getRect(item);
          if (rect.bottom > gridRect.top && rect.top < gridRect.bottom) {
            anchor = candidate.id;
            anchorTop = rect.top;
            break;
          }
        }
        expect(anchor, isNotNull);
        update(() => entries = next);
        await tester.pump();
        await tester.pump();
        final item = find.byKey(ValueKey('grid.item.$anchor'));
        expect(item, findsOneWidget);
        expect(tester.getTopLeft(item).dy, closeTo(anchorTop!, 0.01));
        expect(find.byType(ResourceImage).evaluate().length, lessThan(30));
      }
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      resources.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}

class _GridSource implements ImageSource {
  _GridSource(this.id);
  @override
  final String id;
  @override
  String get name => '$id.png';
  @override
  String get relativePath => name;
  @override
  bool get sensitive => false;
  @override
  Future<SourceFileLease> acquireFile({DecodeRequest? request}) async {
    request?.throwIfCancelled();
    // This test covers layout with failed cards; integration tests verify pixels.
    throw StateError('No image decoding in the layout test');
  }
}
