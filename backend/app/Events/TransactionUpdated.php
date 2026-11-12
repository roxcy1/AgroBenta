<?php

namespace App\Events;

use App\Models\Transaction;
use Illuminate\Broadcasting\PrivateChannel;

/**
 * A transaction changed state: cancelled, completed, or a fulfillment stage
 * moved. Broadcast to the counterparty (the party that did not make the change).
 */
class TransactionUpdated extends BroadcastEvent
{
    public function __construct(
        public readonly Transaction $transaction,
        public readonly string $status,
        public readonly ?string $fulfillmentStatus,
        public readonly int $recipientId,
    ) {
    }

    /**
     * @return array<int, \Illuminate\Broadcasting\Channel>
     */
    public function broadcastOn(): array
    {
        return [new PrivateChannel('user.'.$this->recipientId)];
    }

    public function broadcastAs(): string
    {
        return 'transaction.updated';
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
            'status' => $this->status,
            'fulfillment_status' => $this->fulfillmentStatus,
        ];
    }
}
