import '../core/utils/json_utils.dart';

/// A listing's publication status, as stored in `listings.status`.
///
/// Serialised by `backend/app/Enums/ListingStatus.php` and surfaced verbatim by
/// `MobileListingResource`.
///
/// **The buyer marketplace only ever returns [active].** The server restricts
/// the browse query to `active` ([D-02] rule 9) and rejects a `status` query
/// parameter with a 422, so `draft`, `pending`, `sold` and `inactive` cannot
/// appear in a list response. They are modelled anyway because the detail
/// endpoint can legitimately return a non-active listing to **its owner**, and
/// because a status the client does not recognise is a contract change that
/// must fail loudly rather than render as an unknown chip.
enum ListingStatus {
  /// The seller's own unfinished work. Private to the seller.
  draft('draft'),

  /// Submitted for review. Not yet approved, so not in the marketplace.
  pending('pending'),

  /// Approved and visible in the buyer marketplace. The only status a buyer
  /// normally sees.
  active('active'),

  /// No longer available: the sale completed. Terminal.
  sold('sold'),

  /// Removed from sale, either rejected in review or deactivated by an
  /// administrator. There is no path back to [active] under [D-02].
  inactive('inactive');

  const ListingStatus(this.value);

  /// The exact lowercase string the API sends.
  final String value;

  /// Parses the API value, failing loudly on an unknown one.
  static ListingStatus fromValue(String value) {
    for (final ListingStatus status in ListingStatus.values) {
      if (status.value == value) {
        return status;
      }
    }
    throw FormatException('Unknown listing status "$value".');
  }
}

/// The marketplace-safe seller projection.
///
/// Mirrors `backend/app/Http/Resources/MobileSellerResource.php` exactly: `id`
/// and `name`, nothing else.
///
/// There is deliberately **no `email`**. Marketplace browsing must not harvest
/// seller contact details (functional documentation §10.4, contract §8.1), and
/// the Admin Web's `ListingResource` — which does embed `seller.email` — is an
/// administrator projection that is not reused here. A seller who wants to be
/// contacted does so through a future feature; until then, this is all the
/// marketplace discloses.
class ListingSeller {
  const ListingSeller({required this.id, required this.name});

  factory ListingSeller.fromJson(Map<String, dynamic> json) {
    return ListingSeller(
      id: readInt(json, 'id'),
      name: readString(json, 'name'),
    );
  }

  /// `users.id`.
  final int id;

  /// The seller's display name.
  final String name;

  @override
  String toString() => 'ListingSeller($id, $name)';
}

