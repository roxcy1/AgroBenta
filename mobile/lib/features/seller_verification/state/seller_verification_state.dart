import '../../../models/seller_verification.dart';

/// Where the seller verification flow is in its lifecycle.
///
/// One enum, because the four business states of functional documentation §3.1
/// plus the request states are mutually exclusive presentations: a screen
/// showing "awaiting review" is not also showing a form.
///
/// Named `…UiStatus` rather than simply `SellerVerificationStatus` because that
/// name belongs to the **server's** enum in `models/seller_verification.dart`,
/// which is the one carrying the contract's `submitted` / `pending_review` /
/// `approved` / `rejected` values. The marketplace made the same split with
/// `ListingStatus` and `MarketplaceStatus`; keeping both here as
/// `SellerVerificationStatus` would shadow one with the other in every file that
/// imports the model, and the type error would surface a long way from its
/// cause.
enum SellerVerificationUiStatus {
  /// Constructed, nothing requested yet.
  initial,

  /// Reading the caller's current verification.
  loading,

  /// The user has never submitted. Offers "Become a Seller".
  ///
  /// Distinct from a successful read that returned nothing, because it is the
  /// state a first-time buyer is in and it should never be dressed up as a
  /// result.
  notSubmitted,

  /// A record exists and is open for review. Explains the wait; offers no form.
  ///
  /// Covers both `submitted` and `pending_review` — see
  /// [SellerVerificationStatus.isOpen]. The buyer cannot act on the difference.
  awaitingReview,

  /// A record exists and was declined. Shows the administrator's note when there
  /// is one, and offers "Resubmit".
  rejected,

  /// A record was approved. The account is a seller; `/auth/me` is the
  /// authority for that and this is the corroborating read.
  approved,

  /// The read failed. Retryable.
  failed,

  /// A submission is in flight.
  ///
  /// Separate from [loading] so the form can keep the user's input and show a
  /// busy button, instead of being replaced by a spinner that would discard
  /// everything they typed.
  submitting,
}

/// An immutable snapshot of everything the seller verification screens render.
///
/// [verification] is the server's current record, and it is the only source of
/// the four business states. Nothing here infers a status the server did not
/// send, and in particular nothing infers seller capability: that comes from
/// `/auth/me` and nowhere else (functional documentation §2.6).
class SellerVerificationState {
  const SellerVerificationState({
    this.status = SellerVerificationUiStatus.initial,
    this.verification,
    this.errorMessage,
    this.validationErrors = const <String, List<String>>{},
    this.conflictMessage,
  });

  final SellerVerificationUiStatus status;

  /// The caller's current verification, or `null` before one is known.
  ///
  /// `null` together with [SellerVerificationUiStatus.notSubmitted] means
  /// "never applied"; `null` with [SellerVerificationUiStatus.failed] means the
  /// read failed. The two are different situations and must not be conflated.
  final SellerVerification? verification;

  /// A displayable failure for the whole screen.
  final String? errorMessage;

  /// Per-field messages from a `422`, keyed by contract field name
  /// (`business_name`, …). Rendered beside the field rather than as a dump.
  final Map<String, List<String>> validationErrors;

  /// Set when a submission was refused with a `409`.
  ///
  /// Kept apart from [errorMessage] on purpose. A `409` is not a fault: the user
  /// submitted something valid and the server already has their application.
  /// Showing it in the same red banner as a network failure would tell them
  /// something is broken when the only true thing is that they are already in
  /// the queue.
  final String? conflictMessage;

  /// The caller's current verification status as the server reported it.
  ///
  /// `null` when there is no record. This is a convenience for the screens, and
  /// it is read straight off the record rather than recomputed from
  /// [SellerVerificationState.status] — the two are related but the server's
  /// value is the one that is authoritative.
  SellerVerificationStatus? get businessStatus => verification?.status;

  /// Whether a submission can be filed or resubmitted right now.
  ///
  /// True when the user has never submitted, or their last one was rejected.
  /// False while one is open, once it is approved, and while a request of our own
  /// is in flight — the last of which is what stops a double tap from creating
  /// two applications.
  bool get canSubmit =>
      switch (status) {
        SellerVerificationUiStatus.notSubmitted => true,
        SellerVerificationUiStatus.rejected => true,
        _ => false,
      };

  /// Whether the screen is waiting on a request of ours.
  bool get isBusy =>
      status == SellerVerificationUiStatus.loading ||
      status == SellerVerificationUiStatus.submitting;

  /// The validation message for one field, or `null`.
  ///
  /// Takes the first message: Laravel sends one per rule, and showing them all
  /// stacked under a single-line field is noise.
  String? errorFor(String field) {
    final List<String>? messages = validationErrors[field];
    if (messages == null || messages.isEmpty) {
      return null;
    }
    return messages.first;
  }

  SellerVerificationState copyWith({
    SellerVerificationUiStatus? status,
    SellerVerification? verification,
    String? errorMessage,
    String? conflictMessage,
    Map<String, List<String>>? validationErrors,
    bool clearVerification = false,
    bool clearError = false,
    bool clearConflict = false,
  }) {
    return SellerVerificationState(
      status: status ?? this.status,
      verification: clearVerification
          ? null
          : (verification ?? this.verification),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      conflictMessage: clearConflict
          ? null
          : (conflictMessage ?? this.conflictMessage),
      validationErrors: validationErrors ?? this.validationErrors,
    );
  }

  @override
  String toString() =>
      'SellerVerificationState(${status.name}, ${businessStatus?.name})';
}
