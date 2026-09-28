import 'package:intl/intl.dart';

/// Display formatting for the values the marketplace shows.
///
/// Centralised deliberately. `listings` has **no currency column** and none is
/// to be added (functional documentation §11), so amounts are stored exactly as
/// the seller typed them and the client chooses how to present them. The Admin
/// Web formats as `₱` / `en-PH`; this is the mobile equivalent, and it lives in
/// one place so that being told the currency is wrong is a one-line change
/// rather than a sweep through every screen.
///
/// ## Money
///
/// `asking_price` is a `decimal(14,2)` and the API serialises it as a **string**
/// (`"42500.00"`). It is parsed to a [double] only here, at the display edge,
/// and never round-tripped through the model — `mobile/AGENTS.md` §B is explicit
/// that the model keeps money as a `String`.
///
/// [formatMoney] is therefore total, not partial: it never throws and never
/// shows `NaN`, because a malformed amount must not take down a list of
/// otherwise-valid listings. A value that cannot be parsed falls back to the
/// raw text so a seller-entered figure is still visible to a buyer.
abstract final class AppFormatters {
  /// Peso, grouped, with two decimals. `42500.0` renders as `₱42,500.00`.
  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  /// Compact money for the card, where horizontal room is scarce.
  ///
  /// `42500.0` renders as `₱42,500`. Cards show the figure, not the cents;
  /// the detail screen shows the exact amount.
  static final NumberFormat _moneyCompact = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 0,
  );

  static final DateFormat _date = DateFormat('d MMM yyyy', 'en_PH');
  static final DateFormat _dateTime = DateFormat('d MMM yyyy, h:mm a', 'en_PH');

  /// Formats a decimal string for prominent display, e.g. `₱42,500.00`.
  ///
  /// Returns `null` when [raw] is null or blank so a caller can decide between
  /// showing nothing and showing a placeholder. Returns the trimmed input
  /// unchanged when it is not a number, which keeps an unexpected value visible
  /// instead of silently rendering `₱0.00`.
  static String? formatMoney(String? raw) => _formatMoney(raw, _money);

  /// Formats a decimal string for a card, e.g. `₱42,500`.
  static String? formatMoneyCompact(String? raw) =>
      _formatMoney(raw, _moneyCompact);

  /// Parses a decimal string to a number, or `null` if it is not one.
  ///
  /// Exposed for the two places that genuinely need arithmetic — sorting a
  /// locally-known page, or validating a price filter's bounds before it is
  /// sent. Never use this to re-format money for display; use [formatMoney].
  static double? parseDecimal(String? raw) {
    if (raw == null) {
      return null;
    }
    return double.tryParse(raw.trim());
  }

  /// Formats a timestamp as a date, e.g. `20 Sep 2026`.
  static String formatDate(DateTime? value) =>
      value == null ? '' : _date.format(value);

  /// Formats a timestamp as a date and time, e.g. `20 Sep 2026, 4:12 PM`.
  static String formatDateTime(DateTime? value) =>
      value == null ? '' : _dateTime.format(value);

  /// A short relative description of when something was posted.
  ///
  /// "Just now", "3 hours ago", "2 days ago" answers the question a buyer is
  /// actually asking about a listing far more usefully than a date, and it
  /// degrades to an absolute date beyond a week, where "34 days ago" stops
  /// helping.
  static String formatRelative(DateTime? value, {DateTime? now}) {
    if (value == null) {
      return '';
    }

    final DateTime reference = now ?? DateTime.now();
    final Duration elapsed = reference.difference(value);

    if (elapsed.isNegative || elapsed.inMinutes < 1) {
      return 'Just now';
    }
    if (elapsed.inHours < 1) {
      final int minutes = elapsed.inMinutes;
      return '$minutes minute${minutes == 1 ? '' : 's'} ago';
    }
    if (elapsed.inHours < 24) {
      final int hours = elapsed.inHours;
      return '$hours hour${hours == 1 ? '' : 's'} ago';
    }
    if (elapsed.inDays < 7) {
      final int days = elapsed.inDays;
      return '$days day${days == 1 ? '' : 's'} ago';
    }
    return _date.format(value);
  }

  static String? _formatMoney(String? raw, NumberFormat formatter) {
    if (raw == null) {
      return null;
    }

    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final double? amount = double.tryParse(trimmed);
    if (amount == null) {
      // Not a number. Show what the server sent rather than inventing ₱0.00.
      return trimmed;
    }

    return formatter.format(amount);
  }
}
