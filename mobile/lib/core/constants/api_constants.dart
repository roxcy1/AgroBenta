/// Transport-level constants for API communication.
///
/// Endpoint paths live here, one group per feature, and only once the backend
/// actually serves them. M0 deliberately carried no paths at all: the backend
/// exposed nothing mobile-facing then, and writing a path for an endpoint that
/// does not exist is how invented contracts start. The mobile authentication
/// routes are implemented (`backend/routes/api.php`), and so are the buyer
/// marketplace, seller verification, seller listing and profile routes, so
/// those groups exist below — and nothing else.
library;

abstract final class ApiConstants {
  /// Laravel expects and returns JSON.
  static const String contentTypeJson = 'application/json';

  /// Sent on every request so Laravel returns JSON errors rather than an HTML
  /// error page. Without this, a 500 renders as unparseable HTML and surfaces
  /// as a confusing parse failure.
  static const String acceptJson = 'application/json';

  /// Sanctum personal access token header.
  static const String authorizationHeader = 'Authorization';

  /// Header prefix required by Laravel Sanctum for personal access tokens.
  static const String bearerPrefix = 'Bearer';

  /// Default request timeout.
  ///
  /// Generous enough for a cold Laravel container on a laptop, short enough
  /// that a hung request does not leave the UI spinning indefinitely.
  static const Duration defaultTimeout = Duration(seconds: 30);

  /// Storage key for the Sanctum bearer token inside secure storage.
  ///
  /// The Admin Web uses `localStorage['admin_token']`. Mobile uses a different
  /// store and a different key, because these are different clients with
  /// different lifetimes — not because the token format differs.
  static const String tokenStorageKey = 'agrobenta_api_token';
}

/// Buyer marketplace endpoints, relative to the API root.
///
/// These are the routes implemented in `backend/routes/api.php`. They are the
/// buyer read-only surface and are entirely separate from `/admin/listings*`,
/// which is the Admin Web's flow and is not part of this app's contract.
///
/// Both require a `mobile`-ability Sanctum token. The seller listing surface is
/// a separate group below ([SellerListingEndpoints]), and `/api/livestock` is
/// **not** a path this app ever calls.
abstract final class MarketplaceEndpoints {
  /// `GET` — browse active listings. 200, paginated envelope.
  ///
  /// Query parameters are built by `MarketplaceService` from an explicit
  /// allow-list of the fields `IndexListingRequest` validates. `status` is
  /// deliberately absent: the server rejects it with a 422, because marketplace
  /// visibility is active-only by construction ([D-02] rule 9) and never a
  /// client-selected filter.
  static const String browse = '/listings';

  /// `GET` — one listing's detail. 200, plain envelope.
  ///
  /// [id] is appended to build the path. It is a selector, not proof of
  /// ownership: the server re-checks visibility and answers 404 for a listing
  /// the caller may not see.
  static String detail(int id) => '/listings/$id';

  /// Page size used when the caller does not ask for a specific one.
  ///
  /// Matches the server default, so the first request is an ordinary one rather
  /// than a request that happens to agree with the default.
  static const int defaultPerPage = 15;

  /// Largest page the server will serve.
  ///
  /// `IndexListingRequest` validates `per_page` with `between:1,50`, so
  /// anything above this is rejected with a 422. `MarketplaceRepository`
  /// clamps to this rather than letting a screen discover the limit by
  /// provoking an error.
  static const int maxPerPage = 50;
}

/// Seller verification endpoints, relative to the API root.
///
/// These are the routes implemented in `backend/routes/api.php` for the caller's
/// **own** verification. They are entirely separate from
/// `/admin/seller-verifications*`, which is the Admin Web's review queue: an
/// admin token cannot reach these routes, and nothing here lists, approves or
/// rejects a record.
///
/// Neither endpoint takes an id. The record is always resolved from the
/// authenticated user, which is what makes "read your own verification" a path
/// that cannot be pointed at somebody else's account.
abstract final class SellerVerificationEndpoints {
  /// `GET` — the caller's most recent verification. 200, plain envelope.
  ///
  /// A `404` here means the user has never submitted, which is the normal first
  /// state and not an error to apologise for.
  static const String mine = '/seller-verification/me';

