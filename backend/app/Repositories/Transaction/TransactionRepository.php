<?php

namespace App\Repositories\Transaction;

use App\Enums\TransactionStatus;
use App\Models\Transaction;
use App\Models\User;
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
     * Find one transaction the caller is a party to, or null.
     *
     * Returns null both when the transaction does not exist and when the
     * caller is not a party to it, which is the intent: a user must not be
     * able to probe for another pair's transactions by watching the status
     * code change. `404` for both.
     */
    public function findForUser(int $transactionId, User $user): ?Transaction
    {
        return Transaction::query()
            ->with([
                'buyer:id,name,email',
                'seller:id,name,email',
                'listing:id,livestock_type,breed,photos,seller_id',
            ])
            ->where('id', $transactionId)
            ->where(function (Builder $query) use ($user): void {
                $query->where('buyer_id', $user->getKey())
                    ->orWhere('seller_id', $user->getKey());
            })
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
    ): Transaction {
        return Transaction::query()->create([
            'buyer_id' => $buyer->getKey(),
            'seller_id' => $sellerId,
            'listing_id' => $listingId,
            'quantity' => $quantity,
            'total_amount' => $totalAmount,
            'status' => TransactionStatus::Pending,
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
     * The caller's transactions, optionally narrowed to one side.
     */
    private function scopedQuery(User $user, ?string $role): Builder
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
