<?php

namespace App\Repositories\Marketplace;

use App\Enums\ListingStatus;
use App\Models\Listing;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;

/**
 * Data access for the buyer marketplace.
 *
 * Marketplace visibility is owned here, in the query, and never by a client
 * parameter. Buyers browse only `active` listings [D-02 rules 3 and 9], so the
 * browse query is hard-restricted to that status. `draft` is the seller's own
 * unfinished work, `pending` is in review, `inactive` was removed from sale and
 * `sold` is no longer available — none of them are marketplace inventory.
 *
 * This is deliberately not an extension of `AdminListingRepository`: the admin
 * repository filters on a client-supplied `status` across all five states,
 * which is the opposite of the rule this surface enforces. What is shared is the
 * query shape, not the query intent.
 */
class MarketplaceListingRepository
{
    /**
     * Paginate the active listings that make up the marketplace.
     */
    public function paginateActive(
        ?string $search = null,
        ?string $livestockType = null,
        ?string $location = null,
        ?float $minPrice = null,
        ?float $maxPrice = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        $query = $this->activeQuery();

        $this->applySearch($query, $search);
        $this->applyFilters($query, $livestockType, $location, $minPrice, $maxPrice);

        return $query
            // `created_at` alone is not a total order, so listings written in
            // the same second would otherwise paginate unpredictably.
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->paginate($perPage);
    }

    /**
     * Fetch one listing the viewer is allowed to see, or null.
     *
     * An `active` listing is marketplace inventory and is visible to any
     * authenticated user. Every other status is visible only to the seller who
     * owns it [D-02 rules 1, 2 and 5]. Both conditions are applied in the query
     * so that a caller who is not allowed to see the listing gets the same null
     * as a caller who asked for an id that does not exist — the endpoint turns
     * that into the documented 404, and listing existence is never disclosed
     * through a different status code.
     */
    public function findVisibleListing(int $listingId, int $viewerId): ?Listing
    {
        return Listing::query()
            ->with('seller:id,name')
            ->where('id', $listingId)
            ->where(function (Builder $query) use ($viewerId): void {
                $query->where('status', ListingStatus::Active)
                    ->orWhere('seller_id', $viewerId);
            })
            ->first();
    }

    /**
     * The marketplace base query: active listings only, with a seller
     * projection that never loads the seller's email address.
     */
    private function activeQuery(): Builder
    {
        return Listing::query()
            ->with('seller:id,name')
            ->where('status', ListingStatus::Active);
    }

    /**
     * Free-text search across the three searchable listing columns.
     *
     * Runs in SQL with bound parameters. The marketplace is never loaded into
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

    /**
     * Apply the documented marketplace filters.
     *
     * `livestock_type` stays free text and is compared exactly; it is not an
     * enum and must not become one (functional documentation §4.1).
     */
    private function applyFilters(
        Builder $query,
        ?string $livestockType,
        ?string $location,
        ?float $minPrice,
        ?float $maxPrice,
    ): void {
        if ($livestockType !== null && $livestockType !== '') {
            $query->where('livestock_type', $livestockType);
        }

        if ($location !== null && $location !== '') {
            $query->where('location', $location);
        }

        if ($minPrice !== null) {
            $query->where('asking_price', '>=', $minPrice);
        }

        if ($maxPrice !== null) {
            $query->where('asking_price', '<=', $maxPrice);
        }
    }
}
