import 'dart:async';
import 'dart:convert';

import 'package:agrobenta_mobile/core/constants/api_constants.dart';
import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/inquiries/state/inquiry_scope.dart';
import 'package:agrobenta_mobile/features/inquiries/view/inquire_screen.dart';
import 'package:agrobenta_mobile/features/inquiries/view/inquiry_already_sent_view.dart';
import 'package:agrobenta_mobile/features/inquiries/view/inquiry_validators.dart';
import 'package:agrobenta_mobile/features/messaging/state/conversations_controller.dart';
import 'package:agrobenta_mobile/features/messaging/state/messaging_scope.dart';
import 'package:agrobenta_mobile/features/messaging/view/chat_screen.dart';
import 'package:agrobenta_mobile/models/inquiry.dart';
import 'package:agrobenta_mobile/models/listing.dart';
import 'package:agrobenta_mobile/repositories/inquiry_repository.dart';
import 'package:agrobenta_mobile/repositories/messaging_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/inquiry_fakes.dart';
import '../../support/marketplace_fakes.dart';
import '../../support/messaging_fakes.dart';

/// The Inquiry Sent screen's heading. Every success assertion keys on this;
/// the failure assertions use it as the "not shown" probe.
const String successHeading = 'Your inquiry has been sent to the seller.';

/// The four approved starter messages, copied verbatim from the design spec.
/// A template that drifts from this copy fails here rather than in review.
const String checkAvailabilityTemplate =
    'Hello! Is this livestock still available?';
const String discussPriceTemplate =
    "Hello! I'm interested in this livestock. Is the price negotiable?";
const String visitFarmTemplate =
    'Hello! Can I visit your farm to inspect this livestock?';
const String paymentPickupTemplate =
    "Hello! I'm interested in this livestock. Can we discuss payment and "
    'collection arrangements?';

const Map<String, String> approvedTemplates = <String, String>{
  'Check availability': checkAvailabilityTemplate,
  'Discuss the price': discussPriceTemplate,
  'Visit the farm': visitFarmTemplate,
  'Payment and pickup': paymentPickupTemplate,
};

