import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/inquiry.dart';
import '../../../repositories/inquiry_repository.dart';
import 'inquiry_state.dart';

/// Presentation logic for sending an inquiry.
///
/// The only thing that mutates [state]. The screen calls [checkExisting] once
/// on open and [send] on submit, and listens.
///
/// ## The rules this class exists to enforce
///
/// * **Check before the form.** [checkExisting] asks the server whether this
///   buyer already sent an inquiry about this listing. When one exists the
///   screen shows the already-sent state instead of a form that could only
///   fail; a failed check still renders the form, because the backend's
///   duplicate guard is authoritative.
/// * **Success is the server's answer, never an optimistic one.**
///   [InquiryUiStatus.succeeded] is published only from the create response,
///   so the confirmation view cannot appear for a request that failed or timed
///   out (design spec §3.6).
/// * **One request at a time.** A second [send] while one is in flight returns
///   `false` without touching the network. The button being disabled stops a
///   tap; this stops the request already in flight from being followed by
///   another one.
/// * **A failed submission keeps the form.** Every failure returns to
///   [InquiryUiStatus.failed] with the input untouched — the screen still
///   holds its `TextEditingController`s, and this class never clears them.
///
/// ## Errors
///
///  * `422` — per-field messages, merged into the field validators via
///    [InquiryState.errorFor]. The screen re-validates so they appear beside
///    their fields rather than only in a banner.
///  * `409` / `404` — the listing stopped being eligible (it is not active, it
///    is the caller's own, the buyer already asked, or it is gone). A
///    form-level message: nothing the buyer typed is wrong, and retrying
///    cannot help.
///  * everything else — a form-level message carrying the server's wording.
class InquiryController extends ChangeNotifier {
  InquiryController(this._repository);

  final InquiryRepository _repository;

  InquiryState _state = const InquiryState();
  InquiryState get state => _state;

  bool _disposed = false;

  /// Asks the server whether this buyer already has an inquiry for [listingId].
  ///
  /// Runs once when the screen opens. A found inquiry is published in
  /// [InquiryState.existingInquiry]; a failure is published in
  /// [InquiryState.existingCheckError] and leaves the form usable. The call is
  /// deliberately silent on a re-entry while one is already in flight, the
  /// same one-request-at-a-time rule [send] follows.
  Future<void> checkExisting({required int listingId}) async {
    if (_state.isCheckingExisting || _state.isBusy) {
      return;
    }

    _set(
      _state.copyWith(
        isCheckingExisting: true,
        clearExistingInquiry: true,
        clearExistingCheckError: true,
      ),
    );

    try {
      final Inquiry? existing = await _repository.findExistingForListing(
        listingId,
      );
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          isCheckingExisting: false,
          existingInquiry: existing,
          clearExistingInquiry: existing == null,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          isCheckingExisting: false,
          existingCheckError: error.message,
        ),
      );
    } on Object {
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          isCheckingExisting: false,
          existingCheckError:
              'Could not check whether you have already sent an inquiry. '
              'You can still send one.',
        ),
      );
    }
  }

  /// Sends an inquiry. Returns `true` only when the server confirmed it.
  ///
  /// Validation of required fields happens in the screen, before this is
  /// called; here, [ApiErrorKind.validation] means the server enforced a rule
  /// the client did not model, and those messages are merged into
  /// [InquiryState.validationErrors].
  ///
  /// [paymentMethod] and [collectionMethod] are non-nullable here even though
  /// [InquiryRepository.create] keeps them optional: the form now requires
  /// both, so the screen has no path that could call this without them.
  Future<bool> send({
    required int listingId,
    required String message,
    required InquiryCollectionDateOption collectionDateOption,
    DateTime? preferredSchedule,
    required InquiryPaymentMethod paymentMethod,
    required InquiryCollectionMethod collectionMethod,
    String? subject,
    bool? purchaseInterest,
    InquiryTransactionMethod? transactionMethod,
    InquiryDeliveryMethod? deliveryMethod,
    String? deliveryFee,
    InquiryContactMethod? contactMethod,
  }) async {
    if (_state.isBusy || _state.isCheckingExisting) {
      return false;
    }
    // A found inquiry means the screen is showing the already-sent state; a
    // send from a stale frame must not create a second record.
    if (_state.existingInquiry != null) {
      return false;
    }

    _set(
      _state.copyWith(
        status: InquiryUiStatus.submitting,
        clearError: true,
        validationErrors: const <String, List<String>>{},
      ),
    );

    try {
      final Inquiry inquiry = await _repository.create(
        listingId: listingId,
        message: message,
        collectionDateOption: collectionDateOption,
        preferredSchedule: preferredSchedule,
        subject: subject,
        purchaseInterest: purchaseInterest,
        transactionMethod: transactionMethod,
        deliveryMethod: deliveryMethod,
        deliveryFee: deliveryFee,
        contactMethod: contactMethod,
        paymentMethod: paymentMethod,
        collectionMethod: collectionMethod,
      );

      if (_disposed) {
        return false;
      }

      // The server's own record, echoed from the create response. Nothing here
      // fabricates an id, a timestamp or a status the server did not send.
      _set(
        _state.copyWith(status: InquiryUiStatus.succeeded, inquiry: inquiry),
      );
      return true;
    } on ApiException catch (error) {
      if (_disposed) {
        return false;
      }

      final bool hasFieldErrors = error.validationErrors.isNotEmpty;

      _set(
        _state.copyWith(
          status: InquiryUiStatus.failed,
          // A 422's headline is often a generic "The given data was invalid";
          // the per-field messages carry the real wording and are merged into
          // the validators. The banner still gets a message so the screen never
          // shows a failure with no explanation anywhere.
          errorMessage: error.message,
          validationErrors: hasFieldErrors
              ? error.validationErrors
              : const <String, List<String>>{},
        ),
      );
      return false;
    } on Object {
      if (_disposed) {
        return false;
      }
      _set(
        _state.copyWith(
          status: InquiryUiStatus.failed,
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
      return false;
    }
  }

  /// Discards a form-level error so a retry starts clean.
  void clearError() {
    if (_state.errorMessage == null && _state.validationErrors.isEmpty) {
      return;
    }
    _set(
      _state.copyWith(
        clearError: true,
        validationErrors: const <String, List<String>>{},
      ),
    );
  }

  void _set(InquiryState next) {
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