/// One livestock listing, as the buyer marketplace returns it.
///
/// Mirrors `backend/app/Http/Resources/MobileListingResource.php` field for
/// field. No field is invented and none is omitted, with two deliberate
/// omissions from the contract's example shape:
///
///  * **`price_suggestion`** is absent. Whether a buyer may see an estimate is
///    still undecided (D-13 / OQ-03) and no estimator exists (GAP-10), so
///    modelling a nullable key would encode an answer nobody has given.
///  * **`seller_id`** is absent. Ownership is server-owned (functional
///    documentation §10.1) and the resource does not expose it. The seller
///    arrives as the narrowed [ListingSeller] projection instead.
///
/// ## Decimal fields
///
/// `asking_price`, `age_value` and `weight_value` are all `decimal` columns
/// with no cast on the Eloquent model, so **MySQL returns them as JSON
/// strings** (`"42500.00"`, `"18.0"`) while SQLite — which the test suite runs
/// on — returns native numbers. Both arrive here as `String` via
/// [readDecimalString], which tolerates either, so the client behaves
/// identically against production and against a test double. Money is formatted
/// once, in `AppFormatters`; do not parse it for display.
class Listing {
  const Listing({
    required this.id,
    required this.seller,
    required this.livestockType,
    required this.breed,
    required this.ageValue,
    required this.ageUnit,
    required this.gender,
    required this.weightValue,
    required this.weightUnit,
    required this.quantity,
    required this.askingPrice,
    required this.location,
    required this.healthStatus,
    required this.vaccination,
    required this.shortDescription,
    required this.additionalNotes,
    required this.photos,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Listing.fromJson(Map<String, dynamic> json) {
    return Listing(
      id: readInt(json, 'id'),
      seller: ListingSeller.fromJson(readObject(json, 'seller')),
      livestockType: readString(json, 'livestock_type'),
      breed: readString(json, 'breed'),
      ageValue: _readNullableDecimal(json, 'age_value'),
      ageUnit: readNullableString(json, 'age_unit'),
      gender: readNullableString(json, 'gender'),
      weightValue: _readNullableDecimal(json, 'weight_value'),
      weightUnit: readString(json, 'weight_unit'),
      quantity: readInt(json, 'quantity'),
      askingPrice: readDecimalString(json, 'asking_price'),
      location: readString(json, 'location'),
      healthStatus: readNullableString(json, 'health_status'),
      vaccination: readNullableString(json, 'vaccination'),
      shortDescription: readString(json, 'short_description'),
      additionalNotes: readNullableString(json, 'additional_notes'),
      photos: readStringList(json, 'photos'),
      status: ListingStatus.fromValue(readString(json, 'status')),
      createdAt: readNullableDateTime(json, 'created_at'),
      updatedAt: readNullableDateTime(json, 'updated_at'),
    );
  }

  /// `listings.id`.
  final int id;

  /// The seller, reduced to id and display name. Never carries an email.
  final ListingSeller seller;

  /// Species, as the seller typed it.
  ///
  /// Free text by design — `listings.livestock_type` is a plain string and must
  /// not become an enum without approval (functional documentation §4.1, OQ-04).
  /// The app therefore does not offer a fixed list of species to filter by, and
  /// does not normalise or title-case this value.
  final String livestockType;

  final String breed;

  /// Age magnitude as the API sent it, e.g. `"18.0"`. Null when not recorded.
  final String? ageValue;

  /// `day`, `month` or `year`. Null when [ageValue] is null.
  final String? ageUnit;

  /// `male` or `female`. Null when not recorded.
  final String? gender;

  /// Weight magnitude as the API sent it, e.g. `"320.50"`. Null when not
  /// recorded.
  final String? weightValue;

  /// `kg` or `lb`. Non-null in the schema (it defaults to `kg`).
  final String? weightUnit;

  /// Whole units available. Never negative.
  final int quantity;

  /// The seller's asking price as the API sent it, e.g. `"42500.00"`.
  ///
  /// Kept as a `String` end to end. Parse it only in `AppFormatters`.
  final String askingPrice;

  /// Free-text location, e.g. `Mabalacat, Pampanga`.
  final String location;

  /// Free-text health note. Null when not recorded.
  final String? healthStatus;

  /// Free-text vaccination note. Null when not recorded.
  final String? vaccination;

  final String shortDescription;

  /// Seller's extra notes. Null when not recorded.
  final String? additionalNotes;

  /// Stored photo paths, exactly as the API returns them.
  ///
  /// **Not URLs, and this app does not make them into any.** The backend
  /// returns the raw contents of the `listings.photos` JSON column: there is no
  /// upload endpoint, no storage disk bound to the column, and no agreed URL
  /// scheme (OQ-09 / D-10). A value here is used as an image source only if it
  /// is already an absolute `http`/`https` URL; anything else — a storage-
  /// relative path such as `listings/1/front.jpg` — renders as a placeholder.
  /// See `ListingPhoto`.
  final List<String> photos;

  final ListingStatus status;

  final DateTime? createdAt;

  final DateTime? updatedAt;

  /// Whether this listing has a photo the client can actually fetch.
  ///
  /// A non-empty [photos] list is not sufficient: see [photos]. This exists so
  /// a card can choose between a photo and a placeholder without duplicating
  /// the URL test.
  bool get hasLoadablePhoto => photos.any(isDirectlyLoadablePhotoUrl);

  /// Age as a single display string, e.g. `18 months`, or `null`.
  ///
  /// Requires both halves. A magnitude with no unit, or a unit with no
  /// magnitude, is not something a buyer can read, so nothing is shown rather
  /// than something misleading.
  String? get ageLabel {
    final String? value = ageValue;
    final String? unit = ageUnit;
    if (value == null || unit == null) {
      return null;
    }
    return '${_trimDecimal(value)} ${_pluraliseUnit(value, unit)}';
  }

  /// Weight as a single display string, e.g. `320.5 kg`, or `null`.
  String? get weightLabel {
    final String? value = weightValue;
    final String? unit = weightUnit;
    if (value == null) {
      return null;
    }
    return unit == null ? _trimDecimal(value) : '${_trimDecimal(value)} $unit';
  }

  /// A buyer-facing title for the listing: the breed when there is one,
  /// otherwise the species.
  ///
  /// Falls back rather than rendering an empty heading, because `breed` is a
  /// non-null column but may legitimately be an empty string.
  String get title => breed.trim().isEmpty ? livestockType : breed;

  /// Whether a photo path can be handed to `Image.network` as-is.
  ///
  /// Only an absolute `http`/`https` URL qualifies. This is the whole of the
  /// photo decision: the API does not currently return one, so in practice
  /// every listing renders a placeholder, and that is the correct outcome
  /// rather than a gap in the client. Inventing a base URL here would fabricate
  /// a storage mechanism that does not exist.
  static bool isDirectlyLoadablePhotoUrl(String path) {
    final Uri? uri = Uri.tryParse(path.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return false;
    }
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  static String? _readNullableDecimal(
    Map<String, dynamic> json,
    String key,
  ) {
    final Object? value = json[key];
    if (value == null) {
      return null;
    }
    return readDecimalString(json, key);
  }

  /// Drops a trailing `.0` so `18.0` reads as `18`, while `320.50` keeps its
  /// meaningful precision.
  static String _trimDecimal(String value) {
    final String trimmed = value.trim();
    if (!trimmed.contains('.')) {
      return trimmed;
    }
    final String withoutTrailingZeros = trimmed.replaceFirst(
      RegExp(r'\.?0+$'),
      '',
    );
    return withoutTrailingZeros.isEmpty ? trimmed : withoutTrailingZeros;
  }

  /// Pluralises [unit] only when [value] is not one.
  ///
  /// The count has to be read, not assumed: `1 year` is right and `1 years` is
  /// the kind of small wrongness a buyer notices and stops trusting. A value
  /// that will not parse is treated as plural, since an unreadable magnitude is
  /// more likely to be a count above one than exactly one.
  static String _pluraliseUnit(String value, String unit) {
    final double? amount = double.tryParse(value.trim());
    final bool isSingular = amount == 1;
    if (isSingular) {
      return unit;
    }
    return switch (unit) {
      'day' => 'days',
      'month' => 'months',
      'year' => 'years',
      _ => unit,
    };
  }

  @override
  String toString() => 'Listing($id, $livestockType, $breed, $status)';
}
