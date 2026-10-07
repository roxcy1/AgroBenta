<?php

namespace App\Repositories\SellerListing;

use App\Enums\ListingStatus;
use App\Models\Listing;
use App\Models\User;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;

/**
 * Data access for a seller's own listings.
 *
 * Every method here is scoped to one seller, because the seller of a listing is
 * never a client-selected value (contract §5.4, `seller_id` is prohibited). The
 * scope is applied in SQL, in this repository, so that "not yours" and "does not
 * exist" are the same absence and produce the same documented 404 — the
 * controller cannot forget to check ownership, because ownership is part of the
 * lookup rather than a condition applied afterwards.
 *
 * Status is *not* restricted here. Unlike the marketplace, a seller sees their
 * own work in every state; the lifecycle rules that decide who may change a
 * listing, and from which state, belong to the service.
 */
class SellerListingRepository
{
    /**
     * Paginate one seller's listings, optionally narrowed to one status.
     */
    public function paginateForSeller(
        User $seller,
        ?ListingStatus $status = null,
        ?string $search = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        $query = Listing::query()
            ->with('seller:id,name')
            ->where('seller_id', $seller->getKey());

        if ($status !== null) {
            $query->where('status', $status);
        }

        $this->applySearch($query, $search);

        return $query
            // A total order, so two listings written in the same second cannot
            // appear on two pages at once.
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->paginate($perPage);
    }

    /**
     * Find one listing owned by this seller, or null.
     *
     * Returns null both when the listing does not exist and when it belongs to
     * somebody else, which is the intent: a seller must not be able to probe for
     * the existence of another seller's inventory by watching the status code
     * change. `404` for both.
     */
    public function findOwned(int $listingId, User $seller): ?Listing
    {
        return Listing::query()
            ->with('seller:id,name')
            ->where('id', $listingId)
            ->where('seller_id', $seller->getKey())
            ->first();
    }

    /**
     * Create a listing owned by this seller.
     *
     * `seller_id` and `status` are set here, from the authenticated user and the
     * contract, rather than accepted from the request — the two fields a client
     * must never choose.
     */
    public function createForSeller(User $seller, array $attributes): Listing
    {
        return Listing::query()->create([
            ...$attributes,
            'seller_id' => $seller->getKey(),
            'status' => ListingStatus::Draft,
        ]);
    }

    /**
     * Persist validated attribute changes on a listing the seller owns.
     *
     * Takes the model rather than an id so that ownership and lifecycle have
     * already been established by the caller, and mass assignment cannot
     * re-target the row: `$listing->update()` only ever writes to the instance it
     * was called on.
     */
    public function update(Listing $listing, array $attributes): Listing
    {
        $listing->fill($attributes);
        $listing->save();

        return $listing;
    }

    /**
     * Remove a listing outright.
     *
     * Hard delete, not a soft one: the `listings` table has no `deleted_at`
     * column, and adding one is a schema change this phase does not authorise.
     * The service restricts the call to the states the contract allows to be
     * destroyed, so a removed draft or withdrawn listing leaves nothing behind
     * for moderation to review. An `active` listing is never reachable here.
     *
     * @see \App\Services\SellerListing\SellerListingService::delete()
     */
    public function delete(Listing $listing): void
    {
        $listing->delete();
    }

    /**
     * Free-text search across the searchable listing columns.
     *
     * Runs in SQL with bound parameters; a seller's list is never loaded into
     * PHP to be filtered there.
     */
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
}
