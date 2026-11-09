<?php

namespace App\Services\Transaction;

use App\Enums\ActivityAction;
use App\Enums\FulfillmentStatus;
use App\Enums\TransactionStatus;
use App\Models\Listing;
use App\Models\Transaction;
use App\Models\User;
use App\Notifications\TransactionCreated;
use App\Notifications\TransactionStatusChanged;
use App\Repositories\Transaction\TransactionRepository;
use App\Services\ActivityLogger;
use App\Services\Listing\ListingReservationService;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;

/**
 * The rules for what a user may do to a transaction, and from which state.
 *
 * The repository decides *which* rows are visible to a user. This service
 * decides what may happen to them, and it is the only place that answers
 * those questions, because the answers are the documented lifecycle [D-15]:
 *
 *  - creation is buyer-initiated, against an `active` listing the buyer does
 *    not own, with stock to cover the quantity (rule 1, rule 6, §6.2);
 *  - `total_amount` is `asking_price × quantity`, server-derived (rule 3);
 *  - stock is reserved atomically at creation and returned exactly once on
 *    cancellation;
 *  - `pending → cancelled` by either party before the fulfillment cutoff
 *    (rule 5);
 *  - `completed` is written by `TransactionFulfillmentService` after buyer
 *    receipt confirmation; both terminal states are immutable.
 *
 * Creation and cancellation live here; the seller/buyer fulfillment progression
 * lives in the fulfillment service so this class stays focused on the sale
 * record.
 */
class TransactionService
{
    public function __construct(
        private readonly TransactionRepository $transactions,
        private readonly ListingReservationService $reservations,
        private readonly ActivityLogger $activity,
    ) {
        //
    }

    /**
     * List the caller's transactions, newest first.
     *
     * @param  'buyer'|'seller'|null  $role
     */
    public function listForUser(
        User $user,
        ?string $role = null,
        ?TransactionStatus $status = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        return $this->transactions->paginateForUser($user, $role, $status, $perPage);
    }

    /**
     * Find one transaction the caller is a party to, or null.
     */
    public function findForUser(int $transactionId, User $user): ?Transaction
    {
        return $this->transactions->findForUser($transactionId, $user);
    }

    /**
     * Create a pending transaction for the authenticated buyer.
     *
     * Guards, in order: the listing must exist, must be `active`, must not be
     * the buyer's own, and must have stock for the quantity. A well-formed
     * request against a listing in the wrong state is a 409, not a 422.
     *
     * Every guard runs inside a `DB::transaction()` against a row-level
     * `lockForUpdate()` read, so status, ownership and stock come from the
     * persisted row rather than the caller's model. A concurrent `markSold()`
     * therefore cannot flip the listing to `sold` between the check and the
     * transaction create. `SellerListingService::markSold()` takes the same
     * listing-row lock, so both operations serialize on the listing row with a
     * consistent lock order and no deadlock risk.
     */
    public function create(User $buyer, Listing $listing, int $quantity): Transaction
    {
        return DB::transaction(function () use ($buyer, $listing, $quantity): Transaction {
            // Reserve atomically: this locks the listing row, checks its status
            // and persisted stock, and decrements the quantity. Two concurrent
            // buyers therefore cannot reserve the same heads.
            $locked = $this->reservations->reserve(
                (int) $listing->getKey(),
                $quantity,
            );

            if ((int) $locked->seller_id === (int) $buyer->getKey()) {
                abort(409, 'You cannot transact on your own listing.');
            }

            // Server-derived total amount from the locked listing's current price.
            $totalAmount = number_format(
                (float) $locked->asking_price * $quantity,
                2,
                '.',
                '',
            );

            $transaction = $this->transactions->createPending(
                $buyer,
                (int) $locked->seller_id,
                (int) $locked->getKey(),
                $quantity,
                $totalAmount,
            );

            $this->activity->log(
                $buyer,
                ActivityAction::TransactionCreated,
                sprintf(
                    'Transaction #%d created for listing #%d.',
                    $transaction->getKey(),
                    $locked->getKey(),
                ),
                [
                    'target_type' => 'transaction',
                    'target_id' => $transaction->getKey(),
                    'context' => [
                        'listing_id' => $locked->getKey(),
                        'seller_id' => (int) $locked->seller_id,
                        'quantity' => $quantity,
                    ],
                    'changes' => [
                        'status' => ['from' => null, 'to' => TransactionStatus::Pending->value],
                    ],
                ],
            );

            // Notify the seller that a buyer started a transaction for their
            // listing. The buyer already knows — they just created it. Only the
            // seller needs to learn about it, and only once per row.
            $seller = $locked->seller;
            if ($seller !== null) {
                $seller->notify(new TransactionCreated($transaction->fresh(['listing', 'buyer'])));
            }

            return $transaction;
        });
    }

