import '../core/utils/json_utils.dart';

/// Where a seller verification stands, as stored in
/// `seller_verifications.status`.
///
/// A PHP backed enum serialised to its value by
/// `backend/app/Enums/SellerVerificationStatus.php`. These four values are the
/// complete set the documentation permits (functional documentation §3.1) — a
/// fifth would be a contract change, so [SellerVerificationStatus.fromValue]
/// throws rather than defaulting.
enum SellerVerificationStatus {
  /// Filed by the user, not yet picked up by an administrator.
  submitted('submitted'),

  /// Being looked at by an administrator.
  ///
  /// An open state, exactly like [submitted]: the record is in flight and a new
  /// submission is refused with a `409`. The app shows a single "awaiting
  /// review" presentation for both, because the buyer cannot tell them apart
  /// and the difference has no consequence for anything they can do.
  pendingReview('pending_review'),

  /// The administrator approved it, and the server set
  /// `seller_capability = seller` on the account.
  ///
  /// The app never sets this. It observes it.
  approved('approved'),

  /// The administrator declined it, with a reason in `admin_note`.
  ///
  /// The only state from which a new submission is permitted, and the only one
  /// that offers a "Resubmit" action.
  rejected('rejected');

  const SellerVerificationStatus(this.value);

  /// The exact lowercase string the API sends.
  final String value;

  /// Whether a review is in flight, so no new submission may be filed.
  ///
  /// Mirrors `SellerVerificationStatus::isOpen()` on the backend. The two must
  /// agree, because the server enforces it with a `409` and the app uses this to
  /// decide whether to offer the form at all.
  bool get isOpen => this == submitted || this == pendingReview;

  /// Parses the API value, failing loudly on an unknown one.
  static SellerVerificationStatus fromValue(String value) {
    for (final SellerVerificationStatus status
        in SellerVerificationStatus.values) {
      if (status.value == value) {
        return status;
      }
    }
    throw FormatException('Unknown seller verification status "$value".');
  }
}

enum GovernmentIdType {
  philippineNationalId(
    'philippine_national_id',
    'Philippine National ID (PhilID / ePhilID)',
  ),
  driversLicense('drivers_license', "Driver's License (LTO)"),
  philHealthId('philhealth_id', 'PhilHealth ID'),
  votersId('voters_id', "Voter's ID"),
  postalId('postal_id', 'Postal ID'),
  others('others', 'Others');

  const GovernmentIdType(this.value, this.label);
  final String value;
  final String label;

