<?php

namespace App\Http\Requests\Marketplace;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Query parameters for the buyer marketplace.
 *
 * An allow-list, not a denylist: only the filters named in the mobile API
 * contract §5.2 are accepted, and the controller may only pass the keys
 * declared here to the service. A parameter that is not listed therefore has no
 * path into the query at all, which is what keeps a new request field from
 * becoming a marketplace filter by accident.
 */
class IndexListingRequest extends FormRequest
{
    public function authorize(): bool
    {
        // Authorization is the route's job: `auth:sanctum` plus the
        // `ability:mobile` guard, which is what makes this a marketplace
        // request rather than an admin one.
        return true;
    }

    /**
     * @return array<string, list<string>>
     */
    public function rules(): array
    {
        return [
            'search' => ['nullable', 'string', 'max:255'],
            'livestock_type' => ['nullable', 'string', 'max:255'],
            'location' => ['nullable', 'string', 'max:255'],
            'min_price' => ['nullable', 'numeric', 'min:0'],
            'max_price' => ['nullable', 'numeric', 'min:0'],
            'page' => ['nullable', 'integer', 'min:1'],
            'per_page' => ['nullable', 'integer', 'between:1,50'],

            // Marketplace visibility is the server's decision [D-02 rule 9], and
            // a `status` parameter is rejected rather than honoured — accepting
            // it would be the rule violated, and dropping it silently would
            // hide a client bug. `active` is not a permitted value either: the
            // endpoint is active-only by construction, not by parameter.
            'status' => ['prohibited'],

            // Ownership is never a client-selected scope on a read endpoint
            // (functional documentation §10.3). There is no "browse one
            // seller's listings" marketplace view, and this phase is read-only,
            // so the field is refused rather than quietly ignored.
            'seller_id' => ['prohibited'],
        ];
    }
}
