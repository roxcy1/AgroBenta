<?php

namespace App\Notifications;

use App\Models\Transaction;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

/**
 * "A buyer created a transaction for your listing."
 *
 * Fired by `TransactionService::create()` to the **seller** — the buyer already
 * knows they created it. Notifies once per transaction, at creation time, and
 * never again for that row (a status change fires its own notification).
 *
 * ## Why the payload does not carry the full transaction
 *
 * The mobile screen fetches `/api/transactions/{id}` when the notification is
 * tapped. Embedding a copy of the transaction in `notifications.data` would
 * duplicate it and allow the two copies to disagree if the transaction is later
 * cancelled. The notification is a *pointer* — action `transaction` + the row
 * id — and the screen loads the truth.
 */
class TransactionCreated extends Notification
{
    use Queueable;

    public function __construct(
        public readonly Transaction $transaction,
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
        $listingTitle = trim(
            ($this->transaction->listing?->livestock_type ?? '').' '
            .($this->transaction->listing?->breed ?? '')
        );

        return [
            'type' => 'transactions',
            'title' => 'New transaction',
            'body' => $listingTitle !== ''
                ? "{$this->transaction->buyer->name} created a transaction for {$listingTitle}."
                : "{$this->transaction->buyer->name} created a transaction for your listing.",
            'action' => 'transaction',
            'action_id' => $this->transaction->getKey(),
        ];
    }
}