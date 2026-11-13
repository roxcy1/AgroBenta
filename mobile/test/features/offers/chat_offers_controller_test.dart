import 'package:agrobenta_mobile/features/offers/state/chat_offers_controller.dart';
import 'package:agrobenta_mobile/features/offers/state/offer_state.dart';
import 'package:agrobenta_mobile/models/offer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/offer_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('token');
    recorded = <RecordedRequest>[];
  });

  ChatOffersController build(
    Future<http.Response> Function(RecordedRequest request) handler, {
    int counterpartId = 3,
  }) {
    final ChatOffersController controller = buildChatOffersController(
      tokenStore,
      handler,
      counterpartId: counterpartId,
      recorded: recorded,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  group('load', () {
    test(
      'loads the pair-scoped offers and publishes them newest first',
      () async {
        final ChatOffersController controller = build(
          (_) async => offersResponse(
            offers: <Map<String, dynamic>>[
              offerJson(id: 2, status: 'pending'),
              offerJson(id: 1, status: 'declined'),
            ],
          ),
        );

        await controller.load();

        expect(controller.state.status, ChatOffersStatus.ready);
        expect(controller.state.offers.map((Offer o) => o.id), <int>[2, 1]);
        expect(recorded.single.apiPath, '/offers');
        expect(recorded.single.query, <String, String>{'counterpart_id': '3'});
      },
    );

    test('a load failure is reported without inventing offers', () async {
      final ChatOffersController controller = build(
        (_) async => http.Response('{"message":"Server error."}', 500),
      );

      await controller.load();

      expect(controller.state.status, ChatOffersStatus.failed);
      expect(controller.state.offers, isEmpty);
      expect(controller.state.errorMessage, isNotEmpty);
    });
  });

  group('accept', () {
    test(
      'returns the created transaction and updates the offer in place',
      () async {
        final ChatOffersController controller = build((
          RecordedRequest request,
        ) async {
          if (request.method == 'POST') {
            return offerAcceptedResponse(
              offer: offerJson(id: 1, status: 'accepted'),
            );
          }
          return offersResponse();
        });
        await controller.load();

        final OfferAcceptance? result = await controller.accept(
          controller.state.offers.single,
        );

        expect(result, isNotNull);
        expect(result!.transaction.id, 1);
        expect(controller.state.offers.single.status, OfferStatus.accepted);
        expect(controller.state.busyOfferId, isNull);
      },
    );

    test(
      'a conflict leaves the offer untouched and reports the message',
      () async {
        final ChatOffersController controller = build((
          RecordedRequest request,
        ) async {
          if (request.method == 'POST') {
            return offerConflictResponse(message: 'Already accepted.');
          }
          return offersResponse();
        });
        await controller.load();

        final OfferAcceptance? result = await controller.accept(
          controller.state.offers.single,
        );

        expect(result, isNull);
        expect(controller.state.offers.single.status, OfferStatus.pending);
        expect(controller.state.actionErrorMessage, 'Already accepted.');
        expect(controller.state.busyOfferId, isNull);
      },
    );
  });

  group('decline and withdraw', () {
    test('decline replaces the offer with the server state', () async {
      final ChatOffersController controller = build((
        RecordedRequest request,
      ) async {
        if (request.method == 'POST') {
          return offerUpdatedResponse(
            offer: offerJson(id: 1, status: 'declined'),
          );
        }
        return offersResponse();
      });
      await controller.load();

      await controller.decline(controller.state.offers.single);

      expect(controller.state.offers.single.status, OfferStatus.declined);
      expect(recorded.last.apiPath, '/offers/1/decline');
    });

    test('withdraw replaces the offer with the server state', () async {
      final ChatOffersController controller = build((
        RecordedRequest request,
      ) async {
        if (request.method == 'POST') {
          return offerUpdatedResponse(
            offer: offerJson(id: 1, status: 'withdrawn'),
          );
        }
        return offersResponse();
      });
      await controller.load();

      await controller.withdraw(controller.state.offers.single);

      expect(controller.state.offers.single.status, OfferStatus.withdrawn);
      expect(recorded.last.apiPath, '/offers/1/withdraw');
    });
  });
}
