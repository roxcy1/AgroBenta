<?php

namespace App\Notifications;

use App\Models\Transaction;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

/**
 * "The other party changed the status of transaction #N."
 *
 * Fired to the **counterparty** (the party that did not make the change).
 * Fires for every status transition except `pending → cancelled` (which fires
 * its own [TransactionCancelled] to keep the wording "cancelled" distinct) and
 * `created` (the initial insert is [TransactionCreated]).
 *
 * ## The `$actorId` parameter
 *
 * The notification is addressed to "the other party", so the class needs to
 * know who changed it. Passing the id rather than the User keeps this class
 * decoupled from the service layer that calls it.
 */
class TransactionStatusChanged extends Notification
{
    use Queueable;

    public function __construct(
        public readonly Transaction $transaction,
        public readonly int $actorId,
        public readonly string $oldStatus,
        public readonly string $newStatus,
    ) {
    }

    /**
     * @return array<int, string>
     */
    public function via(object $notifiable): array
    {
        return ['database'];
    }

    /**
     * @return array<string, mixed>
     */
    public function toArray(object $notifiable): array
    {
        return [
            'type' => 'transactions',
            'title' => 'Transaction updated',
            'body' => "Transaction #{$this->transaction->getKey()} is now {$this->newStatus}.",
            'action' => 'transaction',
            'action_id' => $this->transaction->getKey(),
        ];
    }
}