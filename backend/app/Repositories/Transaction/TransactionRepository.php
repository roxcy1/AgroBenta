<?php

namespace App\Repositories\Transaction;

use App\Enums\FulfillmentStatus;
use App\Enums\TransactionStatus;
use App\Models\Transaction;
use App\Models\User;
use Carbon\CarbonInterface;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;

/**
 * Data access for a user's own transactions.
 *
 * Every method here is scoped to the caller, because neither counterparty is
 * ever a client-selected value (contract §5.6). The scope is applied in SQL,
 * in this repository, so that "not yours" and "does not exist" are the same
 * absence and produce the same 404 — the controller cannot forget to check
 * ownership, because ownership is part of the lookup rather than a condition
 * applied afterwards.
 */
class TransactionRepository
{
    /**
     * Paginate the caller's transactions, newest first.
     *
     * @param  'buyer'|'seller'|null  $role  Narrow to one side, or both.
     */
    public function paginateForUser(
        User $user,
        ?string $role = null,
        ?TransactionStatus $status = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        $query = $this->scopedQuery($user, $role);

        if ($status !== null) {
            $query->where('status', $status);
        }

        return $query
            // A total order, so two transactions written in the same second
            // cannot appear on two pages at once.
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->paginate($perPage);
    }

    /**
     * Count the transactions where the caller is the seller.
     *
     * Only the total and pending counts are exposed. A completed count is not
     * returned because transaction completion is outside the documented
     * seller-dashboard scope (OQ-15).
     *
     * @return array{total: int, pending: int}
     */
    public function countsForSeller(User $seller): array
    {
        $counts = Transaction::query()
            ->where('seller_id', $seller->getKey())
            ->selectRaw('status, COUNT(*) as aggregate')
            ->groupBy('status')
            ->pluck('aggregate', 'status');

        $total = 0;

        foreach ($counts as $count) {
            $total += (int) $count;
        }

        return [
            'total' => $total,
            'pending' => (int) ($counts[TransactionStatus::Pending->value] ?? 0),
            // Genuinely completed only; the dashboard's "Completed Sales" tile
            // reads this and never derives a completion from any other state.
            'completed' => (int) ($counts[TransactionStatus::Completed->value] ?? 0),
        ];
    }

    /**
     * Find one transaction the caller is a party to, or null.
     *
     * Returns null both when the transaction does not exist and when the
     * caller is not a party to it, which is the intent: a user must not be
     * able to probe for another pair's transactions by watching the status
     * code change. `404` for both.
     */
    public function findForUser(int $transactionId, User $user): ?Transaction
    {
        return $this->scopedQuery($user)
            ->where('id', $transactionId)
            ->first();
    }

    /**
     * Lock one transaction the caller is a party to.
     *
     * Used by the cancellation path so its status and inventory flag cannot
     * change between the guard and the write.
     */
    public function lockForUser(int $transactionId, User $user): ?Transaction
    {
        return $this->scopedQuery($user)
            ->where('id', $transactionId)
            ->lockForUpdate()
            ->first();
    }

    /**
     * Persist a pending transaction.
     *
     * `buyer_id`, `seller_id`, `total_amount` and `status` are set here, from
     * the authenticated user, the listing and the contract, rather than
     * accepted from the request — the four fields a client must never choose.
     */
    public function createPending(
        User $buyer,
        int $sellerId,
        int $listingId,
        int $quantity,
        string $totalAmount,
        ?int $offerId = null,
        ?string $paymentMethod = null,
        ?string $collectionMethod = null,
        ?string $pickupDate = null,
    ): Transaction {
        return Transaction::query()->create([
            'buyer_id' => $buyer->getKey(),
            'seller_id' => $sellerId,
            'listing_id' => $listingId,
            'offer_id' => $offerId,
            'quantity' => $quantity,
            'total_amount' => $totalAmount,
            'payment_method' => $paymentMethod,
            'collection_method' => $collectionMethod,
            'pickup_date' => $pickupDate,
            'inventory_reserved' => true,
            'inventory_accounted' => true,
            'inventory_accounted_at' => now(),
            'status' => TransactionStatus::Pending,
            'fulfillment_status' => FulfillmentStatus::Confirmed,
        ]);
    }

