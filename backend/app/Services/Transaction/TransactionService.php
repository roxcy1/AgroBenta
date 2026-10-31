<?php

namespace App\Services\Transaction;

use App\Enums\ActivityAction;
use App\Enums\ListingStatus;
use App\Enums\TransactionStatus;
use App\Models\Listing;
use App\Models\Transaction;
use App\Models\User;
use App\Repositories\Transaction\TransactionRepository;
use App\Services\ActivityLogger;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;
use App\Notifications\TransactionCreated;
use App\Notifications\TransactionStatusChanged;

/**
 * The rules for what a user may do to a transaction, and from which state.
 *
 * The repository decides which rows are visible to a user. This service
 * decides what may happen to them.
 */
class TransactionService
{
    public function __construct(
        private readonly TransactionRepository $transactions,
        private readonly ActivityLogger $activity,
    ) {
        //
    }

    /**
     * List the caller's transactions, newest first.
     *
     * @param 'buyer'|'seller'|null $role
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
     */
    public function create(User $buyer, Listing $listing, int $quantity): Transaction
    {
        return DB::transaction(function () use ($buyer, $listing, $quantity): Transaction {
            $locked = Listing::query()
                ->where('id', $listing->getKey())
                ->lockForUpdate()
                ->first();

            if ($locked === null) {
                abort(404, 'Listing not found.');
            }

            if ($locked->status !== ListingStatus::Active) {
                abort(409, 'This listing is not available for new transactions.');
            }

            if ((int) $locked->seller_id === (int) $buyer->getKey()) {
                abort(409, 'You cannot transact on your own listing.');
            }

            if ($quantity < 1) {
                abort(409, 'Quantity must be at least one.');
            }

            if ((int) $locked->quantity < $quantity) {
                abort(409, 'There is not enough stock for the requested quantity.');
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

            // Notify the seller that a buyer started a transaction.
            // The buyer knows because they created the transaction.
            // Only the seller needs to receive this notification.
            $seller = $locked->seller;

            if ($seller !== null) {
                $seller->notify(
                    new TransactionCreated(
                        $transaction->fresh(['listing', 'buyer'])
                    )
                );
            }

            return $transaction;
        });
    }

    /**
     * Cancel a pending transaction. Either party may cancel [D-15 rule 5].
     *
     * The transition is irreversible: a cancelled transaction stays cancelled.
     */
    public function cancel(Transaction $transaction, User $actor): Transaction
    {
        $this->ensureStatusIs(
            $transaction,
            [TransactionStatus::Pending],
            'Only a pending transaction can be cancelled.',
        );

        return DB::transaction(function () use ($transaction, $actor): Transaction {
            $cancelled = $this->transactions->updateStatus(
                $transaction,
                TransactionStatus::Cancelled
            );

            $this->activity->log(
                $actor,
                ActivityAction::TransactionCancelled,
                sprintf('Transaction #%d cancelled.', $transaction->getKey()),
                [
                    'target_type' => 'transaction',
                    'target_id' => $transaction->getKey(),
                    'context' => [
                        'listing_id' => $transaction->listing_id,
                        'buyer_id' => $transaction->buyer_id,
                        'seller_id' => $transaction->seller_id,
                    ],
                    'changes' => [
                        'status' => [
                            'from' => TransactionStatus::Pending->value,
                            'to' => TransactionStatus::Cancelled->value,
                        ],
                    ],
                ],
            );

            // Cancel is a status change like any other.
            // Notify the party who did NOT perform the cancellation.
            $counterpartyId = (int) $actor->getKey() === (int) $transaction->buyer_id
                ? $transaction->seller_id
                : $transaction->buyer_id;

            $counterparty = User::find($counterpartyId);

            if ($counterparty !== null) {
                $counterparty->notify(
                    new TransactionStatusChanged(
                        $cancelled->fresh(['listing']),
                        $actor->getKey(),
                        TransactionStatus::Pending->value,
                        TransactionStatus::Cancelled->value,
                    )
                );
            }

            return $cancelled;
        });
    }

    /**
     * Guard a lifecycle transition on the transaction's current state.
     *
     * @param list<TransactionStatus> $allowed
     */
    private function ensureStatusIs(
        Transaction $transaction,
        array $allowed,
        string $message
    ): void {
        if (in_array($transaction->status, $allowed, true)) {
            return;
        }

        // 409, not 422: the transaction is simply in a state
        // where this action has no meaning.
        abort(409, $message);
    }
}
