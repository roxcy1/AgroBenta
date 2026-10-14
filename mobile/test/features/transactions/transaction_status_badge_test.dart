import 'package:agrobenta_mobile/core/theme/app_colors.dart';
import 'package:agrobenta_mobile/features/transactions/widgets/transaction_status_badge.dart';
import 'package:agrobenta_mobile/models/transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Pumps one badge and returns its label text.
  Future<Text> badge(WidgetTester tester, TransactionStatus status) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TransactionStatusBadge(status: status)),
      ),
    );
    return tester.widget<Text>(
      find.descendant(
        of: find.byType(TransactionStatusBadge),
        matching: find.byType(Text),
      ),
    );
  }

  Future<Color?> foreground(
    WidgetTester tester,
    TransactionStatus status,
  ) async {
    final Text text = await badge(tester, status);
    return text.style?.color;
  }

  testWidgets('labels the three states as the tabs do', (
    WidgetTester tester,
  ) async {
    expect((await badge(tester, TransactionStatus.pending)).data, 'Ongoing');
    expect((await badge(tester, TransactionStatus.completed)).data, 'Completed');
    expect((await badge(tester, TransactionStatus.cancelled)).data, 'Cancelled');
  });

  testWidgets('uses the distinct DESIGN.md §26 tokens for the three states', (
    WidgetTester tester,
  ) async {
    final Color? pending = await foreground(tester, TransactionStatus.pending);
    final Color? completed = await foreground(
      tester,
      TransactionStatus.completed,
    );
    final Color? cancelled = await foreground(
      tester,
      TransactionStatus.cancelled,
    );

    // §26: Ongoing → green/neutral, Completed → success green, Cancelled →
    // red. The neutral token is chosen for Ongoing so green stays reserved
    // for completed alone and no two states can be confusable at a glance.
    expect(pending, AppColors.textSecondary);
    expect(completed, AppColors.success);
    expect(cancelled, AppColors.error);

    expect(pending, isNot(completed));
    expect(pending, isNot(cancelled));
    expect(completed, isNot(cancelled));
  });

  testWidgets('the badge is a chip, not a bare string', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TransactionStatusBadge(status: TransactionStatus.cancelled),
        ),
      ),
    );

    final Container container = tester.widget<Container>(
      find.descendant(
        of: find.byType(TransactionStatusBadge),
        matching: find.byType(Container),
      ),
    );
    final BoxDecoration decoration =
        container.decoration! as BoxDecoration;
    expect(decoration.color, isNotNull);
    expect(decoration.border, isNotNull);
  });
}
