import 'dart:typed_data';

import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/core/utils/app_formatters.dart';
import 'package:agrobenta_mobile/features/receipts/services/receipt_gallery_saver.dart';
import 'package:agrobenta_mobile/features/receipts/services/receipt_png_exporter.dart';
import 'package:agrobenta_mobile/features/receipts/view/transaction_receipt_screen.dart';
import 'package:agrobenta_mobile/features/transactions/state/transaction_scope.dart';
import 'package:flutter/material.dart';
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

  Future<void> pumpReceipt(
    WidgetTester tester,
    Future<http.Response> Function(RecordedRequest request) handler, {
    int transactionId = 1,
    ReceiptGallerySaver? gallerySaver,
    ReceiptPngExporter? pngExporter,
  }) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      TransactionScope(
        repository: buildTransactionRepository(
          tokenStore,
          handler,
          recorded: recorded,
        ),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: TransactionReceiptScreen(
            transactionId: transactionId,
            gallerySaver: gallerySaver ?? FakeReceiptGallerySaver(),
            pngExporter: pngExporter ?? FakeReceiptPngExporter(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Save to Gallery'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders every receipt field from the server snapshot', (
    WidgetTester tester,
  ) async {
    await pumpReceipt(
      tester,
      (_) async => transactionReceiptResponse(
        receipt: transactionReceiptJson(
          reference: 'TRX-012',
          buyerName: 'Pedro Reyes',
          sellerName: 'Juan Dela Cruz',
          livestockType: 'goat',
          breed: 'Boer',
          quantity: 3,
          totalAmount: '36000.50',
          paymentMethod: 'maya',
          collectionMethod: 'seller_arranged_delivery',
        ),
      ),
    );

    expect(recorded.single.apiPath, '/transactions/1/receipt');
    expect(find.text('Purchase Receipt'), findsOneWidget);
    expect(find.text('TRX-012'), findsOneWidget);
    expect(find.text('Pedro Reyes'), findsOneWidget);
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.text('goat'), findsOneWidget);
    expect(find.text('Boer'), findsOneWidget);
    expect(find.text('3 heads'), findsOneWidget);
    expect(
      find.text(AppFormatters.formatMoney('36000.50')!),
      findsOneWidget,
    );
    expect(find.text('Seller-Arranged Delivery'), findsOneWidget);
    expect(find.text('Maya'), findsOneWidget);
    expect(find.text('Not verified by AgroBenta.'), findsOneWidget);
    expect(find.textContaining('not proof of payment'), findsOneWidget);
    expect(find.textContaining('Official Receipt'), findsNothing);
  });

  testWidgets('renders null/legacy methods honestly', (
    WidgetTester tester,
  ) async {
    await pumpReceipt(
      tester,
      (_) async => transactionReceiptResponse(
        receipt: transactionReceiptJson(
          collectionMethod: null,
          paymentMethod: null,
          breed: '',
        ),
      ),
    );

    expect(find.text('Not specified'), findsOneWidget);
    expect(find.text('Not recorded'), findsOneWidget);
    expect(find.text('cattle'), findsOneWidget);
    expect(find.text('Breed'), findsNothing);
  });

  testWidgets('a 409 shows the unavailable state, not a broken receipt', (
    WidgetTester tester,
  ) async {
    await pumpReceipt(
      tester,
      (_) async => transactionConflictResponse(
        message: 'Only a completed transaction has a receipt.',
      ),
    );

    expect(find.text('This receipt is not available'), findsOneWidget);
    expect(find.text('TRX-001'), findsNothing);
  });

  testWidgets('a failure is retryable', (WidgetTester tester) async {
    int calls = 0;
    await pumpReceipt(tester, (_) async {
      calls++;
      return calls == 1
          ? transactionServerErrorResponse(message: 'Receipt service down.')
          : transactionReceiptResponse();
    });

    expect(find.text('Could not load receipt'), findsOneWidget);
    expect(find.text('Something went wrong on the server.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    await tester.pumpAndSettle();

    expect(find.text('TRX-001'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('saving is manual and sends a high-resolution PNG', (
    WidgetTester tester,
  ) async {
    final FakeReceiptGallerySaver saver = FakeReceiptGallerySaver();
    await pumpReceipt(
      tester,
      (_) async => transactionReceiptResponse(
        receipt: transactionReceiptJson(reference: 'TRX-007'),
      ),
      gallerySaver: saver,
    );

    expect(saver.calls, 0, reason: 'opening never saves automatically');

    await tapSave(tester);

    expect(saver.calls, 1);
    expect(saver.bytes, isNotNull);
    expect(saver.bytes!, isNotEmpty);
    expect(saver.name, 'agrobenta-receipt-TRX-007');
    expect(
      saver.bytes!.take(8).toList(),
      <int>[137, 80, 78, 71, 13, 10, 26, 10],
      reason: 'the bytes must be a PNG',
    );
    expect(find.text('Receipt saved to your gallery.'), findsOneWidget);
    expect(find.text('TRX-007'), findsOneWidget);
  });

  testWidgets('a denied gallery permission keeps the receipt on screen', (
    WidgetTester tester,
  ) async {
    final FakeReceiptGallerySaver saver = FakeReceiptGallerySaver();
    await pumpReceipt(
      tester,
      (_) async => transactionReceiptResponse(),
      gallerySaver: saver,
    );

    saver.error = const ReceiptGalleryException(
      ReceiptGalleryError.accessDenied,
    );

    await tapSave(tester);

    expect(
      find.textContaining('Photo library access was denied'),
      findsOneWidget,
    );
    expect(find.text('TRX-001'), findsOneWidget);
    expect(saver.calls, 1);
  });
}

class FakeReceiptGallerySaver implements ReceiptGallerySaver {
  int calls = 0;
  Uint8List? bytes;
  String? name;
  Object? error;

  @override
  Future<void> save(Uint8List pngBytes, {required String name}) async {
    calls++;
    bytes = pngBytes;
    this.name = name;
    final Object? failure = error;
    if (failure != null) {
      throw failure;
    }
  }
}

class FakeReceiptPngExporter implements ReceiptPngExporter {
  int calls = 0;

  static final Uint8List pngBytes = Uint8List.fromList(
    <int>[137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0],
  );

  @override
  Future<Uint8List> capture(GlobalKey boundaryKey) async {
    calls++;
    return pngBytes;
  }
}
