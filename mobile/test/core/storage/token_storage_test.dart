import 'package:agrobenta_mobile/core/constants/api_constants.dart';
import 'package:agrobenta_mobile/core/storage/token_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Remember me" behaviour of the real [TokenStorage], over the plugin's
/// in-memory mock of the keystore.
void main() {
  const FlutterSecureStorage keystore = FlutterSecureStorage();

  Future<String?> saved() => keystore.read(key: ApiConstants.tokenStorageKey);

  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  test('a remembered token is saved to the keystore', () async {
    final TokenStorage storage = TokenStorage();

    await storage.write('remembered');

    expect(await storage.read(), 'remembered');
    expect(await saved(), 'remembered');
  });

  test('a session-only token is never saved to the keystore', () async {
    final TokenStorage storage = TokenStorage();

    await storage.write('session', persist: false);

    expect(await storage.read(), 'session');
    expect(await saved(), isNull);
  });

  test('a session-only token is gone after the app restarts', () async {
    await TokenStorage().write('session', persist: false);

    // A new instance stands in for a fresh app process.
    expect(await TokenStorage().read(), isNull);
  });

  test('a session-only sign-in deletes an older remembered token', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      ApiConstants.tokenStorageKey: 'old-remembered',
    });
    final TokenStorage storage = TokenStorage();

    await storage.write('session', persist: false);

    expect(await saved(), isNull);
    expect(await TokenStorage().read(), isNull);
  });

  test('a remembered sign-in replaces a session-only token', () async {
    final TokenStorage storage = TokenStorage();

    await storage.write('session', persist: false);
    await storage.write('remembered');

    expect(await storage.read(), 'remembered');
    expect(await TokenStorage().read(), 'remembered');
  });

  test('clear removes a session-only token', () async {
    final TokenStorage storage = TokenStorage();

    await storage.write('session', persist: false);
    await storage.clear();

    expect(await storage.read(), isNull);
  });

  test('clearIfCurrent matches a session-only token', () async {
    final TokenStorage storage = TokenStorage();
    await storage.write('session', persist: false);

    expect(await storage.clearIfCurrent('other'), isFalse);
    expect(await storage.read(), 'session');

    expect(await storage.clearIfCurrent('session'), isTrue);
    expect(await storage.read(), isNull);
  });
}
