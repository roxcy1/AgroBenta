import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:agrobenta_mobile/features/seller_listings/state/listing_photo_item.dart';
import 'package:agrobenta_mobile/features/seller_listings/state/seller_listing_controller.dart';
import 'package:agrobenta_mobile/features/seller_listings/state/seller_listing_draft.dart';
import 'package:agrobenta_mobile/models/listing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../support/seller_listing_fakes.dart';

/// A one-pixel PNG, so an upload has real bytes to send.
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

/// The controller is where the lifecycle rules are mirrored, so these tests are
/// about the two things that must never go wrong: a seller must never be offered
/// a transition the server refuses, and a stale response must never overwrite a
/// newer one.
void main() {
  group('availability mirrors', () {
    test('canEdit covers draft and active', () {
      // The backend's EDITABLE_STATUSES are [Draft, Active]: a draft is
      // unfinished work the seller may keep changing, an active listing is
      // live but still editable. Everything else is read-only to the seller.
      expect(_canEdit(ListingStatus.draft), isTrue);
      expect(_canEdit(ListingStatus.active), isTrue);
      expect(_canEdit(ListingStatus.pending), isFalse);
      expect(_canEdit(ListingStatus.sold), isFalse);
      expect(_canEdit(ListingStatus.inactive), isFalse);
    });

    test('canSubmit covers draft only', () {
      // The one transition a seller owns, and one-way: nothing else is
      // submittable, which is what stops a re-submit being offered.
      expect(_canSubmit(ListingStatus.draft), isTrue);
      expect(_canSubmit(ListingStatus.pending), isFalse);
      expect(_canSubmit(ListingStatus.active), isFalse);
      expect(_canSubmit(ListingStatus.sold), isFalse);
      expect(_canSubmit(ListingStatus.inactive), isFalse);
    });

    test('canDelete covers draft and inactive only', () {
      expect(_canDelete(ListingStatus.draft), isTrue);
      expect(_canDelete(ListingStatus.inactive), isTrue);
      expect(_canDelete(ListingStatus.pending), isFalse);
      expect(_canDelete(ListingStatus.active), isFalse);
      expect(_canDelete(ListingStatus.sold), isFalse);
    });

    test('submission requires at least one stored photo', () {
      // DEC-03: a draft may exist without photos, but review may not start
      // until one is stored. The server remains the authority; this mirror is
      // what keeps a refused submit from being offered.
      final Listing empty = Listing.fromJson(
        listingJson(id: 1, status: 'draft'),
      );
      final Listing withPhoto = Listing.fromJson(
        listingJson(
          id: 1,
          status: 'draft',
          photos: <Object?>['https://api.test/storage/listings/a.jpg'],
        ),
      );

      expect(SellerListingController.hasSubmissionPhotos(empty), isFalse);
      expect(SellerListingController.hasSubmissionPhotos(withPhoto), isTrue);
    });
  });

  group('loading', () {
    test('the first page lands as ready with its pagination', () async {
      final harness = buildRecordedController(
        (RecordedRequest request) async => sellerListingListResponse(
          listings: <Map<String, dynamic>>[
            listingJson(id: 1, status: 'draft'),
            listingJson(id: 2, status: 'pending'),
          ],
          perPage: 15,
          total: 2,
        ),
      );
      addTearDown(harness.controller.dispose);

      await harness.controller.loadInitial();

      expect(harness.controller.state.status.name, 'ready');
      expect(harness.controller.state.listings, hasLength(2));
      expect(harness.controller.state.pagination?.total, 2);
      expect(harness.controller.state.errorMessage, isNull);
    });

    test(
      'the request carries no status or search for an unfiltered load',
      () async {
        final harness = buildRecordedController(
          (RecordedRequest request) async => sellerListingListResponse(),
        );
        addTearDown(harness.controller.dispose);

        await harness.controller.loadInitial();

        final RecordedRequest sent = harness.recorded.single;
        expect(sent.method, 'GET');
        expect(sent.apiPath, '/seller/listings');
        expect(sent.query.containsKey('status'), isFalse);
        expect(sent.query.containsKey('search'), isFalse);
      },
    );

    test('a 401 fails the load with the server message', () async {
      final harness = buildRecordedController(
        (RecordedRequest request) async => unauthorizedResponse(),
      );
      addTearDown(harness.controller.dispose);

      await harness.controller.loadInitial();

      expect(harness.controller.state.status.name, 'failed');
      expect(harness.controller.state.errorMessage, isNotNull);
      expect(harness.controller.state.listings, isEmpty);
    });

    test('a 403 is reported as an error, not an empty list', () async {
      // A non-seller reaching this screen. An empty list would read as "you have
      // no listings", which is a different and wrong answer.
      final harness = buildRecordedController(
        (RecordedRequest request) async => notApprovedSellerResponse(),
      );
      addTearDown(harness.controller.dispose);

      await harness.controller.loadInitial();

      expect(harness.controller.state.status.name, 'failed');
      expect(harness.controller.state.listings, isEmpty);
      expect(harness.controller.state.errorMessage, isNotNull);
    });

    test(
      'a loadInitial while one is already in flight costs one request',
      () async {
        // Loading resolves synchronously for a mock transport, so a truly
        // concurrent pair needs a handler that holds the response hostage. That is
        // exactly the case the idempotency guard exists for.
        final Completer<http.Response> gate = Completer<http.Response>();
        final harness = buildRecordedController(
          (RecordedRequest request) => gate.future,
        );
        addTearDown(harness.controller.dispose);

        final Future<void> first = harness.controller.loadInitial();
        final Future<void> second = harness.controller.loadInitial();
        gate.complete(sellerListingListResponse());
        await Future.wait(<Future<void>>[first, second]);

        expect(harness.recorded, hasLength(1));
      },
    );
  });

  group('filtering and search', () {
    test('a status filter is sent and resets to page 1', () async {
      final harness = buildRecordedController(
        (RecordedRequest request) async => sellerListingListResponse(),
      );
      addTearDown(harness.controller.dispose);

      await harness.controller.loadInitial();
      await harness.controller.applyStatusFilter(ListingStatus.draft);

      final RecordedRequest filtered = harness.recorded.last;
      expect(filtered.query['status'], 'draft');
      expect(filtered.query['page'], '1');
      expect(harness.controller.state.statusFilter, ListingStatus.draft);
    });

    test('re-applying the same filter costs no request', () async {
      final harness = buildRecordedController(
        (RecordedRequest request) async => sellerListingListResponse(),
      );
      addTearDown(harness.controller.dispose);

      await harness.controller.loadInitial();
      await harness.controller.applyStatusFilter(ListingStatus.draft);
      final int after = harness.recorded.length;

      await harness.controller.applyStatusFilter(ListingStatus.draft);

      expect(harness.recorded, hasLength(after));
    });

    group('active tab inactive tail', () {
      test(
        'the active tab appends page 1 of inactive below the active rows',
        () async {
          final harness = buildRecordedController((
            RecordedRequest request,
          ) async {
            if (request.query['status'] == 'inactive') {
              return sellerListingListResponse(
                listings: <Map<String, dynamic>>[
                  listingJson(id: 9, status: 'inactive'),
                ],
                total: 1,
              );
            }
            return sellerListingListResponse(
              listings: <Map<String, dynamic>>[
                listingJson(id: 1, status: 'active'),
              ],
              total: 1,
            );
          });
          addTearDown(harness.controller.dispose);

          await harness.controller.applyStatusFilter(ListingStatus.active);

          final List<Listing> listings = harness.controller.state.listings;
          expect(listings.map((Listing listing) => listing.id).toList(), <int>[
            1,
            9,
          ]);
          expect(
            listings.map((Listing listing) => listing.status).toList(),
            <ListingStatus>[ListingStatus.active, ListingStatus.inactive],
          );
        },
      );

      test('other tabs do not fetch the inactive tail', () async {
        final harness = buildRecordedController(
          (RecordedRequest request) async => sellerListingListResponse(),
        );
        addTearDown(harness.controller.dispose);

        await harness.controller.applyStatusFilter(ListingStatus.pending);

        expect(harness.recorded, hasLength(1));
        expect(harness.recorded.single.query['status'], 'pending');
      });

      test(
        'a search on the active tab does not fetch the inactive tail',
        () async {
          final harness = buildRecordedController(
            (RecordedRequest request) async => sellerListingListResponse(),
          );
          addTearDown(harness.controller.dispose);

          await harness.controller.applyStatusFilter(ListingStatus.active);
          final int afterFilter = harness.recorded.length;
          harness.controller.updateSearch('goat');
          await harness.controller.submitSearch();

          expect(harness.recorded, hasLength(afterFilter + 1));
          expect(harness.recorded.last.query['status'], 'active');
        },
      );
    });
    test('clearing the query drops both the filter and the search', () async {
      final harness = buildRecordedController(
        (RecordedRequest request) async => sellerListingListResponse(),
      );
      addTearDown(harness.controller.dispose);

      await harness.controller.loadInitial();
      await harness.controller.applyStatusFilter(ListingStatus.draft);
      harness.controller.updateSearch('cattle');
      await harness.controller.clearQuery();

      expect(harness.controller.state.statusFilter, isNull);
      expect(harness.controller.state.searchText, isEmpty);
      final RecordedRequest last = harness.recorded.last;
      expect(last.query.containsKey('status'), isFalse);
      expect(last.query.containsKey('search'), isFalse);
    });

    test(
      'submitSearch sends the debounced text without waiting for the timer',
      () async {
        final harness = buildRecordedController(
          (RecordedRequest request) async => sellerListingListResponse(),
        );
        addTearDown(harness.controller.dispose);

        await harness.controller.loadInitial();
        harness.controller.updateSearch('cattle');
        await harness.controller.submitSearch();

        expect(harness.recorded.last.query['search'], 'cattle');
      },
    );
  });

  group('pagination', () {
    test('loadMore appends the next page', () async {
      final harness = buildRecordedController((RecordedRequest request) async {
        if (request.query['page'] == '2') {
          return sellerListingListResponse(
            listings: <Map<String, dynamic>>[
              listingJson(id: 3, status: 'active'),
            ],
            currentPage: 2,
            lastPage: 2,
            perPage: 2,
            total: 3,
          );
        }
        return sellerListingListResponse(
          listings: <Map<String, dynamic>>[
            listingJson(id: 1, status: 'draft'),
            listingJson(id: 2, status: 'draft'),
          ],
          perPage: 2,
          total: 3,
          lastPage: 2,
        );
      });
      addTearDown(harness.controller.dispose);

      await harness.controller.loadInitial();
      await harness.controller.loadMore();

      expect(harness.controller.state.listings.map((Listing l) => l.id), <int>[
        1,
        2,
        3,
      ]);
      expect(harness.controller.state.hasMorePages, isFalse);
    });

    test('a failed page keeps the listings already on screen', () async {
      // The page that loaded is still valid. Only the "load more" affordance
      // reports the failure.
      final harness = buildRecordedController((RecordedRequest request) async {
        if (request.query['page'] == '2') {
          return http_500();
        }
        return sellerListingListResponse(
          listings: <Map<String, dynamic>>[listingJson(id: 1, status: 'draft')],
          lastPage: 2,
          perPage: 1,
          total: 2,
        );
      });
      addTearDown(harness.controller.dispose);

      await harness.controller.loadInitial();
      await harness.controller.loadMore();

      expect(harness.controller.state.listings, hasLength(1));
      expect(harness.controller.state.loadMoreErrorMessage, isNotNull);
      expect(harness.controller.state.status.name, 'ready');
    });

    test('loadMore does nothing when there is no next page', () async {
      final harness = buildRecordedController(
        (RecordedRequest request) async => sellerListingListResponse(
          listings: <Map<String, dynamic>>[listingJson(id: 1, status: 'draft')],
          lastPage: 1,
          perPage: 15,
          total: 1,
        ),
      );
      addTearDown(harness.controller.dispose);

      await harness.controller.loadInitial();
      final int after = harness.recorded.length;

      await harness.controller.loadMore();

      expect(harness.recorded, hasLength(after));
    });
  });

  group('create', () {
    test('posts the draft body and merges the new listing in', () async {
      final harness = buildRecordedController(
        (RecordedRequest request) async => sellerListingResponse(
          listing: listingJson(id: 9, status: 'draft'),
          statusCode: 201,
        ),
      );
      addTearDown(harness.controller.dispose);

      final Listing? created = await harness.controller.create(
        SellerListingDraft(
          livestockType: 'Cattle',
          quantity: '4',
          askingPrice: '42500',
          location: 'Mabalacat, Pampanga',
        ),
      );

      expect(created?.id, 9);
      final RecordedRequest sent = harness.recorded.first;
      expect(sent.method, 'POST');
      expect(sent.apiPath, '/seller/listings');
      expect(sent.body['livestock_type'], 'Cattle');
      expect(sent.body['quantity'], 4);
      // An omitted optional field is absent, not null: on a PATCH a null would be
      // asking the server to clear something the seller never touched.
      expect(sent.body.containsKey('breed'), isFalse);
      expect(sent.body.containsKey('status'), isFalse);
    });

    test('a second create while one is in flight is refused locally', () async {
      // The duplicate-submission guard. A disabled button stops a tap; it does not
      // stop a second request following the first one already on the wire.
      final harness = buildRecordedController(
        (RecordedRequest request) async => sellerListingResponse(
          listing: listingJson(id: 9, status: 'draft'),
          statusCode: 201,
        ),
      );
      addTearDown(harness.controller.dispose);

      final Future<Listing?> first = harness.controller.create(
        const SellerListingDraft(livestockType: 'Cattle'),
      );
      final Listing? second = await harness.controller.create(
        const SellerListingDraft(livestockType: 'Goat'),
      );

      expect(second, isNull);
      await first;
      expect(
        harness.recorded.where((RecordedRequest r) => r.method == 'POST'),
        hasLength(1),
      );
    });

    test('a 422 surfaces per-field messages and creates nothing', () async {
      final harness = buildRecordedController(
        (RecordedRequest request) async => validationResponse(
          errors: <String, Object>{
            'asking_price': <String>['The asking price must be at least 0.'],
          },
        ),
      );
      addTearDown(harness.controller.dispose);

      final Listing? created = await harness.controller.create(
        const SellerListingDraft(livestockType: 'Cattle'),
      );

      expect(created, isNull);
      expect(
        harness.controller.state.validationErrors['asking_price'],
        isNotEmpty,
      );
      expect(harness.controller.state.actionErrorMessage, isNotNull);
      expect(harness.controller.state.action.name, 'none');
    });
  });

  group('submit', () {
    test('posts to the submit route and replaces the row in place', () async {
      final harness = buildRecordedController((RecordedRequest request) async {
        if (request.apiPath.endsWith('/submit')) {
          return sellerListingResponse(
            listing: listingJson(id: 1, status: 'pending'),
          );
        }
        return sellerListingListResponse(
          listings: <Map<String, dynamic>>[
            listingJson(id: 1, status: 'draft'),
            listingJson(id: 2, status: 'active'),
          ],
          total: 2,
        );
      });
      addTearDown(harness.controller.dispose);

      await harness.controller.loadInitial();
      await harness.controller.submit(1);

      final RecordedRequest sent = harness.recorded.firstWhere(
        (RecordedRequest r) => r.apiPath.endsWith('/submit'),
      );
      expect(sent.method, 'POST');
      expect(sent.apiPath, '/seller/listings/1/submit');

      final List<Listing> listings = harness.controller.state.listings;
      expect(listings, hasLength(2));
      // Replaced, not appended: the row keeps its place in the list.
      expect(listings.first.id, 1);
      expect(listings.first.status, ListingStatus.pending);
    });

    test('a 409 becomes a conflict message and re-reads the list', () async {
      // The listing has already moved on — already submitted, or approved since.
      final harness = buildRecordedController((RecordedRequest request) async {
        if (request.apiPath.endsWith('/submit')) {
          return listingConflictResponse(
            message: 'Only a draft listing can be submitted for review.',
          );
        }
        return sellerListingListResponse(
          listings: <Map<String, dynamic>>[
            listingJson(id: 1, status: 'pending'),
          ],
          total: 1,
        );
      });
      addTearDown(harness.controller.dispose);

      await harness.controller.loadInitial();
      await harness.controller.submit(1);

      expect(harness.controller.state.conflictMessage, isNotNull);
      expect(harness.controller.state.actionErrorMessage, isNull);
      // The screen must settle on the server's truth, not the client's belief.
      expect(
        harness.controller.state.listings.single.status,
        ListingStatus.pending,
      );
    });
  });

  group('update', () {
    test('patches the listing and swaps the row', () async {
      final harness = buildRecordedController((RecordedRequest request) async {
        if (request.method == 'PATCH') {
          return sellerListingResponse(
            listing: listingJson(id: 1, status: 'draft', breed: 'Brahman'),
          );
        }
        return sellerListingListResponse(
          listings: <Map<String, dynamic>>[listingJson(id: 1, status: 'draft')],
          total: 1,
        );
      });
      addTearDown(harness.controller.dispose);

      await harness.controller.loadInitial();
      final Listing? updated = await harness.controller.update(
        1,
        const SellerListingDraft(
          livestockType: 'Cattle',
          breed: 'Brahman',
          quantity: '2',
          askingPrice: '50000',
          location: 'Mabalacat, Pampanga',
        ),
      );

      expect(updated?.breed, 'Brahman');
      final RecordedRequest sent = harness.recorded.firstWhere(
        (RecordedRequest r) => r.method == 'PATCH',
      );
      expect(sent.apiPath, '/seller/listings/1');
      expect(sent.body['breed'], 'Brahman');
      expect(harness.controller.state.listings.single.breed, 'Brahman');
    });

    test('a 409 on edit becomes a conflict, not a validation error', () async {
      // Editing a listing that has been submitted is a lifecycle problem, and
      // reporting it under a field would send the seller looking in the wrong
      // place.
      final harness = buildRecordedController(
        (RecordedRequest request) async => listingConflictResponse(
          message: 'Only a draft or active listing can be edited.',
        ),
      );
      addTearDown(harness.controller.dispose);

      await harness.controller.update(
        1,
        const SellerListingDraft(livestockType: 'Cattle'),
      );

      expect(harness.controller.state.conflictMessage, isNotNull);
      expect(harness.controller.state.validationErrors, isEmpty);
    });
  });

  group('delete', () {
    test('removes the row locally and reports success', () async {
      final harness = buildRecordedController((RecordedRequest request) async {
        if (request.method == 'DELETE') {
          return sellerListingDeletedResponse();
        }
        return sellerListingListResponse(
          listings: <Map<String, dynamic>>[
            listingJson(id: 1, status: 'draft'),
            listingJson(id: 2, status: 'active'),
          ],
          total: 2,
        );
      });
      addTearDown(harness.controller.dispose);

      await harness.controller.loadInitial();
      final bool deleted = await harness.controller.delete(1);

      expect(deleted, isTrue);
      expect(harness.controller.state.listings.map((Listing l) => l.id), <int>[
        2,
      ]);
      final RecordedRequest sent = harness.recorded.firstWhere(
        (RecordedRequest r) => r.method == 'DELETE',
      );
      expect(sent.apiPath, '/seller/listings/1');
    });

    test('a 404 leaves the row in place', () async {
      // Not the caller's listing, or already gone. The optimistic removal must
      // not stand: the seller is told it failed, and the row stays until the
      // re-read confirms.
      final harness = buildRecordedController(
        (RecordedRequest request) async => listingNotFoundResponse(),
      );
      addTearDown(harness.controller.dispose);

      final bool deleted = await harness.controller.delete(1);

      expect(deleted, isFalse);
      expect(harness.controller.state.listings, isEmpty);
      expect(harness.controller.state.actionErrorMessage, isNotNull);
    });

    test('a 409 on delete becomes a conflict', () async {
      // Deleting a live or pending listing. The server refuses, and the seller is
      // told the listing is not in a state that allows it.
      final harness = buildRecordedController(
        (RecordedRequest request) async => listingConflictResponse(
          message: 'Only a draft or inactive listing can be deleted.',
        ),
      );
      addTearDown(harness.controller.dispose);

      final bool deleted = await harness.controller.delete(1);

      expect(deleted, isFalse);
      expect(harness.controller.state.conflictMessage, isNotNull);
    });
  });

  group('action state', () {
    test('the busy state names the listing the action is for', () async {
      final harness = buildRecordedController(
        (RecordedRequest request) async => listingConflictResponse(),
      );
      addTearDown(harness.controller.dispose);

      final Future<Listing?> pending = harness.controller.submit(42);
      // Synchronously observable, because a card needs to know which row to dim.
      expect(harness.controller.state.actionListingId, 42);
      expect(harness.controller.state.action.name, 'submitting');

      await pending;
      expect(harness.controller.state.actionListingId, isNull);
      expect(harness.controller.state.action.name, 'none');
    });

    test('clearActionMessage discards every form-level message', () async {
      final harness = buildRecordedController(
        (RecordedRequest request) async => listingConflictResponse(),
      );
      addTearDown(harness.controller.dispose);

      await harness.controller.submit(1);
      expect(harness.controller.state.conflictMessage, isNotNull);

      harness.controller.clearActionMessage();

      expect(harness.controller.state.conflictMessage, isNull);
      expect(harness.controller.state.actionErrorMessage, isNull);
    });
  });

  group('photos', () {
    test(
      'uploading pending photos rebuilds the composer from served URLs',
      () async {
        final harness = buildRecordedController((
          RecordedRequest request,
        ) async {
          if (request.method == 'POST' &&
              request.apiPath == '/seller/listings/9/photos') {
            return sellerListingResponse(
              listing: listingJson(
                id: 9,
                status: 'draft',
                photos: <Object?>['https://api.test/storage/listings/a.jpg'],
              ),
              statusCode: 201,
            );
          }
          return http.Response('Not found', 404);
        });
        addTearDown(harness.controller.dispose);

        harness.controller.startPhotoComposer(9, const <String>[]);
        harness.controller.addPickedPhotos(<XFile>[
          XFile.fromData(_pngBytes, path: 'a.png'),
        ]);

        final bool uploaded = await harness.controller.uploadComposerPhotos(9);

        expect(uploaded, isTrue);
        expect(harness.controller.photos, hasLength(1));
        expect(
          harness.controller.photos.single.status,
          ListingPhotoStatus.uploaded,
        );
        expect(
          harness.controller.photos.single.url,
          'https://api.test/storage/listings/a.jpg',
        );
        expect(harness.recorded.single.method, 'POST');
        expect(harness.recorded.single.apiPath, '/seller/listings/9/photos');
        expect(
          harness.recorded.single.request.headers['content-type'],
          contains('multipart/form-data'),
        );
      },
    );

    test('a failed batch is marked failed and can be retried', () async {
      bool failUpload = true;
      final harness = buildRecordedController((RecordedRequest request) async {
        if (request.method == 'POST' &&
            request.apiPath == '/seller/listings/9/photos') {
          if (failUpload) {
            return http_500();
          }
          return sellerListingResponse(
            listing: listingJson(
              id: 9,
              status: 'draft',
              photos: <Object?>['https://api.test/storage/listings/a.jpg'],
            ),
            statusCode: 201,
          );
        }
        return http.Response('Not found', 404);
      });
      addTearDown(harness.controller.dispose);

      harness.controller.startPhotoComposer(9, const <String>[]);
      harness.controller.addPickedPhotos(<XFile>[
        XFile.fromData(_pngBytes, path: 'a.png'),
      ]);

      final bool first = await harness.controller.uploadComposerPhotos(9);

      expect(first, isFalse);
      expect(
        harness.controller.photos.single.status,
        ListingPhotoStatus.failed,
      );
      expect(harness.controller.photos.single.error, isNotNull);
      // The listing id survives the failure, or the retry would have nowhere
      // to send the same batch.
      expect(harness.controller.state.actionListingId, 9);
      expect(harness.controller.state.actionErrorMessage, isNotNull);

      failUpload = false;
      final bool retried = await harness.controller.retryFailedPhotos();

      expect(retried, isTrue);
      expect(
        harness.controller.photos.single.status,
        ListingPhotoStatus.uploaded,
      );
      expect(harness.recorded, hasLength(2));
      expect(
        harness.recorded.map((RecordedRequest r) => r.apiPath),
        everyElement('/seller/listings/9/photos'),
      );
    });

    test('a retry without a listing to attach to does nothing', () async {
      final harness = buildRecordedController(
        (RecordedRequest request) async => http.Response('Not found', 404),
      );
      addTearDown(harness.controller.dispose);

      harness.controller.startPhotoComposer(null, const <String>[]);
      harness.controller.addPickedPhotos(<XFile>[
        XFile.fromData(_pngBytes, path: 'a.png'),
      ]);

      final bool retried = await harness.controller.retryFailedPhotos();

      expect(retried, isFalse);
      expect(harness.recorded, isEmpty);
    });
  });

  group('lifecycle rules', () {
    test('the draft list is immutable, so a repeat save sends the same body', () {
      // A draft is a value. If it were mutable, a body could be built from fields
      // that have since changed on screen.
      const SellerListingDraft first = SellerListingDraft(
        livestockType: 'Cattle',
        quantity: '4',
      );
      final SellerListingDraft second = SellerListingDraft(
        livestockType: 'Goat',
        quantity: '9',
      );

      expect(first.toRequestBody()['livestock_type'], 'Cattle');
      expect(second.toRequestBody()['livestock_type'], 'Goat');
    });
  });
}

/// A draft that is only used for its status.
Listing _listing(ListingStatus status) =>
    Listing.fromJson(listingJson(id: 1, status: status.value));

bool _canEdit(ListingStatus status) =>
    SellerListingController.canEdit(_listing(status));
bool _canSubmit(ListingStatus status) =>
    SellerListingController.canSubmit(_listing(status));
bool _canDelete(ListingStatus status) =>
    SellerListingController.canDelete(_listing(status));

/// A `500`, for the paths that should not be assumed to work.
http.Response http_500() => http.Response('Internal Server Error', 500);
