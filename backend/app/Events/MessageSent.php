<?php

namespace App\Events;

use App\Models\Message;
use Illuminate\Broadcasting\PrivateChannel;

/**
 * A buyer–seller message has been persisted and should reach the receiver.
 *
 * Broadcast to the receiver's private `user.{id}` channel (the wire name is
 * `private-user.{id}`), so only the intended recipient can subscribe. Queued
 * and dispatched after commit — see {@see BroadcastEvent}.
 */
class MessageSent extends BroadcastEvent
{
    public function __construct(public readonly Message $message)
    {
    }

    /**
     * @return array<int, \Illuminate\Broadcasting\Channel>
     */
    public function broadcastOn(): array
    {
        return [new PrivateChannel('user.'.$this->message->receiver_id)];
    }

    public function broadcastAs(): string
    {
        return 'message.sent';
    }

    /**
     * A minimal, explicit payload. The receiver can append the message to an
     * open thread or re-fetch the thread; nothing here depends on the request
     * user or on relations the queued job has not loaded.
     *
     * @return array<string, mixed>
     */
    public function broadcastWith(): array
    {
        return [
            'id' => $this->message->getKey(),
            'sender_id' => (int) $this->message->sender_id,
            'receiver_id' => (int) $this->message->receiver_id,
            'listing_id' => $this->message->listing_id === null ? null : (int) $this->message->listing_id,
            'body' => $this->message->body,
            'created_at' => $this->message->created_at?->toISOString(),
        ];
    }
}
