<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * A minimal user summary, for embedding inside a message or a conversation.
 *
 * Only the fields a chat UI needs — id, name, avatar. Not the full
 * `UserResource`: phone, email, bio, and role have no place in a chat list and
 * shipping them on every message would leak contact details between users who
 * have not agreed to share them.
 */
class UserSummaryResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'avatar_url' => $this->avatar_url,
        ];
    }
}