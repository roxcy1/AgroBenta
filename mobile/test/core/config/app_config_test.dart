import 'package:agrobenta_mobile/core/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('apiBaseUrl', () {
    test('uses 10.0.2.2 on Android', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      // The Android emulator cannot reach the host via localhost; 10.0.2.2 is
      // the documented alias for the host loopback interface.
      expect(AppConfig.apiBaseUrl, 'http://10.0.2.2:8001/api');
    });

    test('uses localhost on iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      expect(AppConfig.apiBaseUrl, 'http://localhost:8001/api');
    });

    test('strips trailing slashes', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      expect(AppConfig.apiBaseUrl, isNot(endsWith('/')));
    });
  });

  group('resolve', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    test('joins the API root with an absolute path', () {
      expect(
        AppConfig.resolve('/admin/dashboard'),
        'http://10.0.2.2:8001/api/admin/dashboard',
      );
    });

    test('tolerates a path without a leading slash', () {
      expect(
        AppConfig.resolve('admin/dashboard'),
        'http://10.0.2.2:8001/api/admin/dashboard',
      );
    });

    test('appends query parameters', () {
      expect(
        AppConfig.resolve('/listings', query: <String, dynamic>{
          'status': 'active',
          'page': 2,
        }),
        'http://10.0.2.2:8001/api/listings?status=active&page=2',
      );
    });

    test('omits null query values, matching the web client behaviour', () {
      final String url = AppConfig.resolve(
        '/listings',
        query: <String, dynamic>{'status': 'active', 'search': null},
      );

      expect(url, 'http://10.0.2.2:8001/api/listings?status=active');
      expect(url, isNot(contains('search')));
    });

    test('produces no query string when the map is empty', () {
      expect(
        AppConfig.resolve('/listings', query: <String, dynamic>{}),
        'http://10.0.2.2:8001/api/listings',
      );
    });
  });

  test('isUsingCleartextHttp reflects the resolved scheme', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    // The development stack is plain HTTP over Nginx on port 8001. This is
    // expected locally; production must use HTTPS.
    expect(AppConfig.isUsingCleartextHttp, isTrue);
  });
}
