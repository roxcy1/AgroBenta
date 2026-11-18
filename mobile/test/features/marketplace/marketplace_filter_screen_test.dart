import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/livestock_types/state/livestock_types_controller.dart';
import 'package:agrobenta_mobile/features/livestock_types/state/livestock_types_scope.dart';
import 'package:agrobenta_mobile/features/marketplace/state/listing_filters.dart';
import 'package:agrobenta_mobile/features/marketplace/views/marketplace_filter_screen.dart';
import 'package:agrobenta_mobile/repositories/livestock_type_repository.dart';
import 'package:agrobenta_mobile/services/livestock_type_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/auth_fakes.dart';

/// Captures what the dialog resolves to, so a test can tell "cancelled"
/// (`returned` true, `value` null) from "never came back".
class _Result {
  ListingFilters? value;
  bool returned = false;
}

void main() {
  /// Pumps a host route that opens the filter dialog through the real entry
  /// point, [showMarketplaceFilterScreen].
  ///
  /// Deliberately builds **no** `MarketplaceScope` or `AuthScope`: the dialog
  /// is presentation over a form and must make no request of its own, so a
  /// missing scope is the assertion that nothing here reaches the API.
  Future<_Result> open(
    WidgetTester tester, {
    ListingFilters initial = ListingFilters.none,
  }) async {
    final _Result result = _Result();
    final LivestockTypeRepository catalogRepository = LivestockTypeRepository(
      LivestockTypeService(
        ApiClient(
          tokenStorage: FakeTokenStore('test-token'),
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'data': <Map<String, dynamic>>[
                  {
                    'value': 'cattle',
                    'label': 'Cattle',
                    'breeds': <String>['Brahman', 'Holstein Friesian'],
                  },
                  {
                    'value': 'carabao',
                    'label': 'Carabao',
                    'breeds': <String>['Murrah'],
                  },
                  {
                    'value': 'goat',
                    'label': 'Goat',
                    'breeds': <String>['Boer', 'Saanen'],
                  },
                  {
                    'value': 'swine',
                    'label': 'Swine',
                    'breeds': <String>['Landrace'],
                  },
                  {
                    'value': 'chicken',
                    'label': 'Chicken',
                    'breeds': <String>['Broiler'],
                  },
                ],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            ),
          ),
        ),
      ),
    );
    final LivestockTypesController catalog = LivestockTypesController(
      catalogRepository,
    );
    addTearDown(catalog.dispose);

    // The default 800x600 surface is shorter than the form, and the lazy list
    // only builds what is on screen. A tall portrait surface makes the whole
    // form real.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      LivestockTypesScope(
        repository: catalogRepository,
        controller: catalog,
        child: MaterialApp(
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
      ),
    );

    await tester.tap(find.text('Open filters'));
    await tester.pumpAndSettle();

    return result;
  }

  group('layout', () {
    testWidgets('shows the header, sections and actions', (tester) async {
      await open(tester);

      expect(find.text('Filter Livestock'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Apply Filters'), findsOneWidget);

      for (final String section in <String>[
        'Animal Type',
        'Breed',
        'Price Range',
        'Additional Filters',
      ]) {
        expect(find.text(section), findsOneWidget, reason: section);
      }

      expect(find.text('Select one or more animal types.'), findsOneWidget);
      expect(
        find.text('Choose breed(s) for the selected animal types.'),
        findsOneWidget,
      );
      expect(
        find.text('Choose at least one animal type to see breeds.'),
        findsOneWidget,
      );

      expect(find.text('Minimum price'), findsOneWidget);
      expect(find.text('Maximum price'), findsOneWidget);
      expect(find.text('Sex'), findsOneWidget);
      expect(find.text('Age (months)'), findsOneWidget);
      expect(find.text('Weight (kg)'), findsOneWidget);
      expect(find.text('Any'), findsOneWidget);
      expect(find.text('Male'), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);
      expect(find.text('Min'), findsWidgets);
      expect(find.text('Max'), findsWidgets);

      for (final String animal in <String>[
        'Cattle',
        'Carabao',
        'Goat',
        'Swine',
        'Chicken',
      ]) {
        expect(find.text(animal), findsOneWidget, reason: animal);
      }
    });
  });

  group('apply', () {
    testWidgets('returns every selected type', (tester) async {
      final _Result result = await open(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('animal-type-cattle')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('animal-type-goat')));
      await tester.pump();
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(
        result.value,
        const ListingFilters(livestockTypes: <String>['cattle', 'goat']),
      );
    });

    testWidgets('tapping a selected type clears it', (tester) async {
      final _Result result = await open(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('animal-type-cattle')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('animal-type-cattle')),
      );
      await tester.pump();
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(result.value, ListingFilters.none);
    });

    testWidgets('applies sex, age and weight', (tester) async {
      final _Result result = await open(tester);

      await tester.tap(find.text('Female'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Min').at(0), '12');
      await tester.enterText(find.widgetWithText(TextField, 'Max').at(0), '24');
      await tester.enterText(
        find.widgetWithText(TextField, 'Min').at(1),
        '200',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Max').at(1),
        '500',
      );
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(
        result.value,
        const ListingFilters(
          gender: 'female',
          minAge: '12',
          maxAge: '24',
          minWeight: '200',
          maxWeight: '500',
        ),
      );
    });
  });

  group('breed selector', () {
    testWidgets('is disabled until a type is chosen', (tester) async {
      await open(tester);

      expect(find.text('Select an animal type first'), findsOneWidget);

      await tester.tap(find.text('Select an animal type first'));
      await tester.pumpAndSettle();

      expect(find.text('Select breeds'), findsNothing);
    });

    testWidgets('offers the selected types\' breeds and returns them', (
      tester,
    ) async {
      final _Result result = await open(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('animal-type-cattle')),
      );
      await tester.pump();
      await tester.tap(find.text('Select breed(s)'));
      await tester.pumpAndSettle();

      expect(find.text('Select breeds'), findsOneWidget);
      expect(find.text('Brahman'), findsOneWidget);
      expect(find.text('Holstein Friesian'), findsOneWidget);

      await tester.tap(find.text('Brahman'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(
        result.value,
        const ListingFilters(
          livestockTypes: <String>['cattle'],
          breeds: <String>['Brahman'],
        ),
      );
    });

    testWidgets('prunes a breed when its type is removed', (tester) async {
      final _Result result = await open(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('animal-type-cattle')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('animal-type-goat')));
      await tester.pump();
      await tester.tap(find.text('Select breed(s)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Brahman'));
      await tester.pump();
      await tester.tap(find.text('Boer'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Removing goat must drop Boer; Brahman belongs to cattle and stays.
      await tester.tap(find.byKey(const ValueKey<String>('animal-type-goat')));
      await tester.pump();
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(
        result.value,
        const ListingFilters(
          livestockTypes: <String>['cattle'],
          breeds: <String>['Brahman'],
        ),
      );
    });

    testWidgets('drops every breed of a removed type', (tester) async {
      final _Result result = await open(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('animal-type-cattle')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('animal-type-goat')));
      await tester.pump();
      await tester.tap(find.text('Select breed(s)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Brahman'));
      await tester.pump();
      await tester.tap(find.text('Boer'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Removing cattle must drop Brahman; Boer belongs to goat and stays.
      await tester.tap(
        find.byKey(const ValueKey<String>('animal-type-cattle')),
      );
      await tester.pump();
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(
        result.value,
        const ListingFilters(
          livestockTypes: <String>['goat'],
          breeds: <String>['Boer'],
        ),
      );
    });
  });

  group('validation', () {
    testWidgets('explains an inverted price range and stays open', (
      tester,
    ) async {
      final _Result result = await open(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Minimum price'),
        '50000',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Maximum price'),
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
            .widget<TextField>(find.widgetWithText(TextField, 'Minimum price'))
            .controller
            ?.text,
        '50000',
      );
    });

    testWidgets('explains an inverted age range', (tester) async {
      final _Result result = await open(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Min').at(0), '24');
      await tester.enterText(find.widgetWithText(TextField, 'Max').at(0), '12');
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(
        find.text('The minimum age is higher than the maximum age.'),
        findsOneWidget,
      );
      expect(result.returned, isFalse);
    });

    testWidgets('explains an inverted weight range', (tester) async {
      final _Result result = await open(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Min').at(1),
        '500',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Max').at(1),
        '200',
      );
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(
        find.text('The minimum weight is higher than the maximum weight.'),
        findsOneWidget,
      );
      expect(result.returned, isFalse);
    });
  });

  group('reset, cancel and initial values', () {
    testWidgets('reset clears the form without applying or closing', (
      tester,
    ) async {
      final _Result result = await open(
        tester,
        initial: const ListingFilters(
          livestockTypes: <String>['cattle'],
          minPrice: '10000',
        ),
      );

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      expect(result.returned, isFalse, reason: 'reset must not submit');
      expect(find.text('Filter Livestock'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Minimum price'))
            .controller
            ?.text,
        isEmpty,
      );

      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();
      expect(result.value, ListingFilters.none);
    });

    testWidgets('cancel discards edits and resolves to null', (tester) async {
      final _Result result = await open(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('animal-type-cattle')),
      );
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result.returned, isTrue);
      expect(result.value, isNull);
    });

    testWidgets('initializes every field from the applied filters', (
      tester,
    ) async {
      await open(
        tester,
        initial: const ListingFilters(
          livestockTypes: <String>['cattle'],
          breeds: <String>['Brahman'],
          gender: 'female',
          minAge: '12',
          maxAge: '24',
          minWeight: '200',
          maxWeight: '500',
          minPrice: '10000',
          maxPrice: '50000',
        ),
      );

      expect(find.text('Brahman'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Minimum price'))
            .controller
            ?.text,
        '10000',
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Maximum price'))
            .controller
            ?.text,
        '50000',
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Min').at(0))
            .controller
            ?.text,
        '12',
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Max').at(0))
            .controller
            ?.text,
        '24',
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Min').at(1))
            .controller
            ?.text,
        '200',
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Max').at(1))
            .controller
            ?.text,
        '500',
      );
    });
  });
}
