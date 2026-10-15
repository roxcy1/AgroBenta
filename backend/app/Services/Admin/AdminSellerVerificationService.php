<?php

namespace App\Services\Admin;

use App\Enums\ActivityAction;
use App\Enums\SellerCapability;
use App\Enums\SellerVerificationStatus;
use App\Models\SellerVerification;
use App\Models\User;
use App\Notifications\SellerVerificationApproved;
use App\Notifications\SellerVerificationRejected;
use App\Repositories\Admin\AdminSellerVerificationRepository;
use App\Services\ActivityLogger;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;

class AdminSellerVerificationService
{
    public function __construct(
        private readonly AdminSellerVerificationRepository $verifications,
        private readonly ActivityLogger $activity,
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

    public function approve(SellerVerification $verification, User $reviewer, ?string $adminNote = null): SellerVerification
    {
        return $this->moderate(
            $verification,
            SellerVerificationStatus::Approved,
            $reviewer,
            $adminNote,
        );
    }

    public function reject(SellerVerification $verification, User $reviewer, string $adminNote): SellerVerification
    {
        return $this->moderate(
            $verification,
            SellerVerificationStatus::Rejected,
            $reviewer,
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
        User $reviewer,
        ?string $adminNote,
    ): SellerVerification {
        return DB::transaction(function () use ($verification, $to, $reviewer, $adminNote): SellerVerification {
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

            // Observed before the write, so the audit records the transition the
            // review actually performed rather than a re-derived guess.
            $previousStatus = $latest->status->value;
            $previousCapability = $applicant->seller_capability->value;

            $newCapability = $to === SellerVerificationStatus::Approved
                ? SellerCapability::Seller
                : SellerCapability::Buyer;

            $latest->update([
                'status' => $to,
                'reviewed_by' => $reviewer->getKey(),
                'reviewed_at' => now(),
                'admin_note' => $adminNote,
            ]);

            // Authority field: server-derived, so it bypasses mass assignment
            // guards on purpose. It is only ever set from this trusted path.
            // Approval grants selling; rejection revokes it, so a previously
            // approved applicant who is later rejected is no longer a seller.
            $applicant->forceFill([
                'seller_capability' => $newCapability,
            ])->save();

            // Fire the applicant's notification. Inside the transaction, on
            // purpose: if the notification write fails, the whole decision
            // rolls back and the admin sees the error. A silently un-notified
            // approval is worse than a failed one, because the applicant would
            // be a seller without knowing it.
            //
            // Laravel's `database` channel is what `via()` returns, so the write
            // is a plain INSERT into `notifications` — no queue worker, no
            // external service, nothing that could be unavailable.
            $notification = $to === SellerVerificationStatus::Approved
                ? new SellerVerificationApproved($latest->fresh())
                : new SellerVerificationRejected($latest->fresh());

            $applicant->notify($notification);

            $action = $to === SellerVerificationStatus::Approved
                ? ActivityAction::SellerVerificationApproved
                : ActivityAction::SellerVerificationRejected;

            $this->activity->log(
                $reviewer,
                $action,
                sprintf('%s for "%s".', $action->label(), $latest->business_name),
                [
                    'target_type' => 'seller_verification',
                    'target_id' => $latest->getKey(),
                    'context' => [
                        'applicant_id' => $applicant->getKey(),
                        'business_name' => $latest->business_name,
                    ],
                    'changes' => [
                        'status' => ['from' => $previousStatus, 'to' => $to->value],
                        'seller_capability' => [
                            'from' => $previousCapability,
                            'to' => $newCapability->value,
                        ],
                    ],
                    'admin_note' => $adminNote,
                ],
            );

            return $latest->fresh(['seller:id,name,email', 'reviewer:id,name']);
        });
    }
}
