<?php

namespace App\Services\Inventory;

/**
 * Decides whether legacy listing inventory can be initialized without a guess.
 *
 * `listings.quantity` is already the available-stock compatibility value. A
 * transaction with `inventory_reserved = false` is not evidence that stock was
 * taken, even if it is pending or completed; those rows require an administrator
 * allocation before the listing may return to sale.
 */
final class LegacyInventoryBackfillPolicy
{
    /**
     * @param  iterable<object{status: string, quantity: int|string, inventory_reserved: int|bool}>  $transactions
     * @return array{reconciliation_required: bool, total_quantity: int|null, legacy_quantity_snapshot: int|null}
     */
    public function assess(int $availableQuantity, string $listingStatus, iterable $transactions): array
    {
        $accounted = 0;
        $hasUnallocatedSale = false;
        $invalidCancelledReservation = false;

        foreach ($transactions as $transaction) {
            $reserved = (bool) $transaction->inventory_reserved;

            if ($transaction->status === 'cancelled' && $reserved) {
                $invalidCancelledReservation = true;
            }

            if (in_array($transaction->status, ['pending', 'completed'], true)) {
                if (! $reserved) {
                    $hasUnallocatedSale = true;
                } else {
                    $accounted += (int) $transaction->quantity;
                }
            }
        }

        $totalQuantity = $availableQuantity + $accounted;
        $requiresReconciliation = $listingStatus === 'sold'
            || $hasUnallocatedSale
            || $invalidCancelledReservation
            || $totalQuantity < 1
            || $totalQuantity > 4294967295;

        return [
            'reconciliation_required' => $requiresReconciliation,
            'total_quantity' => $requiresReconciliation ? null : $totalQuantity,
            'legacy_quantity_snapshot' => $requiresReconciliation ? $availableQuantity : null,
        ];
    }
}
