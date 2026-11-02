import 'package:flutter/foundation.dart';

import '../../../models/offer.dart';

/// The lifecycle states of the seller's make-offer form.
enum MakeOfferStatus { initial, submitting, succeeded, failed }

/// The immutable state of the make-offer form.
@immutable
class MakeOfferState {
  const MakeOfferState({
    this.status = MakeOfferStatus.initial,
    this.errorMessage,
    this.amountErrorMessage,
    this.created,
  });

  final MakeOfferStatus status;

  /// A failure that is not tied to one field, shown above the submit button.
  final String? errorMessage;

  /// A validation message for the amount field.
  final String? amountErrorMessage;

  /// The offer the server created. Non-null only after a success.
  final Offer? created;

  bool get isSubmitting => status == MakeOfferStatus.submitting;

  MakeOfferState copyWith({
    MakeOfferStatus? status,
    String? errorMessage,
    String? amountErrorMessage,
    Offer? created,
    bool clearErrors = false,
  }) {
    return MakeOfferState(
      status: status ?? this.status,
      errorMessage: clearErrors ? null : (errorMessage ?? this.errorMessage),
      amountErrorMessage: clearErrors
          ? null
          : (amountErrorMessage ?? this.amountErrorMessage),
      created: created ?? this.created,
    );
  }
}

/// The lifecycle states of one chat's offer list.
enum ChatOffersStatus { initial, loading, ready, failed }

/// The immutable state of the offers shown inside one chat.
@immutable
class ChatOffersState {
  const ChatOffersState({
    this.status = ChatOffersStatus.initial,
    this.offers = const <Offer>[],
    this.errorMessage,
    this.actionErrorMessage,
    this.busyOfferId,
  });

  final ChatOffersStatus status;

  /// Newest first, the order `GET /offers` returns.
  final List<Offer> offers;

  /// A load failure for the panel's small inline error.
  final String? errorMessage;

  /// A failure from accepting, declining or withdrawing, shown as a snackbar.
  final String? actionErrorMessage;

  /// The offer with an action in flight, if any. All actions are disabled
  /// while it is set so two taps cannot race each other.
  final int? busyOfferId;

  bool get isLoading =>
      status == ChatOffersStatus.initial || status == ChatOffersStatus.loading;

  bool get isBusy => busyOfferId != null;

  ChatOffersState copyWith({
    ChatOffersStatus? status,
    List<Offer>? offers,
    String? errorMessage,
    String? actionErrorMessage,
    int? busyOfferId,
    bool clearError = false,
    bool clearActionError = false,
    bool clearBusy = false,
  }) {
    return ChatOffersState(
      status: status ?? this.status,
      offers: offers ?? this.offers,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      actionErrorMessage: clearActionError
          ? null
          : (actionErrorMessage ?? this.actionErrorMessage),
      busyOfferId: clearBusy ? null : (busyOfferId ?? this.busyOfferId),
    );
  }
}
