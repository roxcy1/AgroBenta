import 'package:agrobenta_mobile/core/utils/app_formatters.dart';
import 'package:agrobenta_mobile/models/seller_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seller_profile_fakes.dart';

void main() {
  group('SellerProfile.fromJson', () {
    test('parses a full MobileSellerProfileResource payload', () {
      final SellerProfile profile = SellerProfile.fromJson(
        sellerProfileJson(
          avatarUrl: 'https://cdn.example.test/avatar.jpg',
          bio: 'Third-generation cattle farmer.',
          activeListingsCount: 4,
        ),
      );

      expect(profile.id, 3);
      expect(profile.name, 'Joseph Basilad');
      expect(profile.avatarUrl, 'https://cdn.example.test/avatar.jpg');
      expect(profile.bio, 'Third-generation cattle farmer.');
      expect(profile.isVerified, isTrue);
      expect(
        profile.publicLocation,
        'Barangay San Isidro, Trinidad, Bohol',
      );
      expect(profile.memberSince, isNotNull);
      expect(profile.activeListingsCount, 4);
      expect(profile.hasBio, isTrue);
      expect(profile.hasPublicLocation, isTrue);
    });

    test('accepts null optional public fields', () {
      final SellerProfile profile = SellerProfile.fromJson(
        sellerProfileJson(
          avatarUrl: null,
          bio: null,
          publicLocation: null,
          memberSince: null,
          activeListingsCount: 0,
        ),
      );

      expect(profile.avatarUrl, isNull);
      expect(profile.bio, isNull);
      expect(profile.publicLocation, isNull);
      expect(profile.memberSince, isNull);
      expect(profile.hasBio, isFalse);
      expect(profile.hasPublicLocation, isFalse);
      expect(profile.activeListingsCount, 0);
    });

    test('treats a blank biography as absent', () {
      final SellerProfile profile = SellerProfile.fromJson(
        sellerProfileJson(bio: '   '),
      );

      expect(profile.hasBio, isFalse);
    });

    test('keeps verification as a strict boolean', () {
      expect(
        SellerProfile.fromJson(sellerProfileJson(isVerified: false)).isVerified,
        isFalse,
      );
      expect(
        SellerProfile.fromJson(sellerProfileJson(isVerified: true)).isVerified,
        isTrue,
      );
    });

    test('formats member since as a month and year', () {
      final SellerProfile profile = SellerProfile.fromJson(
        sellerProfileJson(memberSince: '2026-09-20T08:15:00.000000Z'),
      );

      // The exact month is locale-time independent: the date is midday UTC, so
      // no timezone shifts it across a month boundary.
      expect(AppFormatters.formatMonthYear(profile.memberSince), 'September 2026');
    });

    test('has no field for private contact or administrative data', () {
      // A defence-in-depth restatement of §10.4: the model cannot surface what
      // it cannot parse, even if a contract change sent more.
      final SellerProfile profile = SellerProfile.fromJson(
        <String, dynamic>{
          ...sellerProfileJson(),
          'email': 'seller@example.test',
          'phone': '09171234567',
          'location': 'Purok 4, Barangay San Isidro, Trinidad, Bohol',
          'role': 'user',
          'seller_capability': 'seller',
        },
      );

      expect(profile.toString(), isNot(contains('seller@example.test')));
      expect(profile.toString(), isNot(contains('09171234567')));
      expect(profile.toString(), isNot(contains('Purok 4')));
    });
  });
}
