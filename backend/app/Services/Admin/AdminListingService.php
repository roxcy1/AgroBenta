<?php

namespace App\Services\Admin;

use App\Enums\ActivityAction;
use App\Enums\ListingStatus;
use App\Events\ListingInventoryUpdated;
use App\Models\Listing;
use App\Models\User;
use App\Notifications\ListingApproved;
use App\Notifications\ListingRejected;
use App\Repositories\Admin\AdminListingRepository;
use App\Services\ActivityLogger;
use App\Services\Listing\ListingReactivationEligibility;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class AdminListingService
{
    public function __construct(
        private readonly AdminListingRepository $listings,
        private readonly ActivityLogger $activity,
        private readonly ListingReactivationEligibility $reactivationEligibility,
    ) {
        //
    }

    public function listListings(
        ?string $search = null,
        ?string $livestockType = null,
        ?string $status = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        return $this->listings->list($search, $livestockType, $status, $perPage);
    }

    /**
     * Approve a listing: `pending → active`.
     *
     * This is the only route from `pending` review to publication.
     * [D-02 rule 8] makes administrator approval a precondition for a submitted
     * listing to become `active`; seller reactivation is a separate restoration
     * path for an eligible listing previously deactivated by that seller.
     *
     * A `pending` listing with no stored photo is refused [DEC-03]. That is a
     * legacy guard for rows queued before the submission rule existed; for new
     * submissions the seller-side check is the enforcement point. The same
     * guard also refuses a row whose stored filenames have no files on disk, so
     * a restored or partially lost storage cannot produce a live listing with
     * dead images. Only `pending` is guarded here, so any other state still
     * receives the 409 the transition guard gives it rather than a misleading
     * validation error.
     *
     * @throws ValidationException if a pending listing has no stored photo or a
     *                             stored photo has no file
     */
    public function approve(Listing $listing, User $actor): Listing
    {
        if ($listing->status === ListingStatus::Pending) {
            if (! $listing->hasStoredPhotos()) {
                throw ValidationException::withMessages([
                    'photos' => 'At least one photo is required before a listing can be approved.',
                ]);
            }

            // The stored filenames are checked against the disk as the last
            // gate before publication, so a legacy row — or one whose files
            // have since disappeared — cannot go live with broken images.
            if ($listing->missingPhotoFilenames() !== []) {
                throw ValidationException::withMessages([
                    'photos' => 'One or more listing photos are missing. The listing cannot be approved until they are re-uploaded.',
                ]);
            }
        }

        return $this->moderate(
            $listing,
            ListingStatus::Pending,
            ListingStatus::Active,
            'Only a listing that is pending review can be approved.',
            ActivityAction::ListingApproved,
            $actor,
        );
    }

    /**
     * Reject a listing: `pending → inactive`.
     *
     * The contract's [D-02 transition table] gives this one destination and one
     * only. It is not a new status: `inactive` is the existing state for a
     * listing that is not publicly available. Rejected listings are not restored
     * by seller or admin reactivation (DEC-12). No `rejected`, `declined` or `needs_revision` state is created
     * here, because the enum has exactly five cases and that is the complete set.
     *
     * `$adminNote` is the administrator's reason. It is optional and stored on
     * the row, but it is not a condition: a rejection with no note is still a
     * rejection, because the contract makes the transition unconditional and
     * gates it on the listing's status, not on what a moderator typed.
     */
    public function reject(Listing $listing, User $actor, ?string $adminNote = null): Listing
    {
        return $this->moderate(
            $listing,
            ListingStatus::Pending,
            ListingStatus::Inactive,
            'Only a listing that is pending review can be rejected.',
            ActivityAction::ListingRejected,
            $actor,
            $adminNote,
        );
    }

    /**
     * Withdraw a listing: `active → inactive`.
     *
     * Administrator moderation deactivation. Sellers have a separate voluntary
     * deactivation action with distinct audit provenance (DEC-12).
     */
    public function deactivate(Listing $listing, User $actor): Listing
    {
        return $this->moderate(
            $listing,
            ListingStatus::Active,
            ListingStatus::Inactive,
            'Only an active listing can be deactivated.',
            ActivityAction::ListingDeactivated,
            $actor,
        );
    }

    /**
     * Administrator-only restoration of a listing that an administrator
     * previously deactivated. Rejection and seller withdrawal are not restored
     * through this moderation decision.
     */
    public function reactivate(Listing $listing, User $actor): Listing
    {
        return DB::transaction(function () use ($listing, $actor): Listing {
            // Lock first, then validate both status and provenance against the
            // row that will be changed. A stale audit check before the lock could
            // otherwise race a seller/admin lifecycle action.
            $locked = $this->listings->lockForReactivation((int) $listing->getKey());

            if ($locked === null) {
                abort(404, 'Listing not found.');
            }
            if ($locked->status !== ListingStatus::Inactive) {
                abort(409, 'Only an inactive listing can be reactivated.');
            }
            if (! $this->listings->wasMostRecentlyDeactivatedByAdmin((int) $locked->getKey())) {
                abort(409, 'Only an administrator-deactivated listing can be restored by an administrator.');
            }

            $seller = $locked->seller;
            if ($seller === null || $seller->trashed() || ! $seller->isApprovedSeller()) {
                abort(409, 'The listing owner must be an active, approved seller before reactivation.');
            }

            $inventoryFailure = $this->reactivationEligibility->failureMessage($locked);
            if ($inventoryFailure !== null) {
                abort(409, $inventoryFailure);
            }

            $reactivated = $this->listings->restoreAdminDeactivated($locked);

            ListingInventoryUpdated::dispatch((int) $reactivated->getKey());
            $this->activity->log(
                $actor,
                ActivityAction::ListingAdminReactivated,
                sprintf('Listing #%d reactivated by an administrator.', $reactivated->getKey()),
                [
                    'target_type' => 'listing',
                    'target_id' => $reactivated->getKey(),
                    'context' => ['seller_id' => $reactivated->seller_id],
                    'changes' => [
                        'status' => [
                            'from' => ListingStatus::Inactive->value,
                            'to' => ListingStatus::Active->value,
                        ],
                    ],
                ],
            );

            return $reactivated;
        });
    }

    /**
     * Withdraw a seller's marketplace presence when their verification is
     * revoked.
     *
     * Active listings are administrator-deactivated and pending listings are
     * administrator-rejected. Draft, sold and already-inactive listings are
     * left alone: a draft was never public, sold is terminal, and inactive is
     * already hidden. The existing transitions preserve reservations and
     * transaction history (DEC-12), so this method never cancels or rewrites
     * either.
     *
     * The caller is expected to run this inside the verification-revocation
     * transaction. A transition conflict propagates as a 409 and rolls the
     * whole revocation back.
     *
     * @return array{deactivated: list<int>, rejected: list<int>}
     */
    public function revokeSellerListings(User $seller, User $actor, ?string $reason = null): array
    {
        $deactivated = [];
        $rejected = [];

        foreach ($this->listings->lockForSellerRevocation((int) $seller->getKey()) as $listing) {
            if ($listing->status === ListingStatus::Active) {
                $this->deactivate($listing, $actor);
                $deactivated[] = (int) $listing->getKey();

                continue;
            }

            if ($listing->status === ListingStatus::Pending) {
                $this->reject($listing, $actor, $reason);
                $rejected[] = (int) $listing->getKey();
            }
        }

        return ['deactivated' => $deactivated, 'rejected' => $rejected];
    }

    /**
     * Apply one documented transition, or refuse it.
     *
     * The allowed source status is a private detail of each method above, so a
     * caller cannot ask for a transition that [D-02] does not permit: there is
     * no `$to` parameter on the public surface, and `draft → active` or
     * `sold → active` have no method that could express them. Restoration uses
     * its own provenance- and inventory-checked method above.
     *
     * A refusal is a 409, not a 404 and not a 422. The listing exists and the
     * request is well-formed; the listing is simply in a state where this
     * decision no longer means anything. That is also the answer a stale
     * administrator gets — the two are the same case, which is why the guard
     * lives here and not in the client.
     */
    private function moderate(
        Listing $listing,
        ListingStatus $from,
        ListingStatus $to,
        string $conflictMessage,
        ActivityAction $action,
        User $actor,
        ?string $adminNote = null,
    ): Listing {
        return DB::transaction(function () use ($listing, $from, $to, $conflictMessage, $action, $actor, $adminNote): Listing {
            $moderated = $this->listings->transition($listing, $from, $to, $adminNote);

            abort_if($moderated === null, 409, $conflictMessage);

            ListingInventoryUpdated::dispatch((int) $moderated->getKey());

            // Written in the same transaction as the transition, so an audit
            // entry can never describe a moderation that did not commit.
            $this->activity->log(
                $actor,
                $action,
                sprintf('%s (#%d, %s).', $action->label(), $moderated->getKey(), $moderated->livestock_type),
                [
                    'target_type' => 'listing',
                    'target_id' => $moderated->getKey(),
                    'context' => ['seller_id' => $moderated->seller_id],
                    'changes' => [
                        'status' => ['from' => $from->value, 'to' => $to->value],
                    ],
                    'admin_note' => $adminNote,
                ],
            );

            // Only the two decisions a seller must learn about notify. A
            // deactivation withdraws a live listing rather than answering a
            // submission, so it has no notification of its own.
            $notification = match ($action) {
                ActivityAction::ListingApproved => new ListingApproved($moderated),
                ActivityAction::ListingRejected => new ListingRejected($moderated),
                default => null,
            };

            if ($notification !== null) {
                $moderated->seller->notify($notification);
            }

            return $moderated;
        });
    }
}
