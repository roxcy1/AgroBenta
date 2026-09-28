<?php

namespace App\Services\Admin;

use App\Enums\SellerCapability;
use App\Enums\SellerVerificationStatus;
use App\Models\SellerVerification;
use App\Repositories\Admin\AdminSellerVerificationRepository;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;

class AdminSellerVerificationService
{
    public function __construct(
        private readonly AdminSellerVerificationRepository $verifications,
    ) {
        //
    }

    public function listVerifications(
        ?string $search = null,
        ?string $status = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        return $this->verifications->list($search, $status, $perPage);
    }

    public function approve(SellerVerification $verification, int $reviewerId, ?string $adminNote = null): SellerVerification
    {
        return DB::transaction(function () use ($verification, $reviewerId, $adminNote): SellerVerification {
            $verification->update([
                'status' => SellerVerificationStatus::Approved,
                'reviewed_by' => $reviewerId,
                'reviewed_at' => now(),
                'admin_note' => $adminNote,
            ]);

            // Authority field: server-derived, so it bypasses mass assignment
            // guards on purpose. It is only ever set from this trusted path.
            $verification->seller->forceFill([
                'seller_capability' => SellerCapability::Seller,
            ])->save();

            return $verification->fresh(['seller:id,name,email', 'reviewer:id,name']);
        });
    }

    public function reject(SellerVerification $verification, int $reviewerId, ?string $adminNote = null): SellerVerification
    {
        return DB::transaction(function () use ($verification, $reviewerId, $adminNote): SellerVerification {
            $verification->update([
                'status' => SellerVerificationStatus::Rejected,
                'reviewed_by' => $reviewerId,
                'reviewed_at' => now(),
                'admin_note' => $adminNote,
            ]);

            return $verification->fresh(['seller:id,name,email', 'reviewer:id,name']);
        });
    }
}
