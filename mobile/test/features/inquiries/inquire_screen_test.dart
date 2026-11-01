import 'dart:async';

import 'package:agrobenta_mobile/core/constants/api_constants.dart';
import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/inquiries/state/inquiry_scope.dart';
import 'package:agrobenta_mobile/features/inquiries/view/inquire_screen.dart';
import 'package:agrobenta_mobile/models/inquiry.dart';
import 'package:agrobenta_mobile/models/listing.dart';
import 'package:agrobenta_mobile/repositories/inquiry_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/inquiry_fakes.dart';
import '../../support/marketplace_fakes.dart';

/// The Inquiry Sent screen's heading. Every success assertion keys on this;
/// the failure assertions use it as the "not shown" probe.
const String successHeading = 'Your inquiry has been sent to the seller.';

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
  /// entry route, with only the scope the screen actually reads above
  /// `MaterialApp`. The transport answers `POST /inquiries` through the same
  /// [ApiClient] chain production uses.
  Future<void> pushInquire(
    WidgetTester tester, {
    required Future<http.Response> Function(RecordedRequest request) handler,
  }) async {
    final InquiryRepository repository = buildInquiryRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );

    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      InquiryScope(
        repository: repository,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            appBar: AppBar(title: const Text('Listing detail stand-in')),
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

  Future<void> typeMessage(WidgetTester tester, String text) async {
    await tester.ensureVisible(messageField());
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(messageField(), text);
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> chooseYes(WidgetTester tester) async {
    final Finder yes = find.widgetWithText(RadioListTile<bool>, 'Yes');
    await tester.ensureVisible(yes);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(yes);
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> submit(WidgetTester tester) async {
    final Finder send = find.widgetWithText(FilledButton, 'Send Inquiry');
    await tester.ensureVisible(send);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(send);
    await settle(tester);
  }

  List<RecordedRequest> posts() => recorded
      .where((RecordedRequest r) => r.method == 'POST')
      .toList(growable: false);

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
        find.text('18 months · 320.5 kg · Female'),
        findsOneWidget,
        reason: 'the attributes come from the API, capitalised like detail',
      );
      expect(find.text('Mabalacat, Pampanga'), findsOneWidget);
      // No photo supplied by the fixture — the shared placeholder, not a
      // synthesised image.
      expect(find.text('No photo'), findsOneWidget);
    });

    testWidgets('every section the design spec asks for', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());

      expect(find.text('Your Inquiry'), findsOneWidget);
      expect(find.text('Subject'), findsOneWidget);
      expect(
        find.text('General Inquiry'),
        findsAtLeastNWidgets(1),
        reason: 'the one subject the form offers, selected by default',
      );
      expect(find.text('Message *'), findsOneWidget);
      expect(find.text('Type your inquiry here...'), findsOneWidget);
      expect(find.text('0/500'), findsOneWidget);
      expect(find.text('Are you interested in purchasing? *'), findsOneWidget);

      expect(find.text('Transaction Method (Preferred)'), findsOneWidget);
      expect(
        find.text(
          'Your preference only — this does not create a transaction, '
          'payment, or delivery booking.',
        ),
        findsOneWidget,
      );
      expect(find.text('Direct Deal'), findsOneWidget);
      expect(
        find.text('I will transact directly with the seller.'),
        findsOneWidget,
      );
      expect(find.text('Arrange Delivery'), findsOneWidget);
      expect(
        find.text('I will arrange for the transportation.'),
        findsOneWidget,
      );

      expect(find.text('Delivery Details'), findsOneWidget);
      expect(find.text('Delivery Method'), findsOneWidget);
      expect(
        find.text('Buyer Pickup (I will get the livestock)'),
        findsAtLeastNWidgets(1),
        reason: 'buyer pickup is the default delivery method',
      );
      expect(find.text('Delivery Fee (₱)'), findsOneWidget);
      expect(
        find.text('Buyer pickup — there is no delivery fee.'),
        findsOneWidget,
      );
      expect(find.text('Preferred Contact Method'), findsOneWidget);
      expect(find.text('In-app Message'), findsOneWidget);
      expect(find.text('Preferred Schedule (Optional)'), findsOneWidget);
      expect(find.text('No date chosen'), findsOneWidget);

      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Send Inquiry'), findsOneWidget);
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

  group('client validation', () {
    testWidgets('refuses an empty message and sends nothing', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());
      await chooseYes(tester);
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
      await chooseYes(tester);
      await submit(tester);

      expect(find.text('A message cannot be only spaces.'), findsOneWidget);
      expect(posts(), isEmpty);
    });

    testWidgets('refuses a submission with no purchase answer', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());
      await typeMessage(tester, 'Is this one still available?');
      await submit(tester);

      expect(
        find.text('Please choose whether you are interested in purchasing.'),
        findsOneWidget,
      );
      expect(posts(), isEmpty);
    });

    testWidgets('refuses a negative delivery fee', (WidgetTester tester) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());
      await typeMessage(tester, 'Can you deliver to Pampanga?');
      await chooseYes(tester);

      // Switch to Arrange Delivery so the fee field is editable.
      final Finder deliveryDropdown = find.byType(
        DropdownButtonFormField<InquiryDeliveryMethod>,
      );
      await tester.ensureVisible(deliveryDropdown);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(deliveryDropdown);
      await settle(tester, frames: 20);
      await tester.tap(
        find.text('Arrange Delivery (I will arrange transport)').last,
      );
      await settle(tester, frames: 20);

      final Finder fee = find.widgetWithText(TextFormField, 'Delivery Fee (₱)');
      await tester.ensureVisible(fee);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(fee, '-500');
      await tester.pump(const Duration(milliseconds: 50));

      await submit(tester);

      expect(find.text('A delivery fee cannot be negative.'), findsOneWidget);
      expect(posts(), isEmpty);
    });

    testWidgets('tracks the message length against the 500 ceiling', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());
      await typeMessage(tester, '12345');

      expect(find.text('5/500'), findsOneWidget);
    });
  });

  group('submission', () {
    testWidgets(
      'sends the allow-listed body and shows the confirmation the server '
      'returned',
      (WidgetTester tester) async {
        await pushInquire(
          tester,
          handler: (_) async => inquiryCreatedResponse(
            inquiry: inquiryJson(message: 'Is this one still available?'),
          ),
        );
        await typeMessage(tester, 'Is this one still available?');
        await chooseYes(tester);
        await submit(tester);

        // Success is the server's answer: the confirmation view, by response.
        expect(find.text(successHeading), findsOneWidget);
        expect(find.text('Inquiry Sent'), findsOneWidget);
        expect(find.byType(InquireScreen), findsOneWidget);

        expect(posts(), hasLength(1));
        final RecordedRequest post = posts().single;
        expect(post.apiPath, InquiryEndpoints.create);
        expect(
          post.body.keys.toSet().difference(
            InquiryEndpoints.writableFields.toSet(),
          ),
          isEmpty,
          reason: 'not one key outside the allow-list went out',
        );
        expect(post.body['listing_id'], 12);
        expect(post.body['message'], 'Is this one still available?');
        expect(post.body['subject'], 'General Inquiry');
        expect(post.body['purchase_interest'], isTrue);
        expect(post.body['contact_method'], 'in_app_message');
        expect(post.body['delivery_method'], 'buyer_pickup');
        for (final String forbidden in <String>[
          'buyer_id',
          'seller_id',
          'status',
        ]) {
          expect(post.body.containsKey(forbidden), isFalse);
        }

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
      },
    );

    testWidgets('sends every preference the form gathered', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());
      await typeMessage(tester, 'Can you arrange transport to Baguio?');
      await chooseYes(tester);

      // Direct Deal card.
      await tester.ensureVisible(find.text('Direct Deal'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Direct Deal'));
      await tester.pump(const Duration(milliseconds: 50));

      // Delivery: Arrange Delivery with a proposed fee.
      final Finder deliveryDropdown = find.byType(
        DropdownButtonFormField<InquiryDeliveryMethod>,
      );
      await tester.ensureVisible(deliveryDropdown);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(deliveryDropdown);
      await settle(tester, frames: 20);
      await tester.tap(
        find.text('Arrange Delivery (I will arrange transport)').last,
      );
      await settle(tester, frames: 20);

      final Finder fee = find.widgetWithText(TextFormField, 'Delivery Fee (₱)');
      await tester.ensureVisible(fee);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(fee, '1500');
      await tester.pump(const Duration(milliseconds: 50));

      await submit(tester);

      final RecordedRequest post = posts().single;
      expect(post.body['transaction_method'], 'direct_deal');
      expect(post.body['delivery_method'], 'arrange_delivery');
      expect(post.body['delivery_fee'], '1500');
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
      await chooseYes(tester);

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
      await chooseYes(tester);

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
      await chooseYes(tester);
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
      await chooseYes(tester);
      await submit(tester);

      expect(find.text('Something went wrong on the server.'), findsOneWidget);
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
      await chooseYes(tester);
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
      await chooseYes(tester);

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
      await chooseYes(tester);
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
              transactionMethod: 'direct_deal',
              deliveryMethod: 'arrange_delivery',
              deliveryFee: '1500.00',
            ),
          ),
        );
        await typeMessage(tester, 'Can I collect on the 25th?');
        await chooseYes(tester);
        await submit(tester);

        // The listing summary is the real [Listing] the screen was opened
        // with — the same card the form showed, not a re-fetched sample.
        expect(find.text('CATTLE'), findsOneWidget);
        expect(find.text('Holstein'), findsOneWidget);
        expect(find.text('₱42,500.00'), findsOneWidget);
        expect(find.text('Mabalacat, Pampanga'), findsOneWidget);

        // The inquiry summary is the record the create response returned.
        expect(find.text('Your Inquiry'), findsOneWidget);
        expect(find.text('General Inquiry'), findsOneWidget);
        expect(find.text('Can I collect on the 25th?'), findsOneWidget);
        expect(find.text('Interested in purchasing?'), findsOneWidget);
        expect(find.text('Yes'), findsOneWidget);
        expect(find.text('Transaction preference'), findsOneWidget);
        expect(find.text('Direct Deal'), findsOneWidget);
        expect(find.text('Delivery fee'), findsOneWidget);
        expect(find.text('₱1,500.00'), findsOneWidget);
        expect(find.text('Preferred contact method'), findsOneWidget);
        expect(find.text('In-app Message'), findsOneWidget);
        expect(find.text('Preferred schedule'), findsOneWidget);
        expect(find.text('25 Oct 2026'), findsOneWidget);

        // The form is gone; only the confirmation remains.
        expect(find.text('Inquire About Livestock'), findsNothing);
        expect(find.text('Send Inquiry'), findsNothing);
        expect(find.text(successHeading), findsOneWidget);
      },
    );

    testWidgets('omits a summary row for a field the buyer left empty', (
      WidgetTester tester,
    ) async {
      await pushInquire(
        tester,
        handler: (_) async => inquiryCreatedResponse(
          inquiry: inquiryJson(
            message: 'Just asking about availability',
            subject: null,
            purchaseInterest: null,
            transactionMethod: null,
            deliveryMethod: 'buyer_pickup',
            deliveryFee: null,
            contactMethod: null,
            preferredSchedule: null,
          ),
        ),
      );
      await typeMessage(tester, 'Just asking about availability');
      await chooseYes(tester);
      await submit(tester);

      expect(find.text(successHeading), findsOneWidget);
      expect(find.text('Just asking about availability'), findsOneWidget);
      // No row and no placeholder is invented for an absent field.
      expect(find.text('Subject'), findsNothing);
      expect(find.text('Interested in purchasing?'), findsNothing);
      expect(find.text('Transaction preference'), findsNothing);
      expect(find.text('Delivery fee'), findsNothing);
      expect(find.text('Preferred contact method'), findsNothing);
      expect(find.text('Preferred schedule'), findsNothing);
    });

    testWidgets(
      'renders View Inquiry disabled with an honest caption instead of a '
      'fake route',
      (WidgetTester tester) async {
        await pushInquire(
          tester,
          handler: (_) async => inquiryCreatedResponse(),
        );
        await typeMessage(tester, 'Will the button work?');
        await chooseYes(tester);
        await submit(tester);

        final Finder viewInquiry = find.widgetWithText(
          FilledButton,
          'View Inquiry',
        );
        expect(viewInquiry, findsOneWidget);
        expect(
          tester.widget<FilledButton>(viewInquiry).onPressed,
          isNull,
          reason: 'no buyer endpoint exists to open a saved inquiry',
        );
        expect(
          find.text('Viewing a saved inquiry is not available in the app yet.'),
          findsOneWidget,
        );

        // The dead button leads nowhere and, above all, never re-sends.
        await tester.ensureVisible(viewInquiry);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(viewInquiry, warnIfMissed: false);
        await settle(tester);

        expect(find.byType(InquireScreen), findsOneWidget);
        expect(find.text(successHeading), findsOneWidget);
        expect(posts(), hasLength(1));
      },
    );

    testWidgets('states the workflow position without a fabricated status', (
      WidgetTester tester,
    ) async {
      await pushInquire(tester, handler: (_) async => inquiryCreatedResponse());
      await typeMessage(tester, 'Checking the status card');
      await chooseYes(tester);
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
      expect(longMessage.length, lessThanOrEqualTo(500));

      await pushInquire(
        tester,
        handler: (_) async =>
            inquiryCreatedResponse(inquiry: inquiryJson(message: longMessage)),
      );
      await typeMessage(tester, longMessage);
      await chooseYes(tester);
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
