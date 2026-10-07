/// Client-side validation for the seller listing form.
///
/// These rules exist to give immediate feedback on a field the app can judge on
/// its own, and they deliberately **mirror the contract** rather than extending
/// it. A rule here that the server does not have would let a seller fill in
/// something that is then rejected, and a rule missing here would mean a pointless
/// round trip for something the client could have caught — so neither is useful.
///
/// The bounds are the contract's, with the column ranges folded in for the two
/// decimal fields: `asking_price` is `decimal(14,2)` and `weight_value` is
/// `decimal(10,2)`, so a value beyond those cannot be stored and is reported here
/// rather than as a database error.
library;

/// Maximum length for the short free-text fields, matching the server's
/// `max:255`.
const int kListingShortFieldMax = 255;

/// Maximum length for the free-text notes, matching the server's `max:2000`.
const int kListingNotesMax = 2000;

/// The largest `asking_price` a `decimal(14,2)` can hold.
const String kListingMaxAskingPrice = '99999999999.99';

/// The largest `weight_value` a `decimal(10,2)` can hold.
const String kListingMaxWeightValue = '99999999.99';

/// Validates the required species field.
String? validateLivestockType(String? value) {
  final String trimmed = (value ?? '').trim();
  if (trimmed.isEmpty) {
    return 'Enter the type of livestock.';
  }
  if (trimmed.length > kListingShortFieldMax) {
    return 'Use at most $kListingShortFieldMax characters.';
  }
  return null;
}

/// Validates the required free-text location field.
String? validateListingLocation(String? value) {
  final String trimmed = (value ?? '').trim();
  if (trimmed.isEmpty) {
    return 'Enter the location.';
  }
  if (trimmed.length > kListingShortFieldMax) {
    return 'Use at most $kListingShortFieldMax characters.';
  }
  return null;
}

/// Validates the optional breed field.
String? validateBreed(String? value) {
  final String trimmed = (value ?? '').trim();
  if (trimmed.length > kListingShortFieldMax) {
    return 'Use at most $kListingShortFieldMax characters.';
  }
  return null;
}

/// Validates the asking price.
///
/// A plain non-negative number. Commas, a currency symbol and spaces are all
/// refused rather than stripped, because silently reformatting what a seller
/// typed is how a price ends up different from what they read on screen. The
/// field's own `keyboardType` already discourages them.
String? validateAskingPrice(String? value) {
  final String trimmed = (value ?? '').trim();
  if (trimmed.isEmpty) {
    return 'Enter the asking price.';
  }
  if (!_isPlainDecimal(trimmed)) {
    return 'Enter a number, for example 42500 or 42500.50.';
  }
  if (double.tryParse(trimmed)! < 0) {
    return 'The price cannot be negative.';
  }
  if (double.tryParse(trimmed)! > double.parse(kListingMaxAskingPrice)) {
    return 'That price is too large.';
  }
  return null;
}

/// Validates the quantity, which the contract holds to `integer, min:1`.
String? validateQuantity(String? value) {
  final String trimmed = (value ?? '').trim();
  if (trimmed.isEmpty) {
    return 'Enter how many head are available.';
  }
  final int? amount = int.tryParse(trimmed);
  if (amount == null) {
    return 'Enter a whole number.';
  }
  if (amount < 1) {
    return 'At least one animal must be available.';
  }
  return null;
}

/// Validates the age magnitude, which the contract holds to `integer, min:0`.
///
/// A whole number even though the column is `decimal(5,1)`: the contract is what
/// a client is held to, and a fractional age in months is not something the
/// field can express meaningfully.
String? validateAgeValue(String? value) {
  final String trimmed = (value ?? '').trim();
  if (trimmed.isEmpty) {
    return null; // Optional, and only together with a unit.
  }
  final int? amount = int.tryParse(trimmed);
  if (amount == null) {
    return 'Enter a whole number, for example 18.';
  }
  if (amount < 0) {
    return 'The age cannot be negative.';
  }
  return null;
}

/// Validates the age unit, which is required whenever an age is given.
///
/// The counterpart to [validateAgeValue]: a magnitude with no unit is not
/// something anybody can read, so the pair is checked in the form as well as
/// server-side.
String? validateAgeUnit(String? value, {required bool hasValue}) {
  if (!hasValue) {
    return null;
  }
  if (value == null || value.isEmpty) {
    return 'Choose a unit for the age.';
  }
  return null;
}

/// Validates the weight magnitude, which the contract holds to `numeric, min:0`.
String? validateWeightValue(String? value) {
  final String trimmed = (value ?? '').trim();
  if (trimmed.isEmpty) {
    return null; // Optional, and only together with a unit.
  }
  if (!_isPlainDecimal(trimmed)) {
    return 'Enter a number, for example 320 or 320.5.';
  }
  if (double.tryParse(trimmed)! < 0) {
    return 'The weight cannot be negative.';
  }
  if (double.tryParse(trimmed)! > double.parse(kListingMaxWeightValue)) {
    return 'That weight is too large.';
  }
  return null;
}

/// Validates the weight unit, which is required whenever a weight is given.
String? validateWeightUnit(String? value, {required bool hasValue}) {
  if (!hasValue) {
    return null;
  }
  if (value == null || value.isEmpty) {
    return 'Choose a unit for the weight.';
  }
  return null;
}

/// Validates an optional single-line free-text field.
String? validateOptionalShortText(String? value) {
  final String trimmed = (value ?? '').trim();
  if (trimmed.length > kListingShortFieldMax) {
    return 'Use at most $kListingShortFieldMax characters.';
  }
  return null;
}

/// Validates the optional free-text notes.
String? validateAdditionalNotes(String? value) {
  final String trimmed = (value ?? '').trim();
  if (trimmed.length > kListingNotesMax) {
    return 'Use at most $kListingNotesMax characters.';
  }
  return null;
}

/// Whether [value] is a plain decimal number.
///
/// Accepts an optional sign-free integer or decimal with at most one decimal
/// point, and **rejects** anything a seller would not expect to be read as one
/// number: thousands separators, a currency symbol, scientific notation, or
/// leading/trailing junk. `double.tryParse` accepts several of those, which is
/// why it is not the whole test.
bool _isPlainDecimal(String value) {
  return RegExp(r'^\d+(\.\d+)?$').hasMatch(value);
}
