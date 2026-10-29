import 'dart:async';

import 'package:agrobenta_mobile/features/inquiries/state/received_inquiries_controller.dart';
import 'package:agrobenta_mobile/features/inquiries/state/received_inquiries_state.dart';
import 'package:agrobenta_mobile/models/received_inquiry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/inquiry_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('token');
    recorded = <RecordedRequest>[];
  });

  ({
    ReceivedInquiriesController controller,
    List<ReceivedInquiriesState> states,
  })
  build(Future<http.Response> Function(RecordedRequest request) handler) {
    final ReceivedInquiriesController controller =
        buildReceivedInquiriesController(
          tokenStore,
          handler,
          recorded: recorded,
        );
    addTearDown(controller.dispose);

    final List<ReceivedInquiriesState> states = <ReceivedInquiriesState>[
      controller.state,
    ];
    controller.addListener(() => states.add(controller.state));

    return (controller: controller, states: states);
  }

  group('initial load', () {
    test('starts initial with nothing to show', () {
      final ReceivedInquiriesController controller =
          buildReceivedInquiriesController(
            tokenStore,
            (_) async => sellerInquiryListResponse(),
          );
      addTearDown(controller.dispose);

      expect(controller.state.status, ReceivedInquiriesStatus.initial);
      expect(controller.state.inquiries, isEmpty);
      expect(controller.state.pagination, isNull);
    });

    test('loads page one and publishes the server order', () async {
      final (:controller, :states) = build(
        (_) async => sellerInquiryListResponse(
          inquiries: <Map<String, dynamic>>[
            sellerInquiryJson(id: 5),
            sellerInquiryJson(id: 4),
          ],
          total: 2,
        ),
      );

      await controller.loadInitial();

      expect(controller.state.status, ReceivedInquiriesStatus.ready);
      expect(controller.state.inquiries.map((ReceivedInquiry i) => i.id), <int>[
        5,
        4,
      ]);
      expect(
        states.map((ReceivedInquiriesState s) => s.status),
        containsAllInOrder(<ReceivedInquiriesStatus>[
          ReceivedInquiriesStatus.loading,
          ReceivedInquiriesStatus.ready,
        ]),
      );
      expect(recorded.single.method, 'GET');
      expect(recorded.single.apiPath, '/seller/inquiries');
    });

    test(
      'does not send a second first-page request while one is in flight',
      () async {
        final (:controller, :states) = build(
          (_) async => sellerInquiryListResponse(),
        );

        final Future<void> first = controller.loadInitial();
        final Future<void> second = controller.loadInitial();
        await Future.wait<void>(<Future<void>>[first, second]);

        expect(recorded, hasLength(1));
      },
    );
  });

  test('an empty inbox is ready, not failed', () async {
    final (:controller, :states) = build(
      (_) async => sellerInquiryListResponse(
        inquiries: <Map<String, dynamic>>[],
        total: 0,
      ),
    );

    await controller.loadInitial();

    expect(controller.state.status, ReceivedInquiriesStatus.ready);
    expect(controller.state.isEmpty, isTrue);
    expect(controller.state.errorMessage, isNull);
  });

  group('failures', () {
    test('reports the server message for a first-page failure', () async {
      final (:controller, :states) = build(
        (_) async => inquiryServerErrorResponse(),
      );

      await controller.loadInitial();

      expect(controller.state.status, ReceivedInquiriesStatus.failed);
      expect(controller.state.errorMessage, 'Something went wrong on the server.');
      expect(controller.state.inquiries, isEmpty);
    });

    test('a 403 is displayable, not swallowed', () async {
      final (:controller, :states) = build(
        (_) async => http.Response(
          '{"message":"An approved seller account is required."}',
          403,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      await controller.loadInitial();

      expect(controller.state.status, ReceivedInquiriesStatus.failed);
      expect(
        controller.state.errorMessage,
        'An approved seller account is required.',
      );
    });
  });

  group('pagination', () {
    test('appends the next page and advances the cursor', () async {
      final (:controller, :states) = build((RecordedRequest request) async {
        final int page = int.parse(request.query['page'] ?? '1');
        return sellerInquiryListResponse(
          inquiries: <Map<String, dynamic>>[
            sellerInquiryJson(id: page == 1 ? 5 : 4),
          ],
          currentPage: page,
          lastPage: 2,
          total: 2,
        );
      });

      await controller.loadInitial();
      await controller.loadMore();

      expect(controller.state.status, ReceivedInquiriesStatus.ready);
      expect(controller.state.inquiries.map((ReceivedInquiry i) => i.id), <int>[
        5,
        4,
      ]);
      expect(controller.state.currentPage, 2);
      expect(recorded.last.query['page'], '2');
    });

    test('does not request a page the server does not have', () async {
      final (:controller, :states) = build(
        (_) async => sellerInquiryListResponse(lastPage: 1, total: 1),
      );

      await controller.loadInitial();
      await controller.loadMore();

      expect(recorded, hasLength(1));
    });

    test('keeps loaded records when a later page fails', () async {
      final (:controller, :states) = build((RecordedRequest request) async {
        if (request.query['page'] == '2') {
          return inquiryServerErrorResponse();
        }
        return sellerInquiryListResponse(
          inquiries: <Map<String, dynamic>>[sellerInquiryJson(id: 5)],
          lastPage: 2,
          total: 2,
        );
      });

      await controller.loadInitial();
      await controller.loadMore();

      expect(controller.state.status, ReceivedInquiriesStatus.ready);
      expect(controller.state.inquiries, hasLength(1));
      expect(controller.state.loadMoreErrorMessage, 'Something went wrong on the server.');
    });
  });

  test('refresh keeps results on screen while re-querying page one', () async {
    int calls = 0;
    final (:controller, :states) = build((_) async {
      calls++;
      return sellerInquiryListResponse(
        inquiries: <Map<String, dynamic>>[
          sellerInquiryJson(id: calls == 1 ? 5 : 9),
        ],
      );
    });

    await controller.loadInitial();
    await controller.refresh();

    expect(controller.state.status, ReceivedInquiriesStatus.ready);
    expect(
      states.map((ReceivedInquiriesState s) => s.status),
      contains(ReceivedInquiriesStatus.refreshing),
    );
    expect(controller.state.inquiries.single.id, 9);
    expect(recorded.last.query['page'], '1');
  });

  test('does not publish after dispose', () async {
    final Completer<http.Response> completer = Completer<http.Response>();
    final ReceivedInquiriesController controller =
        buildReceivedInquiriesController(tokenStore, (_) => completer.future);

    unawaited(controller.loadInitial());
    await pumpEventQueue();

    controller.dispose();
    completer.complete(sellerInquiryListResponse());
    await pumpEventQueue();

    expect(controller.state.status, ReceivedInquiriesStatus.loading);
  });
}
