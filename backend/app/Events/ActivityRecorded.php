<?php

namespace App\Events;

use App\Models\Activity;
use Illuminate\Broadcasting\PrivateChannel;

/**
 * An audit entry was written.
 *
 * Broadcast to the shared `admin` channel so administrator dashboards (activity
 * feed, dashboard, moderation lists, reports) can invalidate and re-fetch. One
 * hook at {@see \App\Services\ActivityLogger::log()} covers every audited
 * action across the system.
 */
class ActivityRecorded extends BroadcastEvent
{
    public function __construct(public readonly Activity $activity)
    {
    }

    /**
     * @return array<int, \Illuminate\Broadcasting\Channel>
     */
    public function broadcastOn(): array
    {
        return [new PrivateChannel('admin')];
    }

    public function broadcastAs(): string
    {
        return 'activity.recorded';
    }

    /**
     * @return array<string, mixed>
     */
    public function broadcastWith(): array
    {
        return [
            'id' => $this->activity->getKey(),
            'user_id' => $this->activity->user_id,
            'action' => $this->activity->action,
            'description' => $this->activity->description,
            'created_at' => $this->activity->created_at?->toISOString(),
        ];
    }
}
