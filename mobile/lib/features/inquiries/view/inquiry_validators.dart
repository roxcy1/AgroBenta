/// Pure validation for the inquire form.
///
/// Kept out of the widget so the rules are testable without a `BuildContext`,
/// and so the server's per-field messages can be layered on afterwards by the
/// screen (`validateMessage(v) ?? state.errorFor('message')`) instead of the
/// two sources being entangled in a closure.
///
/// The rules mirror `StoreInquiryRequest` on the backend: `message` required,
/// at most 500 characters, never whitespace-only; `delivery_fee` numeric and
/// never negative, but optional — a plain message with no preferences is a
/// valid inquiry.
library;

/// The server's `max:500` on `message`, duplicated so the client's counter and
/// its validator agree with the rule that will actually reject the request.
const int kInquiryMessageMax = 500;

/// The subject the form offers. One option, because the other subjects the
/// reference shows have no approved requirement behind them, and a dropdown of
/// one is what it looks like to wait for that decision (design spec §3.3).
const String kInquiryGeneralSubject = 'General Inquiry';

/// Required, non-blank, at most [kInquiryMessageMax] characters.
///
/// The whitespace-only check is separate from the emptiness check because
/// `"   "` passes a `isEmpty` test and is still a blank inquiry — the server
/// rejects it with `not_regex`, and a buyer who typed only spaces deserves the
/// same answer locally instead of a round trip to learn it.
String? validateInquiryMessage(String? value) {
  final String text = value ?? '';
  if (text.trim().isEmpty) {
    return text.isEmpty
        ? 'Please enter a message for the seller.'
        : 'A message cannot be only spaces.';
  }
  if (text.length > kInquiryMessageMax) {
    return 'A message may be at most $kInquiryMessageMax characters.';
  }
  return null;
}

/// Optional: `null` or blank is fine (a plain message is a valid inquiry).
/// When a value is given it must be a non-negative number of pesos —
/// non-numeric and negative are both refused, matching the server's
/// `numeric|min:0`.
String? validateDeliveryFee(String? value) {
  final String text = (value ?? '').trim();
  if (text.isEmpty) {
    return null;
  }
  final double? amount = double.tryParse(text);
  if (amount == null || !amount.isFinite) {
    return 'Enter a delivery fee as a number of pesos.';
  }
  if (amount < 0) {
    return 'A delivery fee cannot be negative.';
  }
  return null;
}
