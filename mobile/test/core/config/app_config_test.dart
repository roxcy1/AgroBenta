import 'package:agrobenta_mobile/core/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('apiBaseUrl', () {
    // These assert the real `kIsWeb` + `defaultTargetPlatform` pair, so they
    // hold on whichever platform the suite is running on. That matters because
    // the whole point of the `kIsWeb` guard is that the two disagree on web: a
    // browser reporting Android must still get `localhost`.

    test('a native Android build defaults to the physical-device address', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      // A physical phone cannot reach the host through the emulator's 10.0.2.2
      // alias, so the plain Android default must be the machine's LAN address.
      expect(
        AppConfig.apiBaseUrl,
        kIsWeb
            ? 'http://localhost:8001/api'
            : AppConfig.physicalAndroidApiBaseUrl,
      );
    });

    test('uses localhost on iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      expect(AppConfig.apiBaseUrl, 'http://localhost:8001/api');
    });

    test('strips trailing slashes', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      expect(AppConfig.apiBaseUrl, isNot(endsWith('/')));
    });

    test('a web build points at localhost, never at the emulator alias', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      if (kIsWeb) {
        expect(AppConfig.apiBaseUrl, 'http://localhost:8001/api');
        expect(AppConfig.apiBaseUrl, isNot(contains('10.0.2.2')));
      }
    });
  });

  group('resolveApiBaseUrl platform matrix', () {
    // This is the table the whole connectivity fix rests on, so it is asserted
    // exhaustively rather than one platform at a time. The arguments are the
    // real `kIsWeb` and `defaultTargetPlatform` values, so every row is a build
    // configuration that actually occurs.

    test('a native Android build resolves to the physical-device address', () {
      expect(
        AppConfig.resolveApiBaseUrl(
          isWeb: false,
          platform: TargetPlatform.android,
          override: '',
        ),
        AppConfig.physicalAndroidApiBaseUrl,
      );
    });

    test('an emulator build opts in to the host alias explicitly', () {
      // 10.0.2.2 exists only inside an Android emulator, so it must never be
      // the default — it is selected by an explicit
      // --dart-define=ANDROID_RUN_TARGET=emulator.
      expect(
        AppConfig.resolveApiBaseUrl(
          isWeb: false,
          platform: TargetPlatform.android,
          override: '',
          androidTarget: 'emulator',
        ),
        AppConfig.androidEmulatorApiBaseUrl,
      );
    });

    test('a non-emulator or unknown Android target is a physical build', () {
      for (final String target in <String>['', 'physical', 'nonsense']) {
        expect(
          AppConfig.resolveApiBaseUrl(
            isWeb: false,
            platform: TargetPlatform.android,
            override: '',
            androidTarget: target,
          ),
          AppConfig.physicalAndroidApiBaseUrl,
          reason:
              'ANDROID_RUN_TARGET="$target" must never silently yield '
              '10.0.2.2 on a physical-device build.',
        );
      }
    });

    test('an emulator target never leaks into a web build', () {
      // The kIsWeb guard must win over the android target: a browser can never
      // use 10.0.2.2, no matter what the device toolbar reports.
      expect(
        AppConfig.resolveApiBaseUrl(
          isWeb: true,
          platform: TargetPlatform.android,
          override: '',
          androidTarget: 'emulator',
        ),
        'http://localhost:8001/api',
      );
    });

    test('every other native build resolves to localhost', () {
      for (final TargetPlatform platform in <TargetPlatform>[
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          AppConfig.resolveApiBaseUrl(
            isWeb: false,
            platform: platform,
            override: '',
          ),
          'http://localhost:8001/api',
          reason: '$platform must reach the host over loopback.',
        );
      }
    });

    test('a web build resolves to localhost on every reported platform', () {
      // On Flutter Web `defaultTargetPlatform` is inferred from the browser's
      // user agent. Whichever way that inference lands, the answer is the same:
      // a browser and Laravel are both on the host, so no emulator alias is
      // involved. The android row is the one that regressed before — Chrome's
      // device toolbar reporting Android used to select `10.0.2.2`, which does
      // not exist outside an emulator.
      for (final TargetPlatform platform in TargetPlatform.values) {
        expect(
          AppConfig.resolveApiBaseUrl(
            isWeb: true,
            platform: platform,
            override: '',
          ),
          'http://localhost:8001/api',
          reason: 'A web build must never use 10.0.2.2, but $platform did.',
        );
      }
    });

    test('a web build never resolves to the emulator alias', () {
      expect(
        AppConfig.resolveApiBaseUrl(
          isWeb: true,
          platform: TargetPlatform.android,
          override: '',
        ),
        isNot(contains('10.0.2.2')),
      );
    });

    test('the dart-define overrides every platform', () {
      // A physical device on the LAN, and staging, are both expressed this way.
      const String staging = 'https://api.staging.agrobenta.test/api';

      for (final bool isWeb in <bool>[true, false]) {
        for (final TargetPlatform platform in TargetPlatform.values) {
          expect(
            AppConfig.resolveApiBaseUrl(
              isWeb: isWeb,
              platform: platform,
              override: staging,
            ),
            staging,
            reason: 'web=$isWeb $platform must honour the override.',
          );
        }
      }
    });

    test('a blank or whitespace override falls back to the defaults', () {
      for (final String override in <String>['', '   ', '\n']) {
        expect(
          AppConfig.resolveApiBaseUrl(
            isWeb: false,
            platform: TargetPlatform.android,
            override: override,
          ),
          AppConfig.physicalAndroidApiBaseUrl,
        );
        expect(
          AppConfig.resolveApiBaseUrl(
            isWeb: true,
            platform: TargetPlatform.windows,
            override: override,
          ),
          'http://localhost:8001/api',
        );
      }
    });

    test('an override with a trailing slash is normalised', () {
      expect(
        AppConfig.resolveApiBaseUrl(
          isWeb: true,
          platform: TargetPlatform.windows,
          override: 'http://192.168.1.20:8001/api/',
        ),
        'http://192.168.1.20:8001/api',
      );
    });
  });

  group('resolve', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    test('joins the API root with an absolute path', () {
      expect(
        AppConfig.resolve('/admin/dashboard'),
        '${AppConfig.physicalAndroidApiBaseUrl}/admin/dashboard',
      );
    });

    test('tolerates a path without a leading slash', () {
      expect(
        AppConfig.resolve('admin/dashboard'),
        '${AppConfig.physicalAndroidApiBaseUrl}/admin/dashboard',
      );
    });

    test('appends query parameters', () {
      expect(
        AppConfig.resolve(
          '/listings',
          query: <String, dynamic>{'status': 'active', 'page': 2},
        ),
        '${AppConfig.physicalAndroidApiBaseUrl}/'
        'listings?status=active&page=2',
      );
    });

    test('omits null query values, matching the web client behaviour', () {
      final String url = AppConfig.resolve(
        '/listings',
        query: <String, dynamic>{'status': 'active', 'search': null},
      );

      expect(
        url,
        '${AppConfig.physicalAndroidApiBaseUrl}/listings?status=active',
      );
      expect(url, isNot(contains('search')));
    });

    test('produces no query string when the map is empty', () {
      expect(
        AppConfig.resolve('/listings', query: <String, dynamic>{}),
        '${AppConfig.physicalAndroidApiBaseUrl}/listings',
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
