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

/// Pushes the real edit form from a host route, so Save's `Navigator.pop` is
/// observable instead of popping the only route.
class _EditProfileHost extends StatelessWidget {
  const _EditProfileHost({required this.imagePicker});

  final ImagePicker imagePicker;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (BuildContext context) {
            return FilledButton(
              onPressed: () => Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (BuildContext context) =>
                      EditProfileScreen(imagePicker: imagePicker),
                  fullscreenDialog: true,
                ),
              ),
              child: const Text('Open edit profile'),
            );
          },
        ),
      ),
    );
  }
}

http.Response _jsonResponse(Object body, int statusCode) => http.Response(
  jsonEncode(body),
  statusCode,
  headers: <String, String>{'content-type': 'application/json'},
);

http.Response _profileResponse({String? avatarUrl}) =>
    _jsonResponse(successEnvelope(data: userJson(avatarUrl: avatarUrl)), 200);

Future<ProfileController> _pumpHost(
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
      child: MaterialApp(home: _EditProfileHost(imagePicker: picker)),
    ),
  );
  await tester.pumpAndSettle();

  return controller;
}

Future<void> _openEdit(WidgetTester tester) async {
  await tester.tap(find.text('Open edit profile'));
  await tester.pumpAndSettle();
}

Future<void> _chooseFromGallery(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.camera_alt));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Choose from gallery'));
  await tester.pump();
  await tester.pump();
}

Future<void> _tapSave(WidgetTester tester) async {
  final Finder save = find.widgetWithText(FilledButton, 'Save changes');
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pump();
}

