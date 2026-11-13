import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_messaging.dart';

/// [PushMessaging] backed by Firebase Cloud Messaging.
///
/// Firebase is initialised on first use from `android/app/google-services.json`
/// (applied by the Google Services Gradle plugin), so no options file is
/// generated. A push that arrives while the app is closed or in the background
/// is shown by Android itself; one that arrives while the app is open is not
/// shown, because the open app already updates live over Reverb.
class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging._();

  /// Firebase on Android, nothing elsewhere. iOS also needs an APNs key and
  /// is not set up; web is a development target only.
  static PushMessaging forCurrentPlatform() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return FirebasePushMessaging._();
    }
    return const NoopPushMessaging();
  }

  Future<FirebaseApp>? _initialization;

  Future<FirebaseMessaging> _messaging() async {
    await (_initialization ??= Firebase.initializeApp());
    return FirebaseMessaging.instance;
  }

  @override
  Future<String?> requestPermissionAndGetToken() async {
    final FirebaseMessaging messaging = await _messaging();
    final NotificationSettings settings = await messaging.requestPermission();

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return null;
    }
    return messaging.getToken();
  }

  @override
  Stream<String> get onTokenRefresh async* {
    final FirebaseMessaging messaging = await _messaging();
    yield* messaging.onTokenRefresh;
  }

  @override
  Stream<Map<String, String>> get openedNotifications async* {
    final FirebaseMessaging messaging = await _messaging();
    final RemoteMessage? initial = await messaging.getInitialMessage();

    if (initial != null) {
      yield _stringData(initial);
    }
    yield* FirebaseMessaging.onMessageOpenedApp.map(_stringData);
  }

  @override
  Future<void> deleteToken() async {
    final FirebaseMessaging messaging = await _messaging();
    await messaging.deleteToken();
  }

  static Map<String, String> _stringData(RemoteMessage message) =>
      message.data.map(
        (String key, dynamic value) => MapEntry<String, String>(key, '$value'),
      );
}
