<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * A single message, in the shape the mobile client reads.
 *
 * The resource is nested-aware: `sender` and `receiver` are separate resources
 * so a message carries enough context to render without a second request. The
 * mobile client renders a bubble from `body` + `sender.id` + `created_at`, and
 * shows the counterpart's name from whichever of `sender`/`receiver` is not
 * the current user.
 *
 * `listing_id` is exposed as a plain integer. The `listing` resource itself is
 * not embedded — the thread screen already knows the listing it is chatting
 * about, and pulling it in twice would be wasted payload.
 */
class MessageResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'body' => $this->body,
            'sender_id' => $this->sender_id,
            'receiver_id' => $this->receiver_id,
            'listing_id' => $this->listing_id,
            'read' => $this->read_at !== null,
            'read_at' => $this->read_at?->toISOString(),
            'created_at' => $this->created_at?->toISOString(),
            'sender' => new UserSummaryResource($this->whenLoaded('sender')),
            'receiver' => new UserSummaryResource($this->whenLoaded('receiver')),
        ];
    }
}