    /**
     * Persist a status transition on a transaction the caller is party to.
     */
    public function updateStatus(Transaction $transaction, TransactionStatus $status): Transaction
    {
        $transaction->status = $status;
        $transaction->save();

        return $transaction->refresh();
    }

    /**
     * Record that a transaction's reserved stock has been returned.
     *
     * Called under the transaction row lock, in the same database transaction
     * as the stock increment, so a cancellation cannot release twice.
     */
    public function releaseInventory(Transaction $transaction): Transaction
    {
        $transaction->inventory_reserved = false;
        $transaction->inventory_accounted = false;
        $transaction->inventory_accounted_at = null;
        $transaction->inventory_accounted_by = null;
        $transaction->save();

        return $transaction->refresh();
    }

    /**
     * Persist a fulfillment-stage transition.
     */
    public function updateFulfillmentStatus(
        Transaction $transaction,
        FulfillmentStatus $status,
    ): Transaction {
        $transaction->fulfillment_status = $status;
        $transaction->save();

        return $transaction->refresh();
    }

    /**
     * Mark a transaction completed after the buyer confirms receipt, recording
     * the completion time and the historical receipt snapshot in the same
     * write.
     *
     * @param  array<string, mixed>  $snapshot
     */
    public function complete(
        Transaction $transaction,
        array $snapshot,
        CarbonInterface $completedAt,
    ): Transaction {
        $transaction->status = TransactionStatus::Completed;
        $transaction->fulfillment_status = FulfillmentStatus::Completed;
        $transaction->completed_at = $completedAt;
        $transaction->receipt_snapshot = $snapshot;
        $transaction->save();

        return $transaction->refresh();
    }

    /**
     * Record that a legacy transaction now holds a real stock reservation.
     *
     * Historical pending rows predate `inventory_reserved`; completing one
     * without taking stock would allow it to be sold twice. The completion path
     * reserves the quantity first and then flips this flag.
     */
    public function markInventoryReserved(Transaction $transaction): Transaction
    {
        $transaction->inventory_reserved = true;
        $transaction->inventory_accounted = true;
        $transaction->inventory_accounted_at = now();
        $transaction->save();

        return $transaction->refresh();
    }

    /**
     * Whether a listing has pending transactions that still hold its stock.
     */
    public function hasActiveReservationsForListing(int $listingId): bool
    {
        return Transaction::query()
            ->where('listing_id', $listingId)
            ->where('status', TransactionStatus::Pending)
            ->where('inventory_reserved', true)
            ->exists();
    }

    /**
     * Whether a listing has a completed transaction.
     *
     * Completed sales are historical records and must not disappear with the
     * listing. The seller-listing delete path asks this before destroying a
     * row, so the database's cascade cannot take a receipt with it.
     */
    public function hasCompletedForListing(int $listingId): bool
    {
        return Transaction::query()
            ->where('listing_id', $listingId)
            ->where('status', TransactionStatus::Completed)
            ->exists();
    }

    /**
     * The caller's transactions, optionally narrowed to one side.
     */
    private function scopedQuery(User $user, ?string $role = null): Builder
    {
        $query = Transaction::query()
            ->with([
                'buyer:id,name,email',
                'seller:id,name,email',
                'listing:id,livestock_type,breed,photos,seller_id',
            ]);

        if ($role === 'buyer') {
            return $query->where('buyer_id', $user->getKey());
        }

        if ($role === 'seller') {
            return $query->where('seller_id', $user->getKey());
        }

        return $query->where(function (Builder $nested) use ($user): void {
            // One OR group, never a filter that lets the caller pick an
            // arbitrary user. Both sides of a transaction are visible to the
            // counterparty by design.
            $nested->where('buyer_id', $user->getKey())
                ->orWhere('seller_id', $user->getKey());
        });
    }
}
