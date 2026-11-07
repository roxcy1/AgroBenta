import '../core/utils/json_utils.dart';

/// One approved livestock category, as served by `GET /livestock-types`.
///
/// The backend enum is the source of truth for both halves: [value] is the
/// lowercase string written to `listings.livestock_type`, and [label] is what a
/// person reads. The client never invents either.
class LivestockType {
  const LivestockType({
    required this.value,
    required this.label,
    this.breeds = const <String>[],
  });

  factory LivestockType.fromJson(Map<String, dynamic> json) {
    return LivestockType(
      value: readString(json, 'value'),
      label: readString(json, 'label'),
      breeds: readStringList(json, 'breeds'),
    );
  }

  /// The exact lowercase value stored on a listing, e.g. `cattle`.
  final String value;

  /// The display label, e.g. `Cattle`.
  final String label;

  /// The canonical breed values the price-suggestion provider accepts.
  ///
  /// The backend supplies this per category. An older backend that does not send
  /// the key yields an empty list, which keeps the catalog backward compatible.
  final List<String> breeds;

  /// A readable label for a canonical breed value.
  ///
  /// The API stores values such as `boholano_native_chicken`; this turns them
  /// into `Boholano Native Chicken` for display without inventing a second
  /// vocabulary.
  static String breedLabel(String value) {
    final List<String> words = value
        .trim()
        .split(RegExp(r'[_\s]+'))
        .where((String word) => word.isNotEmpty)
        .toList(growable: false);
    return words
        .map(
          (String word) =>
              '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  /// The canonical breed matching [raw], or `null` when it is not supported.
  ///
  /// Both the canonical slug and its display label are accepted, so a listing
  /// saved as `Broiler` or `broiler` opens with the same dropdown selection.
  static String? matchBreed(String raw, List<String> breeds) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final String slug = trimmed
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    for (final String breed in breeds) {
      if (breed == slug || breed.toLowerCase() == trimmed.toLowerCase()) {
        return breed;
      }
      if (breedLabel(breed).toLowerCase() == trimmed.toLowerCase()) {
        return breed;
      }
    }
    return null;
  }

  /// The label for a raw stored value, given the catalog.
  ///
  /// A supported value gets its server label. A value outside the catalog is
  /// historical data: it is shown exactly as stored, with `(unsupported)`
  /// appended so nobody mistakes it for an approved category. Before the
  /// catalog has loaded there is no way to know which values are approved, so
  /// the raw value is title-cased rather than guessed at.
  static String displayLabel(
    String raw, {
    List<LivestockType> catalog = const <LivestockType>[],
  }) {
    final String value = raw.trim();
    if (value.isEmpty) {
      return '';
    }
    for (final LivestockType type in catalog) {
      if (type.value == value) {
        return type.label;
      }
    }
    if (catalog.isEmpty) {
      return titleCase(value);
    }
    return '$value (unsupported)';
  }

  /// Whether [raw] is one of the approved values in [catalog].
  static bool isSupported(
    String raw, {
    List<LivestockType> catalog = const <LivestockType>[],
  }) {
    final String value = raw.trim();
    for (final LivestockType type in catalog) {
      if (type.value == value) {
        return true;
      }
    }
    return false;
  }

  /// A readable fallback for a value whose catalog is not available.
  ///
  /// Only capitalisation changes; the raw value is otherwise preserved.
  static String titleCase(String raw) {
    final String value = raw.trim();
    if (value.isEmpty) {
      return '';
    }
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  @override
  String toString() => 'LivestockType($value, $label, breeds: $breeds)';
}