  /// `POST` — submit a verification. 201, plain envelope.
  ///
  /// Creates a new record; a rejected verification is resubmitted by filing
  /// again, never by updating the rejected row (functional documentation §3.2).
  /// Refused with a `409` while a verification is open, and with a `403` for an
  /// account that is already an approved seller.
  static const String submit = '/seller-verification';

  /// `POST` — upload one evidence document (multipart). 201, plain envelope.
  ///
  /// The `type` is a field in the multipart body, one of
  /// `VerificationDocumentType`'s values. Refused with a `403` for an approved
  /// seller and a `409` while an application is already open — an upload is
  /// only meaningful before submitting, to stage the documents the submission
  /// will require.
  static const String documents = '/seller-verification/documents';

  /// `GET` — stream one uploaded document back. 200, raw bytes (not enveloped).
  ///
  /// The response is the file itself, so it is fetched through [ApiClient]'s
  /// binary path rather than the JSON envelope machinery. `404` when no such
  /// document exists for the caller's record.
  static String document(String type) => '/seller-verification/documents/$type';

  /// `DELETE` — remove a staged document by type. 200.
  static String deleteDocument(String type) =>
      '/seller-verification/documents/$type';

  /// The multipart field name the document bytes travel in.
  static const String documentFileField = 'document';

  /// The field names `SubmitSellerVerificationRequest` accepts.
  ///
  /// Anything else is `prohibited` server-side and answers `422`. Listed here so
  /// the service's body is visibly an allow-list of exactly this set, and so a
  /// reader does not have to open the Form Request to know what a submission may
  /// contain.
  static const List<String> writableFields = <String>[
    'business_name',
    'business_location',
    'business_description',
    'id_document_ref',
  ];
}

/// Seller listing management endpoints, relative to the API root.
///
/// These are the routes implemented in `backend/routes/api.php` under the
/// `seller` middleware group. Beyond the `mobile`-ability token they require
/// `User::isApprovedSeller()`, so a buyer is answered `403` — which is why the
/// entry point is gated on the caller's own capability rather than assumed.
///
/// No path here takes a seller id. The scope is the token, resolved server-side,
/// so there is no way for a client to name somebody else's inventory. There is
/// also no `activate`, no `deactivate` and no `sold` path: `active` is an
/// administrator decision, `active → inactive` is too, and a sold listing is a
/// transaction. The seller lifecycle ends at `pending` and this group reflects
/// that by having no route for going further.
abstract final class SellerListingEndpoints {
  /// `GET` — the caller's own listings, in every status. 200, paginated
  /// envelope.
  ///
  /// Unlike [MarketplaceEndpoints.browse], `status` **is** a permitted filter: a
  /// seller needs to find their drafts and their listings awaiting review, which
  /// are exactly the records the marketplace never returns. `seller_id` is
  /// rejected server-side and is not built here.
  static const String mine = '/seller/listings';

  /// `POST` — create a draft. 201, plain envelope.
  ///
  /// Creates a `draft` and nothing else. The response carries the stored listing
  /// so the client does not need a second request to populate its list.
  static const String create = '/seller/listings';

  /// `PATCH` — edit a listing the caller owns. 200, plain envelope.
  ///
  /// A true PATCH: absent fields are left alone, and the server permits it only
  /// while the listing is a `draft` or `active`.
  static String update(int id) => '/seller/listings/$id';

  /// `POST` — submit a draft for review. 200, plain envelope.
  ///
  /// [id] is appended. This is the only lifecycle transition a seller can make,
  /// and it is one-way: the server answers `409` for a listing that is not a
  /// draft.
  static String submit(int id) => '/seller/listings/$id/submit';

