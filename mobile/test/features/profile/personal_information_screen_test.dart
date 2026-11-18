import 'dart:async';
import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/features/profile/state/profile_controller.dart';
import 'package:agrobenta_mobile/features/profile/state/profile_scope.dart';
import 'package:agrobenta_mobile/features/profile/view/edit_profile_screen.dart';
import 'package:agrobenta_mobile/features/profile/view/personal_information_screen.dart';
import 'package:agrobenta_mobile/repositories/profile_repository.dart';
import 'package:agrobenta_mobile/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/auth_fakes.dart';

http.Response _profileResponse() => http.Response(
  jsonEncode(successEnvelope(data: userJson())),
  200,
  headers: <String, String>{'content-type': 'application/json'},
);

Future<ProfileController> _pumpDetails(
  WidgetTester tester, {
  required Future<http.Response> Function(http.Request request) handler,
}) async {
  final FakeTokenStore tokenStore = FakeTokenStore('1|test-mobile-token');
  final ProfileRepository repository = ProfileRepository(
    ProfileService(
      ApiClient(tokenStorage: tokenStore, httpClient: MockClient(handler)),
    ),
  );
  final ProfileController controller = ProfileController(repository);
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    ProfileScope(
      repository: repository,
      controller: controller,
      child: const MaterialApp(home: PersonalInformationScreen()),
    ),
  );

  return controller;
}

void main() {
  testWidgets('disables Edit while the profile is loading', (
    WidgetTester tester,
  ) async {
    final Completer<http.Response> profile = Completer<http.Response>();
    await _pumpDetails(
      tester,
      handler: (http.Request request) => profile.future,
    );
    await tester.pump();

    final TextButton edit = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Edit'),
    );
    expect(edit.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    profile.complete(_profileResponse());
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Edit'))
          .onPressed,
      isNotNull,
    );
    expect(find.text('Ana Reyes'), findsOneWidget);
  });

  testWidgets('shows the profile values and opens one edit form', (
    WidgetTester tester,
  ) async {
    final List<http.Request> requests = <http.Request>[];
    await _pumpDetails(
      tester,
      handler: (http.Request request) async {
        requests.add(request);
        return _profileResponse();
      },
    );
    await tester.pumpAndSettle();

    expect(find.byType(PersonalInformationScreen), findsOneWidget);
    expect(find.text('Ana Reyes'), findsOneWidget);
    expect(find.text('ana@example.test'), findsOneWidget);

    final TextButton edit = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Edit'),
    );
    edit.onPressed!();
    edit.onPressed!();
    await tester.pumpAndSettle();

    expect(find.byType(EditProfileScreen), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Edit'), findsNothing);
  });
}
