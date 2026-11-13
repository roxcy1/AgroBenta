/// Pure validation for the inquire form.
///
/// Kept out of the widget so the rule is testable without a `BuildContext`,
/// and so the server's per-field message can be layered on afterwards by the
/// screen (`validateInquiryMessage(v) ?? state.errorFor('message')`) instead of
/// the two sources being entangled in a closure.
///
/// The rule mirrors `StoreInquiryRequest` on the backend: `message` is
/// optional and at most 500 characters, while `payment_method` and
/// `collection_method` remain required.
library;

import '../../../models/inquiry.dart';

/// The server's `max:500` on `message`, duplicated so the client's counter and
/// its validator agree with the rule that will actually reject the request.
const int kInquiryMessageMax = 500;

/// Optional, at most [kInquiryMessageMax] characters.
///
/// An empty field is valid: the interest form records the structured
/// preferences and does not require prose. Whitespace-only input is treated as
/// empty by the service layer rather than shown as an error.
String? validateInquiryMessage(String? value) {
  final String text = value ?? '';
  if (text.length > kInquiryMessageMax) {
    return 'A message may be at most $kInquiryMessageMax characters.';
  }
  return null;
}

/// Required: the buyer must choose how they prefer to pay.
///
/// Mirrors the server's `required` on `payment_method`; the screen shows the
/// message beside the preference cards, not in a banner.
String? validateInquiryPaymentMethod(InquiryPaymentMethod? value) {
  if (value == null) {
    return 'Please choose a preferred payment method.';
  }
  return null;
}

/// Required: the buyer must choose how they plan to collect the livestock.
///
/// Mirrors the server's `required` on `collection_method`.
String? validateInquiryCollectionMethod(InquiryCollectionMethod? value) {
  if (value == null) {
    return 'Please choose a preferred collection method.';
  }
  return null;
}

/// Optional: the buyer may leave the collection date unanswered.
String? validateInquiryCollectionDateOption(
  InquiryCollectionDateOption? value,
) {
  return null;
}

/// Validates the preferred collection date when [option] is `specificDate`
/// or `nextFewDays`.
///
/// A specific date is required and must not be in the past. `nextFewDays`
/// requires a date between tomorrow and three days from today. Relative
/// options (`thisWeek`) do not require a date, so this returns `null` for
/// them even when [date] is null.
String? validateInquiryPreferredDate(
  InquiryCollectionDateOption? option,
  DateTime? date,
) {
  if (option == null) {
    return null;
  }
  final DateTime today = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  final DateTime tomorrow = today.add(const Duration(days: 1));
  final DateTime day3 = today.add(const Duration(days: 3));

  if (date == null) {
    if (option == InquiryCollectionDateOption.specificDate) {
      return 'Please choose a collection date.';
    }
    if (option == InquiryCollectionDateOption.nextFewDays) {
      return 'Please choose a collection date.';
    }
    return null;
  }

  final DateTime selected = DateTime(date.year, date.month, date.day);

  if (option == InquiryCollectionDateOption.specificDate) {
    if (selected.isBefore(today)) {
      return 'The collection date cannot be in the past.';
    }
  } else if (option == InquiryCollectionDateOption.nextFewDays) {
    if (selected.isBefore(tomorrow) || selected.isAfter(day3)) {
      return 'The collection date must be between tomorrow and three days from today.';
    }
  }
  return null;
}
