import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/features/profile/state/profile_controller.dart';
import 'package:agrobenta_mobile/features/profile/state/profile_scope.dart';
import 'package:agrobenta_mobile/features/profile/view/address_screen.dart';
import 'package:agrobenta_mobile/repositories/profile_repository.dart';
import 'package:agrobenta_mobile/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/auth_fakes.dart';
import '../../support/trinidad_location_fakes.dart';

/// The Address screen edits the profile's single optional `location` field.
///
/// The catalog is the shared fake from `trinidad_location_fakes.dart`, so these
/// tests exercise the real selector instead of a stand-in. The profile read and
/// write go through the real repository, service and `ApiClient` over a mock
/// transport, so the assertions cover what actually goes over the wire.
void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> requests;

  const Map<String, String> jsonHeaders = <String, String>{
    'content-type': 'application/json',
  };

  const String savedAddress = 'Purok 4, Barangay Banlasan, Trinidad, Bohol';

  setUp(() {
    tokenStore = FakeTokenStore();
    requests = <RecordedRequest>[];
  });

  /// Loads the profile, then pushes [AddressScreen] from a host route so a
  /// successful save can actually pop back to something.
  Future<void> pumpAddress(
    WidgetTester tester, {
    required String? location,
    required Future<http.Response> Function(RecordedRequest request) handler,
  }) async {
    final ProfileRepository repository = ProfileRepository(
      ProfileService(
        ApiClient(
          tokenStorage: tokenStore,
          httpClient: MockClient((http.Request request) async {
            final RecordedRequest entry = RecordedRequest(request);
            requests.add(entry);
            return handler(entry);
          }),
        ),
      ),
    );
    final ProfileController controller = ProfileController(repository);
    addTearDown(controller.dispose);

    tokenStore.token = 'stored-token';
    await controller.load();
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      ProfileScope(
        repository: repository,
        controller: controller,
        child: TrinidadLocationTestScope(
          tokenStore: tokenStore,
          child: const MaterialApp(home: _AddressHost()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open address'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the saved address and saves a changed one', (
    WidgetTester tester,
  ) async {
    await pumpAddress(
      tester,
      location: savedAddress,
      handler: (RecordedRequest request) async {
        if (request.method == 'PUT') {
          return http.Response(
            jsonEncode(
              successEnvelope(
                data: userJson(
                  location: 'Purok 1, Barangay Poblacion, Trinidad, Bohol',
                ),
              ),
            ),
            200,
            headers: jsonHeaders,
          );
        }
        return http.Response(
          jsonEncode(successEnvelope(data: userJson(location: savedAddress))),
          200,
          headers: jsonHeaders,
        );
      },
    );

    // The stored value is visible: the selector is the view and the editor.
    expect(find.text('Banlasan'), findsOneWidget);
    expect(find.text('Purok 4'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bongbong').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Street / Purok (optional)'),
      'Purok 1',
    );
    await tester.pumpAndSettle();

    final Finder save = find.widgetWithText(FilledButton, 'Save address');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    final Iterable<RecordedRequest> puts = requests.where(
      (RecordedRequest request) => request.method == 'PUT',
    );
    expect(puts, hasLength(1));
    expect(puts.single.apiPath, '/profile');
    expect(puts.single.body.keys, <String>['location']);
    expect(
      puts.single.body['location'],
      'Purok 1, Barangay Bongbong, Trinidad, Bohol',
    );
    expect(find.byType(AddressScreen), findsNothing);
  });

  testWidgets('an unchanged address is not saved', (WidgetTester tester) async {
    await pumpAddress(
      tester,
      location: savedAddress,
      handler: (_) async => http.Response(
        jsonEncode(successEnvelope(data: userJson(location: savedAddress))),
        200,
        headers: jsonHeaders,
      ),
    );

    expect(find.text('Banlasan'), findsOneWidget);

    final Finder save = find.widgetWithText(FilledButton, 'Save address');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    // Nothing was edited, so there is nothing to write — the screen closes.
    expect(
      requests.where((RecordedRequest request) => request.method == 'PUT'),
      isEmpty,
    );
    expect(find.byType(AddressScreen), findsNothing);
  });

  testWidgets('an unmatched legacy address is preserved and not re-sent', (
    WidgetTester tester,
  ) async {
    const String legacy = 'Sitio Riverside, Trinidad, Bohol';

    await pumpAddress(
      tester,
      location: legacy,
      handler: (_) async => http.Response(
        jsonEncode(successEnvelope(data: userJson(location: legacy))),
        200,
        headers: jsonHeaders,
      ),
    );

    expect(find.textContaining('could not be matched'), findsOneWidget);
    expect(find.text(legacy), findsOneWidget);

    final Finder save = find.widgetWithText(FilledButton, 'Save address');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    // Nothing changed, so nothing is written — and the legacy value is intact.
    expect(
      requests.where((RecordedRequest request) => request.method == 'PUT'),
      isEmpty,
    );
    expect(find.byType(AddressScreen), findsNothing);
  });

  testWidgets('clearing the address sends an empty location', (
    WidgetTester tester,
  ) async {
    await pumpAddress(
      tester,
      location: savedAddress,
      handler: (RecordedRequest request) async {
        if (request.method == 'PUT') {
          return http.Response(
            jsonEncode(successEnvelope(data: userJson(location: null))),
            200,
            headers: jsonHeaders,
          );
        }
        return http.Response(
          jsonEncode(successEnvelope(data: userJson(location: savedAddress))),
          200,
          headers: jsonHeaders,
        );
      },
    );

    // A street cannot outlive its barangay, so the street is cleared first.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Street / Purok (optional)'),
      '',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No barangay selected').last);
    await tester.pumpAndSettle();

    final Finder save = find.widgetWithText(FilledButton, 'Save address');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    final Iterable<RecordedRequest> puts = requests.where(
      (RecordedRequest request) => request.method == 'PUT',
    );
    expect(puts, hasLength(1));
    expect(puts.single.body, <String, dynamic>{'location': ''});
  });

  testWidgets('a server location error is shown on the field', (
    WidgetTester tester,
  ) async {
    const String message =
        'Choose a barangay in Trinidad, Bohol and enter a valid location.';

    await pumpAddress(
      tester,
      location: savedAddress,
      handler: (RecordedRequest request) async {
        if (request.method == 'PUT') {
          return http.Response(
            jsonEncode(
              validationErrorBody(
                errors: <String, Object>{
                  'location': <String>[message],
                },
              ),
            ),
            422,
            headers: jsonHeaders,
          );
        }
        return http.Response(
          jsonEncode(successEnvelope(data: userJson(location: savedAddress))),
          200,
          headers: jsonHeaders,
        );
      },
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Street / Purok (optional)'),
      'Purok 9',
    );
    await tester.pumpAndSettle();

    final Finder save = find.widgetWithText(FilledButton, 'Save address');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(find.byType(AddressScreen), findsOneWidget);
    expect(find.text(message), findsOneWidget);
  });
}

/// A host route whose only job is to push [AddressScreen], so a successful save
/// pops back to a real screen instead of emptying the navigator.
class _AddressHost extends StatelessWidget {
  const _AddressHost();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => const AddressScreen(),
            ),
          ),
          child: const Text('Open address'),
        ),
      ),
    );
  }
}
