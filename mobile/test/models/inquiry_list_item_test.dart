import 'package:agrobenta_mobile/models/inquiry_list_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/inquiry_fakes.dart';

void main() {
  group('InquiryListItem counterpart verification', () {
    test('parses the server-provided verification flag', () {
      final InquiryListItem item = InquiryListItem.fromJson(
        inquiryListItemJson(counterpartIsVerified: true),
      );

      expect(item.counterpart?.isVerified, isTrue);
    });

    test('missing and null flags default to unverified', () {
      final Map<String, dynamic> missing = inquiryListItemJson()
        ..['counterpart'] = <String, dynamic>{'id': 3, 'name': 'Seller'};
      final Map<String, dynamic> nullFlag = inquiryListItemJson()
        ..['counterpart'] = <String, dynamic>{
          'id': 3,
          'name': 'Seller',
          'is_verified': null,
        };

      expect(
        InquiryListItem.fromJson(missing).counterpart?.isVerified,
        isFalse,
      );
      expect(
        InquiryListItem.fromJson(nullFlag).counterpart?.isVerified,
        isFalse,
      );
    });
  });
}
