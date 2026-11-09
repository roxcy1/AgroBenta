<?php

namespace App\Services\Listing;

use App\Enums\ListingStatus;
use App\Models\Listing;
use App\Repositories\Listing\ListingStockRepository;
use Symfony\Component\HttpKernel\Exception\HttpException;

/**
 * The one place that takes stock out of a listing and puts it back.
 *
 * Both entry points that create a transaction — the direct buyer purchase
 * (`TransactionService::create`) and an accepted seller offer
 * (`OfferService::accept`) — call {@see reserve()}. That is what keeps
 * "available quantity" honest under concurrent buyers: the listing row is
 * locked, the persisted quantity is checked, and the decrement happens in the
 * same database transaction as the transaction row that owns the reservation.
 *
 * A cancellation calls {@see release()} only for a transaction whose
 * `inventory_reserved` flag is true, so a historical pending record that never
 * decremented stock cannot inflate the listing when it is cancelled.
 */
class ListingReservationService
{
    public function __construct(
        private readonly ListingStockRepository $stock,
    ) {
        //
    }

    /**
     * Atomically reserve [quantity] heads of an active listing.
     *
     * @throws HttpException
     */
    public function reserve(int $listingId, int $quantity): Listing
    {
        $listing = $this->stock->lock($listingId);

        if ($listing === null) {
            abort(404, 'Listing not found.');
        }

        if ($listing->status !== ListingStatus::Active) {
            abort(409, 'This listing is not available for new transactions.');
        }

        if ($quantity < 1) {
            abort(409, 'Quantity must be at least one.');
        }

        if ((int) $listing->quantity < $quantity) {
            abort(409, 'There is not enough stock for the requested quantity.');
        }

        return $this->stock->decrement($listing, $quantity);
    }

    /**
     * Return a previously reserved quantity to the listing.
     *
     * The caller must hold the transaction row lock and must have verified
     * `inventory_reserved`; this method only performs the stock write.
     */
    public function release(int $listingId, int $quantity): void
    {
        $listing = $this->stock->lock($listingId);

        if ($listing === null || $quantity < 1) {
            return;
        }

        $this->stock->increment($listing, $quantity);
    }
}
