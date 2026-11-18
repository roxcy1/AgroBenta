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
/// Prices, ages and weights are held exactly as the user typed them and are
/// sent to the server as written. `IndexListingRequest` validates them with
/// `numeric` bounds, so the server is the authority on whether a value is
/// acceptable; parsing here to a `double` first would only add a second,
/// possibly-differing opinion. The `min*Amount`/`max*Amount` getters exist for
/// the one thing the client does need to decide for itself — whether a range is
/// inverted, which is a usability check, not a validation rule.
///
/// ## Multi-select
///
/// [livestockTypes] and [breeds] are lists because the filter screen offers
/// more than one. They hold the server's exact catalog values, never a
/// client-side label, so the query is a direct match on the stored column.
class ListingFilters {
  const ListingFilters({
    this.livestockTypes = const <String>[],
    this.breeds = const <String>[],
    this.gender = '',
    this.minAge = '',
    this.maxAge = '',
    this.minWeight = '',
    this.maxWeight = '',
    this.minPrice = '',
    this.maxPrice = '',
  });

  /// No filters applied.
  static const ListingFilters none = ListingFilters();

  /// Approved species values, in the server's exact lowercase spelling.
  final List<String> livestockTypes;

  /// Approved breed names, exactly as the catalog spells them.
  final List<String> breeds;

  /// `''` (any), `male` or `female`.
  final String gender;

  /// Lowest acceptable age in months, as typed. Empty means no lower bound.
  final String minAge;

  /// Highest acceptable age in months, as typed. Empty means no upper bound.
  final String maxAge;

  /// Lowest acceptable weight in kilograms, as typed.
  final String minWeight;

  /// Highest acceptable weight in kilograms, as typed.
  final String maxWeight;

  /// Lowest acceptable asking price, as typed. Empty means no lower bound.
  final String minPrice;

  /// Highest acceptable asking price, as typed. Empty means no upper bound.
  final String maxPrice;

  /// Whether any filter is set.
  bool get isActive =>
      livestockTypes.isNotEmpty ||
      breeds.isNotEmpty ||
      gender.trim().isNotEmpty ||
      minAge.trim().isNotEmpty ||
      maxAge.trim().isNotEmpty ||
      minWeight.trim().isNotEmpty ||
      maxWeight.trim().isNotEmpty ||
      minPrice.trim().isNotEmpty ||
      maxPrice.trim().isNotEmpty;

