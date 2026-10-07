import '../../../core/constants/api_constants.dart';
import '../../../models/listing.dart';

/// The values the seller listing form holds, and how they become a request body.
///
/// Deliberately **not** a server model. [Listing] mirrors
/// `MobileListingResource` and is read-only here; this carries what a seller has
/// *typed*, which is a different thing: text as typed, an empty field still
/// empty, and nothing read from the server.
///
/// ## Empty values are omitted, not sent as null
///
/// [toRequestBody] leaves out anything the seller did not fill in, rather than
/// sending `null`. That is the honest encoding of a form, and on a PATCH it is
/// also the correct one: the server treats an absent field as "leave it alone",
/// so a null would be asking to clear a value the seller never touched.
///
/// It also sidesteps a genuine ambiguity. `age_value`/`age_unit` and
/// `weight_value`/`weight_unit` are required in pairs, and the contract expresses
/// that as `required_with` — a rule about *presence*. A body containing
/// `age_value: null, age_unit: null` is present-but-null, which is a fourth thing
/// that is neither "set" nor "absent" and which no rule in the contract
/// describes. Omitting both sides makes the pair unambiguous.
///
/// ## Types on the wire
///
/// `asking_price` and `weight_value` go out as the seller's own digits, as a
/// `String`. They are `decimal` columns, and a JSON number would put a `double`
/// between the seller and the value the database stores for no benefit.
/// `quantity` and `age_value` are validated as integers by the contract, so they
/// go out as `int`.
class SellerListingDraft {
  const SellerListingDraft({
    this.livestockType = '',
    this.breed = '',
    this.ageValue = '',
    this.ageUnit,
    this.gender,
    this.weightValue = '',
    this.weightUnit,
    this.quantity = '',
    this.askingPrice = '',
    this.location = '',
    this.healthStatus = '',
    this.vaccination = '',
    this.shortDescription = '',
    this.additionalNotes = '',
  });

  /// Pre-fills the form from a listing the server already holds.
  ///
  /// Used when editing, so the seller edits what is on record rather than
  /// retyping it. `breed` and `shortDescription` are non-null columns that may be
  /// empty strings, which is why they are read as `?? ''` and not as nullable.
  factory SellerListingDraft.fromListing(Listing listing) {
    return SellerListingDraft(
      livestockType: listing.livestockType,
      breed: listing.breed,
      // Decimals are trimmed of a trailing `.0` so the field does not open
      // showing `2.0` for an age the seller entered as `2`.
      ageValue: listing.ageValue ?? '',
      ageUnit: listing.ageUnit,
      gender: listing.gender,
      weightValue: listing.weightValue ?? '',
      weightUnit: listing.weightUnit,
      quantity: listing.quantity.toString(),
      askingPrice: listing.askingPrice,
      location: listing.location,
      healthStatus: listing.healthStatus ?? '',
      vaccination: listing.vaccination ?? '',
      shortDescription: listing.shortDescription,
      additionalNotes: listing.additionalNotes ?? '',
    );
  }

  /// All final: a draft is a value, not a document to be edited in place. The form
  /// builds a new one from its fields on every save, so mutating one would only
  /// make it possible to save a body that does not match what is on screen.
  final String livestockType;
  final String breed;
  final String ageValue;
  final String? ageUnit;
  final String? gender;
  final String weightValue;
  final String? weightUnit;
  final String quantity;
  final String askingPrice;
  final String location;
  final String healthStatus;
  final String vaccination;
  final String shortDescription;
  final String additionalNotes;

  /// The request body for `POST /seller/listings` or `PATCH /seller/listings/{id}`.
  ///
  /// Built from [SellerListingEndpoints.writableFields] so the set of keys is
  /// read off the contract's allow-list rather than written out again here. An
  /// empty optional field contributes no key; the server fills its own defaults.
  Map<String, dynamic> toRequestBody() {
    final Map<String, dynamic> body = <String, dynamic>{};

    void put(String key, String value) {
      if (value.trim().isNotEmpty) {
        body[key] = value.trim();
      }
    }

    for (final String key in SellerListingEndpoints.writableFields) {
      switch (key) {
        case 'livestock_type':
          put(key, livestockType);
        case 'breed':
          put(key, breed);
        case 'age_value':
          // Integer per the contract. The validators reject anything else before
          // this is reached, so `int.parse` here cannot fail.
          if (ageValue.trim().isNotEmpty) {
            body[key] = int.parse(ageValue.trim());
          }
        case 'age_unit':
          // Only alongside its value. A unit on its own is not a listing anyone
          // can read, and the server requires the pair.
          if (ageValue.trim().isNotEmpty && ageUnit != null) {
            body[key] = ageUnit;
          }
        case 'gender':
          if (gender != null) {
            body[key] = gender;
          }
        case 'weight_value':
          if (weightValue.trim().isNotEmpty) {
            body[key] = weightValue.trim();
          }
        case 'weight_unit':
          if (weightValue.trim().isNotEmpty && weightUnit != null) {
            body[key] = weightUnit;
          }
        case 'quantity':
          if (quantity.trim().isNotEmpty) {
            body[key] = int.parse(quantity.trim());
          }
        case 'asking_price':
          // Sent as the seller's own digits. Not parsed, not reformatted.
          put(key, askingPrice);
        case 'location':
          put(key, location);
        case 'health_status':
          put(key, healthStatus);
        case 'vaccination':
          put(key, vaccination);
        case 'short_description':
          put(key, shortDescription);
        case 'additional_notes':
          put(key, additionalNotes);
      }
    }

    return body;
  }

  /// The fields the contract requires at create, absent from the body.
  ///
  /// Surfaces in the form before a request is made, so an incomplete draft is
  /// caught in the app rather than as a `422`. A draft is a complete but
  /// unpublished record: the contract requires these four, and the form does not
  /// pretend otherwise by offering a "save and finish later" that the server
  /// would refuse.
  List<String> get missingRequiredFields => SellerListingEndpoints
      .requiredFields
      .where((String field) => !toRequestBody().containsKey(field))
      .toList(growable: false);
}
