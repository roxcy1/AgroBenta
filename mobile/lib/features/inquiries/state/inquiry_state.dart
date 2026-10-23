import '../../../models/inquiry.dart';

/// Where an inquiry submission is in its request lifecycle.
///
/// Named `…UiStatus` because `InquiryStatus` is the **server's** enum
/// (`open` / `answered` / `closed`-style workflow values in
/// `backend/app/Enums/InquiryStatus.php`). The server's status is deliberately
/// not modelled on the client at all — an administrator's bookmark gates no
/// mobile behaviour — so the only status this feature has is whether the
/// screen's own request has been sent, succeeded or failed.
enum InquiryUiStatus {
  /// Constructed, nothing sent yet. The form is shown empty.
  initial,

  /// A submission is in flight. The form keeps the user's input and the button
  /// spins — replacing the form with a spinner would discard everything typed.
  submitting,

  /// The server confirmed persistence. The success view is shown, and only
  /// from this status: nothing optimistically succeeds.
  succeeded,

  /// The submission failed. The form keeps its input so a retry does not
  /// start from zero.
  failed,
}

/// An immutable snapshot of everything the inquire screen renders.
///
/// [inquiry] is the server's own record from the create response — never an
/// optimistic guess — and it exists only in
/// [InquiryUiStatus.succeeded]. There is no read endpoint for an inquiry, so
/// this response is the single source of truth the confirmation view has.
class InquiryState {
  const InquiryState({
    this.status = InquiryUiStatus.initial,
    this.inquiry,
    this.errorMessage,
    this.validationErrors = const <String, List<String>>{},
  });

  final InquiryUiStatus status;

  /// The created inquiry, once the server has confirmed it.
  final Inquiry? inquiry;

  /// A displayable failure for the whole screen — a `409`, a `404`, a timeout.
  final String? errorMessage;

  /// Per-field messages from a `422`, keyed by contract field name
  /// (`message`, `listing_id`, …). Merged into the field validators so a
  /// server-side rule the client did not model still lands beside its field.
  final Map<String, List<String>> validationErrors;

  /// Whether a request of ours is in flight.
  bool get isBusy => status == InquiryUiStatus.submitting;

  /// The validation message for one field, or `null`.
  ///
  /// Takes the first message: Laravel sends one per rule, and stacking them
  /// all under a single-line field is noise.
  String? errorFor(String field) {
    final List<String>? messages = validationErrors[field];
    if (messages == null || messages.isEmpty) {
      return null;
    }
    return messages.first;
  }

  InquiryState copyWith({
    InquiryUiStatus? status,
    Inquiry? inquiry,
    String? errorMessage,
    Map<String, List<String>>? validationErrors,
    bool clearInquiry = false,
    bool clearError = false,
  }) {
    return InquiryState(
      status: status ?? this.status,
      inquiry: clearInquiry ? null : (inquiry ?? this.inquiry),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      validationErrors: validationErrors ?? this.validationErrors,
    );
  }

  @override
  String toString() =>
      'InquiryState(${status.name}, ${inquiry?.id ?? 'no inquiry'})';
}