  /// How many filters are set, for the badge on the filter control.
  ///
  /// Counts fields, not values, so selecting five species still reads as one
  /// narrowing choice. A range with both bounds counts as two, matching the
  /// price badge the marketplace has always shown.
  int get activeCount {
    int count = 0;
    if (livestockTypes.isNotEmpty) {
      count++;
    }
    if (breeds.isNotEmpty) {
      count++;
    }
    if (gender.trim().isNotEmpty) {
      count++;
    }
    if (minAge.trim().isNotEmpty) {
      count++;
    }
    if (maxAge.trim().isNotEmpty) {
      count++;
    }
    if (minWeight.trim().isNotEmpty) {
      count++;
    }
    if (maxWeight.trim().isNotEmpty) {
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

  /// [minAge] as a number of months, or `null` when blank or not a number.
  double? get minAgeAmount => AppFormatters.parseDecimal(minAge);

  /// [maxAge] as a number of months, or `null` when blank or not a number.
  double? get maxAgeAmount => AppFormatters.parseDecimal(maxAge);

  /// [minWeight] as a number of kilograms, or `null` when blank or not a number.
  double? get minWeightAmount => AppFormatters.parseDecimal(minWeight);

  /// [maxWeight] as a number of kilograms, or `null` when blank or not a number.
  double? get maxWeightAmount => AppFormatters.parseDecimal(maxWeight);

  /// Whether the price range is the wrong way round, e.g. min 50000 / max 10000.
  bool get hasInvertedPriceRange => _isInverted(minPriceAmount, maxPriceAmount);

  /// Whether the age range is the wrong way round.
  bool get hasInvertedAgeRange => _isInverted(minAgeAmount, maxAgeAmount);

  /// Whether the weight range is the wrong way round.
  bool get hasInvertedWeightRange =>
      _isInverted(minWeightAmount, maxWeightAmount);

  static bool _isInverted(double? min, double? max) =>
      min != null && max != null && min > max;

  /// A short human summary for the filter control.
  ///
  /// Empty when nothing is applied, so the button can fall back to its own
  /// label instead of showing a meaningless summary.
  String get summary {
    final List<String> parts = <String>[];

    if (livestockTypes.isNotEmpty) {
      parts.add(_listSummary(livestockTypes));
    }
    if (breeds.isNotEmpty) {
      parts.add(_listSummary(breeds));
    }
    if (gender.trim().isNotEmpty) {
      parts.add(gender.trim() == 'male' ? 'Male' : 'Female');
    }

    final String? age = _unitRange(minAgeAmount, maxAgeAmount, 'months');
    if (age != null) {
      parts.add(age);
    }

    final String? weight = _unitRange(minWeightAmount, maxWeightAmount, 'kg');
    if (weight != null) {
      parts.add(weight);
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

  static String _listSummary(List<String> values) => values.length == 1
      ? values.first
      : '${values.first} +${values.length - 1}';

  static String? _unitRange(double? min, double? max, String unit) {
    if (min == null && max == null) {
      return null;
    }
    if (min != null && max != null) {
      return '${_formatNumber(min)}–${_formatNumber(max)} $unit';
    }
    if (min != null) {
      return '${_formatNumber(min)}+ $unit';
    }
    return 'up to ${_formatNumber(max!)} $unit';
  }

  /// Drops a trailing `.0` so a whole month or kilogram reads as a person typed it.
  static String _formatNumber(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  /// A copy with the given fields replaced. A `null` argument keeps the current
  /// value; pass an empty list or `''` to clear a field.
  ListingFilters copyWith({
    List<String>? livestockTypes,
    List<String>? breeds,
    String? gender,
    String? minAge,
    String? maxAge,
    String? minWeight,
    String? maxWeight,
    String? minPrice,
    String? maxPrice,
  }) {
    return ListingFilters(
      livestockTypes: livestockTypes ?? this.livestockTypes,
      breeds: breeds ?? this.breeds,
      gender: gender ?? this.gender,
      minAge: minAge ?? this.minAge,
      maxAge: maxAge ?? this.maxAge,
      minWeight: minWeight ?? this.minWeight,
      maxWeight: maxWeight ?? this.maxWeight,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
    );
  }

  /// Returns filters with every field cleared, for the "Clear" action.
  ListingFilters cleared() => ListingFilters.none;

  /// Prunes breeds that are incompatible with the given livestock types.
  ///
  /// When animal types change (e.g., switching from Cattle to Goat via category
  /// chips or Home shortcuts), previously selected breeds that are not compatible
  /// with the new animal type are automatically removed.
  ///
  /// [livestockTypes] are the currently selected animal types from the catalog.
  /// If empty, all breeds are kept (no pruning needed).
  ListingFilters pruneIncompatibleBreeds(List<String> livestockTypes) {
    if (livestockTypes.isEmpty) return this;

    // Keep only breeds that are compatible with at least one current livestock type
    final List<String> filteredBreeds = breeds.where((breed) {
      final lowerBreed = breed.toLowerCase();
      // Check if breed matches any of the current livestock types
      return livestockTypes.any(
        (type) => type.toLowerCase().contains(lowerBreed),
      );
    }).toList();

    return copyWith(breeds: filteredBreeds.isEmpty ? [] : filteredBreeds);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListingFilters &&
          _sameValues(other.livestockTypes, livestockTypes) &&
          _sameValues(other.breeds, breeds) &&
          other.gender == gender &&
          other.minAge == minAge &&
          other.maxAge == maxAge &&
          other.minWeight == minWeight &&
          other.maxWeight == maxWeight &&
          other.minPrice == minPrice &&
          other.maxPrice == maxPrice;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(<String>[...livestockTypes]..sort()),
    Object.hashAll(<String>[...breeds]..sort()),
    gender,
    minAge,
    maxAge,
    minWeight,
    maxWeight,
    minPrice,
    maxPrice,
  );

  /// Whether two selections hold the same values, regardless of order.
  ///
  /// The server matches a set (`whereIn`), so selection order is a UI detail.
  /// Treating it as a difference would make a re-apply of the same selection
  /// fire a duplicate request.
  static bool _sameValues(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }

    final List<String> left = <String>[...a]..sort();
    final List<String> right = <String>[...b]..sort();

    for (int i = 0; i < left.length; i++) {
      if (left[i] != right[i]) {
        return false;
      }
    }

    return true;
  }

  @override
  String toString() =>
      'ListingFilters(livestockTypes: $livestockTypes, breeds: $breeds, '
      'gender: "$gender", minAge: "$minAge", maxAge: "$maxAge", '
      'minWeight: "$minWeight", maxWeight: "$maxWeight", '
      'minPrice: "$minPrice", maxPrice: "$maxPrice")';
}
