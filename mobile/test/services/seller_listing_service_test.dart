import 'package:agrobenta_mobile/services/seller_listing_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seller_listing_fakes.dart';

/// The service sits between the repository and the API, and the one thing this
/// layer must be trusted to do is enforce the writable-field allow-list: no path
/// through it may construct a body containing `status` or `seller_id`, and no
/// undecided contract field (`photos`) may sneak in.
void main() {
  group('writableBody allow-list', () {
    test('keeps every contract field and drops nothing else', () {
      final Map<String, dynamic> body =
          SellerListingService.writableBody(<String, dynamic>{
            'livestock_type': 'Cattle',
            'breed': 'Holstein',
            'age_value': 18,
            'age_unit': 'month',
            'gender': 'female',
            'weight_value': '320.5',
            'weight_unit': 'kg',
            'quantity': 4,
            'asking_price': '42500',
            'location': 'Mabalacat, Pampanga',
            'health_status': 'Healthy',
            'vaccination': 'Vaccinated',
            'short_description': 'Ready for breeding.',
            'additional_notes': 'Weekend delivery.',
          });

      expect(body, hasLength(14));
      expect(body['gender'], 'female');
    });

    test('null values survive, because null is meaningful', () {
      // The allow-list filters keys, never values: a nullable column is set to
      // null on purpose, and dropping it would silently turn a deliberate clear
      // into a no-op.
      final Map<String, dynamic> body = SellerListingService.writableBody(
        <String, dynamic>{'gender': null},
      );

      expect(body, contains('gender'));
      expect(body['gender'], isNull);
    });

    test('status and seller_id have no path into a body', () {
      // The two prohibited fields, input both ways: swallowed silently rather
      // than sent and rejected. A silent drop is a client bug caught in a test;
      // a sent `422` is one a seller has to interpret.
      final Map<String, dynamic> body = SellerListingService.writableBody(
        <String, dynamic>{
          'status': 'active',
          'seller_id': 3,
          'livestock_type': 'Cattle',
        },
      );

      expect(body.containsKey('status'), isFalse);
      expect(body.containsKey('seller_id'), isFalse);
      expect(body['livestock_type'], 'Cattle');
    });

    test('photos is excluded until D-10 is resolved', () {
      // No upload endpoint, no storage URL scheme (D-10 / GAP-06). A body with a
      // photo path would encode an answer nobody has given.
      final Map<String, dynamic> body = SellerListingService.writableBody(
        <String, dynamic>{
          'photos': <String>['listings/1/front.jpg'],
        },
      );

      expect(body.containsKey('photos'), isFalse);
    });
  });

  group('listMine query', () {
    test('blank filters are absent, not echoed', () async {
      final harness = buildRecordedController(
        (RecordedRequest request) async => sellerListingListResponse(),
      );
      addTearDown(harness.controller.dispose);

      await harness.controller.loadInitial();

      expect(harness.recorded.single.query.containsKey('status'), isFalse);
      expect(harness.recorded.single.query.containsKey('search'), isFalse);
    });
  });
}
