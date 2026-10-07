import 'package:agrobenta_mobile/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/auth_fakes.dart';

void main() {
  group('User.fromJson', () {
    test('parses the UserResource shape', () {
      final User user = User.fromJson(userJson());

      expect(user.id, 7);
      expect(user.name, 'Ana Reyes');
      expect(user.email, 'ana@example.test');
      expect(user.role, UserRole.user);
      expect(user.sellerCapability, SellerCapability.buyer);
      expect(user.emailVerifiedAt, isNull);
      expect(user.createdAt, isNotNull);
      expect(user.updatedAt, isNotNull);
    });

    test('reads ISO-8601 timestamps as local times', () {
      final User user = User.fromJson(
        userJson(
          createdAt: '2026-09-25T08:15:00.000000Z',
          updatedAt: '2026-09-26T09:20:00.000000Z',
        ),
      );

      expect(user.createdAt!.toUtc(), DateTime.utc(2026, 9, 25, 8, 15));
      expect(user.updatedAt!.toUtc(), DateTime.utc(2026, 9, 26, 9, 20));
    });

    test('a newly registered account is a buyer, not a seller', () {
      final User user = User.fromJson(
        userJson(role: 'user', sellerCapability: 'buyer'),
      );

      expect(user.isSeller, isFalse);
      expect(user.sellerCapability, SellerCapability.buyer);
      expect(user.isAdmin, isFalse);
    });

    test('reads a server-granted seller capability', () {
      final User user = User.fromJson(userJson(sellerCapability: 'seller'));

      expect(user.isSeller, isTrue);
      expect(user.sellerCapability, SellerCapability.seller);
    });

    test('tolerates the nullable columns being null', () {
      final User user = User.fromJson(
        userJson(
          role: null,
          sellerCapability: null,
          emailVerifiedAt: null,
          createdAt: null,
          updatedAt: null,
        ),
      );

      expect(user.role, isNull);
      expect(user.sellerCapability, isNull);
      expect(user.emailVerifiedAt, isNull);
      expect(user.createdAt, isNull);
      expect(user.updatedAt, isNull);
    });

    test('rejects an unknown seller capability rather than defaulting', () {
      expect(
        () => User.fromJson(userJson(sellerCapability: 'superuser')),
        throwsFormatException,
      );
    });

    test('rejects an unknown role rather than defaulting', () {
      expect(
        () => User.fromJson(userJson(role: 'owner')),
        throwsFormatException,
      );
    });

    test('rejects a non-integer id', () {
      expect(() => User.fromJson(userJson(id: 'seven')), throwsFormatException);
    });
  });
}
