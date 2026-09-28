import '../../../models/listing.dart';

/// Where one listing's detail request is in its lifecycle.
enum ListingDetailStatus {
  /// The request has not been made yet.
  initial,

  /// In flight. The screen shows a dedicated detail loading state.
  loading,

  /// The listing is loaded and may be shown.
  ready,

  /// The listing is not available to this buyer.
  ///
  /// A `404`, which by [D-02] covers a listing that is `draft`, `pending`,
  /// `inactive` or `sold`, one owned by somebody else, and one that never
  /// existed. The backend deliberately does not distinguish them — answering
  /// `403` would confirm the listing exists — so the app must not guess which
  /// it was either, and does not.
  unavailable,

  /// The request failed for a reason other than "not available".
  failed,
}

/// An immutable snapshot for the listing detail screen.
///
/// The one rule this state exists to enforce: a listing is only ever shown from
/// a [status] of [ListingDetailStatus.ready], which is only ever reached by a
/// successful `GET /listings/{listing}`. The list response is never used as the
/// detail screen's content, so a listing that went inactive between the two
/// requests renders as unavailable rather than as stale data.
class ListingDetailState {
  const ListingDetailState({
    this.status = ListingDetailStatus.initial,
    this.listing,
    this.errorMessage,
  });

  final ListingDetailStatus status;

  /// The listing, set only while [status] is [ListingDetailStatus.ready].
  final Listing? listing;

  /// A displayable failure, for [ListingDetailStatus.failed] only.
  ///
  /// Null for [ListingDetailStatus.unavailable]: the message there is fixed
  /// buyer-facing copy ("This listing is no longer available"), not a server
  /// string, because the server's `404` message names the backend's reason and
  /// means nothing to a buyer.
  final String? errorMessage;

  bool get isLoading => status == ListingDetailStatus.loading;

  bool get isUnavailable => status == ListingDetailStatus.unavailable;

  @override
  String toString() => 'ListingDetailState(${status.name})';
}
