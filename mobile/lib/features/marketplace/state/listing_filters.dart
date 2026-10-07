import '../../../core/utils/app_formatters.dart';

/// The buyer's filter selection, as a value.
///
/// Immutable and comparable so the controller can answer "has anything actually
/// changed?" and skip a request when the user re-applies the same filters. That
/// matters: every re-apply is a network round trip, and firing one for an
/// identical selection is the duplicate-call problem `mobile/DESIGN.md` warns
/// about.
///
/// ## Values stay as strings
///
/// Prices are held exactly as the user typed them and are sent to the server as
/// written. `IndexListingRequest` validates `min_price`/`max_price` with
/// `numeric,min:0`, so the server is the authority on whether a value is
/// acceptable; parsing here to a `double` first would only add a second,
/// possibly-differing opinion. [minPriceAmount] and [maxPriceAmount] exist for
/// the one thing the client does need to decide for itself — whether a range
/// is inverted, which is a usability check, not a validation rule.
class ListingFilters {
  const ListingFilters({
    this.livestockType = '',
    this.location = '',
    this.minPrice = '',
    this.maxPrice = '',
  });

  /// No filters applied.
  static const ListingFilters none = ListingFilters();

  /// Seller-entered species, free text.
  ///
  /// This is a text field and not a picker of chips or a dropdown for a reason:
  /// `listings.livestock_type` is a plain string, is matched exactly by the
  /// server, and must not become an enum without approval (functional
  /// documentation §4.1). A controlled vocabulary is a desirable open item
  /// (**OQ-04**) and is not this app's to invent. Offering "Cattle / Goat /
  /// Sheep" would be a guess about seller vocabulary, and a wrong guess makes
  /// the filter silently return nothing.
  final String livestockType;

  /// Seller-entered location, free text.
  ///
  /// `listings.location` is a plain string that the server matches exactly, the
  /// same way as [livestockType] — so this is a text field too, until a
  /// controlled vocabulary exists (**OQ-04**). Anything else would be a guess
  /// about seller wording that a buyer cannot see.
  final String location;

  /// Lowest acceptable asking price, as typed. Empty means no lower bound.
  final String minPrice;

  /// Highest acceptable asking price, as typed. Empty means no upper bound.
  final String maxPrice;

  /// Whether any filter is set.
  bool get isActive =>
      livestockType.trim().isNotEmpty ||
      location.trim().isNotEmpty ||
      minPrice.trim().isNotEmpty ||
      maxPrice.trim().isNotEmpty;

  /// How many filters are set, for the badge on the filter control.
  ///
  /// Counts fields, not the filter as a whole, so a buyer who can see at a
  /// glance that two things are narrowing the results is not left guessing why
  /// the list is short.
  int get activeCount {
    int count = 0;
    if (livestockType.trim().isNotEmpty) {
      count++;
    }
    if (location.trim().isNotEmpty) {
      count++;
    }
    if (minPrice.trim().isNotEmpty) {
      count++;
    }
    if (maxPrice.trim().isNotEmpty) {
      count++;
    }
    return count;
  }

  /// [minPrice] as a number, or `null` when blank or not a number.
  double? get minPriceAmount => AppFormatters.parseDecimal(minPrice);

  /// [maxPrice] as a number, or `null` when blank or not a number.
  double? get maxPriceAmount => AppFormatters.parseDecimal(maxPrice);

  /// Whether the range is the wrong way round, e.g. min 50000 / max 10000.
  ///
  /// Checked before sending so the user gets an explanation rather than a
  /// `422`, and so the filters are not applied at all.
  bool get hasInvertedPriceRange {
    final double? min = minPriceAmount;
    final double? max = maxPriceAmount;
    if (min == null || max == null) {
      return false;
    }
    return min > max;
  }

  /// A short human summary for the filter control, e.g. `Cattle · Pampanga`.
  ///
  /// Empty when nothing is applied, so the button can fall back to its own
  /// label instead of showing a meaningless summary.
  String get summary {
    final List<String> parts = <String>[];

    final String type = livestockType.trim();
    if (type.isNotEmpty) {
      parts.add(type);
    }

    final String locationText = location.trim();
    if (locationText.isNotEmpty) {
      parts.add(locationText);
    }

    final double? min = minPriceAmount;
    final double? max = maxPriceAmount;
    if (min != null && max != null) {
      final String low = AppFormatters.formatMoneyCompact(min.toString()) ?? '';
      final String high =
          AppFormatters.formatMoneyCompact(max.toString()) ?? '';
      parts.add('$low – $high');
    } else if (min != null) {
      parts.add('${AppFormatters.formatMoneyCompact(min.toString()) ?? ''}+');
    } else if (max != null) {
      parts.add(
        'up to ${AppFormatters.formatMoneyCompact(max.toString()) ?? ''}',
      );
    }

    return parts.join(' · ');
  }

  /// A copy with the given fields replaced. Blank [clear] arguments are ignored,
  /// so callers only name what they are changing.
  ListingFilters copyWith({
    String? livestockType,
    String? location,
    String? minPrice,
    String? maxPrice,
  }) {
    return ListingFilters(
      livestockType: livestockType ?? this.livestockType,
      location: location ?? this.location,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
    );
  }

  /// Returns filters with every field cleared, for the "Clear" action.
  ListingFilters cleared() => ListingFilters.none;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListingFilters &&
          other.livestockType == livestockType &&
          other.location == location &&
          other.minPrice == minPrice &&
          other.maxPrice == maxPrice;

  @override
  int get hashCode => Object.hash(livestockType, location, minPrice, maxPrice);

  @override
  String toString() =>
      'ListingFilters(livestockType: "$livestockType", location: "$location", '
      'minPrice: "$minPrice", maxPrice: "$maxPrice")';
}
