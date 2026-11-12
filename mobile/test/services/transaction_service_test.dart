import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/services/transaction_service.dart';
import 'package:agrobenta_mobile/models/transaction.dart';
import 'package:agrobenta_mobile/models/transaction_receipt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/auth_fakes.dart';
import '../support/transaction_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('token');
    recorded = <RecordedRequest>[];
  });

  TransactionService service() {
    final ApiClient client = ApiClient(
      tokenStorage: tokenStore,
      httpClient: MockClient((http.Request request) async {
        recorded.add(RecordedRequest(request));
        return transactionDetailResponse(
          transaction: transactionJson(
            id: 9,
            fulfillmentStatus: 'preparing',
            permittedActions: const <String>['ready_for_pickup', 'cancel'],
          ),
        );
      }),
    );
    return TransactionService(client);
  }

  test('posts every fulfillment action to its exact endpoint', () async {
    final Map<TransactionFulfillmentAction, String> paths =
        <TransactionFulfillmentAction, String>{
          TransactionFulfillmentAction.preparing: '/transactions/9/preparing',
          TransactionFulfillmentAction.readyForPickup:
              '/transactions/9/ready-for-pickup',
          TransactionFulfillmentAction.pickedUp: '/transactions/9/picked-up',
          TransactionFulfillmentAction.onTheWay: '/transactions/9/on-the-way',
          TransactionFulfillmentAction.delivered: '/transactions/9/delivered',
          TransactionFulfillmentAction.confirmReceived:
              '/transactions/9/complete',
        };

    final TransactionService transactionService = service();

    for (final MapEntry<TransactionFulfillmentAction, String> entry
        in paths.entries) {
      final Transaction updated = await transactionService
          .performFulfillmentAction(9, entry.key);

      expect(updated.id, 9);
      expect(recorded.last.method, 'POST');
      expect(recorded.last.apiPath, entry.value);
      expect(recorded.last.query, isEmpty);
    }

    expect(recorded, hasLength(paths.length));
    expect(recorded.map((RecordedRequest r) => r.apiPath), paths.values);
  });

  test(
    'refuses no endpoint for an unknown action because the type is closed',
    () {
      // The switch in TransactionService is exhaustive over the enum. This test
      // documents that there is no raw-string path into the transport.
      expect(TransactionFulfillmentAction.values, hasLength(6));
      expect(TransactionFulfillmentAction.tryFromValue('teleport'), isNull);
    },
  );

  test('gets the receipt from its exact endpoint and parses it', () async {
    final ApiClient client = ApiClient(
      tokenStorage: tokenStore,
      httpClient: MockClient((http.Request request) async {
        recorded.add(RecordedRequest(request));
        return transactionReceiptResponse(receipt: transactionReceiptJson());
      }),
    );

    final TransactionReceipt receipt = await TransactionService(
      client,
    ).receipt(9);

    expect(receipt.reference, 'TRX-001');
    expect(recorded.single.method, 'GET');
    expect(recorded.single.apiPath, '/transactions/9/receipt');
    expect(recorded.single.query, isEmpty);
  });
}
