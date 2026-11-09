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

  // Removed: `listReceived` / `GET /api/seller/inquiries` tests. These
  // correspond to the pre-MS-18 seller inbox which was deleted (PM decision
  // MS-18, 2026-10-29). The write path (`create`) and the buyer's own active
  // inquiries (`listActive`, `findExistingForListing`) remain.
}