  /// `DELETE` — destroy a draft or withdrawn listing. 200.
  ///
  /// [id] is appended. Permitted by the server for a `draft` or `inactive`
  /// listing and `409` for anything else. It is a real deletion, not a
  /// deactivation: nothing here takes a live listing out of sale.
  static String destroy(int id) => '/seller/listings/$id';

  /// `POST` — upload photos to a listing the caller owns. 201.
  ///
  /// [id] is appended. Multipart `photos[]` field; max 10 files per request and
  /// a cumulative per-listing ceiling enforced server-side (422). Permitted only
  /// while the listing is `draft` or `active`.
  static String photos(int id) => '/seller/listings/$id/photos';

  /// `DELETE` — remove one photo from a listing the caller owns. 200.
  ///
  /// [id] is appended. The photo is named by the value the client was served
  /// (URL or bare filename both work) and sent as the `photo` field. 404 when
  /// the named photo is not on the listing.
  static String deletePhoto(int id) => '/seller/listings/$id/photos';

  /// The field names the create and update requests may contain.
  ///
  /// Listed as an explicit allow-list, and used by `SellerListingService` to
  /// build the body, so a server-owned field cannot be added to the request by a
  /// later change to a model. `status` and `seller_id` are absent **by
  /// construction**: the server marks both `prohibited` and answers `422`, and
  /// no code path in this app can put them in a body.
  ///
  /// `photos` is deliberately absent from this JSON body because photos are
  /// associated out of band — `SellerListingService.uploadPhotos` posts them as
  /// multipart to `POST /seller/listings/{id}/photos`, and
  /// `SellerListingService.removePhoto` deletes one by its served URL or
  /// filename — rather than being typed into a field. A draft is created
  /// without photos; locally picked photos are uploaded once the draft has an
  /// id, and the server returns the listing with the absolute URLs it now
  /// serves. Keeping the array out of the create/update body means an unrelated
  /// save cannot rewrite the stored set.
  static const List<String> writableFields = <String>[
    'livestock_type',
    'breed',
    'age_value',
    'age_unit',
    'gender',
    'weight_value',
    'weight_unit',
    'quantity',
    'asking_price',
    'location',
    'health_status',
    'vaccination',
    'short_description',
    'additional_notes',
  ];

  /// The fields the create request requires.
  ///
  /// A subset of [writableFields]. The contract requires these four, so a draft
  /// is a complete-but-unpublished record rather than a half-filled one.
  static const List<String> requiredFields = <String>[
    'livestock_type',
    'location',
    'asking_price',
    'quantity',
  ];

  /// Page size used when the caller does not ask for a specific one.
  ///
  /// Matches the server default and [MarketplaceEndpoints.defaultPerPage]: the
  /// first request is an ordinary one rather than a request that happens to
  /// agree with the default.
  static const int defaultPerPage = 15;

  /// Largest page the server will serve.
  ///
  /// `IndexSellerListingRequest` validates `per_page` with `between:1,50`, so
  /// anything above this is rejected with a `422`. The repository clamps to this
  /// rather than letting a screen discover the limit by provoking an error.
  static const int maxPerPage = 50;
}

/// Transaction endpoints, relative to the API root.
///
/// These are the routes implemented in `backend/routes/api.php` under the
/// `transactions` prefix. Every one requires a `mobile`-ability Sanctum token
/// and resolves the user from that token — no path takes a user id, and
/// `buyer_id` / `seller_id` are refused as filters.
///
/// There is deliberately **no `complete` path** here. The backend answers
/// `POST /transactions/{id}/complete` with an explicit 501 (OQ-15: the
/// confirming actor is undecided), and the client never calls it — hiding the
/// affordance is safer than a button that always errors.
abstract final class TransactionEndpoints {
  /// `GET` — the caller's transactions, newest first. 200, paginated.
  ///
  /// Query allow-list: `role` (`buyer`|`seller`, one side of the caller's own
  /// records), `status` (`pending`|`completed`|`cancelled`, one tab),
  /// `page`, `per_page`. Anything else has no path to the request.
  static const String list = '/transactions';

