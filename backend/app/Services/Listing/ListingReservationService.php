<?php

namespace App\Services\Listing;

use App\Enums\ListingStatus;
use App\Events\ListingInventoryUpdated;
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
 * locked, the persisted compatibility quantity is checked, and the decrement
 * happens in the same database transaction as the transaction row that owns
 * the reservation.
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

        $this->ensureAvailableForNewSale($listing, $quantity);

        $updated = $this->stock->decrement($listing, $quantity);
        ListingInventoryUpdated::dispatch((int) $updated->getKey());

        return $updated;
    }

    /**
     * Return the transaction-backed portion of listing inventory.
     *
     * @return array{reserved: int, completed: int}
     */
    public function accountedQuantities(int $listingId): array
    {
        return $this->stock->accountedQuantities($listingId);
    }

    /**
     * Lock and validate stock for an inquiry without changing inventory.
     *
     * @throws HttpException
     */
    public function lockForInquiry(int $listingId, int $quantity): Listing
    {
        $listing = $this->stock->lock($listingId);

        if ($listing === null) {
            abort(404, 'Listing not found.');
        }

        $this->ensureAvailableForNewSale($listing, $quantity);

        return $listing;
    }

    /**
     * Lock and validate stock before a seller sends an offer. Offers do not
     * reserve stock; buyer acceptance performs the authoritative reservation.
     *
     * @throws HttpException
     */
    public function lockForOffer(int $listingId, int $quantity): Listing
    {
        return $this->lockForInquiry($listingId, $quantity);
    }

    /**
     * Lock a listing for cancellation, completion, or administrative inventory
     * reconciliation without requiring it to remain active.
     */
    public function lockForInventoryMutation(int $listingId): Listing
    {
        $listing = $this->stock->lock($listingId);

        if ($listing === null) {
            abort(404, 'Listing not found.');
        }

        return $listing;
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

        $updated = $this->stock->increment($listing, $quantity);
        ListingInventoryUpdated::dispatch((int) $updated->getKey());
    }

    /**
     * Mark a fully accounted listing sold after a transaction completion.
     * Returns true only for the one call that changes the status.
     */
    public function markSoldIfExhausted(int $listingId): bool
    {
        $listing = $this->stock->lock($listingId);

        if ($listing === null ||
            $listing->status !== ListingStatus::Active ||
            $listing->inventory_reconciliation_required ||
            $listing->total_quantity === null) {
            return false;
        }

        $accounted = $this->stock->accountedQuantities($listingId);
        $sold = $accounted['completed'] + (int) $listing->externally_sold_quantity;
        $expectedAvailable = (int) $listing->total_quantity - $accounted['reserved'] - $sold;

        if ($expectedAvailable !== (int) $listing->quantity) {
            abort(409, 'This listing requires inventory reconciliation before its status can change.');
        }

        if ((int) $listing->quantity !== 0 ||
            $accounted['reserved'] !== 0 ||
            $sold !== (int) $listing->total_quantity) {
            return false;
        }

        $listing->status = ListingStatus::Sold;
        $listing->save();
        ListingInventoryUpdated::dispatch((int) $listing->getKey());

        return true;
    }

    /**
     * Account for a seller's manual sale of every remaining available head.
     * The caller must hold the locked listing row and have checked ownership
     * and its active publication status.
     */
    public function markRemainingExternallySold(Listing $listing): int
    {
        if ($listing->inventory_reconciliation_required || $listing->total_quantity === null) {
            abort(409, 'This listing requires inventory reconciliation before it can be marked sold.');
        }

        $accounted = $this->stock->accountedQuantities((int) $listing->getKey());
        if ($accounted['reserved'] > 0) {
            abort(409, 'A listing with active reservations cannot be marked sold.');
        }

        $sold = $accounted['completed'] + (int) $listing->externally_sold_quantity;
        $expectedAvailable = (int) $listing->total_quantity - $accounted['reserved'] - $sold;
        if ($expectedAvailable !== (int) $listing->quantity) {
            abort(409, 'This listing requires inventory reconciliation before it can be marked sold.');
        }

        $externallySoldNow = (int) $listing->quantity;
        $listing->externally_sold_quantity = (int) $listing->externally_sold_quantity + $externallySoldNow;
        $listing->quantity = 0;
        $listing->status = ListingStatus::Sold;
        $listing->save();
        ListingInventoryUpdated::dispatch((int) $listing->getKey());

        return $externallySoldNow;
    }

    /**
     * The single guard for new inquiry, offer, and transaction activity.
     *
     * @throws HttpException
     */
    private function ensureAvailableForNewSale(Listing $listing, int $quantity): void
    {
        if ($listing->inventory_reconciliation_required || $listing->total_quantity === null) {
            abort(409, 'This listing requires inventory reconciliation before it can be sold.');
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

        $accounted = $this->stock->accountedQuantities((int) $listing->getKey());
        $expectedAvailable = (int) $listing->total_quantity
            - $accounted['reserved']
            - $accounted['completed']
            - (int) $listing->externally_sold_quantity;

        if ($expectedAvailable !== (int) $listing->quantity) {
            abort(409, 'This listing requires inventory reconciliation before it can be sold.');
        }
    }
}
