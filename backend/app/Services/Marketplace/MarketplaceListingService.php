<?php

namespace App\Services\Marketplace;

use App\Models\Listing;
use App\Repositories\Marketplace\MarketplaceListingRepository;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;

/**
 * Application logic for the buyer marketplace.
 *
 * Deliberately thin: this layer exists so the controller never touches the
 * repository directly, matching the layering the rest of the backend uses. All
 * marketplace visibility decisions live in the query, not here, because a
 * service that filtered results in PHP would eventually be bypassed by a
 * paginator that counts the wrong rows.
 */
class MarketplaceListingService
{
    public function __construct(private readonly MarketplaceListingRepository $listings)
    {
        //
    }

    /**
     * Browse the marketplace. Always active listings only.
     */
    public function browseMarketplace(
        ?string $search = null,
        ?string $livestockType = null,
        ?string $location = null,
        ?float $minPrice = null,
        ?float $maxPrice = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        return $this->listings->paginateActive(
            search: $search,
            livestockType: $livestockType,
            location: $location,
            minPrice: $minPrice,
            maxPrice: $maxPrice,
            perPage: $perPage,
        );
    }

    /**
     * Resolve a single listing for a viewer, or null when the viewer is not
     * allowed to see it. The caller maps null to the documented 404 so that a
     * forbidden listing is indistinguishable from a missing one.
     */
    public function findMarketplaceListing(int $listingId, int $viewerId): ?Listing
    {
        return $this->listings->findVisibleListing($listingId, $viewerId);
    }
}
