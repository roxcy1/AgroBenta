import 'package:agrobenta_mobile/core/utils/app_formatters.dart';
import 'package:agrobenta_mobile/models/listing.dart';
import 'package:agrobenta_mobile/models/marketplace_page.dart';
import 'package:agrobenta_mobile/models/pagination.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/marketplace_fakes.dart';

void main() {
  group('Listing.fromJson', () {
    test('parses a full MobileListingResource payload', () {
      final Listing listing = Listing.fromJson(listingJson());

      expect(listing.id, 12);
      expect(listing.livestockType, 'Cattle');
      expect(listing.breed, 'Holstein');
      expect(listing.quantity, 4);
      expect(listing.location, 'Mabalacat, Pampanga');
      expect(listing.shortDescription, contains('Holstein'));
      expect(listing.healthStatus, 'Healthy');
      expect(listing.vaccination, 'Vaccinated');
      expect(listing.additionalNotes, isNotNull);
      expect(listing.status, ListingStatus.active);
      expect(listing.createdAt, isNotNull);
    });

    test('parses the seller as an id-and-name projection only', () {
      final Listing listing = Listing.fromJson(listingJson());

      expect(listing.seller.id, 3);
      expect(listing.seller.name, 'Rizal Farms');
    });

    test('never exposes a seller email, even if the server sends one', () {
      // Defence in depth for §10.4: marketplace browsing must not harvest
      // contact details. The model has no field to hold one, so a payload
      // carrying it is dropped rather than surfaced.
      final Listing listing = Listing.fromJson(
        listingJson(
          seller: <String, dynamic>{
            'id': 3,
            'name': 'Rizal Farms',
            'email': 'seller@example.test',
          },
        ),
      );

      expect(listing.seller.name, 'Rizal Farms');
      expect(listing.seller.toString(), isNot(contains('seller@example.test')));
    });

    test('reads decimal columns as strings, the way MySQL sends them', () {
      final Listing listing = Listing.fromJson(
        listingJson(
          askingPrice: '42500.00',
          ageValue: '18.0',
          weightValue: '320.50',
        ),
      );

      expect(listing.askingPrice, '42500.00');
      expect(listing.ageValue, '18.0');
      expect(listing.weightValue, '320.50');
    });

    test('reads the same decimals as numbers, the way SQLite sends them', () {
      // SQLite is what the test suite runs against, and it returns native
      // numbers for decimal columns. Both drivers must yield one identical
      // client, so this is a contract requirement, not a curiosity.
      final Listing listing = Listing.fromJson(
        listingJson(askingPrice: 42500.0, ageValue: 18.0, weightValue: 320.5),
      );

      expect(listing.askingPrice, '42500.0');
      expect(listing.ageValue, '18.0');
      expect(listing.weightValue, '320.5');
    });

    test('treats absent optional fields as null rather than empty strings', () {
      final Listing listing = Listing.fromJson(
        listingJson(
          ageValue: null,
          ageUnit: null,
          gender: null,
          weightValue: null,
          healthStatus: null,
          vaccination: null,
          additionalNotes: null,
        ),
      );

      expect(listing.ageValue, isNull);
      expect(listing.ageUnit, isNull);
      expect(listing.gender, isNull);
      expect(listing.weightValue, isNull);
      expect(listing.healthStatus, isNull);
      expect(listing.vaccination, isNull);
      expect(listing.additionalNotes, isNull);
      expect(listing.ageLabel, isNull);
      expect(listing.weightLabel, isNull);
    });

    test('rejects a non-string photos entry rather than dropping it', () {
      // Deliberate: a `null` inside the array means the JSON column holds
      // something other than what `MobileListingResource` promises, and
      // silently discarding it would hide a photo a seller believes they
      // uploaded. The backend is the layer that normalises the column and it
      // has its own tests for that, so a failure here is a real contract break.
      expect(
        () => Listing.fromJson(listingJson(photos: <Object?>[null])),
        throwsA(isA<FormatException>()),
      );
    });

    test('treats an absent or null photos column as an empty list', () {
      expect(Listing.fromJson(listingJson(photos: null)).photos, isEmpty);
      expect(Listing.fromJson(listingJson()..remove('photos')).photos, isEmpty);
    });

    test('resolves stored photo paths against the configured API origin', () {
      final Listing listing = Listing.fromJson(
        listingJson(
          photos: <Object?>['listings/12/front.jpg', 'listings/12/side.jpg'],
        ),
      );

      expect(listing.photos, hasLength(2));
      // Relative paths become absolute, fetchable URLs — never `/api/...`.
      expect(listing.photos, everyElement(startsWith('http://')));
      expect(listing.photos, everyElement(isNot(contains('/api/'))));
      expect(listing.photos.first, endsWith('/listings/12/front.jpg'));
      expect(listing.photos.last, endsWith('/listings/12/side.jpg'));
    });

    test('fails loudly on an unrecognised status', () {
      // An unknown status is a contract change. Guessing a default would render
      // it as a normal active listing, which is the worst possible outcome.
      expect(
        () => Listing.fromJson(listingJson(status: 'archived')),
        throwsFormatException,
      );
    });

    test('fails loudly when the seller sub-object is missing', () {
      final Map<String, dynamic> json = listingJson()..remove('seller');

      expect(() => Listing.fromJson(json), throwsA(isA<FormatException>()));
    });
  });

  group('Listing display helpers', () {
    test('formats an age with a pluralised unit and no trailing zero', () {
      final Listing listing = Listing.fromJson(
        listingJson(ageValue: '18.0', ageUnit: 'month'),
      );

      expect(listing.ageLabel, '18 months');
    });

    test('singularises a one-unit age', () {
      final Listing listing = Listing.fromJson(
        listingJson(ageValue: '1.0', ageUnit: 'year'),
      );

      expect(listing.ageLabel, '1 year');
    });

    test('keeps meaningful precision in a weight', () {
      final Listing listing = Listing.fromJson(
        listingJson(weightValue: '320.50', weightUnit: 'kg'),
      );

      expect(listing.weightLabel, '320.5 kg');
    });

    test('falls back to the species when the breed is blank', () {
      final Listing listing = Listing.fromJson(listingJson(breed: '   '));

      expect(listing.title, 'Cattle');
    });

    test('prefers the breed as the title when present', () {
      expect(Listing.fromJson(listingJson()).title, 'Holstein');
    });
  });

  group('photo URL handling', () {
    test('treats a storage-relative path as not loadable', () {
      // There is no upload endpoint and no agreed URL scheme (OQ-09), so the
      // values in flight are not fetchable and must not be handed to a loader.
      expect(
        Listing.isDirectlyLoadablePhotoUrl('listings/12/front.jpg'),
        isFalse,
      );
      expect(
        Listing.isDirectlyLoadablePhotoUrl('/storage/listings/12.jpg'),
        isFalse,
      );
    });

    test('accepts an absolute http or https URL as loadable', () {
      expect(
        Listing.isDirectlyLoadablePhotoUrl('https://api.test/storage/a.jpg'),
        isTrue,
      );
      expect(
        Listing.isDirectlyLoadablePhotoUrl('http://api.test/a.jpg'),
        isTrue,
      );
    });

    test('rejects a non-http scheme', () {
      expect(
        Listing.isDirectlyLoadablePhotoUrl('ftp://api.test/a.jpg'),
        isFalse,
      );
      expect(
        Listing.isDirectlyLoadablePhotoUrl('javascript:alert(1)'),
        isFalse,
      );
    });

    test('resolves relative photo paths against the configured API origin', () {
      final Listing listing = Listing.fromJson(
        listingJson(photos: <Object?>['listings/12/front.jpg']),
      );

      expect(listing.photos, isNotEmpty);
      // A relative path becomes an absolute, fetchable URL against the API
      // origin — never `/api/storage/...` or another malformed shape.
      expect(listing.photos.first, startsWith('http://'));
      expect(listing.photos.first, isNot(contains('/api/')));

      expect(listing.hasLoadablePhoto, isTrue);
    });

    test('preserves absolute external photo URLs unchanged', () {
      final Listing listing = Listing.fromJson(
        listingJson(
          photos: <Object?>['https://cdn.example.test/photos/front.jpg'],
        ),
      );

      expect(listing.photos, <String>['https://cdn.example.test/photos/front.jpg']);
      expect(listing.hasLoadablePhoto, isTrue);
    });
  });

  group('Listing.resolvePhotoUrl', () {
    test('rewrites localhost to the configured API origin', () {
      expect(
        Listing.resolvePhotoUrl(
          'http://localhost:8001/storage/listings/9/foo.jpg',
          apiOrigin: 'http://10.0.2.2:8001',
        ),
        'http://10.0.2.2:8001/storage/listings/9/foo.jpg',
      );
    });

    test('rewrites 127.0.0.1 to the configured API origin', () {
      expect(
        Listing.resolvePhotoUrl(
          'http://127.0.0.1:8001/storage/listings/9/foo.jpg',
          apiOrigin: 'http://192.168.1.14:8001',
        ),
        'http://192.168.1.14:8001/storage/listings/9/foo.jpg',
      );
    });

    test('preserves external CDN/S3 URLs unchanged', () {
      expect(
        Listing.resolvePhotoUrl(
          'https://cdn.example.test/photos/front.jpg',
          apiOrigin: 'http://10.0.2.2:8001',
        ),
        'https://cdn.example.test/photos/front.jpg',
      );

      expect(
        Listing.resolvePhotoUrl(
          'https://s3.us-east-1.amazonaws.com/bucket/photo.jpg',
          apiOrigin: 'http://localhost:8001',
        ),
        'https://s3.us-east-1.amazonaws.com/bucket/photo.jpg',
      );
    });

    test('resolves a path with a leading slash against the origin', () {
      expect(
        Listing.resolvePhotoUrl(
          '/storage/listings/9/foo.jpg',
          apiOrigin: 'http://10.0.2.2:8001',
        ),
        'http://10.0.2.2:8001/storage/listings/9/foo.jpg',
      );
    });

    test('resolves a path without a leading slash against the origin', () {
      expect(
        Listing.resolvePhotoUrl(
          'storage/listings/9/foo.jpg',
          apiOrigin: 'http://10.0.2.2:8001',
        ),
        'http://10.0.2.2:8001/storage/listings/9/foo.jpg',
      );
    });

    test('does not duplicate /api when resolving /storage paths', () {
      expect(
        Listing.resolvePhotoUrl(
          '/storage/listings/9/foo.jpg',
          apiOrigin: 'http://10.0.2.2:8001',
        ),
        isNot(contains('/api/storage')),
      );
    });

    test('keeps query string and fragment on rewritten URLs', () {
      expect(
        Listing.resolvePhotoUrl(
          'http://localhost:8001/storage/listings/9/foo.jpg?token=abc#x',
          apiOrigin: 'http://10.0.2.2:8001',
        ),
        'http://10.0.2.2:8001/storage/listings/9/foo.jpg?token=abc#x',
      );
    });

    test('uses https when the origin is https', () {
      expect(
        Listing.resolvePhotoUrl(
          'http://localhost/storage/foo.jpg',
          apiOrigin: 'https://api.staging.agrobenta.test',
        ),
        'https://api.staging.agrobenta.test/storage/foo.jpg',
      );
    });

    test('returns an empty string unchanged', () {
      expect(
        Listing.resolvePhotoUrl('', apiOrigin: 'http://localhost:8001'),
        '',
      );
    });

    test('treats unparseable input as unchanged', () {
      expect(
        Listing.resolvePhotoUrl('not a url', apiOrigin: 'http://localhost:8001'),
        'not a url',
      );
    });
  });

  group('MarketplacePage.fromJson', () {
    test('parses listings and the four-key pagination object', () {
      final MarketplacePage page = MarketplacePage.fromJson(
        marketplacePageJson(
          listings: <Map<String, dynamic>>[
            listingJson(id: 12),
            listingJson(id: 11),
          ],
          currentPage: 2,
          lastPage: 5,
          perPage: 15,
          total: 68,
        ),
      );

      expect(page.listings, hasLength(2));
      expect(page.listings.first.id, 12);
      expect(page.pagination.currentPage, 2);
      expect(page.pagination.lastPage, 5);
      expect(page.pagination.perPage, 15);
      expect(page.pagination.total, 68);
      expect(page.hasMore, isTrue);
    });

    test('reports no more pages on the last page', () {
      final MarketplacePage page = MarketplacePage.fromJson(
        marketplacePageJson(currentPage: 5, lastPage: 5, total: 68),
      );

      expect(page.hasMore, isFalse);
    });

    test('parses an empty result set', () {
      final MarketplacePage page = MarketplacePage.fromJson(
        marketplacePageJson(listings: <Map<String, dynamic>>[], total: 0),
      );

      expect(page.listings, isEmpty);
      expect(page.isEmpty, isTrue);
    });

    test('fails loudly when the pagination object is missing', () {
      final Map<String, dynamic> json = marketplacePageJson()
        ..remove('pagination');

      expect(
        () => MarketplacePage.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('AppFormatters', () {
    test('formats a peso amount for display and for a card', () {
      expect(AppFormatters.formatMoney('42500.00'), '₱42,500.00');
      expect(AppFormatters.formatMoneyCompact('42500.00'), '₱42,500');
    });

    test('shows an unparseable amount verbatim instead of inventing zero', () {
      expect(AppFormatters.formatMoney('n/a'), 'n/a');
    });

    test('treats a blank amount as absent', () {
      expect(AppFormatters.formatMoney(null), isNull);
      expect(AppFormatters.formatMoney('   '), isNull);
    });

    test('renders a recent timestamp relatively and an old one absolutely', () {
      final DateTime now = DateTime(2026, 9, 28, 12);

      expect(
        AppFormatters.formatRelative(DateTime(2026, 9, 28, 9), now: now),
        '3 hours ago',
      );
      expect(
        AppFormatters.formatRelative(DateTime(2026, 8, 1), now: now),
        '1 Aug 2026',
      );
    });
  });

  group('Pagination', () {
    test('is built from the four documented keys', () {
      final Pagination pagination = Pagination.fromJson(<String, dynamic>{
        'current_page': 3,
        'last_page': 9,
        'per_page': 15,
        'total': 128,
      });

      expect(pagination.currentPage, 3);
      expect(pagination.lastPage, 9);
      expect(pagination.perPage, 15);
      expect(pagination.total, 128);
      expect(pagination.hasNextPage, isTrue);
    });
  });
}