/// The exact approved copy of the already-sent state. A drift from this fails
/// here rather than in review.
const String alreadySentCopy =
    "You've already sent an inquiry about this livestock. You can continue "
    'the conversation in Messages.';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('1|mobile-token');
    recorded = <RecordedRequest>[];
  });

  Future<void> settle(WidgetTester tester, {int frames = 12}) async {
    for (int frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Listing testListing() => Listing.fromJson(listingJson());

  /// Pumps the screen exactly as the app opens it: pushed on top of a stand-in
  /// entry route, with the scopes the screen and its destinations read above
  /// `MaterialApp`. The transport answers `POST /inquiries` through the same
  /// [ApiClient] chain production uses.
  ///
  /// `GET /inquiries/listing/{id}` is routed to [checkHandler] — default: the
  /// buyer has sent none — so a test's [handler] only ever answers the writes
  /// and reads it means to describe. Messaging and auth are wired because the
  /// confirmation's "Go to Messages" pushes the real inbox.
  Future<void> pushInquire(
    WidgetTester tester, {
    required Future<http.Response> Function(RecordedRequest request) handler,
    Future<http.Response> Function(RecordedRequest request)? checkHandler,
    Future<http.Response> Function(RecordedRequest request)? messagingHandler,
  }) async {
    Future<http.Response> routed(RecordedRequest request) {
      if (request.method == 'GET' &&
          request.apiPath.startsWith('/inquiries/listing/')) {
        return (checkHandler ?? (_) async => inquiryCheckResponse())(request);
      }
      return handler(request);
    }

    final InquiryRepository repository = buildInquiryRepository(
      tokenStore,
      routed,
      recorded: recorded,
    );

    final MessagingRepository messagingRepository = buildMessagingRepository(
      tokenStore,
      messagingHandler ?? (_) async => conversationsResponse(),
    );
    final ConversationsController conversationsController =
        ConversationsController(messagingRepository);
    addTearDown(conversationsController.dispose);

    final AuthController authController = AuthController(
      buildAuthRepository(
        tokenStore,
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: userJson(id: 7))),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(authController.dispose);
    await authController.restoreSession();

    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      InquiryScope(
        repository: repository,
        child: MessagingScope(
          repository: messagingRepository,
          conversationsController: conversationsController,
          child: AuthScope(
            controller: authController,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: Scaffold(
                appBar: AppBar(title: const Text('Listing detail stand-in')),
              ),
            ),
          ),
        ),
      ),
    );

    final NavigatorState navigator = tester.state<NavigatorState>(
      find.byType(Navigator),
    );
    navigator.push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            InquireScreen(listing: testListing()),
      ),
    );
    await settle(tester);
  }

  Finder messageField() => find.widgetWithText(TextFormField, 'Message *');

  TextEditingController messageController(WidgetTester tester) =>
      tester.widget<TextFormField>(messageField()).controller!;

  Future<void> typeMessage(WidgetTester tester, String text) async {
    await tester.ensureVisible(messageField());
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(messageField(), text);
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> tapTemplate(WidgetTester tester, String label) async {
    final Finder template = find.widgetWithText(OutlinedButton, label);
    await tester.ensureVisible(template);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(template);
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Taps a preference card by its visible title. The whole card is the tap
  /// target, so tapping the title exercises the same InkWell a buyer does.
  Future<void> chooseOption(WidgetTester tester, String label) async {
    final Finder option = find.text(label);
    await tester.ensureVisible(option);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(option);
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> submit(WidgetTester tester) async {
    final Finder send = find.widgetWithText(FilledButton, 'Send Inquiry');
    await tester.ensureVisible(send);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(send);
    await settle(tester);
  }

  /// Chooses both required preferences with the first option in each section,
  /// plus a collection-date option (now required to submit).
  Future<void> chooseRequiredPreferences(WidgetTester tester) async {
    await chooseOption(tester, 'Cash');
    await chooseOption(tester, 'Farm Pickup');
    await chooseOption(tester, 'Next few days');
  }

  List<RecordedRequest> posts() => recorded
      .where((RecordedRequest r) => r.method == 'POST')
      .toList(growable: false);

  group('validateInquiryMessage', () {
    test('requires a message', () {
      expect(
        validateInquiryMessage(null),
        'Please enter a message for the seller.',
      );
      expect(
        validateInquiryMessage(''),
        'Please enter a message for the seller.',
      );
    });

    test('refuses whitespace-only text', () {
      expect(validateInquiryMessage('   '), 'A message cannot be only spaces.');
      expect(
        validateInquiryMessage(' \n\t '),
        'A message cannot be only spaces.',
      );
    });

    test('accepts exactly the 500-character ceiling', () {
      expect(validateInquiryMessage('a' * kInquiryMessageMax), isNull);
    });

    test('refuses anything over the 500-character ceiling', () {
      expect(
        validateInquiryMessage('a' * (kInquiryMessageMax + 1)),
        'A message may be at most $kInquiryMessageMax characters.',
      );
    });
  });

  group('validateInquiryPreferences', () {
    test('requires a payment method', () {
      expect(
        validateInquiryPaymentMethod(null),
        'Please choose a preferred payment method.',
      );
      expect(validateInquiryPaymentMethod(InquiryPaymentMethod.cash), isNull);
    });

    test('requires a collection method', () {
      expect(
        validateInquiryCollectionMethod(null),
        'Please choose a preferred collection method.',
      );
      expect(
        validateInquiryCollectionMethod(InquiryCollectionMethod.farmPickup),
        isNull,
      );
    });
  });

  group('renders', () {
    testWidgets('the real listing summary and nothing invented', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());

      expect(find.text('Inquire About Livestock'), findsOneWidget);
      expect(find.text('CATTLE'), findsOneWidget);
      expect(find.text('Holstein'), findsOneWidget);
      expect(find.text('₱42,500.00'), findsOneWidget);
      expect(
        find.text('Rizal Farms'),
        findsOneWidget,
        reason: 'the seller name comes from the listing model',
      );
      expect(
        find.text('18 months · 320.5 kg · Female'),
        findsOneWidget,
        reason: 'the attributes come from the API, capitalised like detail',
      );
      expect(find.text('Mabalacat, Pampanga'), findsOneWidget);
      // No photo supplied by the fixture — the shared placeholder, not a
      // synthesised image.
      expect(find.text('No photo'), findsOneWidget);
    });

    testWidgets('the approved sections and controls', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());

      // Additional Message: a visible field, the live counter and the four
      // templates the design spec names.
      expect(find.text('Additional Message'), findsOneWidget);
      expect(find.text('Message *'), findsOneWidget);
      expect(find.text('Type your inquiry here...'), findsOneWidget);
      expect(
        find.text(
          'Ask about availability, additional photos, or the asking price.',
        ),
        findsOneWidget,
      );
      expect(find.text('0/500'), findsOneWidget);
      expect(find.text('Message templates'), findsOneWidget);
      for (final String label in approvedTemplates.keys) {
        expect(
          find.widgetWithText(OutlinedButton, label),
          findsOneWidget,
          reason: 'the "$label" template is offered',
        );
      }

      // Payment preferences.
      expect(find.text('Preferred Payment Method *'), findsOneWidget);
      expect(
        find.text('How would you prefer to pay the seller?'),
        findsOneWidget,
      );
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('GCash'), findsOneWidget);
      expect(find.text('Maya'), findsOneWidget);
      expect(find.text('Other / Discuss with seller'), findsOneWidget);

      // Collection preferences.
      expect(find.text('Preferred Livestock Collection *'), findsOneWidget);
      expect(
        find.text('How do you plan to receive the livestock?'),
        findsOneWidget,
      );
      expect(find.text('Farm Pickup'), findsOneWidget);
      expect(find.text('Arrange Transport'), findsOneWidget);
      expect(find.text('Discuss'), findsOneWidget);

      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Send Inquiry'), findsOneWidget);
      expect(
        find.text('The seller will reply through AgroBenta messages.'),
        findsOneWidget,
      );
    });

    testWidgets('the obsolete fields are gone', (WidgetTester tester) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());

      for (final String obsolete in <String>[
        'Subject',
        'General Inquiry',
        'Are you interested in purchasing? *',
        'Transaction Method (Preferred)',
        'Direct Deal',
        'Arrange Delivery',
        'Delivery Details',
        'Delivery Method',
        'Delivery Fee (₱)',
        'Preferred Contact Method',
        'In-app Message',
        'Preferred Schedule (Optional)',
        'No date chosen',
        'Your Inquiry',
      ]) {
        expect(
          find.text(obsolete),
          findsNothing,
          reason: '"$obsolete" is not part of the approved screen',
        );
      }
    });

    testWidgets('collects nothing the API cannot store', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());

      // The server-owned fields are not rendered as questions anywhere: there
      // is no buyer/seller identity to fill in and no status to choose.
      expect(find.textContaining('Buyer ID'), findsNothing);
      expect(find.textContaining('Seller ID'), findsNothing);
      expect(find.text('Status'), findsNothing);
      // The only contact method that exists is in-app messaging; no phone or
      // address field may collect what the API would refuse to store safely.
      expect(find.text('Phone Number'), findsNothing);
      expect(find.textContaining('Address'), findsNothing);
    });
  });

  group('existing inquiry pre-check', () {
    testWidgets('checks before offering the form and sends nothing', (
      WidgetTester tester,
    ) async {
      final Completer<http.Response> gate = Completer<http.Response>();
      await pushInquire(
        tester,
        handler: (_) async => inquiryCreatedResponse(),
        checkHandler: (_) => gate.future,
      );

      // The first frame is the check. The form is not offered, because the
      // buyer must not start typing an inquiry they cannot submit.
      expect(find.text('Checking your inquiries...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Send Inquiry'), findsNothing);
      expect(find.text('Inquire About Livestock'), findsOneWidget);
      expect(posts(), isEmpty);

      gate.complete(inquiryCheckResponse());
      await settle(tester);

      expect(find.text('Checking your inquiries...'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Send Inquiry'), findsOneWidget);
      expect(posts(), isEmpty);
    });

    testWidgets('shows Inquiry Already Sent instead of a second form', (
      WidgetTester tester,
    ) async {
      await pushInquire(
        tester,
        handler: (_) async => inquiryCreatedResponse(),
        checkHandler: (_) async => inquiryCheckResponse(
          inquiry: inquiryJson(id: 21, message: 'Already asked.'),
        ),
      );

      // The app bar title and the view heading both name the state.
      expect(find.text('Inquiry Already Sent'), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byType(InquiryAlreadySentView),
          matching: find.text('Inquiry Already Sent'),
        ),
        findsOneWidget,
      );
      expect(find.text(alreadySentCopy), findsOneWidget);
      expect(
        find.text(
          'You\'ve already sent an inquiry about this livestock. '
          'You can continue the conversation in Messages.',
        ),
        findsOneWidget,
      );

      // No second form, and no send.
      expect(find.text('Inquire About Livestock'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Send Inquiry'), findsNothing);
      expect(find.text('Message *'), findsNothing);
      expect(posts(), isEmpty);

      // The real listing is still named, and both actions are offered.
      expect(find.text('CATTLE'), findsOneWidget);
      expect(find.text('Holstein'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Go to Messages'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Back to Browse'),
        findsOneWidget,
      );
    });

    testWidgets('Go to Messages opens the exact chat from the already-sent state', (
      WidgetTester tester,
    ) async {
      await pushInquire(
        tester,
        handler: (_) async => inquiryCreatedResponse(),
        checkHandler: (_) async =>
            inquiryCheckResponse(inquiry: inquiryJson(id: 21)),
      );

      final Finder goToMessages = find.widgetWithText(
        FilledButton,
        'Go to Messages',
      );
      await tester.ensureVisible(goToMessages);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(goToMessages);
      await settle(tester);

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('Rizal Farms'), findsOneWidget);
      // MS-04: Go to Messages opens the exact buyer–seller conversation.
      // Opening the chat creates no inquiry and sends no message.
      expect(posts(), isEmpty);
    });

    testWidgets('Back to Browse leaves the already-sent state', (
      WidgetTester tester,
    ) async {
      await pushInquire(
        tester,
        handler: (_) async => inquiryCreatedResponse(),
        checkHandler: (_) async =>
            inquiryCheckResponse(inquiry: inquiryJson(id: 21)),
      );

      final Finder backToBrowse = find.widgetWithText(
        OutlinedButton,
        'Back to Browse',
      );
      await tester.ensureVisible(backToBrowse);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(backToBrowse);
      await settle(tester);

      expect(find.byType(InquireScreen), findsNothing);
      expect(find.text('Listing detail stand-in'), findsOneWidget);
      expect(posts(), isEmpty);
    });

    testWidgets('a failed check still renders a usable form with a notice', (
      WidgetTester tester,
    ) async {
      await pushInquire(
        tester,
        handler: (_) async => inquiryCreatedResponse(
          inquiry: inquiryJson(
            message: 'Sent after a failed check',
            paymentMethod: 'cash',
            collectionMethod: 'farm_pickup',
          ),
        ),
        checkHandler: (_) async =>
            throw http.ClientException('connection refused'),
      );

      // The backend's duplicate guard is authoritative, so a check failure
      // must not make the screen unusable — it explains itself and shows the
      // form.
      expect(find.textContaining('Could not reach the server'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Send Inquiry'), findsOneWidget);

      await typeMessage(tester, 'Sent after a failed check');
      await chooseOption(tester, 'Cash');
      await chooseOption(tester, 'Farm Pickup');
      await chooseOption(tester, 'Next few days');
      await submit(tester);

      expect(posts(), hasLength(1));
      expect(find.text(successHeading), findsOneWidget);
    });
  });

  group('message templates', () {
    testWidgets('each template writes its exact approved message', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());

      for (final MapEntry<String, String> template
          in approvedTemplates.entries) {
        await tapTemplate(tester, template.key);
        expect(
          messageController(tester).text,
          template.value,
          reason: '"${template.key}" writes the approved copy',
        );
        expect(
          find.text('${template.value.length}/500'),
          findsOneWidget,
          reason: 'the counter follows the template text',
        );
      }

      // Filling the field is not sending it.
      expect(posts(), isEmpty);
      expect(find.text(successHeading), findsNothing);
    });

    testWidgets('a template replaces the field instead of appending', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());

      await typeMessage(tester, 'My own words');
      await tapTemplate(tester, 'Check availability');

      expect(messageController(tester).text, checkAvailabilityTemplate);
      expect(
        messageController(tester).text,
        isNot(contains('My own words')),
        reason: 'selecting a template replaces, never appends',
      );
      expect(posts(), isEmpty);
    });

    testWidgets('the template text stays editable', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());

      await tapTemplate(tester, 'Visit the farm');
      await typeMessage(tester, 'Actually, can I visit on Saturday?');

      expect(
        messageController(tester).text,
        'Actually, can I visit on Saturday?',
      );
      expect(find.text('34/500'), findsOneWidget);
    });
  });

  group('client validation', () {
    testWidgets('refuses an empty message and sends nothing', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());
      await submit(tester);

      expect(
        find.text('Please enter a message for the seller.'),
        findsOneWidget,
      );
      expect(posts(), isEmpty);
      expect(find.byType(InquireScreen), findsOneWidget);
    });

    testWidgets('refuses a message of only spaces', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());
      await typeMessage(tester, '     ');
      await submit(tester);

      expect(find.text('A message cannot be only spaces.'), findsOneWidget);
      expect(posts(), isEmpty);
    });

    testWidgets('refuses a submission with no preferences chosen', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());
      await typeMessage(tester, 'A complete message');
      await submit(tester);

      // Both missing answers are reported at once, beside their sections.
      expect(
        find.text('Please choose a preferred payment method.'),
        findsOneWidget,
      );
      expect(
        find.text('Please choose a preferred collection method.'),
        findsOneWidget,
      );
      expect(posts(), isEmpty);
      expect(find.text(successHeading), findsNothing);
    });

    testWidgets('choosing a preference clears its own error', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());
      await typeMessage(tester, 'A complete message');
      await submit(tester);

      await chooseOption(tester, 'Cash');
      expect(
        find.text('Please choose a preferred payment method.'),
        findsNothing,
      );
      expect(
        find.text('Please choose a preferred collection method.'),
        findsOneWidget,
        reason: 'the collection answer is still missing',
      );

      await chooseOption(tester, 'Farm Pickup');
      expect(
        find.text('Please choose a preferred collection method.'),
        findsNothing,
      );
      expect(posts(), isEmpty, reason: 'choosing alone never submits');
    });

    testWidgets('a template clears a stale required-message error', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());
      await submit(tester);
      expect(
        find.text('Please enter a message for the seller.'),
        findsOneWidget,
      );

      await tapTemplate(tester, 'Check availability');
      // The field's error text fades out; let the decoration animation finish
      // before asserting the stale message is gone.
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        messageController(tester).text,
        checkAvailabilityTemplate,
        reason: 'the template wrote its text into the field',
      );
      expect(
        find.text('Please enter a message for the seller.'),
        findsNothing,
        reason: 'the template supplied the missing text',
      );
      expect(posts(), isEmpty);
    });

    testWidgets('tracks the message length against the 500 ceiling', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());
      await typeMessage(tester, '12345');

      expect(find.text('5/500'), findsOneWidget);
    });

    testWidgets('the field stops at the 500-character ceiling', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());
      await typeMessage(tester, 'a' * (kInquiryMessageMax + 50));

      expect(messageController(tester).text.length, kInquiryMessageMax);
      expect(find.text('500/500'), findsOneWidget);
    });
  });

  group('submission', () {
    testWidgets('sends the inquiry and returns to Browse on Back to Browse', (
      WidgetTester tester,
    ) async {
      await pushInquire(
        tester,
        handler: (_) async => inquiryCreatedResponse(
          inquiry: inquiryJson(
            message: 'Is this one still available?',
            paymentMethod: 'cash',
            collectionMethod: 'farm_pickup',
          ),
        ),
      );
      await typeMessage(tester, 'Is this one still available?');
      await chooseOption(tester, 'Cash');
      await chooseOption(tester, 'Farm Pickup');
      await chooseOption(tester, 'Next few days');
      await submit(tester);

      // Success is the server's answer: the confirmation view, by response.
      expect(find.text(successHeading), findsOneWidget);
      expect(find.text('Inquiry Sent'), findsOneWidget);
      expect(find.byType(InquireScreen), findsOneWidget);

      expect(posts(), hasLength(1));
      final RecordedRequest post = posts().single;
      expect(post.apiPath, InquiryEndpoints.create);
      expect(post.body, <String, dynamic>{
        'listing_id': 12,
        'message': 'Is this one still available?',
        'collection_date_option': 'next_few_days',
        'payment_method': 'cash',
        'collection_method': 'farm_pickup',
      }, reason: 'exactly the collected fields, in their API spellings');
      expect(
        post.body.keys.toSet().difference(
          InquiryEndpoints.writableFields.toSet(),
        ),
        isEmpty,
        reason: 'not one key outside the allow-list went out',
      );

      // Back to Browse pops the whole stack to the shell stand-in below
      // the listing detail entry route.
      final Finder backToBrowse = find.widgetWithText(
        OutlinedButton,
        'Back to Browse',
      );
      await tester.ensureVisible(backToBrowse);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(backToBrowse);
      await settle(tester);

      expect(find.byType(InquireScreen), findsNothing);
      expect(find.text('Listing detail stand-in'), findsOneWidget);
      // Leaving never triggers a second submission.
      expect(posts(), hasLength(1));
    });

    testWidgets('sends the chosen payment and collection preferences', (
      WidgetTester tester,
    ) async {
      await pushInquire(
        tester,
        handler: (_) async => inquiryCreatedResponse(
          inquiry: inquiryJson(
            message: 'Can we discuss arrangements?',
            paymentMethod: 'gcash',
            collectionMethod: 'buyer_arranged_transportation',
          ),
        ),
      );
      await typeMessage(tester, 'Can we discuss arrangements?');
      await chooseOption(tester, 'GCash');
      await chooseOption(tester, 'Arrange Transport');
      await chooseOption(tester, 'Next few days');
      await submit(tester);

      final RecordedRequest post = posts().single;
      expect(post.body, <String, dynamic>{
        'listing_id': 12,
        'message': 'Can we discuss arrangements?',
        'collection_date_option': 'next_few_days',
        'payment_method': 'gcash',
        'collection_method': 'buyer_arranged_transportation',
      }, reason: 'exactly the collected values, in their API spellings');
      expect(
        post.body.keys.toSet().difference(
          InquiryEndpoints.writableFields.toSet(),
        ),
        isEmpty,
        reason: 'not one key outside the allow-list went out',
      );
      expect(find.text(successHeading), findsOneWidget);
    });

    testWidgets('shows a spinner and keeps the form while in flight', (
      WidgetTester tester,
    ) async {
      // The POST is held open on purpose: with an immediate answer the state
      // would cycle through `submitting` inside one frame and the assertion
      // would pass for the wrong reason.
      final Completer<http.Response> gate = Completer<http.Response>();
      await pushInquire(
        tester,
        handler: (RecordedRequest request) async =>
            request.method == 'POST' ? gate.future : inquiryCreatedResponse(),
      );
      await typeMessage(tester, 'Kept while the request is in flight');
      await chooseRequiredPreferences(tester);

      final Finder send = find.widgetWithText(FilledButton, 'Send Inquiry');
      await tester.ensureVisible(send);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(send);
      await tester.pump(const Duration(milliseconds: 10));

      final FilledButton button = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(button.onPressed, isNull, reason: 'disabled while submitting');
      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      // The form is still on screen with everything typed — a submission does
      // not replace the form with a spinner.
      expect(find.text('Kept while the request is in flight'), findsOneWidget);
      expect(find.text(successHeading), findsNothing);

      gate.complete(inquiryCreatedResponse());
      await settle(tester, frames: 20);
      expect(find.text(successHeading), findsOneWidget);
    });

    testWidgets('refuses a second request while one is in flight', (
      WidgetTester tester,
    ) async {
      final Completer<http.Response> gate = Completer<http.Response>();
      await pushInquire(
        tester,
        handler: (RecordedRequest request) async =>
            request.method == 'POST' ? gate.future : inquiryCreatedResponse(),
      );
      await typeMessage(tester, 'Only once, please');
      await chooseRequiredPreferences(tester);

      final Finder send = find.widgetWithText(FilledButton, 'Send Inquiry');
      await tester.ensureVisible(send);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(send);
      await tester.pump(const Duration(milliseconds: 10));

      // The button is now a spinner over a null onPressed; tapping the type
      // again exercises the controller's own in-flight guard as well.
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 10));

      gate.complete(inquiryCreatedResponse());
      await settle(tester, frames: 20);

      expect(posts(), hasLength(1), reason: 'exactly one request went out');
      expect(find.text(successHeading), findsOneWidget);
    });

    testWidgets('shows a 422 beside the field it belongs to', (
      WidgetTester tester,
    ) async {
      await pushInquire(
        tester,
        handler: (RecordedRequest request) async => request.method == 'POST'
            ? inquiryValidationResponse(
                errors: <String, Object>{
                  'message': <String>[
                    'The message must not be greater than 500 characters.',
                  ],
                },
              )
            : inquiryCreatedResponse(),
      );
      await typeMessage(tester, 'A message the server will not accept');
      await chooseRequiredPreferences(tester);
      await submit(tester);

      // Back on the form, with the server's message on the message field.
      expect(find.byType(InquireScreen), findsOneWidget);
      expect(
        find.text('The message must not be greater than 500 characters.'),
        findsOneWidget,
      );
      expect(
        find.text('A message the server will not accept'),
        findsOneWidget,
        reason: 'a rejected submission keeps what was typed',
      );
      expect(find.text(successHeading), findsNothing);
    });

    testWidgets('keeps the typed message when the send fails', (
      WidgetTester tester,
    ) async {
      await pushInquire(
        tester,
        handler: (RecordedRequest request) async => request.method == 'POST'
            ? inquiryServerErrorResponse(message: 'Server error.')
            : inquiryCreatedResponse(),
      );
      await typeMessage(tester, 'Typed before the failure');
      await chooseRequiredPreferences(tester);
      await submit(tester);

      expect(find.text('Server error.'), findsOneWidget);
      expect(
        find.text('Typed before the failure'),
        findsOneWidget,
        reason: 'a failed send must never cost the buyer their message',
      );
      expect(find.text(successHeading), findsNothing);

      // The retry button still works: the form is not locked by a failure.
      // (The hint text itself stays mounted at opacity 0 in this Flutter
      // version — `maintainHintSize` defaults to true — so retention is
      // asserted above, through the editable text, not through the hint.)
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Send Inquiry'),
            )
            .onPressed,
        isNotNull,
      );
      await submit(tester);
      expect(posts(), hasLength(2));
    });

    testWidgets('shows a 409 as information without blaming the input', (
      WidgetTester tester,
    ) async {
      await pushInquire(
        tester,
        handler: (RecordedRequest request) async => request.method == 'POST'
            ? inquiryConflictResponse(
                message: 'This listing is not open to inquiries.',
              )
            : inquiryCreatedResponse(),
      );
      await typeMessage(tester, 'Perfectly reasonable');
      await chooseRequiredPreferences(tester);
      await submit(tester);

      expect(
        find.text('This listing is not open to inquiries.'),
        findsOneWidget,
      );
      // No field is marked wrong — nothing about the input caused this.
      expect(find.text('Please enter a message for the seller.'), findsNothing);
      expect(find.text('Perfectly reasonable'), findsOneWidget);
      expect(find.text(successHeading), findsNothing);
    });

    testWidgets('never shows the confirmation before the server answers', (
      WidgetTester tester,
    ) async {
      final Completer<http.Response> gate = Completer<http.Response>();
      await pushInquire(
        tester,
        handler: (RecordedRequest request) async =>
            request.method == 'POST' ? gate.future : inquiryCreatedResponse(),
      );
      await typeMessage(tester, 'Waiting for the answer');
      await chooseRequiredPreferences(tester);

      final Finder send = find.widgetWithText(FilledButton, 'Send Inquiry');
      await tester.ensureVisible(send);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(send);
      await settle(tester);

      expect(find.text(successHeading), findsNothing);

      gate.complete(inquiryConflictResponse());
      await settle(tester, frames: 20);

      expect(find.text(successHeading), findsNothing);
      expect(find.text('Waiting for the answer'), findsOneWidget);
    });

    testWidgets('reports a transport failure as a notice, keeping the form', (
      WidgetTester tester,
    ) async {
      await pushInquire(
        tester,
        handler: (RecordedRequest request) async => request.method == 'POST'
            ? throw http.ClientException('connection refused')
            : inquiryCreatedResponse(),
      );
      await typeMessage(tester, 'Typed before the outage');
      await chooseRequiredPreferences(tester);
      await submit(tester);

      expect(find.textContaining('Could not reach the server'), findsOneWidget);
      expect(find.text('Typed before the outage'), findsOneWidget);
      expect(find.text(successHeading), findsNothing);
    });
  });

  group('inquiry sent view', () {
    testWidgets(
      'shows the real listing and the server-confirmed inquiry values',
      (WidgetTester tester) async {
        await pushInquire(
          tester,
          handler: (_) async => inquiryCreatedResponse(
            inquiry: inquiryJson(
              message: 'Can I collect on the 25th?',
              paymentMethod: 'cash',
              collectionMethod: 'farm_pickup',
            ),
          ),
        );
        await typeMessage(tester, 'Can I collect on the 25th?');
        await chooseOption(tester, 'Cash');
        await chooseOption(tester, 'Farm Pickup');
        await chooseOption(tester, 'Next few days');
        await submit(tester);

        // The listing summary is the real [Listing] the screen was opened
        // with — the same card the form showed, not a re-fetched sample.
        expect(find.text('CATTLE'), findsOneWidget);
        expect(find.text('Holstein'), findsOneWidget);
        expect(find.text('₱42,500.00'), findsOneWidget);
        expect(find.text('Rizal Farms'), findsOneWidget);
        expect(find.text('Mabalacat, Pampanga'), findsOneWidget);

        // The inquiry summary is the record the create response returned.
        expect(find.text('Your Inquiry'), findsOneWidget);
        expect(find.text('Can I collect on the 25th?'), findsOneWidget);
        expect(find.text('Preferred payment method'), findsOneWidget);
        expect(find.text('Cash'), findsOneWidget);
        expect(find.text('Preferred collection'), findsOneWidget);
        expect(find.text("Pick up from the seller's farm"), findsOneWidget);

        // The form is gone; only the confirmation remains.
        expect(find.text('Inquire About Livestock'), findsNothing);
        expect(find.text('Send Inquiry'), findsNothing);
        expect(find.text(successHeading), findsOneWidget);
      },
    );

    testWidgets('renders only the preferences the create response returned', (
      WidgetTester tester,
    ) async {
      // The form now requires both, but the confirmation is built from the
      // server's record — never from what the screen remembers choosing. A
      // response that echoes neither must not grow a row.
      await pushInquire(
        tester,
        handler: (_) async => inquiryCreatedResponse(
          inquiry: inquiryJson(
            message: 'Just asking about availability',
            paymentMethod: null,
            collectionMethod: null,
          ),
        ),
      );
      await typeMessage(tester, 'Just asking about availability');
      await chooseOption(tester, 'Cash');
      await chooseOption(tester, 'Farm Pickup');
      await chooseOption(tester, 'Next few days');
      await submit(tester);

      expect(find.text(successHeading), findsOneWidget);
      expect(find.text('Just asking about availability'), findsOneWidget);
      // No row and no placeholder is invented for an absent preference.
      expect(find.text('Preferred payment method'), findsNothing);
      expect(find.text('Preferred collection'), findsNothing);

      // None of the obsolete rows survive on the confirmation either.
      for (final String obsolete in <String>[
        'Subject',
        'General Inquiry',
        'Interested in purchasing?',
        'Transaction preference',
        'Delivery fee',
        'Preferred contact method',
        'Preferred schedule',
      ]) {
        expect(
          find.text(obsolete),
          findsNothing,
          reason: '"$obsolete" is no longer part of the confirmation',
        );
      }
    });

    testWidgets(
      'Go to Messages opens the exact chat with the seller, not just the inbox',
      (WidgetTester tester) async {
        await pushInquire(
          tester,
          handler: (_) async => inquiryCreatedResponse(),
        );
        await typeMessage(tester, 'Will the button work?');
        await chooseOption(tester, 'Cash');
        await chooseOption(tester, 'Farm Pickup');
        await chooseOption(tester, 'Next few days');
        await submit(tester);

        final Finder goToMessages = find.widgetWithText(
          FilledButton,
          'Go to Messages',
        );
        expect(goToMessages, findsOneWidget);
        expect(
          tester.widget<FilledButton>(goToMessages).onPressed,
          isNotNull,
          reason: 'the destination exists, so the action is live',
        );
        // The disabled inquiry route and its apology are gone.
        expect(find.text('View Inquiry'), findsNothing);
        expect(
          find.text('Viewing a saved inquiry is not available in the app yet.'),
          findsNothing,
        );

        await tester.ensureVisible(goToMessages);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(goToMessages);
        await settle(tester);

        // MS-04: Go to Messages opens the exact buyer–seller conversation,
        // not merely the inbox. The app bar shows the seller as the title.
        expect(find.byType(ChatScreen), findsOneWidget);
        expect(find.text('Rizal Farms'), findsOneWidget);
        expect(posts(), hasLength(1), reason: 'the inquiry is not re-sent');
      },
    );

    testWidgets('states the workflow position without a fabricated status', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());
      await typeMessage(tester, 'Checking the status card');
      await chooseRequiredPreferences(tester);
      await submit(tester);

      expect(find.text('Inquiry Status'), findsOneWidget);
      expect(find.text('Awaiting seller response'), findsOneWidget);
      expect(
        find.text(
          'Your inquiry is saved. The seller can respond through the app.',
        ),
        findsOneWidget,
      );
      // The server's admin-only open/responded/closed enum never appears:
      // mobile neither fetches nor models it.
      expect(find.text('Open'), findsNothing);
      expect(find.text('Responded'), findsNothing);
      expect(find.text('Closed'), findsNothing);
      // And nothing promises a notification the backend does not send.
      expect(find.textContaining("You'll be notified"), findsNothing);
      expect(find.textContaining('notified'), findsNothing);
    });

    testWidgets('keeps a long message readable without an overflow', (
      WidgetTester tester,
    ) async {
      final String longMessage = List<String>.generate(
        40,
        (int index) => 'sentence $index',
      ).join(' ');
      expect(longMessage.length, lessThanOrEqualTo(kInquiryMessageMax));

      await pushInquire(
        tester,
        handler: (_) async =>
            inquiryCreatedResponse(inquiry: inquiryJson(message: longMessage)),
      );
      await typeMessage(tester, longMessage);
      await chooseRequiredPreferences(tester);
      await submit(tester);

      // A RenderFlex overflow would throw and fail the test; the summary
      // wraps the full message rather than truncating it — there is no
      // details screen to show the rest (design spec §3.4).
      expect(find.text(successHeading), findsOneWidget);
      expect(find.text(longMessage), findsOneWidget);
    });
  });

  group('navigation', () {
    testWidgets('Cancel leaves the screen without sending anything', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());
      await typeMessage(tester, 'Not sent');

      final Finder cancel = find.widgetWithText(OutlinedButton, 'Cancel');
      await tester.ensureVisible(cancel);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(cancel);
      await settle(tester);

      expect(find.byType(InquireScreen), findsNothing);
      expect(find.text('Listing detail stand-in'), findsOneWidget);
      expect(posts(), isEmpty);
    });
  });
}
