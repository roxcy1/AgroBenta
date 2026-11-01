<?php

namespace App\Notifications;

use App\Models\Transaction;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

/**
 * "The other party changed the status of transaction #N."
 *
 * Fired to the **counterparty** (the party that did not make the change).
 *
 * Currently triggered when a transaction is cancelled (`pending -> cancelled`).
 * When the `complete` transition is implemented (currently blocked by OQ-15),
 * this same class will fire with `newStatus = 'completed'`.
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