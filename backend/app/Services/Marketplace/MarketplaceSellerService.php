<?php

namespace App\Services\Marketplace;

use App\Repositories\Marketplace\MarketplaceListingRepository;
use App\Repositories\Marketplace\MarketplaceSellerRepository;
use App\Support\TrinidadLocationAddress;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;

/**
 * Application logic for the public seller profile.
 *
 * A seller profile is part of the buyer marketplace, so the same visibility
 * rules apply: only marketplace-visible listings are counted or listed, and an
 * account with nothing public to show is treated as absent. The service owns
 * the two disclosure decisions that must not live in a controller or resource:
 *
 *  - **Who has a public profile.** A non-deleted account is public when the
 *    server has granted seller capability (an approved verification) or when it
 *    has at least one marketplace-visible listing. The second condition keeps
 *    every visible seller card openable — an approved seller whose capability
 *    was later revoked still has active listings — while a plain buyer account
 *    with no inventory remains indistinguishable from an unknown id.
 *  - **Which location is disclosed.** Only the barangay-level Trinidad address
 *    is public. `users.location` stores the owner's full address including a
 *    street or purok, so the raw column never leaves this class. Legacy
 *    free-text locations that cannot be parsed are withheld rather than echoed.
 */
class MarketplaceSellerService
{
    public function __construct(
        private readonly MarketplaceSellerRepository $sellers,
        private readonly MarketplaceListingRepository $listings,
    ) {
        //
    }

    /**
     * The public profile payload, or null when the account is not public.
     *
     * @return array{
     *     id: int,
     *     name: string,
     *     avatar_url: string|null,
     *     bio: string|null,
     *     is_verified: bool,
     *     public_location: string|null,
     *     member_since: string|null,
     *     active_listings_count: int
     * }|null
     */
    public function profile(int $sellerId): ?array
    {
        $seller = $this->sellers->findPublicSeller($sellerId);

        if ($seller === null) {
            return null;
        }

        $activeListings = $this->listings->countActiveForSeller($sellerId);

        if (! $seller->isApprovedSeller() && $activeListings === 0) {
            return null;
        }

        return [
            'id' => (int) $seller->getKey(),
            'name' => (string) $seller->name,
            'avatar_url' => $seller->avatar_url,
            'bio' => $seller->bio,
            'is_verified' => $seller->isApprovedSeller(),
            'public_location' => $this->publicLocation($seller->location),
            'member_since' => $seller->created_at?->toISOString(),
            'active_listings_count' => $activeListings,
        ];
    }

    /**
     * One page of the seller's marketplace-visible listings, or null when the
     * account has no public profile.
     *
     * Search, category and ordering are passed straight to the repository,
     * where they narrow the same visibility query the marketplace uses. They
     * therefore page across the seller's whole visible inventory and cannot
     * widen it.
     */
    public function listingsFor(
        int $sellerId,
        ?string $search = null,
        ?string $livestockType = null,
        string $sort = MarketplaceListingRepository::SORT_NEWEST,
        int $perPage = 15,
    ): ?LengthAwarePaginator {
        if ($this->profile($sellerId) === null) {
            return null;
        }

        return $this->listings->paginateActiveForSeller(
            sellerId: $sellerId,
            search: $search,
            livestockType: $livestockType,
            sort: $sort,
            perPage: $perPage,
        );
    }

    /**
     * The barangay-level public form of a stored Trinidad address.
     *
     * The street or purok is intentionally dropped: it identifies where a
     * person lives and is not needed to judge a listing's area. Anything the
     * canonical parser does not recognise — historical free text, for example —
     * is withheld rather than returned unchanged, because the raw value may
     * itself be an exact address.
     */
    private function publicLocation(?string $location): ?string
    {
        if ($location === null || trim($location) === '') {
            return null;
        }

        $parsed = TrinidadLocationAddress::parse($location);

        if ($parsed === null) {
            return null;
        }

        return TrinidadLocationAddress::format($parsed['barangay']);
    }
}
