import 'package:agrobenta_mobile/core/config/app_config.dart';
import 'package:agrobenta_mobile/core/theme/app_colors.dart';
import 'package:agrobenta_mobile/features/auth/view/register_screen.dart';
import 'package:agrobenta_mobile/features/auth/view/sign_in_screen.dart';
import 'package:agrobenta_mobile/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_app_harness.dart';
import 'support/auth_fakes.dart';

void main() {
  testWidgets('the app boots into the sign-in form', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(AgroBentaApp(tokenStore: FakeTokenStore()));
    await settleAuth(tester);

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(RegisterScreen), findsNothing);
  });

  testWidgets('the AgroBenta theme is applied', (WidgetTester tester) async {
    await tester.pumpWidget(AgroBentaApp(tokenStore: FakeTokenStore()));
    await settleAuth(tester);

    final MaterialApp app = tester.widget<MaterialApp>(
      find.byType(MaterialApp),
    );
    expect(app.title, 'AgroBenta');
    expect(app.theme?.colorScheme.primary, AppColors.primary);
  });

  testWidgets('the API base URL never defaults to the emulator alias', (
    WidgetTester tester,
  ) async {
    // A native Android build has no default URL: it needs API_BASE_URL or an
    // explicit ANDROID_RUN_TARGET=emulator, so there is nothing to assert for
    // it here. Every other platform resolves to loopback, never to 10.0.2.2.
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(AppConfig.apiBaseUrl, 'http://localhost:8001/api');
    expect(AppConfig.apiBaseUrl, isNot(contains('10.0.2.2')));
    debugDefaultTargetPlatformOverride = null;

    await tester.pumpWidget(AgroBentaApp(tokenStore: FakeTokenStore()));
    await settleAuth(tester);

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