  /// `POST` — create a pending transaction. 201, plain envelope.
  ///
  /// The caller is the buyer ([D-15] rule 1). Body allow-list is exactly
  /// `{ listing_id, quantity }`; `buyer_id`, `seller_id`, `total_amount` and
  /// `status` are server-derived and refused with 422.
  static const String create = '/transactions';

  /// `GET` — one transaction the caller is party to. 200, plain envelope.
  ///
  /// [id] is a selector, not proof of party: the server re-checks and answers
  /// 404 for a transaction the caller is not party to.
  static String detail(int id) => '/transactions/$id';

  /// `POST` — cancel a pending transaction. 200, plain envelope.
  ///
  /// Either party may cancel ([D-15] rule 5), pending-only, irreversible.
  /// The body allow-list is empty; any field is 422.
  static String cancel(int id) => '/transactions/$id/cancel';

  /// Page size used when the caller does not ask for a specific one.
  static const int defaultPerPage = 15;

  /// Largest page the server will serve (`between:1,50`).
  static const int maxPerPage = 50;
}

/// Messaging endpoints, relative to the API root.
///
/// These are the routes implemented in `backend/routes/api.php` under the
/// `conversations` and `messages` prefixes. Every one requires a
/// `mobile`-ability Sanctum token and resolves the caller from that token —
/// no path takes a user id as proof of identity.
///
/// ## Why there is no `conversation_id`
///
/// There is no `conversations` table. A conversation is derived from the set
/// of messages that touch the caller, identified by the pair
/// `(counterpart_id, listing_id)`. So the paths are built on the *counterpart*
/// id, never on a conversation id — the id the mobile client knows is the
/// user it wants to talk to, not a row that does not exist.
abstract final class MessagingEndpoints {
  /// `GET` — the caller's inbox. 200, plain envelope.
  static const String conversations = '/conversations';

  /// `GET` — the thread with one counterpart. 200, paginated.
  static String thread(int counterpartId) =>
      '/conversations/$counterpartId/messages';

  /// `POST` — mark every unread message from a counterpart as read. 200.
  static String markRead(int counterpartId) =>
      '/conversations/$counterpartId/read';

  /// `POST` — send a message. 201, plain envelope.
  ///
  /// The receiver id is in the body, not the path: the caller can start a
  /// thread with anybody, including a user they have never messaged before.
  static const String send = '/messages';

  /// `PATCH` — mark one message as read. 200, plain envelope.
  static String markOneRead(int messageId) => '/messages/$messageId/read';

  /// Page size used when the caller does not ask for a specific one.
  ///
  /// Matches the server default the thread endpoint uses when `per_page` is
  /// absent.
  static const int defaultPerPage = 30;

  /// Largest page the server will serve (`between:1,50`).
  static const int maxPerPage = 50;
}

/// Notification endpoints, relative to the API root.
///
/// These are the routes implemented in `backend/routes/api.php` under the
/// `notifications` prefix. Every one requires a `mobile`-ability Sanctum
/// token and resolves the caller from that token — no path takes a user id.
///
/// ## Why `read-all` and `unread-count` are separate paths
///
/// `read-all` is declared before `{id}` in the backend so a literal segment
/// cannot be swallowed by the UUID parameter. `unread-count` exists as its
/// own endpoint because the mobile badge must poll it cheaply — fetching a
/// full page of notifications just to read one integer would be wasteful.
abstract final class NotificationEndpoints {
  /// `GET` — the caller's notifications, newest first. 200, paginated.
  ///
  /// Query allow-list: `type` (one of the four categories the filter chips
  /// map to), `unread` (`0`|`1`), `page`, `per_page`.
  static const String list = '/notifications';

  /// `GET` — the caller's unread count. 200, plain envelope.
  static const String unreadCount = '/notifications/unread-count';

  /// `POST` — mark every unread notification as read. 200.
  static const String readAll = '/notifications/read-all';

