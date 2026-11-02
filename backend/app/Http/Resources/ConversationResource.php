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
 *   'listing_id'     => int|null,             // most relevant listing context
 *   'listing_title'  => string|null,          // human-readable listing
 *   'listing_price'  => string|null,          // that listing's asking price
 *   'last_message'   => string,               // the newest message body
 *   'last_message_at'=> Carbon,               // when it was sent
 *   'unread_count'   => int,                  // unread messages for the caller
 *   'has_inquiry'    => bool,                 // an inquiry exists for the pair
 *   'has_transaction'=> bool,                 // a transaction exists for the pair
 *   'roles'          => list<string>,         // the caller's side(s): buyer/seller
 *   'listing_count'  => int,                  // distinct listings in the thread
 *   'latest_offer'   => ?array,               // newest offer preview
 *   'eligible_inquiry'=> ?array,              // newest inquiry an offer can start from
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
            'listing_price' => $this['listing_price'] ?? null,
            'last_message' => $this['last_message'],
            'last_message_at' => $this['last_message_at']?->toISOString(),
            'unread_count' => $this['unread_count'],
            'has_inquiry' => (bool) $this['has_inquiry'],
            'has_transaction' => (bool) $this['has_transaction'],
            // The caller's side of the pair. A pair can be both, which is why
            // this is a list; an empty list means the thread cannot be
            // classified and the app shows it in both account modes.
            'roles' => array_values($this['roles'] ?? []),
            'listing_count' => (int) ($this['listing_count'] ?? 0),
            'latest_offer' => $this['latest_offer'] ?? null,
            'eligible_inquiry' => $this['eligible_inquiry'] ?? null,
        ];
    }
}
