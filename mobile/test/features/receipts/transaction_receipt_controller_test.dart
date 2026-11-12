import 'package:agrobenta_mobile/features/receipts/state/transaction_receipt_controller.dart';
import 'package:agrobenta_mobile/features/receipts/state/transaction_receipt_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/transaction_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore()..token = 'stored-token';
    recorded = <RecordedRequest>[];
  });

  test('loads the receipt by id and publishes it', () async {
    final TransactionReceiptController controller =
        buildTransactionReceiptController(
          tokenStore,
          (_) async => transactionReceiptResponse(
            receipt: transactionReceiptJson(reference: 'TRX-007'),
          ),
          transactionId: 7,
          recorded: recorded,
        );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.state.status, TransactionReceiptStatus.ready);
    expect(controller.state.receipt!.reference, 'TRX-007');
    expect(recorded.single.apiPath, '/transactions/7/receipt');
  });

  test('maps a 404 to unavailable rather than a failure', () async {
    final TransactionReceiptController controller =
        buildTransactionReceiptController(
          tokenStore,
          (_) async => transactionNotFoundResponse(),
          recorded: recorded,
        );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.state.status, TransactionReceiptStatus.unavailable);
    expect(controller.state.receipt, isNull);
  });

  test('maps a 409 to unavailable because the sale is not completed', () async {
    final TransactionReceiptController controller =
        buildTransactionReceiptController(
          tokenStore,
          (_) async => transactionConflictResponse(
            message: 'Only a completed transaction has a receipt.',
          ),
          recorded: recorded,
        );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.state.status, TransactionReceiptStatus.unavailable);
  });

  test('keeps a server failure retryable', () async {
    int calls = 0;
    final TransactionReceiptController controller =
        buildTransactionReceiptController(
          tokenStore,
          (_) async {
            calls++;
            return calls == 1
                ? transactionServerErrorResponse(message: 'Receipt service down.')
                : transactionReceiptResponse();
          },
          recorded: recorded,
        );
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.state.status, TransactionReceiptStatus.failed);
    expect(controller.state.errorMessage, 'Something went wrong on the server.');

    await controller.load();
    expect(controller.state.status, TransactionReceiptStatus.ready);
    expect(calls, 2);
  });

  test('ignores a second load while one is already in flight', () async {
    int calls = 0;
    final TransactionReceiptController controller =
        buildTransactionReceiptController(
          tokenStore,
          (_) async {
            calls++;
            return http.Response('{}', 500);
          },
          recorded: recorded,
        );
    addTearDown(controller.dispose);

    await Future.wait(<Future<void>>[controller.load(), controller.load()]);

    expect(calls, 1);
  });
}
