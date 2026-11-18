import 'package:agrobenta_mobile/features/marketplace/state/listing_filters.dart';
import 'package:agrobenta_mobile/models/livestock_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// The catalog relationship the pruning rule must honour: a breed belongs to
/// exactly the animal types that list it.
const List<LivestockType> catalog = <LivestockType>[
  LivestockType(
    value: 'cattle',
    label: 'Cattle',
    breeds: <String>['Brahman', 'Holstein Friesian'],
  ),
  LivestockType(
    value: 'goat',
    label: 'Goat',
    breeds: <String>['Boer', 'Saanen'],
  ),
];

void main() {
  group('pruneIncompatibleBreeds', () {
    test('keeps a breed the selected type offers', () {
      const ListingFilters filters = ListingFilters(
        livestockTypes: <String>['cattle'],
        breeds: <String>['Brahman'],
      );

      final ListingFilters pruned = filters.pruneIncompatibleBreeds(
        filters.livestockTypes,
        catalog: catalog,
      );

      expect(pruned.breeds, <String>['Brahman']);
    });

    test(
      'removes a breed when the type changes to one that does not offer it',
      () {
        const ListingFilters filters = ListingFilters(
          livestockTypes: <String>['cattle'],
          breeds: <String>['Brahman'],
        );

        final ListingFilters pruned = filters.pruneIncompatibleBreeds(<String>[
          'goat',
        ], catalog: catalog);

        expect(pruned.livestockTypes, <String>['cattle']);
        expect(pruned.breeds, isEmpty);
      },
    );

    test('clears stale breeds when every type is cleared', () {
      const ListingFilters filters = ListingFilters(
        livestockTypes: <String>['cattle'],
        breeds: <String>['Brahman'],
      );

      final ListingFilters pruned = filters.pruneIncompatibleBreeds(
        <String>[],
        catalog: catalog,
      );

      expect(pruned.breeds, isEmpty);
    });

    test('keeps a breed that any one of several selected types offers', () {
      const ListingFilters filters = ListingFilters(
        livestockTypes: <String>['cattle', 'goat'],
        breeds: <String>['Brahman', 'Boer'],
      );

      final ListingFilters pruned = filters.pruneIncompatibleBreeds(<String>[
        'goat',
      ], catalog: catalog);

      expect(pruned.breeds, <String>['Boer']);
    });

    test('keeps the selection untouched when the catalog has not loaded', () {
      const ListingFilters filters = ListingFilters(
        livestockTypes: <String>['cattle'],
        breeds: <String>['Brahman'],
      );

      final ListingFilters pruned = filters.pruneIncompatibleBreeds(
        filters.livestockTypes,
        catalog: const <LivestockType>[],
      );

      expect(pruned.breeds, <String>['Brahman']);
    });
  });

  group('catalogBreeds', () {
    test(
      'is the de-duplicated union of the selected types, in catalog order',
      () {
        const List<LivestockType> overlapping = <LivestockType>[
          LivestockType(
            value: 'cattle',
            label: 'Cattle',
            breeds: <String>['Brahman'],
          ),
          LivestockType(
            value: 'goat',
            label: 'Goat',
            breeds: <String>['Boer', 'Brahman'],
          ),
        ];

        expect(
          ListingFilters.catalogBreeds(<String>['goat', 'cattle'], overlapping),
          <String>['Boer', 'Brahman'],
        );
      },
    );

    test('ignores a type the catalog does not know', () {
      expect(ListingFilters.catalogBreeds(<String>['horse'], catalog), isEmpty);
    });
  });
}
