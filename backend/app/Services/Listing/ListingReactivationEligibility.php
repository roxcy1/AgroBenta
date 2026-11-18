<?php

namespace App\Services\Listing;

use App\Models\Listing;

/**
 * Shared inventory gate for restoring an inactive listing to the marketplace.
 *
 * The caller must supply a locked/list-projected listing with inventory totals
 * loaded by `withInventoryTotals()`. This class only checks the existing ledger;
 * it never changes stock or transaction rows.
 */
class ListingReactivationEligibility
{
    /**
     * Return a refusal message, or null when the listing has eligible stock.
     */
    public function failureMessage(Listing $listing): ?string
    {
        if ($listing->inventory_reconciliation_required || $listing->total_quantity === null) {
            return 'This listing requires inventory reconciliation before it can be reactivated.';
        }

        $attributes = $listing->getAttributes();
        if (! array_key_exists('reserved_quantity', $attributes) ||
            ! array_key_exists('accounted_completed_quantity', $attributes)) {
            return 'Inventory totals are unavailable; this listing cannot be reactivated yet.';
        }

        $reserved = (int) ($listing->getAttribute('reserved_quantity') ?? 0);
        $completed = (int) ($listing->getAttribute('accounted_completed_quantity') ?? 0);
        $available = (int) $listing->total_quantity
            - $reserved
            - $completed
            - (int) $listing->externally_sold_quantity;

        if ($available !== (int) $listing->quantity) {
            return 'This listing requires inventory reconciliation before it can be reactivated.';
        }

        if ($available < 1) {
            return 'A listing must have available inventory before it can be reactivated.';
        }

        return null;
    }
}
