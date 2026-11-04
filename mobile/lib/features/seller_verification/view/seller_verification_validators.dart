/// Client-side validation for the seller verification form.
///
/// The limits are declared here once and reused by both the validators and the
/// fields' `maxLength`, so the length a buyer can type and the length the
/// server accepts cannot drift apart. They mirror
/// `SubmitSellerVerificationRequest`; the server remains the authority, and
/// every one of these fields is still validated there.
///
/// A blank optional field is **valid**, not an error. `business_location` left
/// empty means "not provided", and the service omits the key entirely rather
/// than sending an empty string — an empty string is stored, and is not the same
/// thing to someone reading a review queue.
library;

/// The contract's `max` for `business_name`, `business_location` and
/// `id_document_ref`.
const int kSellerVerificationShortFieldMax = 255;

/// The contract's `max` for `business_description`.
const int kSellerVerificationDescriptionMax = 2000;

/// Snapshot limits match `users.phone` and `users.location`.
const int kSellerVerificationPhoneMax = 32;
const int kSellerVerificationAddressMax = 191;

/// Required verification phone snapshot, bounded to the profile field's limit.
String? validateVerificationPhone(String? value) => validateRequiredSnapshot(
  value,
  'Phone number',
  kSellerVerificationPhoneMax,
);

/// Required verification address snapshot, bounded to the profile field's limit.
String? validateVerificationAddress(String? value) =>
    validateRequiredSnapshot(value, 'Address', kSellerVerificationAddressMax);

String? validateRequiredSnapshot(String? value, String label, int maxLength) {
  final String trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return '$label is required.';
  }
  if (trimmed.length > maxLength) {
    return '$label must be $maxLength characters or fewer.';
  }
  return null;
}

/// `business_name` is optional, but bounded when given.
String? validateBusinessName(String? value) =>
    validateOptionalShortField(value, 'Business name');

/// `business_location` is optional, but bounded when given.
String? validateBusinessLocation(String? value) =>
    validateOptionalShortField(value, 'Business location');

/// `id_document_ref` is optional, but bounded when given.
///
/// A reference, not a document: a string the seller supplies, such as a document
/// number or their own reference code.
String? validateIdDocumentRef(String? value) =>
    validateOptionalShortField(value, 'ID document reference');

/// Optional fields share one length rule, named for the field in the message.
String? validateOptionalShortField(String? value, String label) {
  final String trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return null;
  }
  if (trimmed.length > kSellerVerificationShortFieldMax) {
    return '$label must be $kSellerVerificationShortFieldMax characters or '
        'fewer.';
  }
  return null;
}

/// `business_description` is optional, with a much larger bound.
String? validateBusinessDescription(String? value) {
  final String trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return null;
  }
  if (trimmed.length > kSellerVerificationDescriptionMax) {
    return 'Business description must be $kSellerVerificationDescriptionMax '
        'characters or fewer.';
  }
  return null;
}
