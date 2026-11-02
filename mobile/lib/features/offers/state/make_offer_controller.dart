import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/inquiry.dart';
import '../../../models/offer.dart';
import '../../../repositories/offer_repository.dart';
import 'offer_state.dart';

/// Presentation logic for the seller creating a purchase offer from an
/// inquiry.
///
/// Per-screen: the make-offer form is a one-shot action, so the screen that
/// owns the request owns the controller and disposes it with the route. The
/// repository is shared through `OfferScope`; nothing about this form is
/// session state.
class MakeOfferController extends ChangeNotifier {
  MakeOfferController(this._repository);

  final OfferRepository _repository;

  MakeOfferState _state = const MakeOfferState();
  MakeOfferState get state => _state;

  bool _disposed = false;

  /// Validates and submits one offer. Returns the created offer, or `null`
  /// when the request did not succeed.
  ///
  /// The amount is the only client-side rule: the server owns everything else
  /// (`buyer_id` comes from the inquiry, `seller_id` from the token, the
  /// status is always `pending`). The local check mirrors `StoreOfferRequest`
  /// — required, numeric, at least 0.01 — so an empty field does not need a
  /// round-trip to say so.
  Future<Offer?> submit({
    required int inquiryId,
    required int listingId,
    required String amount,
    DateTime? pickupDate,
    InquiryPaymentMethod? paymentMethod,
    InquiryCollectionMethod? collectionMethod,
    String? note,
  }) async {
    if (_state.isSubmitting) {
      return null;
    }

    final String trimmed = amount.trim();
    final String? amountError = _validateAmount(trimmed);
    if (amountError != null) {
      _set(
        MakeOfferState(
          status: MakeOfferStatus.failed,
          amountErrorMessage: amountError,
        ),
      );
      return null;
    }

    _set(
      _state.copyWith(status: MakeOfferStatus.submitting, clearErrors: true),
    );

    try {
      final Offer created = await _repository.create(
        inquiryId: inquiryId,
        listingId: listingId,
        proposedAmount: trimmed,
        proposedPickupDate: pickupDate,
        paymentMethod: paymentMethod,
        collectionMethod: collectionMethod,
        note: note,
      );
      if (_disposed) {
        return null;
      }
      _set(
        _state.copyWith(status: MakeOfferStatus.succeeded, created: created),
      );
      return created;
    } on ApiException catch (error) {
      if (_disposed) {
        return null;
      }
      _set(
        _state.copyWith(
          status: MakeOfferStatus.failed,
          amountErrorMessage: error.validationErrors['proposed_amount']?.first,
          errorMessage: error.message,
        ),
      );
      return null;
    } on Object {
      if (_disposed) {
        return null;
      }
      _set(
        _state.copyWith(
          status: MakeOfferStatus.failed,
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
      return null;
    }
  }

  /// A local mirror of the server's `required|numeric|min:0.01` rule.
  static String? _validateAmount(String amount) {
    if (amount.isEmpty) {
      return 'Enter the amount you are offering.';
    }
    final double? parsed = double.tryParse(amount);
    if (parsed == null || !parsed.isFinite) {
      return 'Enter a valid amount.';
    }
    if (parsed < 0.01) {
      return 'Enter an amount of at least 0.01.';
    }
    return null;
  }

  void _set(MakeOfferState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
