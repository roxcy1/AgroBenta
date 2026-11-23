<?php

namespace App\Services\Admin;

use App\Enums\ActivityAction;
use App\Enums\SellerCapability;
use App\Enums\SellerVerificationStatus;
use App\Models\SellerVerification;
use App\Models\User;
use App\Notifications\SellerVerificationApproved;
use App\Notifications\SellerVerificationRejected;
use App\Notifications\SellerVerificationRevoked;
use App\Repositories\Admin\AdminSellerVerificationRepository;
use App\Services\ActivityLogger;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;

class AdminSellerVerificationService
{
    /**
     * The statuses an application holds while no decision has been made.
     *
     * @var list<SellerVerificationStatus>
     */
    private const OPEN_STATUSES = [
        SellerVerificationStatus::Submitted,
        SellerVerificationStatus::PendingReview,
    ];

    public function __construct(
        private readonly AdminSellerVerificationRepository $verifications,
        private readonly AdminListingService $listings,
        private readonly ActivityLogger $activity,
    ) {
        //
    }

    public function listVerifications(
        ?string $search = null,
        ?string $status = null,
        int $perPage = 15,
        bool $allSubmissions = false,
    ): LengthAwarePaginator {
        return $this->verifications->list($search, $status, $perPage, $allSubmissions);
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
            self::OPEN_STATUSES,
            ActivityAction::SellerVerificationApproved,
            'This verification request has already been reviewed.',
        );
    }

    public function reject(SellerVerification $verification, User $reviewer, string $adminNote): SellerVerification
    {
        return $this->moderate(
            $verification,
            SellerVerificationStatus::Rejected,
            $reviewer,
            $adminNote,
            self::OPEN_STATUSES,
            ActivityAction::SellerVerificationRejected,
            'This verification request has already been reviewed.',
        );
    }

    /**
     * Revoke an approved verification.
     *
     * The record becomes `rejected`, which is the only decision state available
     * for a revoked application; no fifth status is introduced. Seller
     * capability is removed and the seller's live and pending listings are
     * withdrawn in the same transaction, so a revocation cannot leave a buyer
     * with listings still open for sale.
     */
    public function revoke(SellerVerification $verification, User $reviewer, string $adminNote): SellerVerification
    {
        return $this->moderate(
            $verification,
            SellerVerificationStatus::Rejected,
            $reviewer,
            $adminNote,
            [SellerVerificationStatus::Approved],
            ActivityAction::SellerVerificationRevoked,
            'Only an approved verification can be revoked.',
        );
    }

    /**
     * Apply a review decision to the applicant's most recent submission.
     * Older records are stale and must never be reviewed, which keeps the
     * applicant's current state authoritative.
     *
     * `$allowedFrom` is action-specific rather than a single open-state check:
     * approval and rejection only accept open applications, while revocation
     * only accepts an approved one. Narrowing it here means approving an
     * already-decided record remains impossible.
     *
     * @param  list<SellerVerificationStatus>  $allowedFrom
     */
    private function moderate(
        SellerVerification $verification,
        SellerVerificationStatus $to,
        User $reviewer,
        ?string $adminNote,
        array $allowedFrom,
        ActivityAction $action,
        string $conflictMessage,
    ): SellerVerification {
        return DB::transaction(function () use (
            $verification,
            $to,
            $reviewer,
            $adminNote,
            $allowedFrom,
            $action,
            $conflictMessage,
        ): SellerVerification {
            // Lock the applicant so concurrent review decisions serialise per
            // applicant and a resubmission cannot race the decision.
            $applicant = User::withTrashed()
                ->lockForUpdate()
                ->findOrFail($verification->user_id);

            $latest = $this->verifications->latestForUser($applicant->id);

            if ($latest === null || $latest->getKey() !== $verification->getKey()) {
                abort(409, 'This verification record is not the applicant\'s most recent submission.');
            }

            if (! in_array($latest->status, $allowedFrom, true)) {
                abort(409, $conflictMessage);
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
            // Approval grants selling; rejection and revocation remove it.
            $applicant->forceFill([
                'seller_capability' => $newCapability,
            ])->save();

            // Revocation must leave no live or pending listing behind. The
            // transition services leave reservations and transaction history
            // untouched, and a conflict here rolls the whole revocation back.
            $withdrawn = $action === ActivityAction::SellerVerificationRevoked
                ? $this->listings->revokeSellerListings($applicant, $reviewer, $adminNote)
                : null;

            // Fire the applicant's notification. Inside the transaction, on
            // purpose: if the notification write fails, the whole decision
            // rolls back and the admin sees the error. A silently un-notified
            // approval is worse than a failed one, because the applicant would
            // be a seller without knowing it.
            //
            // Laravel's `database` channel is what `via()` returns, so the write
            // is a plain INSERT into `notifications` — no queue worker, no
            // external service, nothing that could be unavailable.
            $notification = match ($action) {
                ActivityAction::SellerVerificationApproved => new SellerVerificationApproved($latest->fresh()),
                ActivityAction::SellerVerificationRejected => new SellerVerificationRejected($latest->fresh()),
                ActivityAction::SellerVerificationRevoked => new SellerVerificationRevoked($latest->fresh()),
                default => throw new \LogicException('Unexpected seller-verification activity action.'),
            };

            $applicant->notify($notification);

            $context = [
                'applicant_id' => $applicant->getKey(),
                'business_name' => $latest->business_name,
            ];

            if ($withdrawn !== null) {
                $context['deactivated_listing_ids'] = $withdrawn['deactivated'];
                $context['rejected_listing_ids'] = $withdrawn['rejected'];
            }

            $this->activity->log(
                $reviewer,
                $action,
                sprintf('%s for "%s".', $action->label(), $latest->business_name ?? $applicant->name),
                [
                    'target_type' => 'seller_verification',
                    'target_id' => $latest->getKey(),
                    'context' => $context,
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
