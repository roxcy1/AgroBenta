import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/config/app_config.dart';

/// Obtains a Google ID token for `POST /auth/google`.
///
/// Android only (project decision, MS-11). The Android OAuth client is matched
/// by Google from the app's package name and signing SHA-1, so it is not passed
/// here; [serverClientId] is the backend's "Web application" client ID, which
/// becomes the token's audience that Laravel checks.
class GoogleSignInService {
  GoogleSignInService({this.serverClientId = AppConfig.googleServerClientId});

  /// The backend's Web application client ID.
  final String serverClientId;
  Future<void>? _initialization;

  /// Whether Google sign-in can be offered on this device and build.
  bool get isAvailable =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      serverClientId.isNotEmpty;

  /// Shows Google's account picker and returns the ID token, or `null` when the
  /// user cancels. Any other failure is thrown.
  Future<String?> obtainIdToken() async {
    final GoogleSignIn signIn = GoogleSignIn.instance;

    try {
      await (_initialization ??= signIn.initialize(
        serverClientId: serverClientId,
      ));
    } on Object {
      // Allow a later attempt to initialise again.
      _initialization = null;
      rethrow;
    }

    try {
      final GoogleSignInAccount account = await signIn.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      rethrow;
    }
  }
}
