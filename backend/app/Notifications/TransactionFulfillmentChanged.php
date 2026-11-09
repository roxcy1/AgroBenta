<?php

namespace App\Notifications;

use App\Enums\FulfillmentStatus;
use App\Models\Transaction;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

/**
 * "The other party moved transaction #N to a new fulfillment stage."
 *
 * Fired to the counterparty: the buyer learns about each seller-controlled
 * handover/dispatch update, and the seller learns when the buyer confirms
 * receipt. It is a pointer to the transaction, not a copy of it.
 */
class TransactionFulfillmentChanged extends Notification
{
    use Queueable;

    public function __construct(
        public readonly Transaction $transaction,
        public readonly int $actorId,
        public readonly FulfillmentStatus $oldStatus,
        public readonly FulfillmentStatus $newStatus,
    ) {
        //
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
            'body' => "Transaction #{$this->transaction->getKey()} is now {$this->newStatus->label()}.",
            'action' => 'transaction',
            'action_id' => $this->transaction->getKey(),
        ];
    }
}
