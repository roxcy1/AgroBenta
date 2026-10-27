<?php

namespace App\Http\Requests\Messaging;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Validates the query string for `GET /api/conversations/{userId}/messages`.
 *
 * The path parameter is the counterpart's user id; the query string can narrow
 * the thread to one listing. Everything else is fixed: the thread is always
 * "me and that user", never a free-form user filter.
 */
class IndexMessageRequest extends FormRequest
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
            'per_page' => ['sometimes', 'integer', 'between:1,50'],
            'page' => ['sometimes', 'integer', 'min:1'],
        ];
    }
}