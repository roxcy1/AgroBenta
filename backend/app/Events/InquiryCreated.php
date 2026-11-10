<?php

namespace App\Events;

use App\Models\Inquiry;
use Illuminate\Broadcasting\PrivateChannel;

/**
 * A buyer has sent an inquiry about the seller's listing.
 *
 * Broadcast to the seller's `user.{seller_id}` channel. Distinct from
 * {@see MessageSent} (which also fires for the inquiry's opener message): the
 * client uses this to update the Inquiries tab, not just the thread.
 */
class InquiryCreated extends BroadcastEvent
{
    public function __construct(public readonly Inquiry $inquiry)
    {
    }

    /**
     * @return array<int, \Illuminate\Broadcasting\Channel>
     */
    public function broadcastOn(): array
    {
        return [new PrivateChannel('user.'.$this->inquiry->seller_id)];
    }

    public function broadcastAs(): string
    {
        return 'inquiry.created';
    }

    /**
     * @return array<string, mixed>
     */
    public function broadcastWith(): array
    {
        return [
            'inquiry_id' => $this->inquiry->getKey(),
            'listing_id' => (int) $this->inquiry->listing_id,
            'buyer_id' => (int) $this->inquiry->buyer_id,
            'seller_id' => (int) $this->inquiry->seller_id,
        ];
    }
}
