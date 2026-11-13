import 'package:agrobenta_mobile/features/terms_and_policies/view/terms_and_policies_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows unavailable legal documents without fabricated text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: TermsAndPoliciesScreen()));

    expect(find.text('Terms & Policies'), findsOneWidget);
    expect(find.text('Official documents'), findsOneWidget);
    expect(
      find.textContaining('Approved legal content is not available yet.'),
      findsOneWidget,
    );
    expect(find.text('Terms and Conditions'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Community Guidelines'), findsNothing);
    expect(find.text('Pending approved content'), findsNWidgets(2));

    final ListTile terms = tester.widget<ListTile>(
      find.byKey(termsAndConditionsAvailabilityKey),
    );
    final ListTile privacy = tester.widget<ListTile>(
      find.byKey(privacyPolicyAvailabilityKey),
    );
    expect(terms.enabled, isFalse);
    expect(terms.onTap, isNull);
    expect(privacy.enabled, isFalse);
    expect(privacy.onTap, isNull);
    expect(tester.takeException(), isNull);
  });
}
