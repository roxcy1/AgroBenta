import 'package:agrobenta_mobile/features/help_center/view/help_center_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the bundled help center categories and contact status', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HelpCenterScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Help & Support'), findsOneWidget);
    expect(find.text('How can we help you today?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('help-search-field')),
      findsOneWidget,
    );
    expect(find.text('Account & Profile'), findsWidgets);
    expect(find.text('Buying Livestock'), findsWidgets);
    expect(find.text('Selling Livestock'), findsWidgets);
    expect(find.text('Transactions'), findsWidgets);
    expect(find.text('Safety & Security'), findsWidgets);
    expect(
      find.text('Direct support contact is not configured yet.'),
      findsOneWidget,
    );
    expect(find.text('How do I browse livestock?'), findsOneWidget);
  });

  testWidgets('selects a category and expands and collapses an FAQ', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HelpCenterScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Buying Livestock'));
    await tester.pumpAndSettle();

    expect(find.text('How do I contact a seller?'), findsOneWidget);
    expect(find.text('How do I change my password?'), findsNothing);

    final Finder question = find.text('How do I contact a seller?');
    await tester.tap(question);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Asking a question does not create an inquiry'),
      findsOneWidget,
    );

    await tester.tap(question);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Asking a question does not create an inquiry'),
      findsNothing,
    );
  });

  testWidgets('search filters bundled articles and handles no results', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HelpCenterScreen()));
    await tester.pumpAndSettle();

    final Finder search = find.byKey(
      const ValueKey<String>('help-search-field'),
    );
    await tester.enterText(search, 'offer');
    await tester.pump();
    expect(find.text('How do I accept a seller’s offer?'), findsOneWidget);
    expect(find.text('How do I browse livestock?'), findsNothing);

    await tester.enterText(search, 'no such help topic');
    await tester.pump();
    expect(find.text('No help topics found'), findsOneWidget);
    expect(find.text('Try a different search or category.'), findsOneWidget);
  });
}
