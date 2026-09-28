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
use App\Http\Controllers\Api\Marketplace\ListingController as MarketplaceListingController;
use App\Http\Controllers\Api\SellerVerification\SellerVerificationController as MobileSellerVerificationController;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

Route::get('/user', function (Request $request) {
    return $request->user();
})->middleware('auth:sanctum');

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
// not an accepted parameter �?" see IndexListingRequest.
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

Route::prefix('admin')->middleware('auth:sanctum', 'admin', 'ability:admin')->group(function (): void {
    Route::post('/auth/logout', [AuthController::class, 'logout']);
    Route::get('/auth/me', [AuthController::class, 'me']);
    Route::get('/dashboard', [DashboardController::class, 'index']);
    Route::get('/users', [UserController::class, 'index']);
    Route::get('/listings', [ListingController::class, 'index']);
    Route::get('/seller-verifications', [SellerVerificationController::class, 'index']);
    Route::get('/seller-verifications/{sellerVerification}', [SellerVerificationController::class, 'show']);
    Route::post('/seller-verifications/{sellerVerification}/approve', [SellerVerificationController::class, 'approve']);
    Route::post('/seller-verifications/{sellerVerification}/reject', [SellerVerificationController::class, 'reject']);
    Route::get('/transactions', [TransactionController::class, 'index']);
    Route::get('/activities', [ActivityController::class, 'index']);
    Route::get('/reports', [ReportsController::class, 'index']);
    Route::get('/settings', [SettingsController::class, 'index']);
    Route::put('/settings', [SettingsController::class, 'update']);
});
