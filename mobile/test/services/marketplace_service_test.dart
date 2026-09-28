import 'package:agrobenta_mobile/core/constants/api_constants.dart';
import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/core/network/api_exception.dart';
import 'package:agrobenta_mobile/models/listing.dart';
import 'package:agrobenta_mobile/repositories/marketplace_repository.dart';
import 'package:agrobenta_mobile/services/marketplace_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/auth_fakes.dart';
import '../support/marketplace_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('valid-mobile-token');
    recorded = <RecordedRequest>[];
  });

  /// The service over a mock transport, recording what it sent.
  ///
  /// Built through the same `ApiClient` the app uses, so the envelope
  /// unwrapping, the bearer token and the status-code translation are the real
  /// ones rather than stubs.
  MarketplaceService buildService(
    Future<http.Response> Function(RecordedRequest request) handler,
  ) {
    return MarketplaceService(
      ApiClient(
        tokenStorage: tokenStore,
        httpClient: MockClient((http.Request request) async {
          final RecordedRequest entry = RecordedRequest(request);
          recorded.add(entry);
          return handler(entry);
        }),
      ),
    );
  }

  group('MarketplaceService.browse', () {
    test('requests GET /listings with the default page size', () async {
      final MarketplaceService service = buildService(
        (_) async => marketplaceListResponse(),
      );

      await service.browse();

      expect(recorded, hasLength(1));
      expect(recorded.single.method, 'GET');
      expect(recorded.single.apiPath, '/listings');
      expect(recorded.single.query['page'], '1');
      expect(recorded.single.query['per_page'], '15');
    });

    test('never requests the admin /api/livestock path', () async {
      final MarketplaceService service = buildService(
        (_) async => marketplaceListResponse(),
      );

      await service.browse();

      // §10.2: the admin browse endpoint returns seller fields and accepts
      // filters this app must not send. Reaching for it would be a privacy
      // regression, so the path is asserted rather than trusted.
      expect(recorded.single.path, isNot(contains('/livestock')));
      expect(recorded.single.apiPath, '/listings');
    });

    test('attaches the bearer token', () async {
      final MarketplaceService service = buildService(
        (_) async => marketplaceListResponse(),
      );

      await service.browse();

      expect(recorded.single.authorization, 'Bearer valid-mobile-token');
    });

    test('omits blank filters instead of sending empty values', () async {
      final MarketplaceService service = buildService(
        (_) async => marketplaceListResponse(),
      );

      await service.browse(search: '   ', livestockType: '', minPrice: '  ');

      expect(recorded.single.query.containsKey('search'), isFalse);
      expect(recorded.single.query.containsKey('livestock_type'), isFalse);
      expect(recorded.single.query.containsKey('min_price'), isFalse);
      expect(recorded.single.query.containsKey('max_price'), isFalse);
    });

    test('sends each filter under its documented query key', () async {
      final MarketplaceService service = buildService(
        (_) async => marketplaceListResponse(),
      );

      await service.browse(
        search: 'holstein',
        livestockType: 'Cattle',
        location: 'Pampanga',
        minPrice: '10000',
        maxPrice: '50000',
        page: 3,
        perPage: 20,
      );

      final Map<String, String> query = recorded.single.query;
      expect(query['search'], 'holstein');
      expect(query['livestock_type'], 'Cattle');
      expect(query['location'], 'Pampanga');
      expect(query['min_price'], '10000');
      expect(query['max_price'], '50000');
      expect(query['page'], '3');
      expect(query['per_page'], '20');
    });

    test('trims filter whitespace before sending it', () async {
      final MarketplaceService service = buildService(
        (_) async => marketplaceListResponse(),
      );

      await service.browse(livestockType: '  Cattle  ');

      expect(recorded.single.query['livestock_type'], 'Cattle');
    });

    test('sends no status, seller_id or role filter, so none can be forged', () {
      // A compile-time guarantee restated as a test: the only query keys the
      // service can emit are the ones in its allow-list, so a client-side
      // "show me sold listings" is not expressible.
      expect(MarketplaceEndpoints.browse, '/listings');
    });

    test('parses the listings and pagination out of the envelope', () async {
      final MarketplaceService service = buildService(
        (_) async => marketplaceListResponse(
          listings: <Map<String, dynamic>>[
            listingJson(id: 12),
            listingJson(id: 11),
          ],
          currentPage: 1,
          lastPage: 3,
          total: 40,
        ),
      );

      final page = await service.browse();

      expect(page.listings.map((Listing l) => l.id), <int>[12, 11]);
      expect(page.pagination.lastPage, 3);
      expect(page.hasMore, isTrue);
    });

    test('translates a 401 into an unauthorized ApiException and clears the token',
        () async {
      final MarketplaceService service = buildService(
        (_) async => unauthorizedResponse(),
      );

      await expectLater(
        service.browse(),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.unauthorized,
          ),
        ),
      );
      expect(
        tokenStore.token,
        isNull,
        reason: 'a 401 must clear the stored token so nothing retries it',
      );
    });

    test('translates a 403 into a forbidden ApiException', () async {
      final MarketplaceService service = buildService(
        (_) async => forbiddenResponse(),
      );

      await expectLater(
        service.browse(),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.forbidden,
          ),
        ),
      );
    });

    test('translates a 422 into a validation ApiException with field errors',
        () async {
      final MarketplaceService service = buildService(
        (_) async => validationResponse(),
      );

      try {
        await service.browse(perPage: 500);
        fail('expected an ApiException');
      } on ApiException catch (error) {
        expect(error.kind, ApiErrorKind.validation);
        expect(error.validationErrors.keys, contains('per_page'));
      }
    });

    test('translates a non-JSON 200 into a malformedResponse ApiException',
        () async {
      final MarketplaceService service = buildService(
        (_) async => http.Response('<html>gateway timeout</html>', 200),
      );

      await expectLater(
        service.browse(),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.malformedResponse,
          ),
        ),
      );
    });

    test('translates a 200 whose data is not an object', () async {
      final MarketplaceService service = buildService(
        (_) async => http.Response(
          '{"success":true,"message":"ok","data":"nope"}',
          200,
        ),
      );

      await expectLater(
        service.browse(),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.malformedResponse,
          ),
        ),
      );
    });

    test('reports a transport failure as a network ApiException', () async {
      final MarketplaceService service = buildService(
        (_) async => throw http.ClientException('connection refused'),
      );

      await expectLater(
        service.browse(),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.network,
          ),
        ),
      );
    });
  });

  group('MarketplaceService.detail', () {
    test('requests GET /listings/{id} with no query', () async {
      final MarketplaceService service = buildService(
        (_) async => listingDetailResponse(),
      );

      final Listing listing = await service.detail(12);

      expect(recorded.single.method, 'GET');
      expect(recorded.single.apiPath, '/listings/12');
      expect(listing.id, 12);
    });

    test('parses the full detail payload', () async {
      final MarketplaceService service = buildService(
        (_) async => listingDetailResponse(),
      );

      final Listing listing = await service.detail(12);

      expect(listing.seller.name, 'Rizal Farms');
      expect(listing.livestockType, 'Cattle');
      expect(listing.askingPrice, '42500.00');
      expect(listing.photos, isEmpty);
    });

    test('translates a 404 into a notFound ApiException', () async {
      // The case [D-02] requires: a hidden listing must be indistinguishable
      // from one that never existed, and the detail screen keys its
      // "no longer available" state off exactly this kind.
      final MarketplaceService service = buildService(
        (_) async => listingNotFoundResponse(),
      );

      await expectLater(
        service.detail(99),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.notFound,
          ),
        ),
      );
    });

    test('does not clear the token on a 404', () async {
      final MarketplaceService service = buildService(
        (_) async => listingNotFoundResponse(),
      );

      await expectLater(service.detail(99), throwsA(isA<ApiException>()));

      expect(
        tokenStore.token,
        'valid-mobile-token',
        reason: 'a hidden listing is not an auth problem',
      );
    });
  });

  group('MarketplaceRepository', () {
    MarketplaceRepository buildRepository(
      Future<http.Response> Function(RecordedRequest request) handler,
    ) => MarketplaceRepository(buildService(handler));

    test('clamps a page size above the server cap instead of provoking a 422',
        () async {
      // `IndexListingRequest` rejects per_page > 50 with a 422. Clamping here
      // means a screen asking for 200 gets 50 listings, not an error.
      final MarketplaceRepository repository = buildRepository(
        (_) async => marketplaceListResponse(),
      );

      await repository.browse(perPage: 200);

      expect(recorded.single.query['per_page'], '50');
    });

    test('clamps a page size below one to one', () async {
      final MarketplaceRepository repository = buildRepository(
        (_) async => marketplaceListResponse(),
      );

      await repository.browse(perPage: 0);

      expect(recorded.single.query['per_page'], '1');
    });

    test('clamps a page number below one to the first page', () async {
      final MarketplaceRepository repository = buildRepository(
        (_) async => marketplaceListResponse(),
      );

      await repository.browse(page: -4);

      expect(recorded.single.query['page'], '1');
    });

    test('uses the default page size when none is given', () async {
      final MarketplaceRepository repository = buildRepository(
        (_) async => marketplaceListResponse(),
      );

      await repository.browse();

      expect(recorded.single.query['per_page'], '15');
      expect(recorded.single.query['page'], '1');
    });

    test('passes a page size inside the allowed range through unchanged',
        () async {
      final MarketplaceRepository repository = buildRepository(
        (_) async => marketplaceListResponse(),
      );

      await repository.browse(perPage: 25);

      expect(recorded.single.query['per_page'], '25');
    });

    test('propagates an ApiException rather than translating it again', () async {
      final MarketplaceRepository repository = buildRepository(
        (_) async => unauthorizedResponse(),
      );

      await expectLater(
        repository.browse(),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.unauthorized,
          ),
        ),
      );
    });

    test('forwards a detail request and its notFound outcome', () async {
      final MarketplaceRepository repository = buildRepository(
        (_) async => listingNotFoundResponse(),
      );

      await expectLater(
        repository.detail(99),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.notFound,
          ),
        ),
      );
    });
  });
}
