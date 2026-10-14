<?php

namespace App\Services\Transaction;

use App\Enums\ListingStatus;
use App\Enums\TransactionStatus;
use App\Models\Listing;
use App\Models\Transaction;
use App\Models\User;
use App\Repositories\Transaction\TransactionRepository;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;

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
 *  - `pending → cancelled` by either party, and that is the only transition
 *    this service offers (rule 5);
 *  - `completed` and `cancelled` are terminal — no undo, no reopen.
 *
 * Completion is deliberately absent. [D-15] rule 4 requires "the appropriate
 * transaction confirmation" without naming the actor, and that ambiguity is
 * open as OQ-15. The `complete` transition stays unimplemented until it is
 * answered; no method below offers a substitute for it.
 */
class TransactionService
{
    public function __construct(private readonly TransactionRepository $transactions)
    {
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
     */
    public function create(User $buyer, Listing $listing, int $quantity): Transaction
    {
        if ($listing->status !== ListingStatus::Active) {
            abort(409, 'This listing is not available for new transactions.');
        }

        if ((int) $listing->seller_id === (int) $buyer->getKey()) {
            abort(409, 'You cannot transact on your own listing.');
        }

        if ($quantity < 1) {
            abort(409, 'Quantity must be at least one.');
        }

        if ((int) $listing->quantity < $quantity) {
            abort(409, 'There is not enough stock for the requested quantity.');
        }

        // Server-derived: `asking_price × quantity`, two decimals. The client
        // sends only the quantity and never a price.
        $totalAmount = number_format((float) $listing->asking_price * $quantity, 2, '.', '');

        return $this->transactions->createPending(
            $buyer,
            (int) $listing->seller_id,
            (int) $listing->getKey(),
            $quantity,
            $totalAmount,
        );
    }

    /**
     * Cancel a pending transaction. Either party may cancel [D-15 rule 5].
     *
     * The transition is irreversible: a cancelled transaction stays cancelled.
     */
    public function cancel(Transaction $transaction): Transaction
    {
        $this->ensureStatusIs(
            $transaction,
            [TransactionStatus::Pending],
            'Only a pending transaction can be cancelled.',
        );

        return $this->transactions->updateStatus($transaction, TransactionStatus::Cancelled);
    }

    /**
     * Guard a lifecycle transition on the transaction's current state.
     *
     * @param  list<TransactionStatus>  $allowed
     */
    private function ensureStatusIs(Transaction $transaction, array $allowed, string $message): void
    {
        if (in_array($transaction->status, $allowed, true)) {
            return;
        }

        // 409, not 422: nothing about the request is malformed, the
        // transaction is simply in a state where this action has no meaning.
        abort(409, $message);
    }
}
