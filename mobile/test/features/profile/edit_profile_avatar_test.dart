import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/features/profile/state/profile_controller.dart';
import 'package:agrobenta_mobile/features/profile/state/profile_scope.dart';
import 'package:agrobenta_mobile/features/profile/view/edit_profile_screen.dart';
import 'package:agrobenta_mobile/repositories/profile_repository.dart';
import 'package:agrobenta_mobile/services/profile_service.dart';
import 'package:agrobenta_mobile/widgets/local_image_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';

import '../../support/auth_fakes.dart';

/// A one-pixel PNG, so the preview has a real frame to decode.
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

/// A picker that returns a canned result without opening a platform UI.
class _FakeImagePicker extends ImagePicker {
  _FakeImagePicker(this.file);

  final XFile? file;

  int calls = 0;
  ImageSource? lastSource;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    calls++;
    lastSource = source;
    return file;
  }
}

http.Response _jsonResponse(Object body, int statusCode) => http.Response(
  jsonEncode(body),
  statusCode,
  headers: <String, String>{'content-type': 'application/json'},
);

Future<ProfileController> _pumpEditScreen(
  WidgetTester tester, {
  required Future<http.Response> Function(http.Request request) handler,
  required ImagePicker picker,
}) async {
  final FakeTokenStore tokenStore = FakeTokenStore('1|test-mobile-token');
  final ProfileRepository repository = ProfileRepository(
    ProfileService(
      ApiClient(tokenStorage: tokenStore, httpClient: MockClient(handler)),
    ),
  );
  final ProfileController controller = ProfileController(repository);
  addTearDown(controller.dispose);

  await controller.load();
  await tester.pumpWidget(
    ProfileScope(
      repository: repository,
      controller: controller,
      child: MaterialApp(home: EditProfileScreen(imagePicker: picker)),
    ),
  );
  await tester.pumpAndSettle();

  return controller;
}

Future<void> _chooseFromGallery(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.camera_alt));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Choose from gallery'));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shows picked bytes immediately and uploads them', (
    WidgetTester tester,
  ) async {
    final Completer<http.Response> upload = Completer<http.Response>();
    final List<http.Request> requests = <http.Request>[];
    final _FakeImagePicker picker = _FakeImagePicker(
      XFile.fromData(_pngBytes, path: 'avatar.png', name: 'avatar.png'),
    );

    final ProfileController controller = await _pumpEditScreen(
      tester,
      picker: picker,
      handler: (http.Request request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return _jsonResponse(successEnvelope(data: userJson()), 200);
        }
        return upload.future;
      },
    );

    await _chooseFromGallery(tester);

    // The preview is built from the picked bytes, not a `dart:io` file.
    expect(find.byType(LocalImagePreview), findsOneWidget);
    final Image preview = tester.widget<Image>(find.byType(Image));
    expect(preview.image, isA<MemoryImage>());

    final http.Request sent = requests.last;
    expect(sent.method, 'POST');
    expect(sent.url.path, '/api/profile/avatar');
    expect(latin1.decode(sent.bodyBytes), contains('name="avatar"'));

    // The response intentionally has no avatar URL: `CircleAvatar` would try
    // to fetch a network image in a widget test, and the controller test
    // already covers the URL merge.
    upload.complete(
      _jsonResponse(
        successEnvelope(data: userJson(name: 'Ana Reyes Updated')),
        200,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Profile picture updated.'), findsOneWidget);
    expect(find.byType(LocalImagePreview), findsNothing);
    expect(controller.state.user?.name, 'Ana Reyes Updated');
  });

  testWidgets(
    'a server rejection shows the API message and clears the preview',
    (WidgetTester tester) async {
      const String message =
          'The avatar field must not be greater than 5120 kilobytes.';
      final _FakeImagePicker picker = _FakeImagePicker(
        XFile.fromData(_pngBytes, path: 'avatar.png', name: 'avatar.png'),
      );

      await _pumpEditScreen(
        tester,
        picker: picker,
        handler: (http.Request request) async {
          if (request.method == 'GET') {
            return _jsonResponse(successEnvelope(data: userJson()), 200);
          }
          return _jsonResponse(
            validationErrorBody(
              message: message,
              errors: <String, Object>{
                'avatar': <String>[message],
              },
            ),
            422,
          );
        },
      );

      await _chooseFromGallery(tester);
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(find.byType(LocalImagePreview), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'camera selection uses the camera source and a cancel sends nothing',
    (WidgetTester tester) async {
      final _FakeImagePicker picker = _FakeImagePicker(null);
      final List<http.Request> requests = <http.Request>[];

      await _pumpEditScreen(
        tester,
        picker: picker,
        handler: (http.Request request) async {
          requests.add(request);
          return _jsonResponse(successEnvelope(data: userJson()), 200);
        },
      );

      await tester.tap(find.byIcon(Icons.camera_alt));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();

      expect(picker.lastSource, ImageSource.camera);
      expect(
        requests.where((http.Request request) => request.method == 'POST'),
        isEmpty,
      );
    },
  );
}
