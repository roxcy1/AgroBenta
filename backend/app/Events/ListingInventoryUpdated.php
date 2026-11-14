<?php

namespace App\Events;

use Illuminate\Broadcasting\PrivateChannel;

/**
 * Signals that a listing's available inventory or inventory visibility changed.
 *
 * The payload intentionally carries only the listing id. Both clients refresh
 * through their existing authenticated API, so no stale or privileged resource
 * projection is broadcast. BroadcastEvent queues this after the database commit.
 */
class ListingInventoryUpdated extends BroadcastEvent
{
    public function __construct(public readonly int $listingId)
    {
    }

    /**
     * @return array<int, \Illuminate\Broadcasting\Channel>
     */
    public function broadcastOn(): array
    {
        return [
            new PrivateChannel('marketplace'),
            new PrivateChannel('admin'),
        ];
    }

    public function broadcastAs(): string
    {
        return 'listing.inventory.updated';
    }

    /**
     * @return array{listing_id: int}
     */
    public function broadcastWith(): array
    {
        return ['listing_id' => $this->listingId];
    }
}
