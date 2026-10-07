/// Defensive JSON reading helpers shared by API models.
///
/// The Admin Web's TypeScript types make several optimistic assumptions about
/// the API that the Laravel implementation does not guarantee. In Dart those
/// assumptions fail loudly, which is the behaviour we want — but they should
/// fail with a message that names the offending field rather than with a bare
/// `type 'X' is not a subtype of type 'Y'`.
///
/// ## Conventions these helpers exist to enforce
///
/// * **Identifiers are integers.** Every `id` in the schema is an
///   auto-increment `bigint`. The one exception is the Laravel `notifications`
///   table, whose primary key is a UUID *string* — do not route that through
///   [readInt].
/// * **Money arrives as a decimal string.** `Listings.asking_price` and
///   `Transactions.total_amount` are `decimal` columns serialised as strings
///   (`"12500.00"`). Use [readDecimalString]; parse to a numeric type only in
///   the formatting layer.
/// * **Dates arrive as ISO-8601 UTC strings.** Use [readDateTime] so parsing
///   happens in exactly one place per model.
/// * **Nullable columns are `null`, not absent.** [readNullableString]
///   tolerates both.
library;

/// Reads a required non-empty string.
String readString(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is String) {
    return value;
  }
  throw FormatException(
    'Expected field "$key" to be a String, got ${value.runtimeType}.',
    json.toString(),
  );
}

/// Reads a required string that may legitimately be empty.
String readStringOrEmpty(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is String) {
    return value;
  }
  throw FormatException(
    'Expected field "$key" to be a String, got ${value.runtimeType}.',
    json.toString(),
  );
}

/// Reads a required nullable string, treating an absent key as `null`.
String? readNullableString(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value == null || value is String) {
    return value as String?;
  }
  throw FormatException(
    'Expected field "$key" to be a String or null, got ${value.runtimeType}.',
    json.toString(),
  );
}

/// Reads a required integer identifier.
int readInt(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is int) {
    return value;
  }
  // Tolerate a numeric string, which is what some drivers emit for bigint.
  if (value is String) {
    final int? parsed = int.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw FormatException(
    'Expected field "$key" to be an int, got ${value.runtimeType}.',
    json.toString(),
  );
}

/// Reads a required nullable integer.
int? readNullableInt(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value == null || value is int) {
    return value as int?;
  }
  if (value is String) {
    return int.tryParse(value);
  }
  throw FormatException(
    'Expected field "$key" to be an int or null, got ${value.runtimeType}.',
    json.toString(),
  );
}

/// Reads a required decimal column, which the API serialises as a string.
///
/// Returns the raw string so the value is not silently rounded through a
/// binary floating-point representation. Convert at the formatting layer.
String readDecimalString(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is String) {
    return value;
  }
  // Tolerate a JSON number in case a resource ever changes shape.
  if (value is num) {
    return value.toString();
  }
  throw FormatException(
    'Expected field "$key" to be a decimal string, got ${value.runtimeType}.',
    json.toString(),
  );
}

/// Reads a required ISO-8601 timestamp and converts it to a local [DateTime].
DateTime readDateTime(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is String) {
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed.toLocal();
    }
  }
  throw FormatException(
    'Expected field "$key" to be an ISO-8601 timestamp string.',
    json.toString(),
  );
}

/// Reads a required nullable ISO-8601 timestamp.
DateTime? readNullableDateTime(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    return DateTime.tryParse(value)?.toLocal();
  }
  throw FormatException(
    'Expected field "$key" to be an ISO-8601 timestamp string or null, '
    'got ${value.runtimeType}.',
    json.toString(),
  );
}

/// Casts a JSON value to a nested object map, or `null`.
///
/// Guards against a nested resource arriving as a list or a scalar, which
/// would otherwise surface as an unhelpful cast error deep in a model.
Map<String, dynamic>? readNullableObject(
  Map<String, dynamic> json,
  String key,
) {
  final Object? value = json[key];
  if (value == null) {
    return null;
  }
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  throw FormatException(
    'Expected field "$key" to be an object or null, got ${value.runtimeType}.',
    json.toString(),
  );
}

/// Casts a JSON value to a required nested object map.
///
/// Use this for an embedded resource that the API always sends — a listing's
/// `seller`, for instance. The counterpart of [readNullableObject]: `null` or a
/// non-object here is a contract change, so it throws rather than being papered
/// over with a null the UI would then have to render.
Map<String, dynamic> readObject(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  throw FormatException(
    'Expected field "$key" to be an object, got ${value.runtimeType}.',
    json.toString(),
  );
}

/// Casts a JSON value to a list of strings.
///
/// An absent key or an explicit `null` yields an empty list, because a JSON
/// column that holds nothing is a legitimate state and the client should not
/// have to distinguish "absent" from "empty". Used for `listings.photos`.
///
/// A non-string entry is a contract change and throws: the resource normalises
/// photos to a list of strings, so anything else means the shape moved, and
/// silently dropping entries would hide a listing photo the seller uploaded.
List<String> readStringList(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value == null) {
    return const <String>[];
  }
  if (value is List) {
    return value
        .map((Object? item) {
          if (item is String) {
            return item;
          }
          throw FormatException(
            'Expected every item in "$key" to be a String, got ${item.runtimeType}.',
            json.toString(),
          );
        })
        .toList(growable: false);
  }
  throw FormatException(
    'Expected field "$key" to be a list of strings, got ${value.runtimeType}.',
    json.toString(),
  );
}

/// Casts a JSON value to a list of objects.
///
/// An absent key yields an empty list rather than throwing, so a list endpoint
/// that legitimately returns no records does not need a special case.
List<Map<String, dynamic>> readObjectList(
  Map<String, dynamic> json,
  String key,
) {
  final Object? value = json[key];
  if (value == null) {
    return const <Map<String, dynamic>>[];
  }
  if (value is List) {
    return value
        .map(
          (Object? item) => item is Map
              ? item.cast<String, dynamic>()
              : throw FormatException(
                  'Expected every item in "$key" to be an object.',
                  json.toString(),
                ),
        )
        .toList(growable: false);
  }
  throw FormatException(
    'Expected field "$key" to be a list, got ${value.runtimeType}.',
    json.toString(),
  );
}
