import 'package:agrobenta_mobile/models/seller_verification.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seller_verification_fakes.dart';

void main() {
  group('SellerVerificationStatus', () {
    test('parses every status the contract allows', () {
      expect(
        SellerVerificationStatus.fromValue('submitted'),
        SellerVerificationStatus.submitted,
      );
      expect(
        SellerVerificationStatus.fromValue('pending_review'),
        SellerVerificationStatus.pendingReview,
      );
      expect(
        SellerVerificationStatus.fromValue('approved'),
        SellerVerificationStatus.approved,
      );
      expect(
        SellerVerificationStatus.fromValue('rejected'),
        SellerVerificationStatus.rejected,
      );
    });

    test('rejects an unknown status instead of defaulting', () {
      // A fifth status would be a contract change. Guessing one — say, treating
      // it as "pending" — would show a seller the wrong thing and hide a backend
      // defect, so this throws.
      expect(
        () => SellerVerificationStatus.fromValue('escalated'),
        throwsFormatException,
      );
    });

    test(
      'treats submitted and pending_review as open, matching the server',
      () {
        expect(SellerVerificationStatus.submitted.isOpen, isTrue);
        expect(SellerVerificationStatus.pendingReview.isOpen, isTrue);
        expect(SellerVerificationStatus.approved.isOpen, isFalse);
        expect(SellerVerificationStatus.rejected.isOpen, isFalse);
      },
    );
  });

  group('SellerVerification.fromJson', () {
    test('parses the mobile resource', () {
      final SellerVerification verification = SellerVerification.fromJson(
        sellerVerificationJson(
          id: 9,
          businessName: 'Santos Cattle Co.',
          status: 'rejected',
          adminNote: 'Business name does not match the submitted reference.',
          submittedAt: '2026-09-26T09:30:00.000000Z',
          reviewedAt: '2026-09-27T11:00:00.000000Z',
        ),
      );

      expect(verification.id, 9);
      expect(verification.businessName, 'Santos Cattle Co.');
      expect(verification.businessLocation, 'Mabalacat, Pampanga');
      expect(
        verification.businessDescription,
        'Family-run cattle farm, trading since 2011.',
      );
      expect(verification.idDocumentRef, 'PHL-ID-88213');
      expect(verification.status, SellerVerificationStatus.rejected);
      expect(
        verification.adminNote,
        'Business name does not match the submitted reference.',
      );
      expect(verification.submittedAt, isNotNull);
      expect(verification.reviewedAt, isNotNull);
      expect(verification.isRejected, isTrue);
      expect(verification.canResubmit, isTrue);
    });

    test('tolerates every optional field being null', () {
      final SellerVerification verification = SellerVerification.fromJson(
        sellerVerificationJson(
          businessLocation: null,
          businessDescription: null,
          idDocumentRef: null,
          adminNote: null,
          submittedAt: null,
          reviewedAt: null,
        ),
      );

      expect(verification.businessLocation, isNull);
      expect(verification.businessDescription, isNull);
      expect(verification.idDocumentRef, isNull);
      expect(verification.adminNote, isNull);
      expect(verification.submittedAt, isNull);
      expect(verification.reviewedAt, isNull);
      expect(verification.isAwaitingReview, isTrue);
    });

    test('refuses a payload carrying a seller', () {
      // The mobile resource must not embed the seller. If it ever does, the
      // backend and this model have drifted and the failure belongs here rather
      // than in a silently-degraded screen. The shape of the leaked key does not
      // matter — only that it is there.
      final Map<String, dynamic> json = sellerVerificationJson()
        ..['seller'] = <String, dynamic>{'id': 3, 'name': 'Rizal Farms'};

      expect(() => SellerVerification.fromJson(json), throwsFormatException);
    });

    test('refuses a payload carrying a reviewer', () {
      final Map<String, dynamic> json = sellerVerificationJson()
        ..['reviewer'] = <String, dynamic>{'id': 1, 'name': 'Admin'};

      expect(() => SellerVerification.fromJson(json), throwsFormatException);
    });

    test('refuses a payload carrying user_id', () {
      final Map<String, dynamic> json = sellerVerificationJson()
        ..['user_id'] = 7;

      expect(() => SellerVerification.fromJson(json), throwsFormatException);
    });

    test('requires a status', () {
      final Map<String, dynamic> json = sellerVerificationJson()
        ..remove('status');

      expect(() => SellerVerification.fromJson(json), throwsFormatException);
    });
  });
}
