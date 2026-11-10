import 'package:agrobenta_mobile/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/auth_fakes.dart';
import '../support/transaction_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('token');
    recorded = <RecordedRequest>[];
  });

  test(
    'delegates a fulfillment action and returns the parsed record',
    () async {
      final repository = buildTransactionRepository(
        tokenStore,
        (_) async => transactionDetailResponse(
          transaction: transactionJson(
            id: 4,
            fulfillmentStatus: 'delivered',
            permittedActions: const <String>['confirm_received'],
          ),
        ),
        recorded: recorded,
      );

      final Transaction updated = await repository.performFulfillmentAction(
        4,
        TransactionFulfillmentAction.delivered,
      );

      expect(updated.fulfillmentStatus, TransactionFulfillmentStatus.delivered);
      expect(updated.canConfirmReceived, isTrue);
      expect(recorded.single.apiPath, '/transactions/4/delivered');
      expect(recorded.single.method, 'POST');
    },
  );

  test('clamps the page size before calling the service', () async {
    final repository = buildTransactionRepository(
      tokenStore,
      (_) async => transactionListResponse(),
      recorded: recorded,
    );

    await repository.list(perPage: 500);

    expect(recorded.single.query['per_page'], '50');
  });
}
