/// The phone's push notification source (Firebase Cloud Messaging on Android).
///
/// An interface so the app can run, and be tested, without Firebase: tests and
/// platforms without push (web, iOS for now) use [NoopPushMessaging], and only
/// `main()` creates the Firebase implementation.
abstract interface class PushMessaging {
  /// Ask for notification permission, then return the FCM token, or null when
  /// the user refused or the platform has no push.
  Future<String?> requestPermissionAndGetToken();

  /// New FCM tokens issued after the first one.
  Stream<String> get onTokenRefresh;

  /// The data of each push the user tapped to open the app, including the one
  /// that launched it from a closed state.
  Stream<Map<String, String>> get openedNotifications;

  /// Invalidate this phone's FCM token, so the next sign-in gets a new one.
  Future<void> deleteToken();
}

/// No push: the platform has none, or this is a test.
class NoopPushMessaging implements PushMessaging {
  const NoopPushMessaging();

  @override
  Future<String?> requestPermissionAndGetToken() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream<String>.empty();

  @override
  Stream<Map<String, String>> get openedNotifications =>
      const Stream<Map<String, String>>.empty();

  @override
  Future<void> deleteToken() async {}
}