void main() {
  testWidgets('selecting an image only previews it and sends no upload', (
    WidgetTester tester,
  ) async {
    final List<http.Request> requests = <http.Request>[];
    final _FakeImagePicker picker = _FakeImagePicker(
      XFile.fromData(_pngBytes, path: 'avatar.png', name: 'avatar.png'),
    );

    await _pumpHost(
      tester,
      picker: picker,
      handler: (http.Request request) async {
        requests.add(request);
        return _profileResponse();
      },
    );
    await _openEdit(tester);
    await _chooseFromGallery(tester);

    // The preview is built from the picked bytes, not a `dart:io` file.
    expect(find.byType(LocalImagePreview), findsOneWidget);
    final Image preview = tester.widget<Image>(find.byType(Image));
    expect(preview.image, isA<MemoryImage>());

    expect(
      requests.where((http.Request request) => request.method == 'POST'),
      isEmpty,
      reason: 'selecting an avatar must not upload it before Save',
    );
    expect(picker.lastSource, ImageSource.gallery);
  });

  testWidgets('Save uploads the pending avatar once and closes the form', (
    WidgetTester tester,
  ) async {
    final List<http.Request> requests = <http.Request>[];
    final _FakeImagePicker picker = _FakeImagePicker(
      XFile.fromData(_pngBytes, path: 'avatar.png', name: 'avatar.png'),
    );

    final ProfileController controller = await _pumpHost(
      tester,
      picker: picker,
      handler: (http.Request request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return _profileResponse();
        }
        if (request.method == 'POST') {
          return _profileResponse();
        }
        // The test binding answers any real network-image request with a 400,
        // so this response deliberately carries no URL: the upload request
        // itself is what this test asserts.
        return _profileResponse();
      },
    );

    await _openEdit(tester);
    await _chooseFromGallery(tester);
    await _tapSave(tester);
    await tester.pumpAndSettle();

    final List<http.Request> uploads = requests
        .where((http.Request request) => request.method == 'POST')
        .toList();
    expect(uploads, hasLength(1));
    expect(uploads.single.url.path, '/api/profile/avatar');
    expect(latin1.decode(uploads.single.bodyBytes), contains('name="avatar"'));

    final int uploadIndex = requests.indexWhere(
      (http.Request request) => request.method == 'POST',
    );
    final int saveIndex = requests.indexWhere(
      (http.Request request) => request.method == 'PUT',
    );
    expect(saveIndex, greaterThan(uploadIndex));

    expect(controller.state.user, isNotNull);
    expect(find.byType(EditProfileScreen), findsNothing);
    expect(find.text('Open edit profile'), findsOneWidget);
  });

  testWidgets('Back discards the pending avatar without uploading it', (
    WidgetTester tester,
  ) async {
    final List<http.Request> requests = <http.Request>[];
    final _FakeImagePicker picker = _FakeImagePicker(
      XFile.fromData(_pngBytes, path: 'avatar.png', name: 'avatar.png'),
    );

    await _pumpHost(
      tester,
      picker: picker,
      handler: (http.Request request) async {
        requests.add(request);
        return _profileResponse();
      },
    );
    await _openEdit(tester);
    await _chooseFromGallery(tester);

    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();

    expect(find.byType(EditProfileScreen), findsNothing);
    expect(
      requests.where((http.Request request) => request.method == 'POST'),
      isEmpty,
    );
  });

  testWidgets('an upload failure keeps the preview and does not save fields', (
    WidgetTester tester,
  ) async {
    const String message =
        'The avatar field must not be greater than 5120 kilobytes.';
    final List<http.Request> requests = <http.Request>[];
    final _FakeImagePicker picker = _FakeImagePicker(
      XFile.fromData(_pngBytes, path: 'avatar.png', name: 'avatar.png'),
    );

    await _pumpHost(
      tester,
      picker: picker,
      handler: (http.Request request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return _profileResponse();
        }
        if (request.method == 'POST') {
          return _jsonResponse(
            validationErrorBody(
              message: message,
              errors: <String, Object>{
                'avatar': <String>[message],
              },
            ),
            422,
          );
        }
        return _profileResponse();
      },
    );

    await _openEdit(tester);
    await _chooseFromGallery(tester);
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    expect(find.byType(LocalImagePreview), findsOneWidget);
    expect(find.byType(EditProfileScreen), findsOneWidget);
    expect(
      requests.where((http.Request request) => request.method == 'PUT'),
      isEmpty,
      reason: 'an aborted avatar upload must not persist the text fields',
    );

    final FilledButton save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save changes'),
    );
    expect(save.onPressed, isNotNull);
  });

  testWidgets('a second Save tap during the upload sends only one request', (
    WidgetTester tester,
  ) async {
    final Completer<http.Response> upload = Completer<http.Response>();
    final List<http.Request> requests = <http.Request>[];
    final _FakeImagePicker picker = _FakeImagePicker(
      XFile.fromData(_pngBytes, path: 'avatar.png', name: 'avatar.png'),
    );

    await _pumpHost(
      tester,
      picker: picker,
      handler: (http.Request request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return _profileResponse();
        }
        if (request.method == 'POST') {
          return upload.future;
        }
        return _profileResponse();
      },
    );

    await _openEdit(tester);
    await _chooseFromGallery(tester);

    final Finder saveFinder = find.widgetWithText(FilledButton, 'Save changes');
    await tester.ensureVisible(saveFinder);
    await tester.pumpAndSettle();

    final VoidCallback? save = tester
        .widget<FilledButton>(saveFinder)
        .onPressed;
    expect(save, isNotNull);
    save!();
    save();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(
      requests.where((http.Request request) => request.method == 'POST'),
      hasLength(1),
    );

    upload.complete(_profileResponse());
    await tester.pumpAndSettle();

    expect(
      requests.where((http.Request request) => request.method == 'POST'),
      hasLength(1),
    );
    expect(find.byType(EditProfileScreen), findsNothing);
  });

  testWidgets('camera selection uses the camera source and defers the upload', (
    WidgetTester tester,
  ) async {
    final _FakeImagePicker picker = _FakeImagePicker(null);
    final List<http.Request> requests = <http.Request>[];

    await _pumpHost(
      tester,
      picker: picker,
      handler: (http.Request request) async {
        requests.add(request);
        return _profileResponse();
      },
    );
    await _openEdit(tester);

    await tester.tap(find.byIcon(Icons.camera_alt));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();

    expect(picker.lastSource, ImageSource.camera);
    expect(
      requests.where((http.Request request) => request.method == 'POST'),
      isEmpty,
    );
  });
}
