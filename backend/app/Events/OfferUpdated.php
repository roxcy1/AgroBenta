<?php

namespace App\Events;

use App\Models\Offer;
use Illuminate\Broadcasting\PrivateChannel;

/**
 * An offer moved to a terminal state (accepted, declined, or withdrawn).
 *
 * Broadcast to the counterparty — the seller when the buyer accepts or
 * declines, the buyer when the seller withdraws. On acceptance the payload
 * carries the id of the `pending` transaction that acceptance created, so the
 * seller can navigate straight to it.
 */
class OfferUpdated extends BroadcastEvent
{
    public function __construct(
        public readonly Offer $offer,
        public readonly string $status,
        public readonly int $recipientId,
        public readonly ?int $transactionId = null,
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
        return 'offer.updated';
    }

    /**
     * @return array<string, mixed>
     */
    public function broadcastWith(): array
    {
        return [
            'offer_id' => $this->offer->getKey(),
            'listing_id' => (int) $this->offer->listing_id,
            'buyer_id' => (int) $this->offer->buyer_id,
            'seller_id' => (int) $this->offer->seller_id,
            'status' => $this->status,
            'transaction_id' => $this->transactionId,
        ];
    }
}
