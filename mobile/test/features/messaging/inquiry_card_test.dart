import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/messaging/widgets/message_bubble.dart';
import 'package:agrobenta_mobile/models/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/messaging_fakes.dart';

void main() {
  Future<void> pumpBubble(
    WidgetTester tester, {
    required Map<String, dynamic> message,
    bool isMine = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: MessageBubble(
            message: Message.fromJson(message),
            isMine: isMine,
            isPlaceholder: false,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the inquiry opener renders as a structured card, not prose', (
    WidgetTester tester,
  ) async {
    await pumpBubble(
      tester,
      message: messageJson(
        inquiry: inquiryCardJson(
          title: 'Holstein Heifer',
          askingPrice: '50000.00',
          paymentMethod: 'gcash',
          collectionMethod: 'farm_pickup',
          preferredSchedule: '2026-11-10',
          message: 'Still available? I can pick it up.',
        ),
      ),
    );

    expect(find.text('Inquiry'), findsOneWidget);
    expect(find.text('Holstein Heifer'), findsOneWidget);
    expect(find.textContaining('50,000'), findsOneWidget);
    expect(find.text('Preferred date'), findsOneWidget);
    expect(find.text('Still available? I can pick it up.'), findsOneWidget);

    // Human labels, never raw enum values.
    expect(find.text('GCash'), findsOneWidget);
    expect(find.text('Pick up from the seller\'s farm'), findsOneWidget);
    expect(find.text('gcash'), findsNothing);
    expect(find.text('farm_pickup'), findsNothing);
  });

  testWidgets('a missing listing photo falls back to the livestock glyph', (
    WidgetTester tester,
  ) async {
    await pumpBubble(
      tester,
      message: messageJson(inquiry: inquiryCardJson(photoUrl: null)),
    );

    expect(find.byIcon(Icons.pets_outlined), findsOneWidget);
  });

  testWidgets('a normal message stays a plain bubble', (
    WidgetTester tester,
  ) async {
    await pumpBubble(tester, message: messageJson(body: 'Yes, still available.'));

    expect(find.text('Yes, still available.'), findsOneWidget);
    expect(find.text('Inquiry'), findsNothing);
  });
}
