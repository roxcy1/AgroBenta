<?php

namespace App\Repositories\Marketplace;

use App\Enums\ListingStatus;
use App\Enums\TransactionStatus;
use App\Models\Listing;
use App\Models\Transaction;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

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
            // Completed-sale count for the card, aggregated in the same query
            // (one sub-select, never per-row queries).
            ->withCount([
                'transactions as completed_sales' => fn (Builder $query) => $query
                    ->where('status', TransactionStatus::Completed),
            ])
            // `created_at` alone is not a total order, so listings written in
            // the same second would otherwise paginate unpredictably.
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->paginate($perPage);
    }

    /**
     * How far back a completed sale counts toward "popular".
     */
    public const POPULAR_WINDOW_DAYS = 30;

    /**
     * The only livestock categories the buyer surface ranks, lowercased for
     * comparison. `listings.livestock_type` is free text; anything else is not
     * a category this feature can present, so it is excluded rather than
     * guessed at.
     *
     * @var list<string>
     */
    public const POPULAR_TYPES = ['cattle', 'carabao', 'goat', 'swine'];

    /**
     * Rank the canonical livestock categories by completed sales, newest window
     * first.
     *
     * A completed transaction is the only genuine "popularity" signal the
     * schema has: pending and cancelled rows never count, and a sale counts
     * once because each `transactions.id` is counted with `DISTINCT`. The
     * completion date is `updated_at` — the moment the status moved to
     * `completed` (the table has no dedicated `completed_at` column).
     *
     * @return Collection<int, array{livestock_type: string, completed_sales: int, photo_url: string|null}>
     */
    public function popularLivestock(int $days = self::POPULAR_WINDOW_DAYS): Collection
    {
        $since = now()->subDays($days);

        $ranked = Transaction::query()
            ->join('listings', 'listings.id', '=', 'transactions.listing_id')
            ->where('transactions.status', TransactionStatus::Completed)
            ->where('transactions.updated_at', '>=', $since)
            ->whereIn(DB::raw('LOWER(listings.livestock_type)'), self::POPULAR_TYPES)
            ->selectRaw('LOWER(listings.livestock_type) as livestock_type')
            ->selectRaw('COUNT(DISTINCT transactions.id) as completed_sales')
            ->groupByRaw('LOWER(listings.livestock_type)')
            ->orderByDesc('completed_sales')
            ->orderBy('livestock_type')
            ->get();

        if ($ranked->isEmpty()) {
            return collect();
        }

        // One representative photo per category: the listing of its most recent
        // completed sale. Separate query so the aggregate stays simple and the
        // photo accessor runs on real Listing models.
        $recentListings = Transaction::query()
            ->join('listings', 'listings.id', '=', 'transactions.listing_id')
            ->where('transactions.status', TransactionStatus::Completed)
            ->where('transactions.updated_at', '>=', $since)
            ->whereIn(DB::raw('LOWER(listings.livestock_type)'), self::POPULAR_TYPES)
            ->orderByDesc('transactions.updated_at')
            ->orderByDesc('transactions.id')
            ->get(['listings.id as listing_id', 'listings.livestock_type']);

        $photoByType = [];
        foreach ($recentListings as $row) {
            $type = strtolower((string) $row->livestock_type);
            if (! isset($photoByType[$type])) {
                $photoByType[$type] = (int) $row->listing_id;
            }
        }

        $photos = Listing::query()
            ->whereIn('id', array_values($photoByType))
            ->get()
            ->mapWithKeys(fn (Listing $listing): array => [
                $listing->id => $listing->photos[0] ?? null,
            ]);

        return $ranked->map(fn ($row): array => [
            'livestock_type' => ucfirst((string) $row->livestock_type),
            'completed_sales' => (int) $row->completed_sales,
            'photo_url' => $photos[$photoByType[(string) $row->livestock_type]] ?? null,
        ])->values();
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
            // Same completed-sale aggregate as the list, so the card and the
            // detail screen can never disagree.
            ->withCount([
                'transactions as completed_sales' => fn (Builder $query) => $query
                    ->where('status', TransactionStatus::Completed),
            ])
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
