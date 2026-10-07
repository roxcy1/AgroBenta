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
    required this.businessName,
    required this.businessLocation,
    required this.businessDescription,
    required this.idDocumentRef,
    required this.status,
    required this.adminNote,
    required this.submittedAt,
    required this.reviewedAt,
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
      businessName: readString(json, 'business_name'),
      businessLocation: readNullableString(json, 'business_location'),
      businessDescription: readNullableString(json, 'business_description'),
      idDocumentRef: readNullableString(json, 'id_document_ref'),
      status: SellerVerificationStatus.fromValue(readString(json, 'status')),
      adminNote: readNullableString(json, 'admin_note'),
      submittedAt: readNullableDateTime(json, 'submitted_at'),
      reviewedAt: readNullableDateTime(json, 'reviewed_at'),
    );
  }

  /// `seller_verifications.id`.
  final int id;

  /// The only required field of the form.
  final String businessName;

  final String? businessLocation;

  final String? businessDescription;

  /// A reference to an identity document — **not** the document.
  ///
  /// There is no upload endpoint and no storage for one (functional documentation
  /// §3.3), so this is a string the seller supplies: a document number, a
  /// reference code, whatever their own process uses. The app must never present
  /// a file picker here, which would imply a mechanism that does not exist.
  final String? idDocumentRef;

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
