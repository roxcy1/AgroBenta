<?php

namespace App\Http\Requests\Messaging;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Validates the body for `POST /api/conversations/{userId}/read`.
 *
 * The only optional field is `listing_id`, used to scope "mark this thread
 * read" to one listing. Without it, every unread message from that user is
 * marked read — the sensible default, because the mobile thread screen does
 * not distinguish between listings that share the same counterpart.
 */
class MarkMessagesReadRequest extends FormRequest
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
            'listing_id' => ['sometimes', 'nullable', 'integer', 'exists:listings,id'],
        ];
    }
}