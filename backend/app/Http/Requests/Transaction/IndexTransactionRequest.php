<?php

namespace App\Http\Requests\Transaction;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Query parameters for a user's own transaction list.
 *
 * The scope is never the client's to choose. `buyer_id` and `seller_id` are
 * prohibited: ownership is derived from the token, and `role` only narrows
 * within the caller's own two sides (buyer side, seller side, or both).
 * A `role` value is a side selector, not a user selector.
 */
class IndexTransactionRequest extends FormRequest
{
    public function authorize(): bool
    {
        // `auth:sanctum` + `ability:mobile`. Any authenticated user may list
        // their own transactions; the repository scopes the query.
        return true;
    }

    /**
     * @return array<string, list<string>>
     */
    public function rules(): array
    {
        return [
            'role' => ['nullable', 'in:buyer,seller'],
            'status' => ['nullable', 'in:pending,completed,cancelled'],
            'page' => ['nullable', 'integer', 'min:1'],
            'per_page' => ['nullable', 'integer', 'between:1,50'],

            'buyer_id' => ['prohibited'],
            'seller_id' => ['prohibited'],
        ];
    }
}
