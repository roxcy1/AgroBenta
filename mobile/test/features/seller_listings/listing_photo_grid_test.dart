import 'dart:convert';
import 'dart:typed_data';

import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/seller_listings/state/listing_photo_item.dart';
import 'package:agrobenta_mobile/features/seller_listings/state/seller_listing_controller.dart';
import 'package:agrobenta_mobile/features/seller_listings/state/seller_listing_scope.dart';
import 'package:agrobenta_mobile/features/seller_listings/widgets/listing_photo_grid.dart';
import 'package:agrobenta_mobile/repositories/seller_listing_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../support/seller_listing_fakes.dart';

/// A one-pixel PNG, so a tile has real bytes to render.
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

/// Mounts the photo grid over a real controller. No request is expected, so any
/// that is made answers `404`.
Future<SellerListingController> _pumpGrid(WidgetTester tester) async {
  final SellerListingRepository repository = buildSellerListingRepository(
    FakeTokenStore('1|test-mobile-token'),
    (RecordedRequest request) async => http.Response('Not found', 404),
  );
  final SellerListingController controller = SellerListingController(
    repository,
  );
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    SellerListingScope(
      repository: repository,
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            // The scope is not a notifier, so the screen that owns the grid
            // rebuilds it when the controller changes. A const instance would
            // be reused as-is and never refresh.
            child: ListenableBuilder(
              listenable: controller,
              builder: (BuildContext context, Widget? child) =>
                  ListingPhotoGrid(key: UniqueKey()),
            ),
          ),
        ),
      ),
    ),
  );
  return controller;
}

List<String?> _order(SellerListingController controller) => controller.photos
    .map((ListingPhotoItem photo) => photo.file?.path)
    .toList();

void main() {
  group('add photo', () {
    testWidgets('asks whether to use the gallery or the camera', (
      WidgetTester tester,
    ) async {
      await _pumpGrid(tester);

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();

      expect(find.text('Add photos from'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
    });

    testWidgets('dismissing the choice adds nothing and opens no picker', (
      WidgetTester tester,
    ) async {
      final SellerListingController controller = await _pumpGrid(tester);

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();

      // Tap the barrier outside the dialog. If this fell through to a picker,
      // the test platform has no image_picker plugin and the call would throw.
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(find.text('Add photos from'), findsNothing);
      expect(controller.photos, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('move controls', () {
    testWidgets('the down arrow moves a photo after its neighbour', (
      WidgetTester tester,
    ) async {
      final SellerListingController controller = await _pumpGrid(tester);
      controller.startPhotoComposer(9, const <String>[]);
      controller.addPickedPhotos(<XFile>[
        XFile.fromData(_pngBytes, path: 'a.png'),
        XFile.fromData(_pngBytes, path: 'b.png'),
      ]);
      await tester.pump();

      // Only the first tile has a down arrow that leads anywhere: the last
      // tile has none.
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_downward));
      await tester.pump();

      expect(_order(controller), <String?>['b.png', 'a.png']);
    });
  });
}
