import 'package:flutter_test/flutter_test.dart';

import '../support/auth_fakes.dart';
import '../support/inquiry_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('token');
    recorded = <RecordedRequest>[];
  });

  group('listReceived', () {
    test('clamps per_page to the server maximum', () async {
      await buildInquiryRepository(
        tokenStore,
        (_) async => sellerInquiryListResponse(),
        recorded: recorded,
      ).listReceived(perPage: 999);

      expect(recorded.single.query['per_page'], '50');
    });

    test('clamps a per_page below one to one', () async {
      await buildInquiryRepository(
        tokenStore,
        (_) async => sellerInquiryListResponse(),
        recorded: recorded,
      ).listReceived(perPage: 0);

      expect(recorded.single.query['per_page'], '1');
    });

    test('normalises a page below one to page one', () async {
      await buildInquiryRepository(
        tokenStore,
        (_) async => sellerInquiryListResponse(),
        recorded: recorded,
      ).listReceived(page: 0);

      expect(recorded.single.query['page'], '1');
    });

    test('sends the default page size explicitly', () async {
      await buildInquiryRepository(
        tokenStore,
        (_) async => sellerInquiryListResponse(),
        recorded: recorded,
      ).listReceived();

      expect(recorded.single.query['per_page'], '15');
    });
  });
}
