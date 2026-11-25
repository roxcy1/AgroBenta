import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/terms_and_policies/content/legal_documents.dart';
import 'package:agrobenta_mobile/features/terms_and_policies/content/legal_metadata.dart';
import 'package:agrobenta_mobile/features/terms_and_policies/model/legal_document.dart';
import 'package:agrobenta_mobile/features/terms_and_policies/view/legal_document_screen.dart';
import 'package:agrobenta_mobile/features/terms_and_policies/view/terms_and_policies_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders all eight accessible legal document entries', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const TermsAndPoliciesScreen(),
        ),
      );

      expect(find.text('Terms and Policies'), findsOneWidget);
      expect(
        find.text(
          'Learn about your rights, responsibilities, and how AgroBenta operates.',
        ),
        findsOneWidget,
      );
      expect(find.text('Draft for review'), findsNothing);
      expect(find.text(LegalMetadata.draftNotice), findsNothing);
      expect(LegalMetadata.isDraft, isTrue);
      expect(LegalDocuments.all, hasLength(8));

      for (final LegalDocument document in LegalDocuments.all) {
        final Finder tileFinder = find.byKey(legalDocumentTileKey(document.id));
        expect(tileFinder, findsOneWidget, reason: document.title);
        expect(find.text(document.title), findsOneWidget);
        expect(find.text(document.description), findsOneWidget);

        final Size tileSize = tester.getSize(tileFinder);
        expect(tileSize.height, greaterThanOrEqualTo(48));
        expect(tester.getSemantics(tileFinder).label, contains(document.title));
      }

      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('every policy entry opens its complete document and returns', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const TermsAndPoliciesScreen(),
      ),
    );

    for (final LegalDocument document in LegalDocuments.all) {
      await tester.ensureVisible(find.byKey(legalDocumentTileKey(document.id)));
      await tester.tap(find.byKey(legalDocumentTileKey(document.id)));
      await tester.pumpAndSettle();

      expect(find.byType(LegalDocumentScreen), findsOneWidget);
      expect(find.text(document.title), findsNWidgets(2));
      expect(find.text(document.introduction), findsOneWidget);
      expect(find.text('Draft for review'), findsNothing);
      expect(find.text(LegalMetadata.draftNotice), findsNothing);

      for (final LegalSection section in document.sections) {
        expect(find.textContaining(section.heading), findsOneWidget);
        for (final String paragraph in section.paragraphs) {
          expect(find.text(paragraph), findsOneWidget);
        }
        for (final String bullet in section.bullets) {
          expect(find.text(bullet), findsOneWidget);
        }
      }

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(TermsAndPoliciesScreen), findsOneWidget);
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('long documents scroll to their final sections', (
    WidgetTester tester,
  ) async {
    final LegalDocument document =
        LegalDocuments.transactionAndCancellationPolicy;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: LegalDocumentScreen(document: document),
      ),
    );

    final Finder finalHeading = find.textContaining('Disputes, remedies');
    expect(finalHeading, findsOneWidget);
    await tester.ensureVisible(finalHeading);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(finalHeading).dy, lessThan(600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Privacy Policy explains optional local receipt gallery export', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: LegalDocumentScreen(document: LegalDocuments.privacyPolicy),
      ),
    );

    expect(
      find.textContaining('a buyer may choose Save to Gallery'),
      findsOneWidget,
    );
    expect(
      find.textContaining('saves a PNG copy in the device photo library'),
      findsOneWidget,
    );
    expect(
      find.textContaining('does not upload the image to the AgroBenta backend'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Take care when storing or sharing'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu and reader remain usable on a small screen at large text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(1.8),
          ),
          child: const TermsAndPoliciesScreen(),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(legalDocumentTileKey(LegalDocuments.privacyPolicy.id)),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(legalDocumentTileKey(LegalDocuments.privacyPolicy.id)),
    );
    await tester.pumpAndSettle();

    final Finder lastSection = find.textContaining(
      'Children and policy changes',
    );
    await tester.ensureVisible(lastSection);
    await tester.pumpAndSettle();
    expect(lastSection, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