  static GovernmentIdType? fromNullableValue(String? value) {
    for (final GovernmentIdType type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// Which evidence document an upload or fetch refers to.
///
/// Mirrors `backend/app/Enums/SellerVerificationDocumentType.php`. The wire
/// value is the enum case's lowercase string, and it is what the API expects in
/// the `type` multipart field and what appears in the `/documents/{type}` path.
enum VerificationDocumentType {
  /// A photo of a government-issued identity document.
  idDocument('id_document'),
  idDocumentFront('id_document_front'),
  idDocumentBack('id_document_back'),

  /// A selfie of the applicant holding the same identity document.
  selfie('selfie'),

  /// A document showing the applicant's address, e.g. a utility bill.
  proofOfAddress('proof_of_address'),

  /// An optional photo of the livestock or farm area. Unlike the others, an
  /// application can hold several.
  farmPhoto('farm_photo');

  const VerificationDocumentType(this.value);

  /// The exact lowercase string the API sends and expects.
  final String value;
}

/// The authenticated user's own seller verification, as returned by
/// `GET /api/seller-verification/me` and `POST /api/seller-verification`.
///
/// Mirrors `backend/app/Http/Resources/MobileSellerVerificationResource.php`
/// field for field.
///
/// What is deliberately **not** here, because the mobile resource omits it:
///
///  * `seller` — the caller's own name and email, which they already have.
///  * `reviewer` — an administrator's identity. The admin resource embeds it and
///    the mobile one must not (contract §8.1).
///  * `user_id`, `created_at`, `updated_at` — bookkeeping.
///
/// A record that carried a `reviewer` here would mean the backend resource and
/// this model had drifted, so [fromJson] rejects the payload rather than
/// quietly ignoring the extra keys.
class SellerVerification {
  const SellerVerification({
    required this.id,
    required this.phone,
    required this.address,
    required this.businessName,
    required this.businessLocation,
    required this.businessDescription,
    required this.idDocumentRef,
    this.governmentIdType,
    this.governmentIdDescription,
    this.hasNoBackImage,
    required this.status,
    required this.adminNote,
    required this.submittedAt,
    required this.reviewedAt,
    this.hasIdDocumentFront = false,
    this.hasIdDocumentBack = false,
    this.hasIdDocument = false,
    this.hasSelfie = false,
    this.hasProofOfAddress = false,
    this.farmPhotoIds = const <String>[],
  });

  /// Field names the mobile resource must not contain.
  ///
  /// Checked rather than merely absent, so a regression in the backend resource
  /// surfaces here as a failing test instead of as a phone that quietly received
  /// an administrator's name.
  static const List<String> forbiddenFields = <String>[
    'reviewer',
    'seller',
    'user_id',
  ];

  factory SellerVerification.fromJson(Map<String, dynamic> json) {
    for (final String field in forbiddenFields) {
      if (json.containsKey(field)) {
        throw FormatException(
          'The seller verification response must not contain "$field".',
        );
      }
    }

    return SellerVerification(
      id: readInt(json, 'id'),
      phone: readNullableString(json, 'phone'),
      address: readNullableString(json, 'address'),
      businessName: readNullableString(json, 'business_name'),
      businessLocation: readNullableString(json, 'business_location'),
      businessDescription: readNullableString(json, 'business_description'),
      idDocumentRef: readNullableString(json, 'id_document_ref'),
      governmentIdType: GovernmentIdType.fromNullableValue(
        readNullableString(json, 'government_id_type'),
      ),
      governmentIdDescription: readNullableString(
        json,
        'government_id_description',
      ),
      hasNoBackImage: json['has_no_back_image'] is bool
          ? json['has_no_back_image'] as bool
          : null,
      status: SellerVerificationStatus.fromValue(readString(json, 'status')),
      adminNote: readNullableString(json, 'admin_note'),
      submittedAt: readNullableDateTime(json, 'submitted_at'),
      reviewedAt: readNullableDateTime(json, 'reviewed_at'),
      hasIdDocument: _readBool(json, 'has_id_document'),
      hasIdDocumentFront:
          json['has_id_document_front'] == true ||
          _readBool(json, 'has_id_document'),
      hasIdDocumentBack: json['has_id_document_back'] == true,
      hasSelfie: _readBool(json, 'has_selfie'),
      hasProofOfAddress: _readBool(json, 'has_proof_of_address'),
      farmPhotoIds: _readStringList(json, 'farm_photo_ids'),
    );
  }

  /// `seller_verifications.id`.
  final int id;

  /// Contact phone snapshot supplied with this verification. Nullable on
  /// legacy records created before the snapshot fields were introduced.
  final String? phone;

  /// Applicant address snapshot supplied with this verification. Nullable on
  /// legacy records created before the snapshot fields were introduced.
  final String? address;

  /// The farm or business name. Optional, so `null` when it was left blank.
  final String? businessName;

  final String? businessLocation;

  final String? businessDescription;

  /// A free-text reference to an identity document, such as a document number.
  ///
  /// This is **not** the document, which is uploaded separately, so the app must
  /// never present a file picker for this field.
  final String? idDocumentRef;

  final GovernmentIdType? governmentIdType;
  final String? governmentIdDescription;
  final bool? hasNoBackImage;

  final SellerVerificationStatus status;

  /// Why an administrator approved or rejected this, when they said.
  ///
  /// `null` is the normal case and must not be replaced with a fabricated
  /// reason: a rejection with no note is shown as a rejection with no stated
  /// reason.
  final String? adminNote;

  final DateTime? submittedAt;

  /// When the administrator decided. `null` while the record is still open.
  final DateTime? reviewedAt;

  /// Whether an identity document has been uploaded for this application.
  ///
  /// The resource exposes only this boolean — never a path or URL — because the
  /// document is private and streamed through an authenticated endpoint. `false`
  /// when the key is absent, so the model keeps working against an older resource
  /// that predates the documents migration.
  final bool hasIdDocument;
  final bool hasIdDocumentFront;
  final bool hasIdDocumentBack;

  /// Whether a selfie has been uploaded for this application.
  final bool hasSelfie;

  /// Whether a proof of address has been uploaded for this application.
  final bool hasProofOfAddress;

  /// The ids that name this application's farm photos on the document endpoint.
  final List<String> farmPhotoIds;

  /// Reads a list of strings the resource always sends.
  static List<String> _readStringList(Map<String, dynamic> json, String key) {
    final Object? value = json[key];
    if (value is List) {
      return value.cast<String>().toList(growable: false);
    }
    throw FormatException(
      'Expected field "$key" to be a list, got ${value.runtimeType}.',
      json.toString(),
    );
  }

  /// Reads a boolean the resource always sends.
  ///
  /// A missing key is a contract change — the resource emits every flag on every
  /// record — so it throws rather than defaulting, matching the strictness of
  /// the rest of this model's parsing.
  static bool _readBool(Map<String, dynamic> json, String key) {
    final Object? value = json[key];
    if (value is bool) {
      return value;
    }
    throw FormatException(
      'Expected field "$key" to be a bool, got ${value.runtimeType}.',
      json.toString(),
    );
  }

  /// Whether the account is waiting on an administrator.
  bool get isAwaitingReview => status.isOpen;

  /// Whether the administrator declined this.
  bool get isRejected => status == SellerVerificationStatus.rejected;

  /// Whether the administrator approved it.
  ///
  /// Note that this reflects the *verification record*, which is what this phase
  /// reads. The account's actual capability lives in `/auth/me` as
  /// `seller_capability`, and that is what the app treats as authoritative — a
  /// mismatch between the two would be a backend bug worth reporting, not
  /// something the client papers over by inferring one from the other.
  bool get isApproved => status == SellerVerificationStatus.approved;

  /// Whether a new submission is permitted.
  ///
  /// Only after a rejection, matching the server's `409` precondition. An open
  /// record blocks it, and so does an approved one — though an approved seller
  /// is refused at the endpoint with a `403` and is not offered the form at all.
  bool get canResubmit => isRejected;

  @override
  String toString() =>
      'SellerVerification($id, $businessName, ${status.value})';
}
