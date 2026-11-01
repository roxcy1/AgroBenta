<?php

use App\Http\Controllers\Api\Admin\ActivityController;
use App\Http\Controllers\Api\Admin\AuthController;
use App\Http\Controllers\Api\Admin\DashboardController;
use App\Http\Controllers\Api\Admin\InquiryController;
use App\Http\Controllers\Api\Admin\ListingController;
use App\Http\Controllers\Api\Admin\ReportsController;
use App\Http\Controllers\Api\Admin\SellerVerificationController;
use App\Http\Controllers\Api\Admin\SettingsController;
use App\Http\Controllers\Api\Admin\TransactionController;
use App\Http\Controllers\Api\Admin\UserController;
use App\Http\Controllers\Api\Auth\AuthController as MobileAuthController;
use App\Http\Controllers\Api\CurrentUserController;
use App\Http\Controllers\Api\Inquiry\InquiryController as MobileInquiryController;
use App\Http\Controllers\Api\Marketplace\ListingController as MarketplaceListingController;
use App\Http\Controllers\Api\Messaging\ConversationController;
use App\Http\Controllers\Api\Messaging\MessageController;
use App\Http\Controllers\Api\Notification\NotificationController;
use App\Http\Controllers\Api\Profile\ProfileController;
use App\Http\Controllers\Api\SellerDashboard\SellerDashboardController;
use App\Http\Controllers\Api\SellerInquiry\SellerInquiryController;
use App\Http\Controllers\Api\SellerListing\SellerListingController;
use App\Http\Controllers\Api\SellerVerification\SellerVerificationController as MobileSellerVerificationController;
use App\Http\Controllers\Api\Transaction\TransactionController as MobileTransactionController;
use Illuminate\Support\Facades\Route;

Route::middleware('auth:sanctum')->get('/user', CurrentUserController::class);

Route::post('/admin/auth/login', [AuthController::class, 'login'])
    ->middleware('throttle:10,1');

// Mobile authentication. Separate from the admin flow: the token issued here
// carries the `mobile` ability only, and the `ability:mobile` guard on the
// authenticated routes is what actually enforces it.
Route::prefix('auth')->group(function (): void {
    Route::post('/register', [MobileAuthController::class, 'register'])
        ->middleware('throttle:5,1');
    Route::post('/login', [MobileAuthController::class, 'login'])
        ->middleware('throttle:10,1');

    Route::middleware('auth:sanctum', 'ability:mobile')->group(function (): void {
        Route::get('/me', [MobileAuthController::class, 'me']);
        Route::post('/logout', [MobileAuthController::class, 'logout']);
    });
});

// Buyer marketplace. Read-only: browse and detail for active listings only.
// `ability:mobile` is the authorisation boundary, so a mobile token reaches
// this group and an admin token does not, in the same direction enforced for
// the auth group above. Visibility is enforced in the query, and `status` is
// not an accepted parameter — see IndexListingRequest.
Route::middleware('auth:sanctum', 'ability:mobile')->group(function (): void {
    Route::get('/listings', [MarketplaceListingController::class, 'index']);
    Route::get('/listings/{listing}', [MarketplaceListingController::class, 'show']);
});