    /**
     * Cancel a pending transaction. Either party may cancel [D-15 rule 5].
     *
     * The row is locked, the status re-checked, and any stock this transaction
     * reserved is returned in the same database transaction that marks it
     * cancelled. The `inventory_reserved` flag makes the release idempotent:
     * a second cancel is a 409 and releases nothing.
     *
     * The fulfillment phase will narrow "before handover or dispatch" to a
     * concrete cutoff once those stages exist.
     */
    public function cancel(Transaction $transaction, User $actor): Transaction
    {
        return DB::transaction(function () use ($transaction, $actor): Transaction {
            // Re-read under a row lock: the model handed in by the controller
            // may be stale, and a concurrent cancel must not release stock
            // twice.
            $locked = $this->transactions->lockForUser(
                (int) $transaction->getKey(),
                $actor,
            );

            if ($locked === null) {
                abort(404, 'Transaction not found.');
            }

            if ($locked->status !== TransactionStatus::Pending) {
                abort(409, 'Only a pending transaction can be cancelled.');
            }

            $flow = FulfillmentStatus::flowFor($locked->collection_method);
            $fulfillment = $locked->fulfillment_status ?? FulfillmentStatus::Confirmed;

            if (! $fulfillment->allowsCancellation($flow)) {
                abort(409, 'This transaction can no longer be cancelled after handover or dispatch.');
            }

            // Return reserved stock only when this transaction actually took
            // it. Historical pending rows created before reservation have the
            // flag false and must not inflate the listing.
            if ($locked->inventory_reserved) {
                $this->reservations->release(
                    (int) $locked->listing_id,
                    (int) $locked->quantity,
                );
                $this->transactions->releaseInventory($locked);
            }

            $cancelled = $this->transactions->updateStatus($locked, TransactionStatus::Cancelled);

            $this->activity->log(
                $actor,
                ActivityAction::TransactionCancelled,
                sprintf('Transaction #%d cancelled.', $locked->getKey()),
                [
                    'target_type' => 'transaction',
                    'target_id' => $locked->getKey(),
                    'context' => [
                        'listing_id' => $locked->listing_id,
                        'buyer_id' => $locked->buyer_id,
                        'seller_id' => $locked->seller_id,
                    ],
                    'changes' => [
                        'status' => [
                            'from' => TransactionStatus::Pending->value,
                            'to' => TransactionStatus::Cancelled->value,
                        ],
                    ],
                ],
            );

            // Notify the counterparty about the cancellation. The actor already
            // knows they cancelled it; only the other party needs to learn.
            $counterpartyId = $actor->getKey() === $locked->buyer_id
                ? $locked->seller_id
                : $locked->buyer_id;

            $counterparty = User::find($counterpartyId);
            if ($counterparty !== null) {
                $counterparty->notify(new TransactionStatusChanged(
                    $cancelled->fresh(['listing']),
                    $actor->getKey(),
                    TransactionStatus::Pending->value,
                    TransactionStatus::Cancelled->value,
                ));
            }

            return $cancelled;
        });
    }
}
