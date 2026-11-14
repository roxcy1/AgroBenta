<?php

namespace App\Services\Admin;

use App\Enums\ActivityAction;
use App\Enums\FulfillmentStatus;
use App\Enums\ListingStatus;
use App\Enums\TransactionStatus;
use App\Events\TransactionUpdated;
use App\Events\ListingInventoryUpdated;
use App\Models\Listing;
use App\Models\ListingInventoryReconciliation;
use App\Models\Transaction;
use App\Models\User;
use App\Repositories\Listing\ListingStockRepository;
use App\Services\ActivityLogger;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpKernel\Exception\HttpException;

/**
 * Evidence-backed administrator reconciliation for quarantined inventory.
 *
 * The listing row is locked before historical transaction rows. The same lock
 * order is used by current reservation, cancellation, and completion writes, so
 * a reconciliation cannot race a quantity adjustment or allocate a transaction
 * twice.
 */
class ListingInventoryReconciliationService
{
    public function __construct(
        private readonly ListingStockRepository $stock,
        private readonly ActivityLogger $activity,
    ) {
        //
    }

    /**
     * Reconcile a listing from an administrator's verified physical count and
     * evidence-backed allocation of every unaccounted pending/completed row.
     *
     * @param  list<int>  $transactionIds
     * @return array{listing: Listing, reconciliation: ListingInventoryReconciliation, transactions: list<Transaction>}
     */
    public function reconcile(
        int $listingId,
        User $admin,
        int $verifiedPhysicalQuantity,
        int $verifiedExternallySoldQuantity,
        array $transactionIds,
        string $reason,
        ?string $evidence,
    ): array {
        return DB::transaction(function () use (
            $listingId,
            $admin,
            $verifiedPhysicalQuantity,
            $verifiedExternallySoldQuantity,
            $transactionIds,
            $reason,
            $evidence,
        ): array {
            $listing = $this->stock->lock($listingId);

            if ($listing === null) {
                abort(404, 'Listing not found.');
            }

            if (! $listing->inventory_reconciliation_required) {
                abort(409, 'This listing does not require inventory reconciliation.');
            }

            $unaccounted = Transaction::query()
                ->where('listing_id', $listingId)
                ->where('inventory_accounted', false)
                ->where('inventory_reserved', false)
                ->whereIn('status', [TransactionStatus::Pending, TransactionStatus::Completed])
                ->orderBy('id')
                ->lockForUpdate()
                ->get();

            $expectedIds = $unaccounted->modelKeys();
            $providedIds = array_values(array_unique(array_map('intval', $transactionIds)));
            sort($expectedIds);
            sort($providedIds);

            if ($expectedIds !== $providedIds) {
                abort(409, 'Every unaccounted pending or completed transaction must be verified exactly once.');
            }

            $newPending = 0;
            $newCompleted = 0;
            foreach ($unaccounted as $transaction) {
                if ($transaction->status === TransactionStatus::Pending) {
                    $newPending += (int) $transaction->quantity;
                } else {
                    $newCompleted += (int) $transaction->quantity;
                }
            }

            $existing = $this->stock->accountedQuantities($listingId);
            if ($verifiedExternallySoldQuantity < (int) $listing->externally_sold_quantity) {
                abort(409, 'Verified external sales cannot reduce a previously reconciled quantity.');
            }
            $pendingQuantity = $existing['reserved'] + $newPending;
            $completedQuantity = $existing['completed'] + $newCompleted;
            $totalQuantity = $verifiedPhysicalQuantity
                + $pendingQuantity
                + $completedQuantity
                + $verifiedExternallySoldQuantity;

            if ($totalQuantity < 1 || $totalQuantity > 4294967295) {
                abort(422, 'The reconciled total quantity must be a positive whole number within the supported limit.');
            }

            if ($listing->status === ListingStatus::Sold &&
                ($verifiedPhysicalQuantity !== 0 || $pendingQuantity !== 0)) {
                abort(409, 'A sold listing can only be reconciled with no available or reserved animals.');
            }

            if (($newCompleted > 0 || $verifiedExternallySoldQuantity > 0) &&
                ($evidence === null || trim($evidence) === '')) {
                abort(422, 'Evidence is required for completed or externally reported sales.');
            }

            foreach ($unaccounted as $transaction) {
                $transaction->inventory_accounted = true;
                $transaction->inventory_accounted_at = now();
                $transaction->inventory_accounted_by = $admin->getKey();

                // Only pending transactions receive a new reservation now.
                // Completed legacy rows become accounted sales without being
                // rewritten as if they had reserved stock at creation time.
                if ($transaction->status === TransactionStatus::Pending) {
                    $transaction->inventory_reserved = true;
                }

                $transaction->save();
            }

            $legacyQuantity = $listing->legacy_quantity_snapshot;
            $listing->total_quantity = $totalQuantity;
            $listing->quantity = $verifiedPhysicalQuantity;
            $listing->externally_sold_quantity = $verifiedExternallySoldQuantity;
            $listing->inventory_reconciliation_required = false;
            $listing->legacy_quantity_snapshot = null;

            $automaticallySold = $listing->status === ListingStatus::Active
                && $verifiedPhysicalQuantity === 0
                && $pendingQuantity === 0
                && $completedQuantity + $verifiedExternallySoldQuantity === $totalQuantity;

            if ($automaticallySold) {
                $listing->status = ListingStatus::Sold;
            }

            $listing->save();
            ListingInventoryUpdated::dispatch((int) $listing->getKey());

            $reconciliation = ListingInventoryReconciliation::query()->create([
                'listing_id' => $listing->getKey(),
                'admin_id' => $admin->getKey(),
                'verified_physical_quantity' => $verifiedPhysicalQuantity,
                'verified_pending_quantity' => $pendingQuantity,
                'verified_completed_quantity' => $completedQuantity,
                'verified_externally_sold_quantity' => $verifiedExternallySoldQuantity,
                'verified_total_quantity' => $totalQuantity,
                'verified_available_quantity' => $verifiedPhysicalQuantity,
                'accounted_transaction_ids' => $providedIds,
                'reason' => trim($reason),
                'evidence' => $evidence === null ? null : trim($evidence),
            ]);

            $this->activity->log(
                $admin,
                ActivityAction::ListingInventoryReconciled,
                sprintf('Inventory reconciled for listing #%d.', $listing->getKey()),
                [
                    'target_type' => 'listing',
                    'target_id' => $listing->getKey(),
                    'context' => [
                        'reconciliation_id' => $reconciliation->getKey(),
                        'accounted_transaction_ids' => $providedIds,
                    ],
                    'changes' => [
                        'quantity' => ['from' => $legacyQuantity, 'to' => $verifiedPhysicalQuantity],
                        'total_quantity' => ['from' => null, 'to' => $totalQuantity],
                        'inventory_reconciliation_required' => ['from' => true, 'to' => false],
                    ],
                ],
            );

            // Both parties may have this legacy transaction open. Reuse the
            // established transaction event so their clients refresh the
            // authoritative resource after commit.
            foreach ($unaccounted as $transaction) {
                $fresh = $transaction->fresh();
                if ($fresh === null) {
                    continue;
                }

                foreach ([(int) $fresh->buyer_id, (int) $fresh->seller_id] as $recipientId) {
                    TransactionUpdated::dispatch(
                        $fresh,
                        $fresh->status->value,
                        $fresh->fulfillment_status?->value,
                        $recipientId,
                    );
                }
            }

            return [
                'listing' => $listing->fresh(),
                'reconciliation' => $reconciliation,
                'transactions' => $unaccounted->all(),
            ];
        });
    }
}