// Seller verification, for the caller's own account. `/me` is declared before
// the group so a future `/seller-verification/{id}` could never be shadowed by
// it, and no route here takes an id: the record is always resolved from the
// authenticated user, so one buyer cannot read another's verification.
//
// Submission grants nothing. `seller_capability` is set only by the admin
// approval endpoint above, and `SellerVerificationController` never writes it.
//
// No throttle here, deliberately. The contract's throttling inventory (§3.5)
// lists only login, register and price-suggestion, and D-09 is still open, so a
// limit on this route would be an undocumented behaviour change: it would turn
// the sixth attempt in a minute into a 429 that the contract never promises. The
// abuse ceiling that does exist is the open-record rule below — one application
// per buyer per open state, refused with 409 — plus `auth:sanctum`. Revisit under
// D-09 if a limit is decided.
Route::middleware('auth:sanctum', 'ability:mobile')->prefix('seller-verification')->group(function (): void {
    Route::get('/me', [MobileSellerVerificationController::class, 'me']);
    Route::post('/', [MobileSellerVerificationController::class, 'store']);

    // Document upload (government ID + selfie). Staged under the caller's own
    // id before submission, replaced or deleted while the application is still
    // being assembled, and promoted onto the record when `POST /` succeeds.
    //
    // Neither route takes an id: the account is the token, so there is no path
    // that could stage a file against somebody else's application. The file
    // rules live in UploadSellerVerificationDocumentRequest and are enforced on
    // the bytes, not the client's filename. The response never carries a path
    // or URL — the file is on private storage and is read back only through
    // GET /documents/{type} below, which resolves the record from the token.
    Route::post('/documents', [MobileSellerVerificationController::class, 'storeDocument']);
    Route::get('/documents/{type}', [MobileSellerVerificationController::class, 'showDocument']);
    Route::delete('/documents/{type}', [MobileSellerVerificationController::class, 'destroyDocument']);
});

// Seller listing management, for the caller's own account. `seller` is the
// capability gate: `auth:sanctum` + `ability:mobile` proves the token is a mobile
// one, and `seller` proves `isApprovedSeller()`. A buyer is refused with 403.
//
// No route here takes a seller id. Ownership is derived from the token inside the
// repository, so there is no parameter that could widen a seller's list to
// somebody else's, and no id that could redirect a write at a foreign row.
//
// `submit` and `destroy` are declared before `/seller/listings/{listing}` for the
// same reason `/me` is declared before its group: a static segment must never be
// swallowed by a parameter. Neither is a deactivation — `active -> inactive` is an
// administrator action [D-02 rule 4] and is not exposed to sellers.
Route::middleware('auth:sanctum', 'ability:mobile', 'seller')->prefix('seller/listings')->group(function (): void {
    Route::get('/', [SellerListingController::class, 'index']);
    Route::post('/', [SellerListingController::class, 'store']);
    Route::post('/{listing}/submit', [SellerListingController::class, 'submit']);
    Route::post('/{listing}/mark-sold', [SellerListingController::class, 'markSold']);
    Route::patch('/{listing}', [SellerListingController::class, 'update']);
    Route::delete('/{listing}', [SellerListingController::class, 'destroy']);

    // Listing photos (functional documentation §4.5, contract D-10). Multipart
    // upload and removal by the name the client was served, both scoped to the
    // caller's own listings by the same ownership lookup as everything above —
    // another seller's id is a 404 here, never a 403 that confirms it exists.
    Route::post('/{listing}/photos', [SellerListingController::class, 'storePhotos']);
    Route::delete('/{listing}/photos', [SellerListingController::class, 'destroyPhoto']);
});

// Inquiries received by the caller as a seller. Read-only in this phase:
// responding and declining are later work, and no status transition is exposed
// here.
//
// No route takes a seller id. The scope is the token's user and is applied in
// the repository, so a seller can see only inquiries about their own listings
// (functional documentation section 8.2 rule 2). `buyer_id`, `seller_id` and `status`
// are refused as query parameters: none of them is a filter this list supports.
Route::middleware('auth:sanctum', 'ability:mobile', 'seller')
    ->prefix('seller/inquiries')
    ->group(function (): void {
        Route::get('/', [SellerInquiryController::class, 'index']);
    });

// The seller dashboard aggregates the caller's own listings, received
// inquiries, and sales. The seller is the token's user. No route or query
// parameter takes a seller id, and no revenue or conversion metric is exposed.
Route::middleware('auth:sanctum', 'ability:mobile', 'seller')
    ->prefix('seller/dashboard')
    ->group(function (): void {
        Route::get('/', [SellerDashboardController::class, 'show']);
    });