  /// `PATCH` — mark one notification as read. 200, plain envelope.
  static String read(String id) => '/notifications/$id/read';

  /// `DELETE` — delete one notification. 200.
  ///
  /// Currently unused on mobile — no swipe-to-dismiss in the initial version.
  /// Kept here so a future feature can reach for it without adding a new
  /// constant group.
  static String destroy(String id) => '/notifications/$id';

  /// Page size used when the caller does not ask for a specific one.
  ///
  /// Matches the server default (`IndexNotificationRequest` validates
  /// `between:1,50`).
  static const int defaultPerPage = 15;

  /// Largest page the server will serve.
  static const int maxPerPage = 50;

  /// The four categories the client's filter chips send.
  ///
  /// Mirrors `IndexNotificationRequest::TYPES` on the backend. `All` is not
  /// in the list — it is the absence of a `type` query parameter.
  static const List<String> filterTypes = <String>[
    'transactions',
    'inquiries',
    'listings',
    'system',
  ];
}

/// Profile endpoints, relative to the API root.
///
/// These are the routes implemented in `backend/routes/api.php` for the
/// caller's own account details and credentials. No path takes an id: the
/// record is always resolved from the token, so one account cannot read or
/// write another's profile.
///
/// All three require a `mobile`-ability Sanctum token. `show` and `update`
/// are the caller's own resource; `changePassword` proves the current password
/// before accepting a new one.
abstract final class ProfileEndpoints {
  /// `GET` — the caller's own profile. 200, plain envelope.
  static const String show = '/profile';

  /// `PUT` — update the caller's own profile. 200, plain envelope.
  ///
  /// The Form Request guards every field with `sometimes`, so a partial body
  /// is already a patch in effect. An empty string is a real value — it clears
  /// the column — while an absent key leaves it alone.
  static const String update = '/profile';

  /// `PUT` — change the caller's password. 200, message-only envelope.
  ///
  /// Refused with a `422` when `current_password` does not match, and with a
  /// `422` when the new password fails the policy. The response carries no
  /// `data`; the caller only needs to know the request succeeded.
  static const String changePassword = '/profile/password';

  /// The field names the update request accepts.
  ///
  /// Listed as an explicit allow-list so a service body is visibly exactly this
  /// set. `role`, `seller_capability` and `id` are absent by construction: the
  /// server marks none of them `prohibited` in a way that would answer 422, but
  /// they are not fillable on the model, so sending them is a no-op — which is
  /// worse than a refusal. The allow-list is what keeps them out.
  static const List<String> writableFields = <String>[
    'name',
    'email',
    'phone',
    'location',
    'avatar_url',
    'bio',
  ];
}

/// Inquiry endpoints, relative to the API root.
///
/// These are the routes implemented in `backend/routes/api.php` under the
/// `inquiries`-creating mobile group: one write path, `POST /inquiries`, the
/// buyer's structured contact with a seller about a listing, plus the buyer's
/// pre-check `GET /inquiries/listing/{listing}`. Reading received inquiries is
/// the seller surface in [SellerInquiryEndpoints]; triaging and re-statusing an
/// inquiry are the Admin Web's `/admin/inquiries*` flow and are not part of
/// this app's contract.
///
/// The route takes no user id. The buyer is the token and the seller is
/// `listing.seller_id`, resolved server-side, so there is no parameter or body
/// field that could point an inquiry at a foreign account.
abstract final class InquiryEndpoints {
  /// `POST` — send an inquiry about a listing. 201, plain envelope.
  ///
  /// Body allow-list is exactly [writableFields]; `buyer_id`, `seller_id` and
  /// `status` are server-owned and refused with `422`. The inquiry is created
  /// `open` and changes nothing else — not the listing's status, not a
  /// transaction.
  static const String create = '/inquiries';

