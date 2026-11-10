import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/transactions/state/transaction_scope.dart';
import 'package:agrobenta_mobile/features/transactions/views/transaction_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/auth_fakes.dart';
import '../../support/transaction_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore()..token = 'stored-token';
    recorded = <RecordedRequest>[];
  });

  Future<void> pumpDetail(
    WidgetTester tester, {
    required String role,
    required String status,
  }) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      TransactionScope(
        repository: buildTransactionRepository(
          tokenStore,
          (RecordedRequest request) async {
            if (request.apiPath == '/transactions/1/receipt') {
              return transactionReceiptResponse();
            }
            return transactionDetailResponse(
              transaction: transactionJson(
                id: 1,
                role: role,
                status: status,
                permittedActions: const <String>[],
              ),
            );
          },
          recorded: recorded,
        ),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const TransactionDetailScreen(transactionId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the buyer of a completed transaction can open the receipt', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, role: 'buyer', status: 'completed');

    expect(find.widgetWithText(OutlinedButton, 'View receipt'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'View receipt'));
    await tester.pumpAndSettle();

    expect(find.text('Purchase Receipt'), findsOneWidget);
    expect(find.text('TRX-001'), findsOneWidget);
    expect(recorded.map((RecordedRequest r) => r.apiPath), contains(
      '/transactions/1/receipt',
    ));
  });

  testWidgets('a seller never sees the buyer receipt action', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, role: 'seller', status: 'completed');

    expect(find.widgetWithText(OutlinedButton, 'View receipt'), findsNothing);
  });

  testWidgets('a pending buyer transaction has no receipt action', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, role: 'buyer', status: 'pending');

    expect(find.widgetWithText(OutlinedButton, 'View receipt'), findsNothing);
  });

  testWidgets('a cancelled buyer transaction has no receipt action', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, role: 'buyer', status: 'cancelled');

    expect(find.widgetWithText(OutlinedButton, 'View receipt'), findsNothing);
  });
}
