<?php

namespace App\Events;

use App\Models\User;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Notifications\Notification;

/**
 * A database notification was written for a user.
 *
 * Broadcast to that user's `user.{id}` channel so the mobile bell badge can
 * refresh live — including notifications produced by administrator actions
 * (listing approved/rejected, seller verification approved/rejected) that have
 * no domain event of their own. The payload is the notification's own
 * `toArray()` pointer (`type`, `title`, `body`, `action`, `action_id`); the
 * client re-fetches the list for the full record.
 */
class NotificationCreated extends BroadcastEvent
{
    public function __construct(
        public readonly User $notifiable,
        public readonly Notification $notification,
    ) {
    }

    /**
     * @return array<int, \Illuminate\Broadcasting\Channel>
     */
    public function broadcastOn(): array
    {
        return [new PrivateChannel('user.'.$this->notifiable->id)];
    }

    public function broadcastAs(): string
    {
        return 'notification.created';
    }

    /**
     * @return array<string, mixed>
     */
    public function broadcastWith(): array
    {
        return $this->notification->toArray($this->notifiable);
    }
}