  /// `GET` — the authenticated buyer's inquiry about one listing, or
  /// `data: null`. 200, plain envelope.
  ///
  /// The pre-check the Inquire screen runs before rendering the form. The
  /// buyer is the token, so the path carries only the listing id and no query
  /// can widen it to another buyer's record. An inquiry in any status is
  /// returned: the buyer may have only one per listing, whatever its status.
  static String existingForListing(int listingId) =>
      '/inquiries/listing/$listingId';

  /// The field names `StoreInquiryRequest` accepts.
  ///
  /// Listed as an explicit allow-list so the service body is visibly exactly
  /// this set, and so a server-owned field cannot reach a request body by a
  /// later change to a model. `buyer_id`, `seller_id` and `status` are absent
  /// **by construction**: the server marks them `prohibited`.
  ///
  /// `listing_id`, `message`, `payment_method` and `collection_method` are the
  /// four the server requires; everything after them is an optional preference
  /// the schema stores or does not, as the buyer filled it in.
  static const List<String> writableFields = <String>[
    'listing_id',
    'message',
    'collection_date_option',
    'subject',
    'purchase_interest',
    'transaction_method',
    'delivery_method',
    'delivery_fee',
    'contact_method',
    'preferred_schedule',
    'payment_method',
    'collection_method',
  ];
}

/// Seller received-inquiry endpoints, relative to the API root.
///
/// These are the routes implemented in `backend/routes/api.php` under the
/// `seller` middleware group. Beyond the `mobile`-ability token they require
/// `User::isApprovedSeller()`, so a buyer is answered `403` - the entry point is
/// shown only on Seller Home, which already exists for approved sellers.
///
/// The path takes no seller id. The scope is the token, resolved server-side, so
/// there is no parameter that could widen the list to another seller's inbox.
abstract final class SellerInquiryEndpoints {
  /// `GET` - the caller's received inquiries, newest first. 200, paginated.
  ///
  /// Query allow-list is `page` and `per_page` only. `buyer_id`, `seller_id`
  /// and `status` are refused server-side with `422`: this list has no filters
  /// in this phase, and the administrator-facing status is not shown to sellers.
  static const String received = '/seller/inquiries';

  /// Page size used when the caller does not ask for a specific one.
  ///
  /// Matches the server default, so the first request is an ordinary one rather
  /// than a request that happens to agree with the default.
  static const int defaultPerPage = 15;

  /// Largest page the server will serve.
  ///
  /// `IndexSellerInquiryRequest` validates `per_page` with `between:1,50`, so
  /// anything above this is rejected with a `422`. The repository clamps to this
  /// rather than letting a screen discover the limit by provoking an error.
  static const int maxPerPage = 50;
}

/// Seller dashboard endpoint, relative to the API root.
///
/// The response contains listing counts by status, the received-inquiry total,
/// and the seller-side transaction total plus pending count. Revenue,
/// conversion, and completed-transaction figures are deliberately absent.
abstract final class SellerDashboardEndpoints {
  /// `GET` - the authenticated seller's own summary. 200, plain envelope.
  ///
  /// The seller comes from the token. Ownership-shaped query parameters are
  /// refused server-side with `422`, and this service sends no query at all.
  static const String summary = '/seller/dashboard';
}

/// Mobile authentication endpoints, relative to the API root.
///
/// These are the routes implemented in `backend/routes/api.php`. They are
/// separate from `/admin/auth/*`, which is the Admin Web's flow and is not part
/// of this app's contract.
///
/// `me` and `logout` require a `mobile`-ability Sanctum token; `register` and
/// `login` are unauthenticated and are throttled server-side.
abstract final class AuthEndpoints {
  /// `POST` — creates a buyer account and returns a mobile token. 201.
  static const String register = '/auth/register';

  /// `POST` — exchanges credentials for a mobile token. 200.
  static const String login = '/auth/login';

  /// `GET` — the authenticated user's own resource. 200.
  static const String me = '/auth/me';

  /// `POST` — revokes the caller's current mobile token. 200.
  static const String logout = '/auth/logout';
}
