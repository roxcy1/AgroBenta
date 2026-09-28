import '../core/network/api_exception.dart';
import '../models/seller_verification.dart';
import '../services/seller_verification_service.dart';

/// Orchestration for seller verification.
///
/// Thin, like `MarketplaceRepository`: the transport is already behind
/// [SellerVerificationService] and the session behind `AuthRepository`, so there
/// is no lifetime or ordering policy to arbitrate here.
///
/// The one thing this layer owns is the "never submitted" answer. A `404` from
/// `/seller-verification/me` is the *normal* state for a buyer who has not
/// applied — it is most of this feature's users — and returning it as a null
/// rather than an exception is what stops the common case from being rendered as
/// an error. It is deliberately **not** applied to any other failure, so a
/// genuine `404` from a moved endpoint still surfaces as one.
class SellerVerificationRepository {
  const SellerVerificationRepository(this._service);

  final SellerVerificationService _service;

  /// The caller's current verification, or `null` if they have never submitted.
  ///
  /// Returns `null` for [ApiErrorKind.notFound] and propagates every other
  /// [ApiException] unchanged.
  Future<SellerVerification?> current() async {
    try {
      return await _service.current();
    } on ApiException catch (error) {
      if (error.kind == ApiErrorKind.notFound) {
        return null;
      }
      rethrow;
    }
  }

  /// Files a verification and returns the created record.
  ///
  /// No error translation: the `409` and `422` that reach the screen carry
  /// meaning of their own, and rewriting them here would be a second place for
  /// wording to drift. The controller branches on [ApiErrorKind] instead.
  Future<SellerVerification> submit({
    required String businessName,
    String? businessLocation,
    String? businessDescription,
    String? idDocumentRef,
  }) {
    return _service.submit(
      businessName: businessName,
      businessLocation: businessLocation,
      businessDescription: businessDescription,
      idDocumentRef: idDocumentRef,
    );
  }
}
