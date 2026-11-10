<?php

namespace App\Events;

use App\Models\Offer;
use Illuminate\Broadcasting\PrivateChannel;

/**
 * A seller has created a purchase offer for the inquiry's buyer.
 *
 * Broadcast to the buyer's `user.{buyer_id}` channel.
 */
class OfferCreated extends BroadcastEvent
{
    public function __construct(public readonly Offer $offer)
    {
    }

    /**
     * @return array<int, \Illuminate\Broadcasting\Channel>
     */
    public function broadcastOn(): array
    {
        return [new PrivateChannel('user.'.$this->offer->buyer_id)];
    }

    public function broadcastAs(): string
    {
        return 'offer.created';
    }

    /**
     * @return array<string, mixed>
     */
    public function broadcastWith(): array
    {
        return [
            'offer_id' => $this->offer->getKey(),
            'inquiry_id' => (int) $this->offer->inquiry_id,
            'listing_id' => (int) $this->offer->listing_id,
            'buyer_id' => (int) $this->offer->buyer_id,
            'seller_id' => (int) $this->offer->seller_id,
            'proposed_amount' => $this->offer->proposed_amount,
        ];
    }
}
