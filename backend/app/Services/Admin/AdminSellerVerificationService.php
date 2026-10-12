<?php

namespace App\Services\Admin;

use App\Enums\SellerCapability;
use App\Enums\SellerVerificationStatus;
use App\Models\SellerVerification;
use App\Models\User;
use App\Repositories\Admin\AdminSellerVerificationRepository;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Collection;
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

    /**
     * Prior verification records for the same applicant, newest first.
     */
    public function historyFor(SellerVerification $verification): Collection
    {
        return $this->verifications->historyFor($verification->user_id, $verification->id);
    }

    public function approve(SellerVerification $verification, int $reviewerId, ?string $adminNote = null): SellerVerification
    {
        return $this->moderate(
            $verification,
            SellerVerificationStatus::Approved,
            $reviewerId,
            $adminNote,
        );
    }

    public function reject(SellerVerification $verification, int $reviewerId, string $adminNote): SellerVerification
    {
        return $this->moderate(
            $verification,
            SellerVerificationStatus::Rejected,
            $reviewerId,
            $adminNote,
        );
    }

    /**
     * Apply a review decision (approve or reject) to the applicant's most
     * recent submission. Older records are stale and must never be reviewed,
     * which keeps the applicant's current state authoritative.
     */
    private function moderate(
        SellerVerification $verification,
        SellerVerificationStatus $to,
        int $reviewerId,
        ?string $adminNote,
    ): SellerVerification {
        return DB::transaction(function () use ($verification, $to, $reviewerId, $adminNote): SellerVerification {
            // Lock the applicant so concurrent review decisions serialise per
            // applicant and a resubmission cannot race the decision.
            $applicant = User::query()->lockForUpdate()->findOrFail($verification->user_id);

            $latest = $this->verifications->latestForUser($applicant->id);

            if ($latest === null || $latest->getKey() !== $verification->getKey()) {
                abort(409, 'This verification record is not the applicant\'s most recent submission.');
            }

            if (! $latest->status->isOpen()) {
                abort(409, 'This verification request has already been reviewed.');
            }

            $latest->update([
                'status' => $to,
                'reviewed_by' => $reviewerId,
                'reviewed_at' => now(),
                'admin_note' => $adminNote,
            ]);

            // Authority field: server-derived, so it bypasses mass assignment
            // guards on purpose. It is only ever set from this trusted path.
            // Approval grants selling; rejection revokes it, so a previously
            // approved applicant who is later rejected is no longer a seller.
            $applicant->forceFill([
                'seller_capability' => $to === SellerVerificationStatus::Approved
                    ? SellerCapability::Seller
                    : SellerCapability::Buyer,
            ])->save();

            return $latest->fresh(['seller:id,name,email', 'reviewer:id,name']);
        });
    }
}
