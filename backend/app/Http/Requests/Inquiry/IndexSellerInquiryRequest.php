<?php

namespace App\Http\Requests\Inquiry;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Query parameters for the seller's received-inquiry list.
 *
 * The only client-settable values are pagination. The seller whose inquiries
 * are returned is always the token's user, so `seller_id` is prohibited: there
 * is no filter that could widen the query to another seller's records.
 *
 * `buyer_id` and `status` are prohibited for the same reason. Received
 * inquiries are not searchable or triageable from the mobile client in this
 * phase, and the administrator-facing status is deliberately not exposed to
 * sellers (see `SellerInquiryResource`).
 */
class IndexSellerInquiryRequest extends FormRequest
{
    public function authorize(): bool
    {
        // The route's job, and not this method's: the middleware stack is
        // `auth:sanctum` + `ability:mobile` + the `seller` capability gate. The
        // ownership scope is applied in the repository, from the token.
        return true;
    }

    /**
     * @return array<string, list<string>>
     */
    public function rules(): array
    {
        return [
            'page' => ['nullable', 'integer', 'min:1'],
            'per_page' => ['nullable', 'integer', 'between:1,50'],

            'buyer_id' => ['prohibited'],
            'seller_id' => ['prohibited'],
            'status' => ['prohibited'],
        ];
    }
}
