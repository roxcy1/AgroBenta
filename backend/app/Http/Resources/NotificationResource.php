<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * A single notification, in the shape the mobile client reads.
 *
 * The resource does not expose Laravel's internal `type` (the FQCN of the
 * notification class), `notifiable_type` or `notifiable_id` — the client has no
 * use for any of them. The payload's `data` blob (which carries `title`, `body`,
 * `type`, `action` and `action_id`) is flattened into the resource's top level
 * so the mobile model can read them as plain fields, not as a nested object
 * it has to dig through.
 */
class NotificationResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        /** @var array<string, mixed> $data */
        $data = $this->data ?? [];

        return [
            'id' => $this->id,
            'title' => $data['title'] ?? 'Notification',
            'body' => $data['body'] ?? '',
            'type' => $data['type'] ?? 'system',
            'action' => $data['action'] ?? null,
            'action_id' => $data['action_id'] ?? null,
            'read' => $this->read_at !== null,
            'read_at' => $this->read_at?->toISOString(),
            'created_at' => $this->created_at?->toISOString(),
        ];
    }
}