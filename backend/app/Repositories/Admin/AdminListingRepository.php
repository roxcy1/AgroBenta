<?php

namespace App\Repositories\Admin;

use App\Enums\ActivityAction;
use App\Enums\ListingStatus;
use App\Models\Activity;
use App\Models\Listing;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

class AdminListingRepository
{
    /**
     * Confirm the listing's latest inactive decision was an administrator
     * deactivation, not seller withdrawal or rejection.
     */
    public function wasMostRecentlyDeactivatedByAdmin(int $listingId): bool
    {
        $activity = Activity::query()
            ->where('metadata->target_type', 'listing')
            ->where('metadata->target_id', $listingId)
            ->whereIn('action', [
                ActivityAction::ListingApproved->value,
                ActivityAction::ListingRejected->value,
                ActivityAction::ListingDeactivated->value,
                ActivityAction::ListingSellerDeactivated->value,
                ActivityAction::ListingSellerReactivated->value,
                ActivityAction::ListingAdminReactivated->value,
                ActivityAction::ListingMarkedSold->value,
            ])
            ->orderByDesc('id')
            ->first();

        return $activity !== null &&
            $activity->action === ActivityAction::ListingDeactivated->value;
    }

    public function list(
        ?string $search = null,
        ?string $livestockType = null,
        ?string $status = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        $query = Listing::query()->withInventoryTotals()->with([
            'seller' => fn ($seller) => $seller
                ->withTrashed()
                ->select(['id', 'name', 'email']),
            'inventoryReconciliations.admin:id,name',
            'unaccountedInventoryTransactions:id,listing_id,status,quantity,inventory_accounted',
        ]);

        $this->applySearch($query, $search);
        $this->applyFilters($query, $livestockType, $status);

        return $query
            ->orderByDesc('created_at')
            ->paginate($perPage);
    }

    /**
     * Move a listing from one status to another, but only if it is still in the
     * expected one. Returns null when the transition is not legal.
     *
     * The re-read is inside the transaction and the row is locked, and that is
     * the whole point. A moderation decision is made from a screen the
     * administrator has been looking at for some time, so the row this method is
     * asked about is very often no longer the row that is stored: a second
     * administrator may have approved it in the meantime. Re-reading under a
     * lock, and refusing unless the status is still `$from`, turns that race
     * into the same answer a stale client would have got anyway — no
     * transition, reported as a conflict — instead of letting a stale decision
     * overwrite a newer one.
     *
     * The predicate is applied to the locked row rather than to an `UPDATE ...
     * WHERE status = ?` affected-row count, so the caller gets the model back
     * with its relations already loaded and does not have to re-fetch to tell
     * whether anything happened.
     *
     * `$adminNote` is written only when supplied, so approving or deactivating
     * a listing that already carries a note from an earlier rejection keeps it:
     * a moderator's explanation is history and is not erased by a later,
     * unrelated decision.
     */
    public function transition(
        Listing $listing,
        ListingStatus $from,
        ListingStatus $to,
        ?string $adminNote = null,
        bool $clearAdminNote = false,
    ): ?Listing {
        return DB::transaction(function () use ($listing, $from, $to, $adminNote, $clearAdminNote): ?Listing {
            $current = Listing::query()
                ->withInventoryTotals()
                ->with([
                    'seller' => fn ($seller) => $seller
                        ->withTrashed()
                        ->select(['id', 'name', 'email']),
                    'inventoryReconciliations.admin:id,name',
                    'unaccountedInventoryTransactions:id,listing_id,status,quantity,inventory_accounted',
                ])
                ->whereKey($listing->getKey())
                ->lockForUpdate()
                ->first();

            if ($current === null || $current->status !== $from) {
                return null;
            }

            $current->status = $to;

            if ($adminNote !== null) {
                $current->admin_note = $adminNote;
            } elseif ($clearAdminNote) {
                $current->admin_note = null;
            }

            $current->save();

            return $current;
        });
    }

    private function applySearch(Builder $query, ?string $search): void
    {
        if ($search === null || $search === '') {
            return;
        }

        $term = '%'.$search.'%';

        $query->where(function (Builder $q) use ($term): void {
            $q->where('livestock_type', 'like', $term)
                ->orWhere('breed', 'like', $term)
                ->orWhere('location', 'like', $term);
        });
    }

    private function applyFilters(Builder $query, ?string $livestockType, ?string $status): void
    {
        if ($livestockType !== null && $livestockType !== '') {
            $query->where('livestock_type', $livestockType);
        }

        if ($status !== null && $status !== '') {
            $query->where('status', ListingStatus::from($status));
        }
    }
}
