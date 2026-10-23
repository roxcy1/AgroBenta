import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/marketplace/state/listing_filters.dart';
import 'package:agrobenta_mobile/features/marketplace/views/marketplace_filter_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures what the screen resolves to, so a test can tell "cancelled"
/// (`returned` true, `value` null) from "never came back".
class _Result {
  ListingFilters? value;
  bool returned = false;
}

void main() {
  /// Pumps a host route that opens the filter screen through the real entry
  /// point, [showMarketplaceFilterScreen].
  ///
  /// Deliberately builds **no** `MarketplaceScope` or `AuthScope`: the screen is
  /// presentation over a form and must make no request of its own, so a missing
  /// scope is the assertion that nothing here reaches the API.
  Future<_Result> open(
    WidgetTester tester, {
    ListingFilters initial = ListingFilters.none,
  }) async {
    final _Result result = _Result();

    // The default 800x600 surface is shorter than the form, and the lazy list
    // only builds what is on screen — so Condition, Health Status and Sort By
    // would never be laid out for a finder to see. A tall portrait surface
    // makes the whole form real.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result.value = await showMarketplaceFilterScreen(
                    context: context,
                    filters: initial,
                  );
                  result.returned = true;
                },
                child: const Text('Open filters'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open filters'));
    await tester.pumpAndSettle();

    return result;
  }

  group('layout', () {
    testWidgets('shows the header, sections and actions', (
      WidgetTester tester,
    ) async {
      await open(tester);

      expect(find.text('Filter Livestock'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Apply Filters'), findsOneWidget);

      for (final String section in <String>[
        'Animal Type',
        'Price Range',
        'Condition',
        'Health Status',
        'Sort By',
      ]) {
        expect(find.text(section), findsOneWidget, reason: section);
      }

      // "Location" is both the section heading and the field label, so it is
      // asserted by presence rather than uniqueness.
      expect(find.text('Location'), findsWidgets);

      for (final String animal in <String>[
        'Cattle',
        'Swine',
        'Goat',
        'Carabao',
      ]) {
        expect(find.text(animal), findsOneWidget, reason: animal);
      }

      expect(find.widgetWithText(TextField, 'Min price'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Max price'), findsOneWidget);
    });

    testWidgets('offers the reference condition and health options', (
      WidgetTester tester,
    ) async {
      await open(tester);

      for (final String option in <String>[
        'All',
        'Young',
        'Adult',
        'Pregnant',
        'Healthy',
        'Needs Care',
      ]) {
        expect(find.text(option), findsWidgets, reason: option);
      }
    });
  });

  group('unsupported filters', () {
    testWidgets('say so rather than pretending to filter', (
      WidgetTester tester,
    ) async {
      await open(tester);

      expect(
        find.textContaining('cannot filter by condition'),
        findsOneWidget,
      );
      expect(
        find.textContaining('cannot filter by health status'),
        findsOneWidget,
      );
    });

    testWidgets('show the only sort order the endpoint actually provides', (
      WidgetTester tester,
    ) async {
      await open(tester);

      expect(find.text('Newest First'), findsOneWidget);
      expect(find.byIcon(Icons.sort), findsOneWidget);
      expect(
        find.textContaining('only order the marketplace provides'),
        findsOneWidget,
      );
    });
  });

  group('apply', () {
    testWidgets('returns the selected type and price', (
      WidgetTester tester,
    ) async {
      final _Result result = await open(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('animal-type-Cattle')),
      );
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Min price'),
        '10000',
      );
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(result.returned, isTrue);
      expect(
        result.value,
        const ListingFilters(livestockType: 'Cattle', minPrice: '10000'),
      );
    });

    testWidgets('tapping a selected animal tile clears it', (
      WidgetTester tester,
    ) async {
      final _Result result = await open(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('animal-type-Cattle')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('animal-type-Cattle')),
      );
      await tester.pump();
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(result.value, ListingFilters.none);
    });

    testWidgets('keeps the screen open and explains an inverted range', (
      WidgetTester tester,
    ) async {
      final _Result result = await open(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Min price'),
        '50000',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Max price'),
        '10000',
      );
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(
        find.text('The minimum price is higher than the maximum price.'),
        findsOneWidget,
      );
      expect(result.returned, isFalse);
      // The input is explained, never cleared.
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Min price'))
            .controller
            ?.text,
        '50000',
      );
    });
  });

  group('reset and cancel', () {
    testWidgets('reset clears the form without applying or closing', (
      WidgetTester tester,
    ) async {
      final _Result result = await open(
        tester,
        initial: const ListingFilters(
          livestockType: 'Cattle',
          minPrice: '10000',
        ),
      );

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      expect(result.returned, isFalse, reason: 'reset must not submit');
      expect(find.text('Filter Livestock'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Min price'))
            .controller
            ?.text,
        isEmpty,
      );
      expect(
        // The Animal Type section's "exact wording" field is the first text
        // field in the tree, ahead of Min price, Max price and Location.
        tester.widget<TextField>(find.byType(TextField).at(0)).controller?.text,
        isEmpty,
      );
    });

    testWidgets('cancel discards edits and resolves to null', (
      WidgetTester tester,
    ) async {
      final _Result result = await open(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('animal-type-Cattle')),
      );
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result.returned, isTrue);
      expect(result.value, isNull);
    });
  });
}
