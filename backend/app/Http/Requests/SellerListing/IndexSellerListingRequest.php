<?php

namespace App\Http\Requests\SellerListing;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Query parameters for a seller's own listing management list.
 *
 * The marketplace list and this one differ in exactly one respect that matters:
 * a `status` filter is allowed here, because a seller legitimately needs to see
 * their own work in every state (§5.4), including the `draft` and `pending`
 * records the marketplace can never return [D-02 rule 9].
 *
 * The scope is still not the client's to choose. `seller_id` is prohibited for
 * the same reason as in `IndexListingRequest` — ownership is derived from the
 * token, so there is no filter that could widen the query.
 */
class IndexSellerListingRequest extends FormRequest
{
    use SellerListingRules;

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
            'status' => ['nullable', 'in:'.implode(',', self::ownStatusValues())],
            'search' => ['nullable', 'string', 'max:255'],
            'page' => ['nullable', 'integer', 'min:1'],
            'per_page' => ['nullable', 'integer', 'between:1,50'],

            'seller_id' => ['prohibited'],
        ];
    }
}
