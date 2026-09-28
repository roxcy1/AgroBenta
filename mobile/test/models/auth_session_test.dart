import 'package:agrobenta_mobile/models/auth_session.dart';
import 'package:agrobenta_mobile/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/auth_fakes.dart';

void main() {
  group('AuthSession.fromJson', () {
    test('parses the register and login data payload', () {
      final AuthSession session = AuthSession.fromJson(authSessionJson());

      expect(session.token, '1|test-mobile-token');
      expect(session.tokenType, 'Bearer');
      expect(session.user.id, 7);
      expect(session.user.email, 'ana@example.test');
      expect(session.user.sellerCapability, SellerCapability.buyer);
    });

    test('rejects a payload with no user object', () {
      expect(
        () => AuthSession.fromJson(<String, dynamic>{
          'token': '1|abc',
          'token_type': 'Bearer',
          'user': null,
        }),
        throwsFormatException,
      );
    });

    test('rejects a payload with no token', () {
      final Map<String, dynamic> json = authSessionJson()
        ..remove('token');

      expect(() => AuthSession.fromJson(json), throwsFormatException);
    });

    test('rejects a payload with no token_type', () {
      final Map<String, dynamic> json = authSessionJson()
        ..remove('token_type');

      expect(() => AuthSession.fromJson(json), throwsFormatException);
    });
  });
}
