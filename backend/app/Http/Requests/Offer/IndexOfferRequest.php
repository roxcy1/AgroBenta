<?php

namespace App\Http\Requests\Offer;

use App\Enums\OfferStatus;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Query filters for the caller's offer list.
 *
 * Every value narrows a list that is already scoped to the token in the
 * repository. `buyer_id`, `seller_id` and `user_id` are refused with a 422:
 * ownership is never a client-selected value, so there is no parameter that
 * could widen the result to another buyer–seller pair.
 */
class IndexOfferRequest extends FormRequest
{
    public function authorize(): bool
    {
        // `auth:sanctum` + `ability:mobile`. The repository scopes the list to
        // the authenticated user.
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'inquiry_id' => ['sometimes', 'integer', 'min:1'],
            'listing_id' => ['sometimes', 'integer', 'min:1'],
            'counterpart_id' => ['sometimes', 'integer', 'min:1'],
            'status' => ['sometimes', Rule::enum(OfferStatus::class)],

            'buyer_id' => ['prohibited'],
            'seller_id' => ['prohibited'],
            'user_id' => ['prohibited'],
        ];
    }
}
