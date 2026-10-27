<?php

namespace App\Services\Admin;

use App\Enums\ActivityAction;
use App\Enums\ListingStatus;
use App\Models\Listing;
use App\Models\User;
use App\Notifications\ListingApproved;
use App\Notifications\ListingRejected;
use App\Repositories\Admin\AdminListingRepository;
use App\Services\ActivityLogger;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;

class AdminListingService
{
    public function __construct(
        private readonly AdminListingRepository $listings,
        private readonly ActivityLogger $activity,
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
     * This is the only route by which a listing becomes visible to buyers.
     * [D-02 rule 8] makes administrator approval a precondition for `active`,
     * and a seller has no path to it at all — `SellerListingService` stops at
     * `pending` and does not contain an equivalent method.
     */
    public function approve(Listing $listing, User $actor): Listing
    {
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
     * listing that is not publicly available, and [D-02] defines no path back
     * from it to `active` (A-02 / OQ-16), so a rejection is final for this
     * record. No `rejected`, `declined` or `needs_revision` state is created
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
     * Reserved to an administrator for the same reason rejection is
     * [D-02 rule 4]: taking a live listing out of the marketplace is a
     * moderation decision, which is why `SellerListingService` cannot delete an
     * `active` listing [D-25].
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
     * Apply one documented transition, or refuse it.
     *
     * The allowed source status is a private detail of each method above, so a
     * caller cannot ask for a transition that [D-02] does not permit: there is
     * no `$to` parameter on the public surface, and `draft → active`,
     * `sold → active` and `inactive → active` have no method that could express
     * them.
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
