<?php

namespace App\Repositories\Listing;

use App\Models\Listing;
use App\Models\Transaction;

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
     * Inventory-backed quantities whose transaction rows have been explicitly
     * accounted. Legacy rows are deliberately excluded until an administrator
     * reconciles them.
     *
     * @return array{reserved: int, completed: int}
     */
    public function accountedQuantities(int $listingId): array
    {
        $totals = Transaction::query()
            ->where('listing_id', $listingId)
            ->selectRaw(
                'COALESCE(SUM(CASE WHEN status = ? AND (inventory_accounted = 1 OR inventory_reserved = 1) THEN quantity ELSE 0 END), 0) as reserved_quantity, '.
                'COALESCE(SUM(CASE WHEN status = ? AND (inventory_accounted = 1 OR inventory_reserved = 1) THEN quantity ELSE 0 END), 0) as completed_quantity',
                ['pending', 'completed'],
            )
            ->first();

        return [
            'reserved' => (int) ($totals?->reserved_quantity ?? 0),
            'completed' => (int) ($totals?->completed_quantity ?? 0),
        ];
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

    /**
     * Persist the legacy available-stock projection and the authoritative
     * listing total while the listing row lock is held.
     */
    public function setInventory(Listing $listing, int $totalQuantity, int $availableQuantity): Listing
    {
        $listing->total_quantity = $totalQuantity;
        $listing->quantity = $availableQuantity;
        $listing->save();

        return $listing->refresh();
    }
}
