import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/core/storage/token_store.dart';
import 'package:agrobenta_mobile/models/auth_session.dart';
import 'package:agrobenta_mobile/models/user.dart';
import 'package:agrobenta_mobile/repositories/auth_repository.dart';
import 'package:agrobenta_mobile/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory [TokenStore] so tests never touch the Android Keystore or the
/// iOS Keychain. The real `TokenStorage` is exercised by the platform, not by
/// a unit test.
class FakeTokenStore implements TokenStore {
  FakeTokenStore([this.token]);

  String? token;

  int writeCount = 0;
  int clearCount = 0;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async {
    token = value;
    writeCount++;
  }

  @override
  Future<void> clear() async {
    token = null;
    clearCount++;
  }
}

/// A `UserResource` payload exactly as the backend serialises one.
///
/// Field names, nullability and value spellings are copied from
/// `backend/app/Http/Resources/UserResource.php`; a test that passes against
/// this fixture is asserting against the real contract, not against a guess.
Map<String, dynamic> userJson({
  Object? id = 7,
  String name = 'Ana Reyes',
  String email = 'ana@example.test',
  Object? role = 'user',
  Object? sellerCapability = 'buyer',
  Object? emailVerifiedAt,
  Object? createdAt = '2026-09-25T08:15:00.000000Z',
  Object? updatedAt = '2026-09-25T08:15:00.000000Z',
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'email': email,
    'role': role,
    'seller_capability': sellerCapability,
    'email_verified_at': emailVerifiedAt,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

/// The `data` payload of a successful register or login.
Map<String, dynamic> authSessionJson({
  String token = '1|test-mobile-token',
  String tokenType = 'Bearer',
  Map<String, dynamic>? user,
}) {
  return <String, dynamic>{
    'token': token,
    'token_type': tokenType,
    'user': user ?? userJson(),
  };
}

/// A Laravel success envelope.
Map<String, dynamic> successEnvelope({Object? data, String? message}) =>
    <String, dynamic>{'success': true, 'message': message, 'data': data};

/// A Laravel 422 body, as `FormRequest` produces it.
Map<String, dynamic> validationErrorBody({
  String message = 'The given data was invalid.',
  Map<String, Object> errors = const <String, Object>{},
}) {
  return <String, dynamic>{'message': message, 'errors': errors};
}

/// A recorded HTTP exchange, for asserting on what the app actually sent.
class RecordedRequest {
  RecordedRequest(this.request);

  final http.Request request;

  String get method => request.method;

  String get path => request.url.path;

  /// The path relative to the API root, e.g. `/auth/login`.
  String get apiPath => path.replaceFirst(RegExp(r'^/api'), '');

  /// The decoded query string, for asserting on filters and pagination.
  Map<String, String> get query => request.url.queryParameters;

  Map<String, dynamic> get body =>
      jsonDecode(request.body) as Map<String, dynamic>;

  String? get authorization => request.headers['Authorization'];
}

/// Builds an [AuthService] over a mock transport that records every request.
AuthService buildAuthService(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  List<RecordedRequest>? recorded,
}) {
  final ApiClient client = ApiClient(
    tokenStorage: tokenStore,
    httpClient: MockClient((http.Request request) async {
      final RecordedRequest entry = RecordedRequest(request);
      recorded?.add(entry);
      return handler(entry);
    }),
  );
  return AuthService(client);
}

/// The full authentication stack over a mock transport, which is what most
/// tests want.
AuthRepository buildAuthRepository(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  List<RecordedRequest>? recorded,
}) {
  return AuthRepository(
    buildAuthService(tokenStore, handler, recorded: recorded),
    tokenStore,
  );
}

/// A [User] built from the canonical fixture.
User fixtureUser({int id = 7, String name = 'Ana Reyes'}) =>
    AuthSession.fromJson(
      authSessionJson(
        user: userJson(id: id, name: name),
      ),
    ).user;
