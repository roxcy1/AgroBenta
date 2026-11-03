import '../core/utils/json_utils.dart';

/// One approved livestock category, as served by `GET /livestock-types`.
///
/// The backend enum is the source of truth for both halves: [value] is the
/// lowercase string written to `listings.livestock_type`, and [label] is what a
/// person reads. The client never invents either.
class LivestockType {
  const LivestockType({required this.value, required this.label});

  factory LivestockType.fromJson(Map<String, dynamic> json) {
    return LivestockType(
      value: readString(json, 'value'),
      label: readString(json, 'label'),
    );
  }

  /// The exact lowercase value stored on a listing, e.g. `cattle`.
  final String value;

  /// The display label, e.g. `Cattle`.
  final String label;

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
  String toString() => 'LivestockType($value, $label)';
}
