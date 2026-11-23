<?php

namespace App\Http\Requests\Messaging;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Validates a new message.
 *
 * ## The receiver cannot be the caller
 *
 * A message to yourself is nonsense and would create an orphan conversation
 * whose counterpart is the caller. The `not_in` rule rejects it at the
 * boundary rather than letting the service filter it later.
 *
 * ## The listing is optional
 *
 * A first message typically carries a `listing_id` — "I'm interested in your
 * cattle" needs to point at which cattle. But a follow-up question about a
 * different listing, or a general "hello", is also valid. The column is
 * nullable for exactly that reason. Listing visibility is verified by the
 * messaging service against the sender and conversation history.
 */
class StoreMessageRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user() !== null;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            // These are server-owned fields. `missing` rejects even explicit
            // null/empty values, rather than silently discarding them.
            'sender_id' => ['missing'],
            'read_at' => ['missing'],
            'receiver_id' => [
                'required',
                'integer',
                'exists:users,id',
                'not_in:'.$this->user()->id,
            ],
            // Listing existence and visibility are checked against the
            // authenticated sender and conversation history in the service.
            // Keeping this syntactic rule free of `exists` avoids a listing-id
            // existence oracle for hidden listings.
            'listing_id' => ['nullable', 'integer'],
            'body' => ['required', 'string', 'min:1', 'max:2000'],
        ];
    }
}
