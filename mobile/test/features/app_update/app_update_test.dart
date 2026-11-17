import 'package:agrobenta_mobile/features/app_update/state/app_update_controller.dart';
import 'package:agrobenta_mobile/features/app_update/state/app_update_scope.dart';
import 'package:agrobenta_mobile/features/app_update/view/app_update_tile.dart';
import 'package:agrobenta_mobile/models/app_release.dart';
import 'package:agrobenta_mobile/repositories/app_release_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_update_fakes.dart';

void main() {
  group('AppRelease.fromJson', () {
    test('reads the GET /app-release resource', () {
      final AppRelease release = AppRelease.fromJson(
        appReleaseEnvelope(
              versionCode: 3,
              versionName: '1.2.0',
              notes: 'New',
            )['data']
            as Map<String, dynamic>,
      );

      expect(release.versionName, '1.2.0');
      expect(release.versionCode, 3);
      expect(release.sizeBytes, 52428800);
      expect(release.notes, 'New');
      expect(release.publishedAt.toUtc(), DateTime.utc(2026, 11, 14));
      expect(release.downloadUrl, startsWith('https://'));
    });
  });

  group('AppReleaseRepository', () {
    test('no published release means no update', () async {
      final AppUpdateCheck check = await fakeAppReleaseRepository(
        envelope: appReleaseEnvelope(),
      ).check();

      expect(check.latest, isNull);
      expect(check.updateAvailable, isFalse);
    });

    test('an update needs a strictly higher build number', () async {
      Future<bool> availableFor(int serverCode) async =>
          (await fakeAppReleaseRepository(
            envelope: appReleaseEnvelope(versionCode: serverCode),
            installedApp: FakeInstalledApp(code: 2),
          ).check()).updateAvailable;

      expect(await availableFor(1), isFalse);
      expect(await availableFor(2), isFalse);
      expect(await availableFor(3), isTrue);
    });

    test('opens only an HTTPS download link', () async {
      final FakeLinkOpener opener = FakeLinkOpener();
      final AppReleaseRepository repository = fakeAppReleaseRepository(
        linkOpener: opener,
      );

      AppRelease release(String url) => AppRelease.fromJson(
        appReleaseEnvelope(versionCode: 2, downloadUrl: url)['data']
            as Map<String, dynamic>,
      );

      expect(
        await repository.openDownload(release('http://insecure.test/a.apk')),
        isFalse,
      );
      expect(
        await repository.openDownload(
          release('https://agrobenta.example/a.apk'),
        ),
        isTrue,
      );
      expect(opener.opened, <Uri>[
        Uri.parse('https://agrobenta.example/a.apk'),
      ]);
    });
  });

  group('AppUpdateController', () {
    test('a failed check can be retried', () async {
      final AppUpdateController controller = AppUpdateController(
        fakeAppReleaseRepository(
          statusCode: 500,
          envelope: <String, dynamic>{},
        ),
      );
      addTearDown(controller.dispose);

      await controller.check();

      expect(controller.status, AppUpdateStatus.failed);
      expect(controller.installed?.name, '1.0.0');
      expect(await controller.openDownload(), isFalse);
    });
  });

  group('AppUpdateTile', () {
    Future<FakeLinkOpener> pumpTile(
      WidgetTester tester, {
      required Map<String, dynamic> envelope,
      int installedCode = 1,
    }) async {
      final FakeLinkOpener opener = FakeLinkOpener();
      await tester.pumpWidget(
        AppUpdateScope(
          repository: fakeAppReleaseRepository(
            envelope: envelope,
            installedApp: FakeInstalledApp(code: installedCode),
            linkOpener: opener,
          ),
          child: const MaterialApp(
            home: Scaffold(
              body: AppUpdateTile(leading: Icon(Icons.system_update_outlined)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return opener;
    }

    testWidgets('shows the installed version when it is up to date', (
      WidgetTester tester,
    ) async {
      await pumpTile(tester, envelope: appReleaseEnvelope(versionCode: 1));

      expect(find.text('App Update'), findsOneWidget);
      expect(find.text('Version 1.0.0 · Up to date'), findsOneWidget);
      expect(find.text('Update'), findsNothing);

      await tester.tap(find.text('App Update'));
      await tester.pumpAndSettle();
      expect(find.text('You have the latest version.'), findsOneWidget);
    });

    testWidgets('offers a newer build and opens its download', (
      WidgetTester tester,
    ) async {
      final FakeLinkOpener opener = await pumpTile(
        tester,
        envelope: appReleaseEnvelope(
          versionCode: 2,
          versionName: '1.0.1',
          notes: 'Faster photo uploads.',
        ),
      );

      expect(find.text('Version 1.0.1 is available'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);

      await tester.tap(find.text('App Update'));
      await tester.pumpAndSettle();
      expect(find.text('Update to version 1.0.1'), findsOneWidget);
      expect(find.text('Faster photo uploads.'), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(opener.opened, isEmpty);

      await tester.tap(find.text('App Update'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download update'));
      await tester.pumpAndSettle();
      expect(opener.opened, <Uri>[
        Uri.parse('https://agrobenta.example/storage/releases/agrobenta.apk'),
      ]);
    });

    testWidgets('says when the check failed and retries on tap', (
      WidgetTester tester,
    ) async {
      await pumpTile(
        tester,
        envelope: <String, dynamic>{'message': 'Server Error'},
      );
      expect(
        find.text('Version 1.0.0 · Could not check. Tap to retry.'),
        findsOneWidget,
      );
    });
  });
}
