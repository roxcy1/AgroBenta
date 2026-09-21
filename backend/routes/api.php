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
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

Route::get('/user', function (Request $request) {
    return $request->user();
})->middleware('auth:sanctum');

Route::post('/admin/auth/login', [AuthController::class, 'login'])
    ->middleware('throttle:10,1');

Route::prefix('admin')->middleware('auth:sanctum', 'admin')->group(function (): void {
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