// Transactions — the caller's own transactions as buyer or seller.
//
// No route here takes a user id. Both counterparties are resolved from the
// token inside the repository, so there is no parameter that could widen a
// list to somebody else's transactions, and no id that could redirect a
// write at a foreign row. `role` narrows to one side of the caller's own
// records; `buyer_id` / `seller_id` are refused.
//
// The `complete` route exists only to answer 501 explicitly: [D-15] rule 4
// leaves the confirming actor undecided (OQ-15), so the transition stays
// unimplemented rather than guessed. The mobile client never calls it.
Route::middleware('auth:sanctum', 'ability:mobile')->prefix('transactions')->group(function (): void {
    Route::get('/', [MobileTransactionController::class, 'index']);
    Route::post('/', [MobileTransactionController::class, 'store']);
    Route::get('/{transaction}', [MobileTransactionController::class, 'show']);
    Route::post('/{transaction}/cancel', [MobileTransactionController::class, 'cancel']);
    Route::post('/{transaction}/complete', [MobileTransactionController::class, 'complete']);
});

// Inquiries — the buyer's structured contact with a seller about a listing.
//
// The buyer's write path. Reading received inquiries is the seller route above;
// triaging, re-statusing and deleting an inquiry belong to the administrator
// block below; its route comment reserves creation for the buyer's mobile
// client, and this is that path.
//
// No route here takes a user id. The buyer is resolved from the token and the
// seller from `listing.seller_id` inside the service, so there is no parameter
// or body field that could point an inquiry at a foreign account. Sending an
// inquiry changes nothing else: the listing's status, the transaction
// lifecycle and any payment state are untouched — an inquiry is a message of
// record, not a sale.
//
// No throttle, deliberately, matching `POST /seller-verification` (D-09 is
// still open, so a limit here would be an undocumented behaviour change). The
// 500-character message ceiling and `auth:sanctum` are the abuse bounds that
// exist today. Revisit under D-09 if a limit is decided.
Route::middleware('auth:sanctum', 'ability:mobile')->group(function (): void {
    Route::post('/inquiries', [MobileInquiryController::class, 'store']);
});

// Profile — the caller's own account details and credentials.
//
// No route here takes an id. The record is always resolved from the token, the
// same design as the seller-verification group, so one account cannot read or
// write another's profile.
//
// `PUT` rather than `PATCH`: the Form Request guards every field with
// `sometimes`, so a partial body is already a patch in effect, and one verb
// for the update is simpler than exposing both.
Route::middleware('auth:sanctum', 'ability:mobile')->prefix('profile')->group(function (): void {
    Route::get('/', [ProfileController::class, 'show']);
    Route::put('/', [ProfileController::class, 'update']);
    Route::put('/password', [ProfileController::class, 'changePassword']);
});

// Messaging — the caller's own conversations and messages.
//
// A "conversation" is derived, not stored: it is the pair
// (counterpart_id, listing_id) over the messages that touch the caller. That
// is why there is no `/conversations/{id}` route — an id would require a row
// that does not exist.
//
// `/conversations/{userId}/messages` is the thread with a counterpart;
// `/conversations/{userId}/read` flips the caller's unread messages in that
// thread. `/messages` is where a new message is sent, because the receiver is
// a body field, not a route segment: the caller can start a thread with
// anybody, including a user they have never messaged before.
Route::middleware('auth:sanctum', 'ability:mobile')->group(function (): void {
    Route::get('/conversations', [ConversationController::class, 'index']);
    Route::post('/conversations/{userId}/read', [ConversationController::class, 'markRead'])
        ->whereNumber('userId');

    Route::get('/conversations/{userId}/messages', [MessageController::class, 'index'])
        ->whereNumber('userId');
    Route::post('/messages', [MessageController::class, 'store']);
    Route::patch('/messages/{id}/read', [MessageController::class, 'markRead'])
        ->whereNumber('id');
});

