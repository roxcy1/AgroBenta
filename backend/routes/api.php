<?php

use App\Http\Controllers\Api\Admin\ActivityController;
use App\Http\Controllers\Api\Admin\AuthController;
use App\Http\Controllers\Api\Admin\DashboardController;
use App\Http\Controllers\Api\Admin\ListingController;
use App\Http\Controllers\Api\Admin\ReportsController;
use App\Http\Controllers\Api\Admin\SellerVerificationController;
use App\Http\Controllers\Api\Admin\SettingsController;
use App\Http\Controllers\Api\Admin\TransactionController;
use App\Http\Controllers\Api\Admin\UserController;
use App\Http\Controllers\Api\Auth\AuthController as MobileAuthController;
use App\Http\Controllers\Api\CurrentUserController;
use App\Http\Controllers\Api\Marketplace\ListingController as MarketplaceListingController;
use App\Http\Controllers\Api\Notification\NotificationController;
use App\Http\Controllers\Api\Profile\ProfileController;
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
    Route::patch('/{listing}', [SellerListingController::class, 'update']);
    Route::delete('/{listing}', [SellerListingController::class, 'destroy']);

    // Listing photos (functional documentation §4.5, contract D-10). Multipart
    // upload and removal by the name the client was served, both scoped to the
    // caller's own listings by the same ownership lookup as everything above —
    // another seller's id is a 404 here, never a 403 that confirms it exists.
    Route::post('/{listing}/photos', [SellerListingController::class, 'storePhotos']);
    Route::delete('/{listing}/photos', [SellerListingController::class, 'destroyPhoto']);
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
    Route::post('/seller-verifications/{sellerVerification}/approve', [SellerVerificationController::class, 'approve']);
    Route::post('/seller-verifications/{sellerVerification}/reject', [SellerVerificationController::class, 'reject']);
    Route::get('/transactions', [TransactionController::class, 'index']);
    Route::get('/transactions/{transaction}', [TransactionController::class, 'show']);
    Route::get('/activities', [ActivityController::class, 'index']);
    Route::get('/activities/summary', [ActivityController::class, 'summary']);
    Route::get('/reports', [ReportsController::class, 'index']);
    Route::get('/settings', [SettingsController::class, 'index']);
    Route::put('/settings', [SettingsController::class, 'update']);
});
