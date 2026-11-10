<?php

namespace App\Events;

use App\Models\Transaction;
use Illuminate\Broadcasting\PrivateChannel;

/**
 * A buyer has created a pending transaction against the seller's listing.
 *
 * Broadcast to the seller's `user.{seller_id}` channel. Covers both a direct
 * purchase and the transaction created when a buyer accepts an offer (the
 * seller also receives {@see OfferUpdated} for the acceptance itself).
 */
class TransactionCreated extends BroadcastEvent
{
    public function __construct(public readonly Transaction $transaction)
    {
    }

    /**
     * @return array<int, \Illuminate\Broadcasting\Channel>
     */
    public function broadcastOn(): array
    {
        return [new PrivateChannel('user.'.$this->transaction->seller_id)];
    }

    public function broadcastAs(): string
    {
        return 'transaction.created';
    }

    /**
     * @return array<string, mixed>
     */
    public function broadcastWith(): array
    {
        return [
            'transaction_id' => $this->transaction->getKey(),
            'listing_id' => (int) $this->transaction->listing_id,
            'buyer_id' => (int) $this->transaction->buyer_id,
            'seller_id' => (int) $this->transaction->seller_id,
            'quantity' => (int) $this->transaction->quantity,
            'total_amount' => $this->transaction->total_amount,
        ];
    }
}
