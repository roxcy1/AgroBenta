import 'package:agrobenta_mobile/core/constants/api_constants.dart';
import 'package:agrobenta_mobile/repositories/seller_listing_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seller_listing_fakes.dart';

/// The repository owns exactly one policy: the server caps `per_page` at 50 with
/// a `422`, which is a fact about the API and so belongs at this layer.
void main() {
  group('per-page clamping', () {
    test('a value above the server cap is clamped to it', () async {
      final harness = _recorded();
      await _listWithPerPage(harness.repo, 200);

      expect(
        harness.recorded.single.query['per_page'],
        '${SellerListingEndpoints.maxPerPage}',
      );
    });

    test('a value below 1 is clamped to 1', () async {
      final harness = _recorded();
      await _listWithPerPage(harness.repo, 0);

      expect(harness.recorded.single.query['per_page'], '1');
    });

    test('in-range values pass through untouched', () async {
      final harness = _recorded();
      await _listWithPerPage(harness.repo, 25);

      expect(harness.recorded.single.query['per_page'], '25');
    });
  });
}

Future<void> _listWithPerPage(SellerListingRepository repo, int perPage) =>
    repo.listMine(perPage: perPage);

({SellerListingRepository repo, List<RecordedRequest> recorded}) _recorded() {
  final List<RecordedRequest> recorded = <RecordedRequest>[];
  return (
    repo: buildSellerListingRepository(
      FakeTokenStore('1|test-mobile-token'),
      (RecordedRequest request) async => sellerListingListResponse(),
      recorded: recorded,
    ),
    recorded: recorded,
  );
}
