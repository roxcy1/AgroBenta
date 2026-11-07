import 'dart:convert';
import 'dart:typed_data';

import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/livestock_types/state/livestock_types_controller.dart';
import 'package:agrobenta_mobile/features/livestock_types/state/livestock_types_scope.dart';
import 'package:agrobenta_mobile/features/seller_listings/state/listing_photo_item.dart';
import 'package:agrobenta_mobile/features/seller_listings/state/seller_listing_controller.dart';
import 'package:agrobenta_mobile/features/seller_listings/state/seller_listing_scope.dart';
import 'package:agrobenta_mobile/features/seller_listings/view/seller_listing_form_screen.dart';
import 'package:agrobenta_mobile/models/listing.dart';
import 'package:agrobenta_mobile/repositories/seller_listing_repository.dart';
import 'package:agrobenta_mobile/widgets/local_image_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../support/livestock_type_fakes.dart';
import '../../support/seller_listing_fakes.dart';
import '../../support/seller_listings_app_harness.dart';

/// A one-pixel PNG, so the composer preview has a real frame to decode.
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

/// Widget-level behaviour of the listing form's validation and formatting.
///
/// The validators and formatters are unit-tested in
/// `seller_listing_validators_test.dart`; these tests cover the wiring the unit
/// tests cannot see — which field gets which rule, when an error becomes
/// visible, and which step opens when a save is refused.
void main() {
  Future<http.Response> emptyListHandler(RecordedRequest request) async {
    if (request.method == 'GET' && request.apiPath == '/seller/listings') {
      return sellerListingListResponse(
        listings: <Map<String, dynamic>>[],
        total: 0,
      );
    }
    return http.Response('Not found', 404);
  }

  /// Opens the create form from the empty My Listings screen.
  Future<SellerListingsHarness> openForm(
    WidgetTester tester, {
    required Future<http.Response> Function(RecordedRequest request) handler,
  }) async {
    final SellerListingsHarness harness = await SellerListingsHarness.pump(
      tester,
      handler: handler,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create a listing'));
    await settleSellerListings(tester);

    expect(find.byType(SellerListingFormScreen), findsOneWidget);
    return harness;
  }

  /// Mounts the form directly over a listing, for draft and non-draft cases.
  Future<List<RecordedRequest>> pumpEditForm(
    WidgetTester tester, {
    required Listing listing,
    required Future<http.Response> Function(RecordedRequest request) handler,
  }) async {
    final FakeTokenStore tokenStore = FakeTokenStore('1|test-mobile-token');
    final List<RecordedRequest> recorded = <RecordedRequest>[];
    final SellerListingRepository repository = buildSellerListingRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );
    final SellerListingController controller = SellerListingController(
      repository,
    );
    final catalogRepository = buildLivestockTypeRepository(tokenStore);
    final LivestockTypesController catalog = LivestockTypesController(
      catalogRepository,
    );
    addTearDown(controller.dispose);
    addTearDown(catalog.dispose);
    await catalog.ensureLoaded();

    await tester.pumpWidget(
      LivestockTypesScope(
        repository: catalogRepository,
        controller: catalog,
        child: SellerListingScope(
          repository: repository,
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: SellerListingFormScreen(listing: listing),
          ),
        ),
      ),
    );
    await settleSellerListings(tester);
    return recorded;
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  String fieldText(WidgetTester tester, String label) =>
      tester.widget<TextFormField>(field(label)).controller!.text;

  Finder ageUnitDropdown() => find.ancestor(
    of: find.text('Age unit'),
    matching: find.byType(DropdownButtonFormField<String>),
  );

  Finder livestockTypeDropdown() => find.ancestor(
    of: find.text('Type of livestock'),
    matching: find.byType(DropdownButtonFormField<String>),
  );

  Finder breedDropdown() => find.ancestor(
    of: find.text('Breed'),
    matching: find.byType(DropdownButtonFormField<String>),
  );

  Finder weightUnitDropdown() => find.ancestor(
    of: find.text('Weight unit'),
    matching: find.byType(DropdownButtonFormField<String>),
  );

  Finder genderDropdown() => find.ancestor(
    of: find.text('Gender'),
    matching: find.byType(DropdownButtonFormField<String>),
  );

  Finder aiButton() => find.byKey(const ValueKey<String>('ai-suggest-price'));

  Future<void> tapAiButton(WidgetTester tester) async {
    await tester.ensureVisible(aiButton());
    await tester.pumpAndSettle();
    await tester.tap(aiButton());
    await tester.pumpAndSettle();
  }

  String? fieldError(WidgetTester tester, String label) {
    if (label == 'Type of livestock') {
      return tester
          .widget<DropdownButtonFormField<String>>(livestockTypeDropdown())
          .decoration
          .errorText;
    }
    final TextField input = tester.widget<TextField>(
      find.descendant(of: field(label), matching: find.byType(TextField)),
    );
    return input.decoration?.errorText;
  }

  Future<void> selectLivestockType(WidgetTester tester, String label) async {
    final Finder dropdown = livestockTypeDropdown();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> selectAgeUnit(WidgetTester tester, String label) async {
    final Finder dropdown = ageUnitDropdown();
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> selectWeightUnit(WidgetTester tester, String label) async {
    final Finder dropdown = weightUnitDropdown();
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> selectGender(WidgetTester tester, String label) async {
    final Finder dropdown = genderDropdown();
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  /// Taps a form control, scrolling the Stepper to it first.
  ///
  /// Every step's controls exist in the Stepper's list, and the list builds
  /// lazily, so a finder has to be narrowed to what is actually on screen and
  /// scrolled into view when the step's content is taller than the viewport.
  Future<void> tapFormControl(WidgetTester tester, Finder finder) async {
    final Finder target = finder.hitTestable();
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.byType(Scrollable).hitTestable().first,
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> tapContinue(WidgetTester tester) =>
      tapFormControl(tester, find.widgetWithText(FilledButton, 'Continue'));

  /// Fills the fields the AI action needs and moves to Details.
  Future<void> fillSuggestionInputs(WidgetTester tester) async {
    await selectLivestockType(tester, 'Cattle');
    await tester.enterText(field('Breed'), 'Brahman');
    await tester.enterText(field('Age'), '2');
    await selectAgeUnit(tester, 'Year');
    await tester.enterText(field('Weight'), '500');
    await selectWeightUnit(tester, 'Kilograms');
    await tester.pump();
    await tapContinue(tester);

    await tester.enterText(field('Quantity available'), '1');
    await tester.enterText(field('Asking price'), '42500');
    await tester.enterText(field('Location'), 'Trinidad, Bohol');
    await selectGender(tester, 'Male');
    await tester.pump();
  }

  Future<void> tapSave(WidgetTester tester) => tapFormControl(
    tester,
    find.widgetWithText(FilledButton, 'Save as draft'),
  );

  /// Fills the required fields and walks to the Review step.
  Future<void> fillAndReview(WidgetTester tester) async {
    await selectLivestockType(tester, 'Cattle');
    await tester.pump();
    await tapContinue(tester);

    await tester.enterText(field('Quantity available'), '2');
    await tester.enterText(field('Asking price'), '42500');
    await tester.enterText(field('Location'), 'Trinidad, Bohol');
    await tester.pump();
    await tapContinue(tester);
  }

  int currentStep(WidgetTester tester) =>
      tester.widget<Stepper>(find.byType(Stepper)).currentStep;

  testWidgets('shows no validation errors before a field is touched', (
    WidgetTester tester,
  ) async {
    await openForm(tester, handler: emptyListHandler);

    expect(find.text('Enter the type of livestock.'), findsNothing);
    expect(find.text('Enter the location.'), findsNothing);
    expect(find.text('Enter how many head are available.'), findsNothing);
    expect(find.text('Enter the asking price.'), findsNothing);

    // Auto-validation is per field, so a field the seller has not reached stays
    // quiet. The Form itself must not auto-validate.
    final Form form = tester.widget<Form>(find.byType(Form));
    expect(form.autovalidateMode, AutovalidateMode.disabled);

    final Iterable<TextFormField> textFields = tester.widgetList<TextFormField>(
      find.byType(TextFormField),
    );
    expect(textFields, isNotEmpty);
    for (final TextFormField textField in textFields) {
      expect(textField.autovalidateMode, AutovalidateMode.onUserInteraction);
    }

    final Iterable<DropdownButtonFormField<String>> dropdowns = tester
        .widgetList<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        );
    expect(dropdowns, isNotEmpty);
    for (final DropdownButtonFormField<String> dropdown in dropdowns) {
      expect(dropdown.autovalidateMode, AutovalidateMode.onUserInteraction);
    }
  });

  testWidgets('rejects pasted text instead of stripping or rounding it', (
    WidgetTester tester,
  ) async {
    await openForm(tester, handler: emptyListHandler);

    await tester.enterText(field('Age'), '18 months');
    await tester.pump();
    expect(fieldText(tester, 'Age'), isEmpty);

    await tester.enterText(field('Age'), '18');
    await tester.pump();
    expect(fieldText(tester, 'Age'), '18');

    await tester.enterText(field('Weight'), '1,320');
    await tester.pump();
    expect(fieldText(tester, 'Weight'), isEmpty);

    await tester.enterText(field('Weight'), '320.50');
    await tester.pump();
    expect(fieldText(tester, 'Weight'), '320.50');

    // The third decimal is refused rather than truncated to `320.50`.
    await tester.enterText(field('Weight'), '320.505');
    await tester.pump();
    expect(fieldText(tester, 'Weight'), '320.50');

    // The third decimal is refused rather than rounded by the validator.
    expect(fieldError(tester, 'Weight'), isNull);
  });

  testWidgets('offers Day and applies the 9,125-day age limit', (
    WidgetTester tester,
  ) async {
    await openForm(tester, handler: emptyListHandler);

    await selectAgeUnit(tester, 'Day');
    expect(find.text('Day'), findsOneWidget);

    await tester.enterText(field('Age'), '9126');
    await tester.pump();
    expect(fieldError(tester, 'Age'), 'Enter an age of at most 9,125 days.');

    await tester.enterText(field('Age'), '9125');
    await tester.pump();
    expect(fieldError(tester, 'Age'), isNull);
  });

  testWidgets('re-checks the typed age when its unit changes', (
    WidgetTester tester,
  ) async {
    await openForm(tester, handler: emptyListHandler);

    await tester.enterText(field('Age'), '300');
    await tester.pump();
    expect(fieldError(tester, 'Age'), isNull);

    // 300 months is inside the limit...
    await selectAgeUnit(tester, 'Month');
    expect(fieldError(tester, 'Age'), isNull);

    // ...but 300 years is not, and only the age field is re-checked.
    await selectAgeUnit(tester, 'Year');
    expect(fieldError(tester, 'Age'), 'Enter an age of at most 25 years.');
    expect(find.text('Enter the type of livestock.'), findsNothing);
  });

  testWidgets('Continue checks only the step being left', (
    WidgetTester tester,
  ) async {
    await openForm(tester, handler: emptyListHandler);

    // Step 1 is still empty. It must not block leaving step 0.
    await selectLivestockType(tester, 'Cattle');
    await tester.pump();
    await tapContinue(tester);

    expect(currentStep(tester), 1);
    expect(find.text('Enter how many head are available.'), findsNothing);
  });

  testWidgets('a valid form posts a create request and closes', (
    WidgetTester tester,
  ) async {
    final SellerListingsHarness harness = await openForm(
      tester,
      handler: (RecordedRequest request) async {
        if (request.method == 'POST' && request.apiPath == '/seller/listings') {
          return sellerListingResponse(
            listing: listingJson(id: 7, status: 'draft'),
            statusCode: 201,
          );
        }
        return emptyListHandler(request);
      },
    );

    await selectLivestockType(tester, 'Cattle');
    await tester.pump();
    await tapContinue(tester);

    await tester.enterText(field('Quantity available'), '2');
    await tester.enterText(field('Asking price'), '42500');
    await tester.enterText(field('Location'), 'Trinidad, Bohol');
    await tester.pump();
    await tapContinue(tester);

    await tapSave(tester);
    await settleSellerListings(tester);

    final List<RecordedRequest> posts = harness.recorded
        .where((RecordedRequest r) => r.method == 'POST')
        .toList();
    expect(posts, hasLength(1));
    expect(posts.single.body['livestock_type'], 'cattle');
    expect(posts.single.body['quantity'], 2);
    expect(posts.single.body['asking_price'], '42500');
    expect(posts.single.body['location'], 'Trinidad, Bohol');
    // The client never sends a status; the server decides it.
    expect(posts.single.body.containsKey('status'), isFalse);

    expect(find.byType(SellerListingFormScreen), findsNothing);
  });

  testWidgets('chicken offers only the supported breed choices', (
    WidgetTester tester,
  ) async {
    final SellerListingsHarness harness = await openForm(
      tester,
      handler: (RecordedRequest request) async {
        if (request.method == 'POST' && request.apiPath == '/seller/listings') {
          return sellerListingResponse(
            listing: listingJson(id: 8, status: 'draft'),
            statusCode: 201,
          );
        }
        return emptyListHandler(request);
      },
    );

    await selectLivestockType(tester, 'Chicken');
    await tester.pump();

    expect(find.widgetWithText(TextFormField, 'Breed'), findsNothing);

    await tester.tap(breedDropdown());
    await tester.pumpAndSettle();
    for (final String breed in <String>[
      'Boholano Native Chicken',
      'Broiler',
      'Improved Native Chicken',
      'Layer',
    ]) {
      expect(find.text(breed), findsWidgets, reason: breed);
    }
    expect(find.text('Duck'), findsNothing);
    await tester.tap(find.text('Broiler').last);
    await tester.pumpAndSettle();

    await tapContinue(tester);
    await tester.enterText(field('Quantity available'), '1');
    await tester.enterText(field('Asking price'), '500');
    await tester.enterText(field('Location'), 'Trinidad, Bohol');
    await tester.pump();
    await tapContinue(tester);
    await tapSave(tester);
    await settleSellerListings(tester);

    final RecordedRequest post = harness.recorded.singleWhere(
      (RecordedRequest request) =>
          request.method == 'POST' && request.apiPath == '/seller/listings',
    );
    expect(post.body['livestock_type'], 'chicken');
    expect(post.body['breed'], 'broiler');
  });

  testWidgets(
    'AI Suggest saves a new draft, keeps the form open, and shows the estimate',
    (WidgetTester tester) async {
      final SellerListingsHarness harness = await openForm(
        tester,
        handler: (RecordedRequest request) async {
          if (request.method == 'POST' &&
              request.apiPath == '/seller/listings') {
            return sellerListingResponse(
              listing: listingJson(id: 7, status: 'draft'),
              statusCode: 201,
            );
          }
          if (request.method == 'POST' &&
              request.apiPath == '/seller/listings/7/price-suggestion') {
            return aiPriceSuggestionResponse();
          }
          return emptyListHandler(request);
        },
      );

      await fillSuggestionInputs(tester);
      expect(aiButton(), findsOneWidget);
      expect(
        find.text(
          'Requesting AI assistance saves this draft first. The suggestion is '
          'reference only; you still choose the final asking price.',
        ),
        findsOneWidget,
      );

      await tapAiButton(tester);
      await settleSellerListings(tester, frames: 20);

      expect(find.byType(SellerListingFormScreen), findsOneWidget);
      expect(find.text('AI Price Suggestion'), findsOneWidget);
      expect(find.text('₱9,798.00'), findsOneWidget);
      expect(
        find.text(
          'Synthetic Data — Reference Only. This is not a valuation; you decide the final asking price.',
        ),
        findsOneWidget,
      );
      expect(find.text('Model v3-targeted · synthetic data'), findsOneWidget);
      expect(fieldText(tester, 'Asking price'), '42500');

      expect(
        harness.recorded.where(
          (RecordedRequest request) =>
              request.method == 'POST' && request.apiPath == '/seller/listings',
        ),
        hasLength(1),
      );
      expect(
        harness.recorded.where(
          (RecordedRequest request) =>
              request.method == 'POST' &&
              request.apiPath == '/seller/listings/7/price-suggestion',
        ),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'Use This Price only changes the editable asking price when tapped',
    (WidgetTester tester) async {
      await openForm(
        tester,
        handler: (RecordedRequest request) async {
          if (request.method == 'POST' &&
              request.apiPath == '/seller/listings') {
            return sellerListingResponse(
              listing: listingJson(id: 7, status: 'draft'),
              statusCode: 201,
            );
          }
          if (request.method == 'POST' &&
              request.apiPath == '/seller/listings/7/price-suggestion') {
            return aiPriceSuggestionResponse();
          }
          return emptyListHandler(request);
        },
      );

      await fillSuggestionInputs(tester);
      await tapAiButton(tester);
      await settleSellerListings(tester, frames: 20);
      expect(fieldText(tester, 'Asking price'), '42500');

      await tester.ensureVisible(find.text('Use This Price'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use This Price'));
      await tester.pump();

      expect(fieldText(tester, 'Asking price'), '9798.00');
    },
  );

  testWidgets('editing a model input clears the previous suggestion', (
    WidgetTester tester,
  ) async {
    await openForm(
      tester,
      handler: (RecordedRequest request) async {
        if (request.method == 'POST' && request.apiPath == '/seller/listings') {
          return sellerListingResponse(
            listing: listingJson(id: 7, status: 'draft'),
            statusCode: 201,
          );
        }
        if (request.method == 'POST' &&
            request.apiPath == '/seller/listings/7/price-suggestion') {
          return aiPriceSuggestionResponse();
        }
        return emptyListHandler(request);
      },
    );

    await fillSuggestionInputs(tester);
    await tapAiButton(tester);
    await settleSellerListings(tester, frames: 20);
    expect(find.text('AI Price Suggestion'), findsOneWidget);

    await tapFormControl(tester, find.widgetWithText(TextButton, 'Back'));
    await tester.enterText(field('Weight'), '600');
    await tester.pump();
    await tapContinue(tester);

    expect(find.text('AI Price Suggestion'), findsNothing);
  });

  testWidgets('a warning is shown with its server warning text', (
    WidgetTester tester,
  ) async {
    await openForm(
      tester,
      handler: (RecordedRequest request) async {
        if (request.method == 'POST' && request.apiPath == '/seller/listings') {
          return sellerListingResponse(
            listing: listingJson(id: 7, status: 'draft'),
            statusCode: 201,
          );
        }
        if (request.method == 'POST' &&
            request.apiPath == '/seller/listings/7/price-suggestion') {
          return aiPriceSuggestionResponse(
            estimate: aiPriceEstimateJson(
              status: 'warning',
              warnings: <String>['Outside the typical age-band range.'],
            ),
          );
        }
        return emptyListHandler(request);
      },
    );

    await fillSuggestionInputs(tester);
    await tapAiButton(tester);
    await settleSellerListings(tester, frames: 20);

    expect(find.text('Review recommended'), findsOneWidget);
    expect(find.text('Outside the typical age-band range.'), findsOneWidget);
  });

  testWidgets('withheld shows no price and no Use This Price action', (
    WidgetTester tester,
  ) async {
    await openForm(
      tester,
      handler: (RecordedRequest request) async {
        if (request.method == 'POST' && request.apiPath == '/seller/listings') {
          return sellerListingResponse(
            listing: listingJson(id: 7, status: 'draft'),
            statusCode: 201,
          );
        }
        if (request.method == 'POST' &&
            request.apiPath == '/seller/listings/7/price-suggestion') {
          return aiPriceSuggestionErrorResponse(
            status: 'withheld',
            warnings: <String>['Outside the supported model envelope.'],
            reasonCodes: <String>['insufficient_model_support'],
          );
        }
        return emptyListHandler(request);
      },
    );

    await fillSuggestionInputs(tester);
    await tapAiButton(tester);
    await settleSellerListings(tester, frames: 20);

    expect(find.text('Price suggestion withheld'), findsOneWidget);
    expect(find.text('Outside the supported model envelope.'), findsOneWidget);
    expect(find.text('Reason: insufficient_model_support'), findsOneWidget);
    expect(find.text('Use This Price'), findsNothing);
    expect(find.text('₱'), findsNothing);
  });

  testWidgets('unavailable is displayed and Retry requests again', (
    WidgetTester tester,
  ) async {
    bool firstAttempt = true;
    final SellerListingsHarness harness = await openForm(
      tester,
      handler: (RecordedRequest request) async {
        if (request.method == 'POST' && request.apiPath == '/seller/listings') {
          return sellerListingResponse(
            listing: listingJson(id: 7, status: 'draft'),
            statusCode: 201,
          );
        }
        if (request.method == 'PATCH' &&
            request.apiPath == '/seller/listings/7') {
          return sellerListingResponse(
            listing: listingJson(id: 7, status: 'draft'),
          );
        }
        if (request.method == 'POST' &&
            request.apiPath == '/seller/listings/7/price-suggestion') {
          if (firstAttempt) {
            firstAttempt = false;
            return aiPriceSuggestionErrorResponse(
              status: 'unavailable',
              reasonCodes: <String>['provider_unavailable'],
              message: 'The price suggestion service is unavailable.',
              statusCode: 503,
            );
          }
          return aiPriceSuggestionResponse();
        }
        return emptyListHandler(request);
      },
    );

    await fillSuggestionInputs(tester);
    await tapAiButton(tester);
    await settleSellerListings(tester, frames: 20);

    expect(find.text('Price suggestion unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Use This Price'), findsNothing);

    await tester.ensureVisible(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await settleSellerListings(tester, frames: 20);

    expect(find.text('AI Price Suggestion'), findsOneWidget);
    expect(find.text('₱9,798.00'), findsOneWidget);
    expect(find.text('Use This Price'), findsOneWidget);

    expect(
      harness.recorded.where(
        (RecordedRequest request) =>
            request.method == 'POST' && request.apiPath == '/seller/listings',
      ),
      hasLength(1),
    );
    expect(
      harness.recorded.where(
        (RecordedRequest request) =>
            request.method == 'POST' &&
            request.apiPath == '/seller/listings/7/price-suggestion',
      ),
      hasLength(2),
    );
  });

  testWidgets('an active listing does not offer AI Suggest Price', (
    WidgetTester tester,
  ) async {
    final Listing active = Listing.fromJson(
      listingJson(id: 42, status: 'active'),
    );
    await pumpEditForm(
      tester,
      listing: active,
      handler: (_) async => sellerListingListResponse(),
    );

    await tapContinue(tester);
    expect(aiButton(), findsNothing);
    expect(find.text('AI Suggest Price'), findsNothing);
  });

  testWidgets('an existing draft updates before requesting the suggestion', (
    WidgetTester tester,
  ) async {
    final Listing draft = Listing.fromJson(
      listingJson(id: 42, status: 'draft'),
    );
    final List<RecordedRequest> recorded = await pumpEditForm(
      tester,
      listing: draft,
      handler: (RecordedRequest request) async {
        if (request.method == 'PATCH' &&
            request.apiPath == '/seller/listings/42') {
          return sellerListingResponse(
            listing: listingJson(id: 42, status: 'draft'),
          );
        }
        if (request.method == 'POST' &&
            request.apiPath == '/seller/listings/42/price-suggestion') {
          return aiPriceSuggestionResponse(
            estimate: aiPriceEstimateJson(listingId: 42),
          );
        }
        return sellerListingListResponse();
      },
    );

    await tapContinue(tester);
    await tapAiButton(tester);
    await settleSellerListings(tester, frames: 20);

    expect(find.text('AI Price Suggestion'), findsOneWidget);
    expect(find.text('Use This Price'), findsOneWidget);

    final int patchIndex = recorded.indexWhere(
      (RecordedRequest request) =>
          request.method == 'PATCH' && request.apiPath == '/seller/listings/42',
    );
    final int suggestionIndex = recorded.indexWhere(
      (RecordedRequest request) =>
          request.method == 'POST' &&
          request.apiPath == '/seller/listings/42/price-suggestion',
    );
    expect(patchIndex, greaterThanOrEqualTo(0));
    expect(suggestionIndex, greaterThan(patchIndex));
    expect(
      recorded.where(
        (RecordedRequest request) =>
            request.method == 'POST' && request.apiPath == '/seller/listings',
      ),
      isEmpty,
    );
  });

  testWidgets('a 422 opens the step that owns the field it names', (
    WidgetTester tester,
  ) async {
    const String serverMessage = 'The asking price must be at least 1 peso.';
    final SellerListingsHarness harness = await openForm(
      tester,
      handler: (RecordedRequest request) async {
        if (request.method == 'POST' && request.apiPath == '/seller/listings') {
          return validationResponse(
            errors: <String, Object>{
              'asking_price': <String>[serverMessage],
            },
          );
        }
        return emptyListHandler(request);
      },
    );

    await selectLivestockType(tester, 'Cattle');
    await tester.pump();
    await tapContinue(tester);

    await tester.enterText(field('Quantity available'), '2');
    await tester.enterText(field('Asking price'), '42500');
    await tester.enterText(field('Location'), 'Trinidad, Bohol');
    await tester.pump();
    await tapContinue(tester);

    await tapSave(tester);
    await settleSellerListings(tester);

    expect(
      harness.recorded.where((RecordedRequest r) => r.method == 'POST'),
      hasLength(1),
    );
    // The message belongs to a field on Details, so Details is reopened.
    expect(currentStep(tester), 1);
    expect(fieldError(tester, 'Asking price'), serverMessage);

    // The server's message wins over the local one: clearing the field leaves
    // the server's wording on it, not the client's "Enter the asking price."
    tester.widget<TextFormField>(field('Asking price')).controller!.text = '';
    await tester.pump();
    expect(fieldError(tester, 'Asking price'), serverMessage);
    expect(find.text('Enter the asking price.'), findsNothing);
  });

  testWidgets('a 422 opens the earliest step that has a failing field', (
    WidgetTester tester,
  ) async {
    const String typeMessage = 'The type of livestock has already been taken.';
    final SellerListingsHarness harness = await openForm(
      tester,
      handler: (RecordedRequest request) async {
        if (request.method == 'POST' && request.apiPath == '/seller/listings') {
          return validationResponse(
            errors: <String, Object>{
              'livestock_type': <String>[typeMessage],
              'asking_price': <String>['The asking price is invalid.'],
            },
          );
        }
        return emptyListHandler(request);
      },
    );

    await selectLivestockType(tester, 'Cattle');
    await tester.pump();
    await tapContinue(tester);

    await tester.enterText(field('Quantity available'), '2');
    await tester.enterText(field('Asking price'), '42500');
    await tester.enterText(field('Location'), 'Trinidad, Bohol');
    await tester.pump();
    await tapContinue(tester);
    expect(currentStep(tester), 2);

    await tapSave(tester);
    await settleSellerListings(tester);

    expect(
      harness.recorded.where((RecordedRequest r) => r.method == 'POST'),
      hasLength(1),
    );
    // Information is earlier than Details, so it is the step that opens.
    expect(currentStep(tester), 0);
    expect(fieldError(tester, 'Type of livestock'), typeMessage);
    expect(find.text('Enter the type of livestock.'), findsNothing);
  });

  testWidgets('previews a picked photo through the shared byte preview', (
    WidgetTester tester,
  ) async {
    final SellerListingsHarness harness = await openForm(
      tester,
      handler: emptyListHandler,
    );

    harness.controller.addPickedPhotos(<XFile>[
      XFile.fromData(_pngBytes, path: 'a.png'),
    ]);
    await tester.pump();
    await tester.pump();

    // The tile renders the picked file from its bytes, so the preview works in
    // a web build where `Image.file` cannot.
    expect(find.byType(LocalImagePreview), findsOneWidget);
    final Image image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
  });

  testWidgets('an upload failure keeps the form open on the photo step', (
    WidgetTester tester,
  ) async {
    final SellerListingsHarness harness = await openForm(
      tester,
      handler: (RecordedRequest request) async {
        if (request.method == 'POST' && request.apiPath == '/seller/listings') {
          return sellerListingResponse(
            listing: listingJson(id: 42, status: 'draft'),
            statusCode: 201,
          );
        }
        if (request.method == 'POST' &&
            request.apiPath == '/seller/listings/42/photos') {
          return http.Response('Upload failed', 500);
        }
        return emptyListHandler(request);
      },
    );

    harness.controller.addPickedPhotos(<XFile>[
      XFile.fromData(_pngBytes, path: 'a.png'),
    ]);
    await tester.pump();

    await fillAndReview(tester);
    await tapSave(tester);
    await settleSellerListings(tester);

    // The draft exists, but its photo does not. Closing the form here would
    // claim a success the seller did not get.
    expect(find.byType(SellerListingFormScreen), findsOneWidget);
    expect(currentStep(tester), 0);
    expect(find.text('1 photo failed to upload.'), findsOneWidget);
    expect(harness.controller.photos.single.status, ListingPhotoStatus.failed);
  });

  testWidgets('retrying a failed photo reuses the created draft', (
    WidgetTester tester,
  ) async {
    bool failUpload = true;
    final SellerListingsHarness harness = await openForm(
      tester,
      handler: (RecordedRequest request) async {
        if (request.method == 'POST' && request.apiPath == '/seller/listings') {
          return sellerListingResponse(
            listing: listingJson(id: 42, status: 'draft'),
            statusCode: 201,
          );
        }
        if (request.method == 'PATCH' &&
            request.apiPath == '/seller/listings/42') {
          return sellerListingResponse(
            listing: listingJson(id: 42, status: 'draft'),
          );
        }
        if (request.method == 'POST' &&
            request.apiPath == '/seller/listings/42/photos') {
          if (failUpload) return http.Response('Upload failed', 500);
          return sellerListingResponse(
            listing: listingJson(
              id: 42,
              status: 'draft',
              photos: <Object?>['https://api.test/storage/listings/a.jpg'],
            ),
            statusCode: 201,
          );
        }
        return emptyListHandler(request);
      },
    );

    harness.controller.addPickedPhotos(<XFile>[
      XFile.fromData(_pngBytes, path: 'a.png'),
    ]);
    await tester.pump();

    await fillAndReview(tester);
    await tapSave(tester);
    await settleSellerListings(tester);
    expect(harness.controller.photos.single.status, ListingPhotoStatus.failed);

    failUpload = false;
    await tapFormControl(tester, find.widgetWithText(TextButton, 'Retry'));
    await settleSellerListings(tester);

    expect(
      harness.controller.photos.single.status,
      ListingPhotoStatus.uploaded,
    );

    // Saving again must update the draft the first save created. Creating a
    // second draft would leave the seller with a duplicate listing.
    await tapContinue(tester);
    await tapContinue(tester);
    await tapSave(tester);
    await settleSellerListings(tester);

    final Iterable<RecordedRequest> creates = harness.recorded.where(
      (RecordedRequest r) =>
          r.method == 'POST' && r.apiPath == '/seller/listings',
    );
    expect(creates, hasLength(1));
    expect(
      harness.recorded.where(
        (RecordedRequest r) =>
            r.method == 'PATCH' && r.apiPath == '/seller/listings/42',
      ),
      hasLength(1),
    );
    expect(
      harness.recorded.where(
        (RecordedRequest r) => r.apiPath == '/seller/listings/42/photos',
      ),
      hasLength(2),
    );
    expect(find.byType(SellerListingFormScreen), findsNothing);
  });
}
