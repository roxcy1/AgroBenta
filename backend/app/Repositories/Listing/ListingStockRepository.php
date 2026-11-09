<?php

namespace App\Repositories\Listing;

use App\Models\Listing;

/**
 * Row-level data access for listing stock.
 *
 * Reserved stock is taken from `listings.quantity`, which has always meant the
 * number of heads currently available. The repository only performs the
 * reads/writes; the availability rules themselves belong to
 * `ListingReservationService`.
 */
class ListingStockRepository
{
    /**
     * Read one listing with a row lock for the duration of a transaction.
     */
    public function lock(int $listingId): ?Listing
    {
        return Listing::query()
            ->whereKey($listingId)
            ->lockForUpdate()
            ->first();
    }

    /**
     * Take [quantity] heads out of the locked listing's available stock.
     */
    public function decrement(Listing $listing, int $quantity): Listing
    {
        $listing->quantity = (int) $listing->quantity - $quantity;
        $listing->save();

        return $listing->refresh();
    }

    /**
     * Put [quantity] heads back onto the locked listing's available stock.
     */
    public function increment(Listing $listing, int $quantity): Listing
    {
        $listing->quantity = (int) $listing->quantity + $quantity;
        $listing->save();

        return $listing->refresh();
    }
}
