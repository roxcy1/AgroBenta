<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * A conversation, derived from a pair of users and (optionally) a listing.
 *
 * ## Why this is a plain resource, not a model
 *
 * There is no `conversations` table — a conversation is a *view* over messages.
 * The list is built in `MessagingService::conversationsFor()` and passed here
 * as a plain array. The resource exists so the shape of a conversation is
 * defined in one place, not assembled ad-hoc in the controller.
 *
 * ## The expected array shape
 *
 * ```
 * [
 *   'counterpart'    => User,                 // the other user in the thread
 *   'listing_id'     => int|null,             // listing context, if any
 *   'listing_title'  => string|null,          // human-readable listing
 *   'last_message'   => string,               // the newest message body
 *   'last_message_at'=> Carbon,               // when it was sent
 *   'unread_count'   => int,                  // unread messages for the caller
 * ]
 * ```
 */
class ConversationResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'counterpart' => new UserSummaryResource($this['counterpart']),
            'listing_id' => $this['listing_id'],
            'listing_title' => $this['listing_title'],
            'last_message' => $this['last_message'],
            'last_message_at' => $this['last_message_at']?->toISOString(),
            'unread_count' => $this['unread_count'],
        ];
    }
}