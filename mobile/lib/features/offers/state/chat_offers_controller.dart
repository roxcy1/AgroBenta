import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/realtime/realtime_event.dart';
import '../../../models/offer.dart';
import '../../../repositories/offer_repository.dart';
import 'offer_state.dart';

/// Presentation logic for the offers shown inside one chat thread.
///
/// Per-screen, like `ChatController`: the thread's offers are disposed with
/// the route. The list is always scoped by `counterpart_id`, because a
/// conversation is the buyer–seller pair rather than one listing, so every
/// offer exchanged with this person belongs in the same panel.
///
/// ## Why the actions live here
///
/// Accept, decline and withdraw all change one record and then re-render the
/// same small list. Keeping them beside the list means a successful action
/// updates the badge in place instead of requiring a second fetch, and a
/// duplicate tap is prevented by [ChatOffersState.busyOfferId].
class ChatOffersController extends ChangeNotifier {
  ChatOffersController(
    this._repository, {
    required this.counterpartId,
    this.realtimeEvents,
    this.connection,
  }) {
    _realtimeSubscription = realtimeEvents?.listen(_onRealtimeEvent);
    _connectionSubscription = connection?.listen(_onConnectionChanged);
  }

  final OfferRepository _repository;

  /// The other user in the thread. The list endpoint filters by counterpart,
  /// so this never widens to another buyer–seller pair.
  final int counterpartId;

  /// The session's decoded events. When supplied, an offer created or updated
  /// with this counterpart refreshes the open panel.
  final Stream<RealtimeEvent>? realtimeEvents;

  /// Connection changes; a reconnect re-fetches to recover missed offers.
  final Stream<bool>? connection;

  StreamSubscription<RealtimeEvent>? _realtimeSubscription;
  StreamSubscription<bool>? _connectionSubscription;

  ChatOffersState _state = const ChatOffersState();
  ChatOffersState get state => _state;

  bool _disposed = false;
  bool _loading = false;
  int _generation = 0;

  /// Loads this thread's offers, unless one is already in flight.
  Future<void> load() async {
    if (_loading) {
      return;
    }
    _loading = true;

    final int generation = ++_generation;
    _set(_state.copyWith(status: ChatOffersStatus.loading, clearError: true));

    try {
      final List<Offer> offers = await _repository.list(
        counterpartId: counterpartId,
      );
      if (_disposed || generation != _generation) {
        return;
      }
      _set(_state.copyWith(status: ChatOffersStatus.ready, offers: offers));
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: ChatOffersStatus.failed,
          errorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: ChatOffersStatus.failed,
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
    } finally {
      _loading = false;
    }
  }

  /// The buyer accepts a pending offer.
  ///
  /// Returns the accepted offer **and** the transaction the server created,
  /// or `null` on failure. The transaction is used for the one honest
  /// "View transaction" link the app can offer: `OfferResource` does not carry
  /// a transaction id, so a previously accepted offer cannot be linked later.
  Future<OfferAcceptance?> accept(Offer offer) async {
    if (_state.isBusy) {
      return null;
    }
    _begin(offer.id);

    try {
      final OfferAcceptance result = await _repository.accept(offer.id);
      if (_disposed) {
        return null;
      }
      _replace(result.offer);
      _end();
      return result;
    } on ApiException catch (error) {
      if (_disposed) {
        return null;
      }
      _fail(error.message);
      return null;
    } on Object {
      if (_disposed) {
        return null;
      }
      _fail('Something went wrong. Please try again.');
      return null;
    }
  }

  /// The buyer declines a pending offer.
  Future<void> decline(Offer offer) async {
    if (_state.isBusy) {
      return;
    }
    _begin(offer.id);

    try {
      final Offer updated = await _repository.decline(offer.id);
      if (_disposed) {
        return;
      }
      _replace(updated);
      _end();
    } on ApiException catch (error) {
      if (_disposed) {
        return;
      }
      _fail(error.message);
    } on Object {
      if (_disposed) {
        return;
      }
      _fail('Something went wrong. Please try again.');
    }
  }

  /// The creating seller withdraws a pending offer.
  Future<void> withdraw(Offer offer) async {
    if (_state.isBusy) {
      return;
    }
    _begin(offer.id);

    try {
      final Offer updated = await _repository.withdraw(offer.id);
      if (_disposed) {
        return;
      }
      _replace(updated);
      _end();
    } on ApiException catch (error) {
      if (_disposed) {
        return;
      }
      _fail(error.message);
    } on Object {
      if (_disposed) {
        return;
      }
      _fail('Something went wrong. Please try again.');
    }
  }

  /// Clears the action error after the snackbar has shown it.
  void clearActionError() {
    if (_state.actionErrorMessage == null) {
      return;
    }
    _set(_state.copyWith(clearActionError: true));
  }

  /// An offer created/updated in this buyer–seller pair refreshes the panel.
  /// Scoped to the counterpart so another pair's offer never re-fetches it.
  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.name != 'offer.created' && event.name != 'offer.updated') {
      return;
    }

    final Object? buyerId = event.data['buyer_id'];
    final Object? sellerId = event.data['seller_id'];
    if (buyerId == counterpartId || sellerId == counterpartId) {
      load();
    }
  }

  /// A reconnect may have missed offers while the socket was down.
  void _onConnectionChanged(bool connected) {
    if (connected) {
      load();
    }
  }

  void _begin(int offerId) {
    _set(_state.copyWith(busyOfferId: offerId, clearActionError: true));
  }

  void _end() {
    _set(_state.copyWith(clearBusy: true));
  }

  void _fail(String message) {
    _set(_state.copyWith(actionErrorMessage: message, clearBusy: true));
  }

  void _replace(Offer updated) {
    final List<Offer> next = _state.offers
        .map((Offer offer) => offer.id == updated.id ? updated : offer)
        .toList(growable: false);
    _set(_state.copyWith(offers: next));
  }

  void _set(ChatOffersState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _disposed = true;
    super.dispose();
  }
}
