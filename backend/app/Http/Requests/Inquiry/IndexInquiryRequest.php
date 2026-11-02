<?php

namespace App\Http\Requests\Inquiry;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Query for the caller's active inquiry list.
 *
 * `role` narrows to the side the caller is acting on — the Messages tab passes
 * the active Account Mode. Ownership filters are refused: the list is always
 * scoped to the token, so there is no way to widen it to another account.
 */
class IndexInquiryRequest extends FormRequest
{
    public function authorize(): bool
    {
        // `auth:sanctum` + `ability:mobile`.
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'role' => ['nullable', 'string', Rule::in(['buyer', 'seller'])],

            'buyer_id' => ['prohibited'],
            'seller_id' => ['prohibited'],
            'user_id' => ['prohibited'],
            'status' => ['prohibited'],
        ];
    }
}