// Notifications — the caller's own notification feed.
//
// No route here takes a user id. The record is resolved from the token, so
// one account cannot read or mark another account's notifications. The route
// group is deliberately flat rather than nested under `/users/me`, matching
// how `/profile` is exposed.
//
// `read-all` is declared before `{id}` so a literal segment cannot be
// swallowed by the parameter. The controller's `{id}` type is `string`
// because Laravel notifications use UUID keys, not integers.
Route::middleware('auth:sanctum', 'ability:mobile')->prefix('notifications')->group(function (): void {
    Route::get('/', [NotificationController::class, 'index']);
    Route::get('/unread-count', [NotificationController::class, 'unreadCount']);
    Route::post('/read-all', [NotificationController::class, 'markAllAsRead']);
    Route::patch('/{id}/read', [NotificationController::class, 'markAsRead']);
    Route::delete('/{id}', [NotificationController::class, 'destroy']);
});

Route::prefix('admin')->middleware('auth:sanctum', 'admin', 'ability:admin')->group(function (): void {
    Route::post('/auth/logout', [AuthController::class, 'logout']);
    Route::get('/auth/me', [AuthController::class, 'me']);
    Route::get('/dashboard', [DashboardController::class, 'index']);
    Route::get('/users', [UserController::class, 'index']);
    Route::get('/users/{user}', [UserController::class, 'show']);
    Route::get('/listings', [ListingController::class, 'index']);
    // Listing moderation. [D-02 rule 8] makes administrator approval the only
    // route to `active`, and the transition table reserves `pending -> inactive`
    // and `active -> inactive` to an administrator as well, so all three land
    // here. Each is a named action rather than a parameterised status update, so
    // a client cannot name a transition at all: `draft -> active`,
    // `sold -> active` and `inactive -> active` have no route that could express
    // them. No reactivation route exists, because [D-02] defines no path back to
    // `active` (A-02 / OQ-16).
    Route::post('/listings/{listing}/approve', [ListingController::class, 'approve']);
    Route::post('/listings/{listing}/reject', [ListingController::class, 'reject']);
    Route::post('/listings/{listing}/deactivate', [ListingController::class, 'deactivate']);
    Route::get('/listings/{listing}', [ListingController::class, 'show']);
    Route::get('/seller-verifications', [SellerVerificationController::class, 'index']);
    Route::get('/seller-verifications/{sellerVerification}', [SellerVerificationController::class, 'show']);
    // Documents. Streamed from the private disk with no-cache headers, guarded
    // by this group's admin ability, and never by a public URL — the web server
    // has no route to the storage root.
    Route::get('/seller-verifications/{sellerVerification}/documents/{type}', [SellerVerificationController::class, 'document']);
    Route::post('/seller-verifications/{sellerVerification}/approve', [SellerVerificationController::class, 'approve']);
    Route::post('/seller-verifications/{sellerVerification}/reject', [SellerVerificationController::class, 'reject']);
    Route::get('/transactions', [TransactionController::class, 'index']);
    Route::get('/transactions/{transaction}', [TransactionController::class, 'show']);
    // Buyer-to-seller inquiries. Administrator-only: an inquiry is read and
    // worked here, never created here — the write path belongs to the buyer's
    // mobile client, and the status is an internal bookmark the buyer never
    // sees. `status` and `destroy` carry their own requests, so the only
    // mutable field is the workflow status.
    Route::get('/inquiries', [InquiryController::class, 'index']);
    Route::get('/inquiries/{inquiry}', [InquiryController::class, 'show']);
    Route::patch('/inquiries/{inquiry}/status', [InquiryController::class, 'updateStatus']);
    Route::delete('/inquiries/{inquiry}', [InquiryController::class, 'destroy']);
    Route::get('/activities', [ActivityController::class, 'index']);
    Route::get('/activities/summary', [ActivityController::class, 'summary']);
    Route::get('/reports', [ReportsController::class, 'index']);
    Route::get('/settings', [SettingsController::class, 'index']);
    Route::put('/settings', [SettingsController::class, 'update']);
});
