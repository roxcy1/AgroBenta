/// Input formatters for the seller listing form.
///
/// These stop an unparseable value at the keyboard, before a validator has to
/// reject it on save. They are a convenience, not the rule: the validators in
/// `seller_listing_validators.dart` and the API remain the authority.
///
/// Both formatters **reject** an edit that would make the field invalid and
/// leave the previous value in place. They deliberately do not use
/// `FilteringTextInputFormatter`, which *strips* the offending characters: a
/// paste of `12a` would silently become `12`, which is not what the seller
/// typed, and a paste of `1.234` would become `1.23` — a different amount read
/// as if it were theirs.
library;

import 'package:flutter/services.dart';

/// Accepts only ASCII digits.
///
/// Used by Age and Quantity, which the contract holds to integers. An empty
/// value is allowed so the field can be cleared.
class DigitsOnlyInputFormatter extends TextInputFormatter {
  const DigitsOnlyInputFormatter();

  static final RegExp _digits = RegExp(r'^[0-9]*$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return _digits.hasMatch(newValue.text) ? newValue : oldValue;
  }
}

/// Accepts a plain non-negative decimal with at most [maxDecimalPlaces] decimal
/// places.
///
/// Used by Weight and Asking Price, whose columns are `decimal(10,2)` and
/// `decimal(14,2)`. A third decimal is refused outright rather than rounded, so
/// the number the seller sees is the number that is stored.
///
/// A trailing decimal point (`12.`) is allowed while typing — otherwise the
/// seller could never reach the fractional part — and the validator rejects it
/// on save if they leave it there.
class DecimalInputFormatter extends TextInputFormatter {
  const DecimalInputFormatter({this.maxDecimalPlaces = 2});

  /// How many digits may follow the decimal point.
  final int maxDecimalPlaces;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String text = newValue.text;
    if (text.isEmpty) {
      return newValue;
    }
    final RegExp pattern = RegExp('^[0-9]+(\\.[0-9]{0,$maxDecimalPlaces})?\$');
    return pattern.hasMatch(text) ? newValue : oldValue;
  }
}
